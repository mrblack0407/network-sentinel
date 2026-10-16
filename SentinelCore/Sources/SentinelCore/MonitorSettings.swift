import Foundation

/// What the app monitors and when it notifies.
///
/// The type is `Codable` and carries the defaults everywhere, so the app can
/// hand `JSONDecoder()` a value that was never written and still gets a usable
/// configuration. Time is never read here: the query interval and the retention
/// are plain values, and the caller decides how to use them.
public struct MonitorSettings: Codable, Equatable {
    /// Events that produce a notification.
    public var monitoredEvents: Set<MonitoredEvent>
    /// Notification rules: severity threshold, restore override, merging.
    public var notifications: NotificationSettings
    /// Seconds between two log queries. One of `queryIntervalOptions`.
    public var queryIntervalSeconds: Int
    /// Days of log history the app keeps around.
    public var logRetentionDays: Int

    /// Query intervals the app offers, in seconds.
    public static let queryIntervalOptions = [15, 30, 60]
    /// Log retention periods the app offers, in days.
    public static let logRetentionOptions = [30, 90, 180]

    public static let defaultQueryIntervalSeconds = 30
    public static let defaultLogRetentionDays = 90

    /// Events monitored unless the user changes them.
    public static let defaultMonitoredEvents: Set<MonitoredEvent> = [
        .internetDown,
        .internetRestored,
        .internetDownMultipleTimes,
        .threatDetected,
        .internetDownTemporary,
    ]

    /// Events that stay off unless the user turns them on.
    public static let defaultDisabledEvents: Set<MonitoredEvent> = [
        .packetLoss,
        .highLatency,
    ]

    public init(
        monitoredEvents: Set<MonitoredEvent> = MonitorSettings.defaultMonitoredEvents,
        notifications: NotificationSettings = NotificationSettings(),
        queryIntervalSeconds: Int = MonitorSettings.defaultQueryIntervalSeconds,
        logRetentionDays: Int = MonitorSettings.defaultLogRetentionDays
    ) {
        self.monitoredEvents = monitoredEvents
        self.notifications = notifications
        self.queryIntervalSeconds = queryIntervalSeconds
        self.logRetentionDays = logRetentionDays
    }

    /// `true` when the user wants notifications for this event.
    public func isEnabled(_ event: MonitoredEvent) -> Bool {
        monitoredEvents.contains(event)
    }

    /// Events the app does not monitor by default, in the order of `MonitoredEvent`.
    public static var disabledByDefault: [MonitoredEvent] {
        MonitoredEvent.allCases.filter { !defaultMonitoredEvents.contains($0) }
    }
}

/// How notifications are filtered and merged.
public struct NotificationSettings: Codable, Equatable {
    /// Only notifications at this severity or above are sent.
    public var minimumSeverity: LogSeverity
    /// Send 互联网已恢复 regardless of its severity.
    public var alwaysNotifyOnRestore: Bool
    /// Merge same-kind events of one time window into a single notification.
    public var mergeSameKind: Bool
    /// Length of the merge window in seconds; 10 minutes by default.
    public var mergeWindowSeconds: Int

    public static let defaultMinimumSeverity: LogSeverity = .high
    public static let defaultMergeWindowSeconds = 600
    /// `true` by default: a restore is important even when the gateway marks it low.
    public static let defaultAlwaysNotifyOnRestore = true

    public init(
        minimumSeverity: LogSeverity = NotificationSettings.defaultMinimumSeverity,
        alwaysNotifyOnRestore: Bool = NotificationSettings.defaultAlwaysNotifyOnRestore,
        mergeSameKind: Bool = true,
        mergeWindowSeconds: Int = NotificationSettings.defaultMergeWindowSeconds
    ) {
        self.minimumSeverity = minimumSeverity
        self.alwaysNotifyOnRestore = alwaysNotifyOnRestore
        self.mergeSameKind = mergeSameKind
        self.mergeWindowSeconds = mergeWindowSeconds
    }

    /// The merge window as a `TimeInterval`.
    public var mergeWindow: TimeInterval {
        TimeInterval(max(0, mergeWindowSeconds))
    }

    /// `true` when a notification of this severity may be sent for this event.
    ///
    /// A restore bypasses the threshold while `alwaysNotifyOnRestore` is on.
    /// An unknown severity is treated as 低.
    public func passesThreshold(_ severity: LogSeverity?, for event: MonitoredEvent) -> Bool {
        if event == .internetRestored, alwaysNotifyOnRestore {
            return true
        }
        return Self.effectiveSeverity(severity) >= minimumSeverity
    }

    /// Severity used for the threshold: an unknown severity counts as 低.
    public static func effectiveSeverity(_ severity: LogSeverity?) -> LogSeverity {
        severity ?? .low
    }

    private enum CodingKeys: String, CodingKey {
        case minimumSeverity
        case alwaysNotifyOnRestore
        case mergeSameKind
        case mergeWindowSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumSeverity = (try? container.decodeIfPresent(LogSeverity.self, forKey: .minimumSeverity)) ?? nil
            ?? Self.defaultMinimumSeverity
        alwaysNotifyOnRestore = (try? container.decodeIfPresent(Bool.self, forKey: .alwaysNotifyOnRestore)) ?? nil
            ?? Self.defaultAlwaysNotifyOnRestore
        mergeSameKind = (try? container.decodeIfPresent(Bool.self, forKey: .mergeSameKind)) ?? nil
            ?? true
        mergeWindowSeconds = (try? container.decodeIfPresent(Int.self, forKey: .mergeWindowSeconds)) ?? nil
            ?? Self.defaultMergeWindowSeconds
    }
}

extension MonitorSettings {
    private enum CodingKeys: String, CodingKey {
        case monitoredEvents
        case notifications
        case queryIntervalSeconds
        case logRetentionDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitoredEvents = (try? container.decodeIfPresent(Set<MonitoredEvent>.self, forKey: .monitoredEvents)) ?? nil
            ?? Self.defaultMonitoredEvents
        notifications = (try? container.decodeIfPresent(NotificationSettings.self, forKey: .notifications)) ?? nil
            ?? NotificationSettings()
        queryIntervalSeconds = (try? container.decodeIfPresent(Int.self, forKey: .queryIntervalSeconds)) ?? nil
            ?? Self.defaultQueryIntervalSeconds
        logRetentionDays = (try? container.decodeIfPresent(Int.self, forKey: .logRetentionDays)) ?? nil
            ?? Self.defaultLogRetentionDays
    }
}
