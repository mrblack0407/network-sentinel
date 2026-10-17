import Foundation

/// The pure rules of the monitoring engine.
///
/// Nothing here reads the clock, the network or the file system: the query range,
/// the first-run rule, the 24-hour summary, the wake summary and the status line
/// come from injected values, so `MonitorService` stays a thin shell around them
/// and every rule is testable.
public enum MonitorLogSpec {
    /// How far back a query reaches when the app never read the log.
    public static let firstRunWindow: TimeInterval = 24 * 60 * 60
    /// How far back a query reaches before the newest entry it already read.
    ///
    /// The overlap covers a gateway that logs an entry a little late; the
    /// deduplication table drops whatever was already handled.
    public static let queryOverlap: TimeInterval = 2 * 60
    /// A wake round sends one summary instead of single notifications past this count.
    public static let wakeSummaryThreshold = 3
    /// Length of the 24-hour counters of the 主窗口 and the 菜单栏弹出面板.
    public static let summaryWindow: TimeInterval = 24 * 60 * 60
    /// Seconds in a day, for the log retention.
    public static let secondsPerDay: TimeInterval = 24 * 60 * 60

    // MARK: - Query range

    /// The time range of one query.
    ///
    /// - Parameters:
    ///   - lastReadAt: the newest log timestamp already read, or `nil` when the
    ///     app has no local records at all.
    ///   - now: the current time.
    /// - Returns: `to` is always `now`; `from` is the overlap before
    ///   `lastReadAt`, or the last 24 hours on the first run.
    public static func queryRange(lastReadAt: Date?, now: Date) -> (from: Date, to: Date) {
        guard let lastReadAt else {
            return (now.addingTimeInterval(-firstRunWindow), now)
        }
        // A clock that jumped backwards must not produce an empty range.
        return (min(lastReadAt.addingTimeInterval(-queryOverlap), now), now)
    }

    // MARK: - First run

    /// `true` when the app has no local records and therefore must not notify.
    ///
    /// A fresh install reads 24 hours of history; notifying all of it would be a
    /// burst of old events, so the first round only records them.
    public static func isFirstRun(seenLogIDs: SeenLogIDs) -> Bool {
        seenLogIDs.isEmpty
    }

    // MARK: - Facts of one round

    /// Everything one round knows after reading the gateway, before any rule runs.
    public struct RoundFacts: Equatable {
        /// The answer of `stat/device`, or `nil` when it failed.
        public let gatewayStatus: GatewayStatus?
        /// The log entries of the query range.
        public let entries: [SystemLogEntry]
        /// `true` when the gateway answered at least one query.
        public let isReachable: Bool

        public init(gatewayStatus: GatewayStatus?, entries: [SystemLogEntry], isReachable: Bool) {
            self.gatewayStatus = gatewayStatus
            self.entries = entries
            self.isReachable = isReachable
        }

        /// Monitored events of the round, oldest first.
        public var monitoredEvents: [MonitoredLogEvent] {
            SystemLogEntry.monitoredLogEvents(in: entries)
        }
    }

    // MARK: - Deduplication

    /// The monitored events of a batch that the app has not seen yet.
    ///
    /// The ids of the returned events are remembered in `seenLogIDs`, so a
    /// second round never reports them again. The table only ever holds the ids
    /// of the seven monitored events: an entry the app does not monitor is
    /// neither reported nor remembered.
    public static func newEvents(
        in entries: [SystemLogEntry],
        seenLogIDs: inout SeenLogIDs
    ) -> [MonitoredLogEvent] {
        let monitored = SystemLogEntry.monitoredLogEvents(in: entries)
        return seenLogIDs.filterNew(monitored.map(\.entry)).new.compactMap(\.monitoredLogEvent)
    }

