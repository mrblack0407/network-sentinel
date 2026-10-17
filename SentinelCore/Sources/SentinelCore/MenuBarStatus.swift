import Foundation

/// The dot of the 菜单栏图标.
///
/// The dot shows the highest severity of the last 24 hours of the local log and
/// the state of the gateway; the 菜单栏弹出面板 and the 主窗口 线路标签 reuse the
/// same value, so the three never disagree.
public enum MenuBarIndicatorState: String, CaseIterable {
    /// No 中 or higher event: the icon shows the shield alone.
    case quiet
    /// A 中 or 高 event: a yellow dot.
    case warning
    /// A 非常高 event, or a line that is down right now: a red dot.
    case critical
    /// 网关连不上, API Key 无效 or 证书变了: a gray dot.
    case disconnected

    /// Name of the state, for the read-out of the icon, in the current language.
    public var displayName: String {
        switch self {
        case .quiet: return T(.indicatorQuiet)
        case .warning: return T(.indicatorWarning)
        case .critical: return T(.indicatorCritical)
        case .disconnected: return T(.indicatorDisconnected)
        }
    }
}

/// One WAN line as the 菜单栏弹出面板 and the 主窗口 线路标签 show it.
///
/// The state follows the same rules as the 状态文件, so the panel, the widget
/// and the 概览 page never tell different stories.
public struct WANLineStatus: Equatable, Identifiable {
    /// `WAN1` or `WAN2`.
    public let id: String
    /// Provider name from `ISP_NAME` of the newest log entry of that line.
    public let ispName: String?
    /// 在线 / 离线 / 未启用 / 备用.
    public let state: SnapshotWANState
    /// Start of the outage that is still open, `nil` while the line is up.
    public let outageStartedAt: Date?

    public init(
        id: String,
        ispName: String?,
        state: SnapshotWANState,
        outageStartedAt: Date? = nil
    ) {
        self.id = id
        self.ispName = ispName
        self.state = state
        self.outageStartedAt = outageStartedAt
    }

    /// `true` while the gateway reports the line as down.
    ///
    /// This is the line that turns the 菜单栏图标 dot red and the row dot of the
    /// 菜单栏弹出面板 red. A 备用 line is up, the gateway only uses another line.
    public var isDown: Bool { state == .offline }

    /// Short name, for the 主窗口 线路标签.
    public var displayName: String {
        switch state {
        case .online: return T(.lineStateOnline)
        case .offline: return T(.lineStateDown)
        case .disabled: return T(.lineStateDisabled)
        case .standby: return T(.lineStateStandby)
        }
    }

    /// `WAN1 在线`, the text of one 主窗口 线路标签.
    public var chipText: String { "\(id) \(displayName)" }

    /// What the 菜单栏弹出面板 writes on the right of the line row.
    ///
    /// - Parameter now: the current time; 已断开 counts from the open outage.
    public func detailText(now: Date) -> String {
        switch state {
        case .online:
            return T(.lineStateOnline)
        case .offline:
            guard let outageStartedAt else { return T(.lineStateDown) }
            let seconds = Int(max(0, now.timeIntervalSince(outageStartedAt)).rounded(.down))
            return T(.lineStateDownFor, DurationText.text(seconds: seconds))
        case .disabled:
            return T(.lineStateDisabled)
        case .standby:
            return T(.lineStateStandby)
        }
    }

    /// The whole line in one sentence, for a screen reader.
    public func accessibilityText(now: Date) -> String {
        var parts: [String] = [id]
        if let ispName, !ispName.isEmpty {
            parts.append(ispName)
        }
        parts.append(detailText(now: now))
        return parts.joined(separator: T(.commonListSeparator))
    }
}

