import Foundation

/// State of one WAN interface as shown by the status file.
public enum SnapshotWANState: String, Codable {
    case online
    case offline
    case disabled
    /// The line is enabled and up, but the gateway uses another line.
    case standby

    /// Text for the app, in the current language.
    public var displayName: String {
        switch self {
        case .online: return T(.wanStateOnline)
        case .offline: return T(.wanStateOffline)
        case .disabled: return T(.wanStateDisabled)
        case .standby: return T(.wanStateStandby)
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

    /// The WAN interface that still has an open outage in the local log.
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

        let lines = gatewayStatus?.wanInterfaces ?? []
        let states = WANLineRules.states(of: lines)

        let wanInterfaces = lines.enumerated().map { index, wan in
            WANSnapshot(
                id: wan.id,
                ispName: WANLineRules.ispName(forWAN: wan.id, in: events),
                state: states[index],
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
    /// `title` is the Chinese event name, for example `互联网中断`; the event
    /// itself is in `event`. The gateway title stays in `MonitoredLogEvent`.
    public static func summaries(of events: [MonitoredLogEvent]) -> [LogSummary] {
        events
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(StatusSnapshot.recentLogLimit)
            .map { event in
                LogSummary(
                    id: event.id,
                    event: event.event,
                    severity: event.severity,
                    title: event.event.displayName,
                    timestamp: event.timestamp
                )
            }
    }
}