    /// The events of a batch that happened at or after `date`, oldest first.
    ///
    /// The wake summary only counts what appeared while the Mac was asleep.
    public static func eventsSince(_ date: Date, in entries: [SystemLogEntry]) -> [MonitoredLogEvent] {
        SystemLogEntry.monitoredLogEvents(in: entries)
            .filter { $0.timestamp >= date }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - 24-hour summary

    /// What the app shows about the last 24 hours of local log.
    public struct LogSummaryStats: Equatable {
        /// 互联网中断 entries of the window.
        public let outageCount: Int
        /// 检测到威胁 entries of the window.
        public let threatCount: Int
        /// Highest severity of the window, or `nil` when there was none.
        public let highestSeverity: LogSeverity?

        public init(outageCount: Int, threatCount: Int, highestSeverity: LogSeverity?) {
            self.outageCount = outageCount
            self.threatCount = threatCount
            self.highestSeverity = highestSeverity
        }

        /// The empty window.
        public static let none = LogSummaryStats(outageCount: 0, threatCount: 0, highestSeverity: nil)
    }

    /// Counts the last 24 hours of the local log, ending at `now`.
    public static func summary(of events: [MonitoredLogEvent], now: Date) -> LogSummaryStats {
        let windowStart = now.addingTimeInterval(-summaryWindow)
        let recent = events.filter { $0.timestamp >= windowStart && $0.timestamp <= now }

        return LogSummaryStats(
            outageCount: recent.filter { $0.event == .internetDown }.count,
            threatCount: recent.filter { $0.event == .threatDetected }.count,
            highestSeverity: recent.compactMap(\.severity).max()
        )
    }

    // MARK: - Wake summary

    /// What the app shows after waking up when a round found many new entries.
    public struct WakeSummary: Equatable {
        public let title: String
        public let body: String
        /// Number of new entries the summary covers.
        public let count: Int
        /// 严重性 of the most severe entry the summary covers.
        ///
        /// The 严重性 decides the Bark level of the push. An unknown one counts
        /// as 低, exactly like the notification threshold.
        public let severity: LogSeverity

        public init(title: String, body: String, count: Int, severity: LogSeverity = .low) {
            self.title = title
            self.body = body
            self.count = count
            self.severity = severity
        }
    }

    /// `true` when a wake round sends one summary instead of single notifications.
    public static func shouldSummarizeWake(newEventCount: Int) -> Bool {
        newEventCount > wakeSummaryThreshold
    }

    /// The one summary notification of a wake round, or `nil` for a quiet wake.
    ///
    /// The body lists the most severe entry (the newest one at that severity,
    /// when several share it) and leaves the rest to the 主窗口.
    ///
    /// - Parameter timeText: formats the timestamp of the most severe entry.
    public static func wakeSummary(
        for events: [MonitoredLogEvent],
        timeText: (Date) -> String
    ) -> WakeSummary? {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return nil }

        let mostSevere = sorted.max { first, second in
            let firstSeverity = NotificationSettings.effectiveSeverity(first.severity)
            let secondSeverity = NotificationSettings.effectiveSeverity(second.severity)
            if firstSeverity != secondSeverity {
                return firstSeverity < secondSeverity
            }
            return first.timestamp < second.timestamp
        }
        guard let mostSevere else { return nil }

        let remaining = sorted.count - 1
        let body = T(.wakeEntry, mostSevere.title, timeText(mostSevere.timestamp))
            + (remaining > 0 ? T(.wakeMore, remaining) : "")

        return WakeSummary(
            title: T(.wakeTitle, sorted.count),
            body: body,
            count: sorted.count,
            severity: NotificationSettings.effectiveSeverity(mostSevere.severity)
        )
    }

    // MARK: - Retention