/// Everything the 菜单栏图标 and the 菜单栏弹出面板 show.
///
/// The 菜单栏弹出面板 keeps only the newest five events of its filter, so the
/// view decides what the list shows.
public struct MenuBarStatus: Equatable {
    /// Name of the gateway, empty when it was never read.
    public let gatewayName: String
    /// Seconds between two queries, for the 「30 秒查一次」 chip.
    public let queryIntervalSeconds: Int
    /// State of the gateway of the last query.
    public let connectionState: GatewayConnectionState
    /// Chinese reason of a failed connection, `nil` while the gateway answers.
    public let connectionReason: String?
    /// Highest severity of the last 24 hours, `nil` when there was none.
    public let highestSeverity: LogSeverity?
    /// 互联网中断 entries of the last 24 hours.
    public let outageCount24h: Int
    /// 检测到威胁 entries of the last 24 hours.
    public let threatCount24h: Int
    /// WAN lines of the last successful query, in gateway order.
    public let lines: [WANLineStatus]
    /// The monitored events of the last 24 hours, newest first.
    public let recentEvents: [MonitoredLogEvent]
    /// The dot of the 菜单栏图标.
    public let indicator: MenuBarIndicatorState

    public init(
        gatewayName: String,
        queryIntervalSeconds: Int,
        connectionState: GatewayConnectionState,
        connectionReason: String?,
        highestSeverity: LogSeverity?,
        outageCount24h: Int,
        threatCount24h: Int,
        lines: [WANLineStatus],
        recentEvents: [MonitoredLogEvent],
        indicator: MenuBarIndicatorState
    ) {
        self.gatewayName = gatewayName
        self.queryIntervalSeconds = queryIntervalSeconds
        self.connectionState = connectionState
        self.connectionReason = connectionReason
        self.highestSeverity = highestSeverity
        self.outageCount24h = outageCount24h
        self.threatCount24h = threatCount24h
        self.lines = lines
        self.recentEvents = recentEvents
        self.indicator = indicator
    }

    /// `true` while the gateway cannot be reached at all.
    public var isGatewayUnreachable: Bool { connectionState == .reconnecting }

    /// What a screen reader reads for the 菜单栏图标, for example
    /// 「Network Sentinel：WAN1 在线，近 24 小时有非常高的事件」.
    public var accessibilityText: String {
        var parts: [String] = []
        if connectionState == .connected {
            parts.append(contentsOf: lines.map(\.chipText))
        } else {
            parts.append(connectionState.displayName)
        }
        parts.append(contentsOf: severityPhrases)
        let readOut = parts.joined(separator: T(.commonListSeparator))
        return readOut.isEmpty ? "Network Sentinel" : T(.menuBarReadOut, readOut)
    }

    /// The severity part of the read-out, per state of the dot.
    private var severityPhrases: [String] {
        switch indicator {
        case .quiet:
            return [T(.indicatorQuiet)]
        case .warning:
            guard let highestSeverity else { return [] }
            return [T(.menuBarSeverityPhrase, highestSeverity.displayName)]
        case .critical:
            var phrases: [String] = []
            if highestSeverity == .veryHigh {
                phrases.append(T(.menuBarVeryHighPhrase))
            }
            if lines.contains(where: { $0.isDown }) {
                phrases.append(T(.menuBarLineDownPhrase))
            }
            return phrases
        case .disconnected:
            // The state of the gateway already says what is wrong.
            return []
        }
    }
}

