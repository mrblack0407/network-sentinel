import Foundation

/// State of one WAN interface as shown by the status file.
public enum SnapshotWANState: String, Codable {
    case online
    case offline
    case disabled
    /// The line is up but the gateway is running on the backup connection.
    case standby

    /// Chinese text for the app.
    public var displayName: String {
        switch self {
        case .online: return "在线"
        case .offline: return "离线"
        case .disabled: return "未启用"
        case .standby: return "备用"
        }
    }
}

/// One WAN interface inside the status file.
public struct WANSnapshot: Codable, Equatable, Identifiable {
    /// `WAN1` / `WAN2`.
    public let id: String
    public let ispName: String?
    public let state: SnapshotWANState
    /// Start of the outage that is still open, or `nil` when the line is up.
    public let outageStartedAt: Date?

    public init(id: String, ispName: String?, state: SnapshotWANState, outageStartedAt: Date? = nil) {
        self.id = id
        self.ispName = ispName
        self.state = state
        self.outageStartedAt = outageStartedAt
    }
}

/// One monitored log entry inside the status file.
public struct LogSummary: Codable, Equatable, Identifiable {
    /// The log entry id.
    public let id: String
    public let event: MonitoredEvent
    /// `nil` when the gateway sent a severity this version does not know.
    public let severity: LogSeverity?
    public let title: String
    public let timestamp: Date

    public init(id: String, event: MonitoredEvent, severity: LogSeverity?, title: String, timestamp: Date) {
        self.id = id
        self.event = event
        self.severity = severity
        self.title = title
        self.timestamp = timestamp
    }
}

/// Everything the future desktop widget needs, in one small `Codable` value.
///
/// The snapshot never carries the API Key: it holds only what the widget shows.
public struct StatusSnapshot: Codable, Equatable {
    /// Gateway name, for example `Dream Machine Pro Max`.
    public let gatewayName: String
    /// When the snapshot was built.
    public let updatedAt: Date
    /// The gateway as a whole is reachable.
    public let isGatewayReachable: Bool
    public let wanInterfaces: [WANSnapshot]
    /// 互联网中断 entries of the last 24 hours.
    public let outageCount24h: Int
    /// 检测到威胁 entries of the last 24 hours.
    public let threatCount24h: Int
    /// Highest severity of the last 24 hours, or `nil` when there was none.
    public let highestSeverity24h: LogSeverity?
    /// Last five monitored entries, newest first.
    public let recentLogs: [LogSummary]

    public static let recentLogLimit = 5
    public static let countWindow: TimeInterval = 24 * 60 * 60

    public init(
        gatewayName: String,
        updatedAt: Date,
        isGatewayReachable: Bool,
        wanInterfaces: [WANSnapshot],
        outageCount24h: Int,
        threatCount24h: Int,
        highestSeverity24h: LogSeverity?,
        recentLogs: [LogSummary]
    ) {
        self.gatewayName = gatewayName
        self.updatedAt = updatedAt
        self.isGatewayReachable = isGatewayReachable
        self.wanInterfaces = wanInterfaces
        self.outageCount24h = outageCount24h
        self.threatCount24h = threatCount24h
        self.highestSeverity24h = highestSeverity24h
        self.recentLogs = recentLogs
    }

    public var wan1: WANSnapshot? { wanInterfaces.first { $0.id == "WAN1" } }
    public var wan2: WANSnapshot? { wanInterfaces.first { $0.id == "WAN2" } }

    /// The WAN interface that is offline and still has an open outage.
    public var currentOutageWAN: WANSnapshot? {
        wanInterfaces.first { $0.outageStartedAt != nil }
    }
}

/// Builds the status file content. Pure: takes the status, the entries and a time.
public enum StatusSnapshotBuilder {
    /// Builds a snapshot.
    ///
    /// - Parameters:
    ///   - gatewayStatus: name and WAN state of the gateway, or `nil` when it was not read.
    ///   - events: monitored entries to summarize, in any order.
    ///   - now: the injected current time; the 24-hour window ends here.
    ///   - isGatewayReachable: state of the gateway probe.
    public static func snapshot(
        gatewayStatus: GatewayStatus?,
        events: [MonitoredLogEvent],
        now: Date,
        isGatewayReachable: Bool
    ) -> StatusSnapshot {
        let windowStart = now.addingTimeInterval(-StatusSnapshot.countWindow)
        let recent = events.filter { $0.timestamp >= windowStart && $0.timestamp <= now }
        let outages = OutagePairer.outages(in: events)

        let wanInterfaces = (gatewayStatus?.wanInterfaces ?? []).map { wan in
            WANSnapshot(
                id: wan.id,
                ispName: ispName(forWAN: wan.id, in: events),
                state: snapshotState(of: wan, at: now, outages: outages),
                outageStartedAt: OutagePairer.ongoingOutage(forWAN: wan.id, in: outages)?.start
            )
        }

        return StatusSnapshot(
            gatewayName: gatewayStatus?.name ?? "",
            updatedAt: now,
            isGatewayReachable: isGatewayReachable,
            wanInterfaces: wanInterfaces,
            outageCount24h: recent.filter { $0.event == .internetDown }.count,
            threatCount24h: recent.filter { $0.event == .threatDetected }.count,
            highestSeverity24h: recent.compactMap(\.severity).max(),
            recentLogs: summaries(of: events)
        )
    }

    /// The last five monitored entries, newest first.
    ///
    /// `title` is the gateway title with placeholders filled, for example
    /// `WAN1 Internet Down`; the event name is in `event`.
    public static func summaries(of events: [MonitoredLogEvent]) -> [LogSummary] {
        events
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(StatusSnapshot.recentLogLimit)
            .map { event in
                LogSummary(
                    id: event.id,
                    event: event.event,
                    severity: event.severity,
                    title: event.title,
                    timestamp: event.timestamp
                )
            }
    }

    /// Gateway state mapped to the status file, with 备用 for a line the gateway
    /// reports as up while it is running on the backup connection.
    ///
    /// The backup flag comes from the log: a 互联网中断 entry of that line that
    /// has no restore yet, while the gateway still reports the line as up.
    private static func snapshotState(
        of wan: WANStatus,
        at now: Date,
        outages: [Outage]
    ) -> SnapshotWANState {
        switch wan.state {
        case .disabled:
            return .disabled
        case .offline:
            return .offline
        case .online:
            guard let ongoing = OutagePairer.ongoingOutage(forWAN: wan.id, in: outages) else {
                return .online
            }
            // The line came back on the backup connection while the primary
            // outage is still open.
            return ongoing.start <= now ? .standby : .online
        }
    }

    /// Provider name of the newest WAN event of that line.
    private static func ispName(forWAN wanID: String, in events: [MonitoredLogEvent]) -> String? {
        events
            .filter { ($0.wanID == wanID) && ($0.ispName?.isEmpty == false) }
            .max { $0.timestamp < $1.timestamp }?
            .ispName
    }
}