    /// The events inside the retention period, oldest first.
    ///
    /// - Parameters:
    ///   - events: the local log, in any order.
    ///   - now: the current time; a retention of `0` days keeps nothing.
    ///   - retentionDays: days of history the app keeps.
    public static func retained(
        _ events: [StoredMonitorEvent],
        now: Date,
        retentionDays: Int
    ) -> [StoredMonitorEvent] {
        let cutoff = now.addingTimeInterval(-TimeInterval(max(0, retentionDays)) * secondsPerDay)
        return events
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Status line

    /// What the 连接 card of 设置 shows.
    public enum MonitorStatusText: Equatable {
        case connected(secondsAgo: Int)
        case notQueried
        case unreachable(reason: String)
        case certificateChanged
        case apiKeyRejected

        /// Text of the status line, in the current language; `secondsAgo` is
        /// never negative.
        public var text: String {
            switch self {
            case .connected(let secondsAgo):
                return T(.monitorConnectedAgo, max(0, secondsAgo))
            case .notQueried:
                return T(.monitorNotQueried)
            case .unreachable(let reason):
                return reason
            case .certificateChanged:
                return T(.monitorCertificateChanged)
            case .apiKeyRejected:
                return T(.monitorAPIKeyRejected)
            }
        }
    }

    /// The status the 连接 card shows for one state of the engine.
    ///
    /// - Parameters:
    ///   - state: state of the last query.
    ///   - lastQueryAt: when the last round finished, `nil` before the first one.
    ///   - now: the current time.
    ///   - errorDescription: text of the last failure, used when the gateway is
    ///     unreachable.
    public static func statusText(
        state: GatewayConnectionState,
        lastQueryAt: Date?,
        now: Date,
        errorDescription: String?
    ) -> MonitorStatusText {
        switch state {
        case .certificateChanged:
            return .certificateChanged
        case .reconnecting:
            return .unreachable(reason: errorDescription ?? T(.connectionStateReconnecting))
        case .apiKeyRejected:
            return .apiKeyRejected
        case .connected:
            guard let lastQueryAt else { return .notQueried }
            return .connected(secondsAgo: Int(now.timeIntervalSince(lastQueryAt).rounded(.down)))
        }
    }

    /// The one-time notification of a gateway state change, or `nil`.
    ///
    /// The same state never notifies twice: the caller only asks when the state
    /// of the last round differs from the state before it.
    public static func stateChangeNotification(
        previous: GatewayConnectionState,
        current: GatewayConnectionState,
        address: String?,
        errorDescription: String?
    ) -> NotificationKind? {
        switch current {
        case .connected:
            // 已连接 is the state the app starts in, so only a real recovery
            // from a warned state is worth a notification.
            guard previous == .reconnecting || previous == .apiKeyRejected else { return nil }
            return .gatewayRestored
        case .reconnecting:
            let reason = errorDescription.map { T(.notificationReasonSuffix, $0) } ?? ""
            let target = address.map { T(.notificationUnreachableTarget, $0) }
                ?? T(.notificationUnreachableGateway)
            return .gatewayUnreachable(reason: target + reason)
        case .apiKeyRejected:
            return .apiKeyRejected
        case .certificateChanged:
            return .certificateChanged
        }
    }
}

/// One entry of the local monitoring log.
///
/// The local log keeps only the seven monitored events; client connect /
/// disconnect and firmware entries are never written. The whole gateway entry is
/// stored, so the 主窗口 can show the same text the UniFi log page shows. A
/// stored entry never carries an API Key: `SystemLogEntry` has no such field.
public struct StoredMonitorEvent: Codable, Equatable, Identifiable {
    /// The id of the gateway log entry, which is also the deduplication id.
    public let id: String
    /// The monitored event this entry belongs to.
    public let event: MonitoredEvent
    /// Entry time, the sort key of the log.
    public let timestamp: Date
    /// The gateway entry as it was received.
    public let entry: SystemLogEntry

    public init(id: String, event: MonitoredEvent, timestamp: Date, entry: SystemLogEntry) {
        self.id = id
        self.event = event
        self.timestamp = timestamp
        self.entry = entry
    }

    /// Builds a stored entry, or `nil` for an entry the app does not monitor.
    public init?(entry: SystemLogEntry) {
        guard let monitored = entry.monitoredLogEvent else { return nil }
        self.init(id: monitored.id, event: monitored.event, timestamp: monitored.timestamp, entry: entry)
    }

    /// The entry as the notification rules and the status file see it.
    public var monitoredLogEvent: MonitoredLogEvent? {
        MonitoredLogEvent(entry: entry)
    }
}

/// Reads and writes the local monitoring log.
///
/// The directory is the Application Support directory of the app (the container
/// path inside the sandbox). Three files live there: the monitored events, the
/// deduplication table and the time of the newest log entry the app read.
///
/// Every file is written atomically, so a crash never leaves a half-written
/// file. A file that does not exist, or that does not decode, counts as empty:
/// the app never crashes on a broken log. No file ever holds an API Key.
public struct MonitorLogStore {
    /// File names inside the directory.
    public enum FileName {
        /// The monitored events, pruned by the retention setting.
        public static let events = "monitor-events.json"
        /// The deduplication table, `SeenLogIDs`.
        public static let seenLogIDs = "seen-log-ids.json"
        /// The newest log timestamp the app read, with the failed-query count.
        public static let readState = "monitor-read-state.json"
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The monitored events file.
    public var eventsURL: URL { directory.appendingPathComponent(FileName.events) }

    /// The deduplication table file.
    public var seenLogIDsURL: URL { directory.appendingPathComponent(FileName.seenLogIDs) }

    /// The read state file.
    public var readStateURL: URL { directory.appendingPathComponent(FileName.readState) }