/// Builds the state of the 菜单栏图标 and the 菜单栏弹出面板.
///
/// Pure: the clock, the gateway answer and the local log all come in as values,
/// so `MonitorService` stays a thin shell and the rules are tested without a
/// gateway.
public enum MenuBarStatusBuilder {
    /// The state of the menu bar, from what the engine published.
    ///
    /// - Parameters:
    ///   - gatewayName: name of the gateway, `nil` before the first successful query.
    ///   - queryIntervalSeconds: seconds between two queries, for the chip.
    ///   - connectionState: state of the gateway of the last query.
    ///   - errorDescription: Chinese text of the last failure, for the reason line.
    ///   - gatewayStatus: WAN lines of the last successful query, `nil` when it never answered.
    ///   - events: the local log, in any order.
    ///   - now: the current time; the 24-hour window and 「已断开 N 分」 end here.
    public static func status(
        gatewayName: String?,
        queryIntervalSeconds: Int,
        connectionState: GatewayConnectionState,
        errorDescription: String?,
        gatewayStatus: GatewayStatus?,
        events: [MonitoredLogEvent],
        now: Date
    ) -> MenuBarStatus {
        let summary = MonitorLogSpec.summary(of: events, now: now)
        let outages = OutagePairer.outages(in: events)
        let windowStart = now.addingTimeInterval(-MonitorLogSpec.summaryWindow)

        let wanInterfaces = gatewayStatus?.wanInterfaces ?? []
        let states = WANLineRules.states(of: wanInterfaces)

        let lines = wanInterfaces.enumerated().map { index, wan in
            WANLineStatus(
                id: wan.id,
                ispName: WANLineRules.ispName(forWAN: wan.id, in: events),
                state: states[index],
                outageStartedAt: OutagePairer.ongoingOutage(forWAN: wan.id, in: outages)?.start
            )
        }

        return MenuBarStatus(
            gatewayName: gatewayName ?? "",
            queryIntervalSeconds: max(1, queryIntervalSeconds),
            connectionState: connectionState,
            connectionReason: connectionReason(
                state: connectionState,
                errorDescription: errorDescription,
                now: now
            ),
            highestSeverity: summary.highestSeverity,
            outageCount24h: summary.outageCount,
            threatCount24h: summary.threatCount,
            lines: lines,
            recentEvents: events
                .filter { $0.timestamp >= windowStart && $0.timestamp <= now }
                .sorted { $0.timestamp > $1.timestamp },
            indicator: indicator(
                connectionState: connectionState,
                highestSeverity: summary.highestSeverity,
                lines: lines
            )
        )
    }

    /// The dot of the 菜单栏图标.
    ///
    /// A broken connection wins over the log: while the app cannot read the
    /// gateway, the newest 24 hours are not trustworthy. 非常高 or a line that is
    /// down wins over a 中 or 高 event.
    public static func indicator(
        connectionState: GatewayConnectionState,
        highestSeverity: LogSeverity?,
        lines: [WANLineStatus]
    ) -> MenuBarIndicatorState {
        switch connectionState {
        case .reconnecting, .apiKeyRejected, .certificateChanged:
            return .disconnected
        case .connected:
            break
        }

        if highestSeverity == .veryHigh || lines.contains(where: { $0.isDown }) {
            return .critical
        }
        if let highestSeverity, highestSeverity >= .medium {
            return .warning
        }
        return .quiet
    }

    /// The red line the 菜单栏弹出面板 shows above the lines, or `nil`.
    private static func connectionReason(
        state: GatewayConnectionState,
        errorDescription: String?,
        now: Date
    ) -> String? {
        // 已连接 has no reason line, and its status text is the 设置 卡片 one.
        guard state != .connected else { return nil }
        return MonitorLogSpec.statusText(
            state: state,
            lastQueryAt: nil,
            now: now,
            errorDescription: errorDescription
        ).text
    }
}

/// The WAN rules shared by the 状态文件 and the 菜单栏弹出面板.
enum WANLineRules {
    /// The state the app shows for every line, in gateway order.
    ///
    /// The gateway is the source of truth for 在线 and 断网中: `stat/device`
    /// reports a line as down exactly when its `up` flag is false, whatever the
    /// local log says. A 互联网中断 entry without a restore never changes the
    /// state; it only gives the 「已断开 N 分」 text.
    ///
    /// 备用 is a second line that is enabled and up while the first line carries
    /// the traffic. The answer does not say which line is the current exit, so
    /// the first line that is up is taken as the one in use; while no line is
    /// up, no line is 备用.
    static func states(of wanInterfaces: [WANStatus]) -> [SnapshotWANState] {
        let isPrimaryUp = wanInterfaces.first?.state == .online

        return wanInterfaces.enumerated().map { index, wan in
            switch wan.state {
            case .disabled:
                return .disabled
            case .offline:
                return .offline
            case .online:
                return index > 0 && isPrimaryUp ? .standby : .online
            }
        }
    }

    /// Provider name from `ISP_NAME` of the newest log entry of that line.
    static func ispName(forWAN wanID: String, in events: [MonitoredLogEvent]) -> String? {
        events
            .filter { ($0.wanID == wanID) && ($0.ispName?.isEmpty == false) }
            .max { $0.timestamp < $1.timestamp }?
            .ispName
    }

}