    /// The monitored events, oldest first; empty when the file is missing or broken.
    public func loadEvents() -> [StoredMonitorEvent] {
        guard let data = try? Data(contentsOf: eventsURL),
              let events = try? Self.decoder.decode([StoredMonitorEvent].self, from: data) else {
            return []
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    /// Writes the monitored events with an atomic write.
    public func saveEvents(_ events: [StoredMonitorEvent]) throws {
        try save(events, to: eventsURL)
    }

    /// The deduplication table, or an empty one when the file is missing or broken.
    public func loadSeenLogIDs() -> SeenLogIDs {
        guard let data = try? Data(contentsOf: seenLogIDsURL),
              let seen = try? Self.decoder.decode(SeenLogIDs.self, from: data) else {
            return SeenLogIDs()
        }
        return seen
    }

    /// Writes the deduplication table with an atomic write.
    public func saveSeenLogIDs(_ seenLogIDs: SeenLogIDs) throws {
        try save(seenLogIDs, to: seenLogIDsURL)
    }

    /// What the app remembers between two rounds.
    ///
    /// The reachability counter is part of it: a gateway that was already
    /// unreachable before a restart keeps its count instead of warning again.
    public func loadReadState() -> MonitorReadState {
        guard let data = try? Data(contentsOf: readStateURL),
              let state = try? Self.decoder.decode(MonitorReadState.self, from: data) else {
            return MonitorReadState()
        }
        return state
    }

    /// Writes the read state with an atomic write.
    public func saveReadState(_ state: MonitorReadState) throws {
        try save(state, to: readStateURL)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// ISO 8601 dates, so the log stays readable outside the app.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// What the app remembers between two monitoring rounds.
public struct MonitorReadState: Codable, Equatable {
    /// The newest log timestamp the app has read, or `nil` before the first round.
    public private(set) var lastReadAt: Date?
    /// State of the gateway as of the last round.
    public private(set) var reachability: GatewayReachability

    public init(
        lastReadAt: Date? = nil,
        reachability: GatewayReachability = GatewayReachability()
    ) {
        self.lastReadAt = lastReadAt
        self.reachability = reachability
    }

    /// The state the app shows, including a changed certificate.
    public var connectionState: GatewayConnectionState {
        reachability.isCertificateChanged ? .certificateChanged : reachability.state
    }

    /// Folds one query result in.
    ///
    /// A changed certificate is recorded as such: the app asks for a new
    /// 「测试连接」 instead of counting network failures.
    @discardableResult
    public mutating func recordQuery(succeeded: Bool, error: SentinelAPIError?) -> Bool {
        if succeeded {
            return reachability.record(GatewayProbe.success)
        }
        if error == .certificateChanged {
            return reachability.recordCertificateChanged()
        }
        guard let error else {
            return reachability.record(GatewayProbe.failure(.network(URLError(.unknown))))
        }
        return reachability.record(error: error)
    }

    /// Remembers the newest log timestamp of the round that just finished.
    public mutating func recordRead(at date: Date) {
        if let lastReadAt, lastReadAt > date { return }
        lastReadAt = date
    }

    /// Forgets the read time and the reachability, for a new gateway.
    public mutating func reset() {
        lastReadAt = nil
        reachability.reset()
    }

    private enum CodingKeys: String, CodingKey {
        case lastReadAt
        case reachability
    }

    /// Tolerant decoding: a file written by an older version still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastReadAt = (try? container.decodeIfPresent(Date.self, forKey: .lastReadAt)) ?? nil
        reachability = (try? container.decode(GatewayReachability.self, forKey: .reachability))
            ?? GatewayReachability()
    }
}

/// One notification the engine sends, in the words the user reads.
///
/// The type only carries text and a category: the API Key never appears here.
public enum NotificationKind: Equatable {
    /// A monitored log event, from `NotificationPlanner`.
    case monitorEvent(NotificationRecord)
    /// The one summary of a wake round with many new entries.
    case wakeSummary(MonitorLogSpec.WakeSummary)
    /// The gateway cannot be reached.
    case gatewayUnreachable(reason: String)
    /// The gateway answers again.
    case gatewayRestored
    /// HTTP 401 / 403: the API Key is wrong.
    case apiKeyRejected
    /// The presented certificate is not the pinned one.
    case certificateChanged

    /// Title of the notification, in the language of the moment it is sent.
    public var title: String {
        switch self {
        case .monitorEvent(let record):
            return record.title
        case .wakeSummary(let summary):
            return summary.title
        case .gatewayUnreachable:
            return T(.notificationGatewayUnreachableTitle)
        case .gatewayRestored:
            return T(.notificationGatewayRestoredTitle)
        case .apiKeyRejected:
            return T(.notificationAPIKeyRejectedTitle)
        case .certificateChanged:
            return T(.notificationCertificateChangedTitle)
        }
    }

    /// Body of the notification, without the API Key.
    public var body: String {
        switch self {
        case .monitorEvent(let record):
            return record.body
        case .wakeSummary(let summary):
            return summary.body
        case .gatewayUnreachable(let reason):
            return T(.notificationGatewayUnreachableBody, reason)
        case .gatewayRestored:
            return T(.notificationGatewayRestoredBody)
        case .apiKeyRejected:
            return T(.notificationAPIKeyRejectedBody)
        case .certificateChanged:
            return T(.notificationCertificateChangedBody)
        }
    }

    /// `true` for the notifications the merge rules already handled.
    public var isMonitorEvent: Bool {
        if case .monitorEvent = self { return true }
        return false
    }
}
