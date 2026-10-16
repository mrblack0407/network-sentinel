import Foundation

/// One notification the app is about to show.
///
/// A record carries the event, the severity, the line and the time of the whole
/// merged group, so the app can store it and hand it back on the next query to
/// merge with. `mergedCount` is 1 for a notification that stands alone.
public struct NotificationRecord: Codable, Equatable, Identifiable {
    public let event: MonitoredEvent
    public let severity: LogSeverity
    /// `WAN1` / `WAN2`, or `nil` for events without a line.
    public let wanID: String?
    public let title: String
    /// Body last line first; merged groups append the "N 条" line.
    public let body: String
    /// Ids of the log entries this notification covers, oldest first.
    public let logIDs: [String]
    /// Time of the newest log entry of the group.
    public let timestamp: Date
    /// How many entries were merged into this notification.
    public let mergedCount: Int

    public init(
        event: MonitoredEvent,
        severity: LogSeverity,
        wanID: String?,
        title: String,
        body: String,
        logIDs: [String],
        timestamp: Date,
        mergedCount: Int
    ) {
        self.event = event
        self.severity = severity
        self.wanID = wanID
        self.title = title
        self.body = body
        self.logIDs = logIDs
        self.timestamp = timestamp
        self.mergedCount = max(1, mergedCount)
    }

    /// Stable id of the group: its first log entry.
    public var id: String { logIDs.first ?? "\(event.rawValue)-\(timestamp.timeIntervalSince1970)" }

    /// `true` when this record covers more than one log entry.
    public var isMerged: Bool { mergedCount > 1 }

    /// This record folded under a newer one of the same kind.
    public func merging(_ newer: SystemLogEntry) -> NotificationRecord {
        NotificationRecord(
            event: event,
            severity: severity,
            wanID: wanID,
            title: title,
            body: body,
            logIDs: logIDs,
            timestamp: newer.timestamp,
            mergedCount: mergedCount + 1
        )
    }
}

/// What one query produces: what to show, and what to remember.
public struct NotificationPlan: Equatable {
    /// Notifications to show, oldest group first.
    public let notifications: [NotificationRecord]
    /// `notifications` plus the groups that only grew inside this query.
    ///
    /// A group that was already notified less than the merge window ago is not
    /// sent again; its record is still here so the caller keeps the count.
    public let records: [NotificationRecord]
    /// Ids of the entries that were folded into another notification.
    public let mergedLogIDs: [String]
    /// Number of new entries whose event is switched off or below the threshold.
    public let filteredOutCount: Int

    public init(
        notifications: [NotificationRecord] = [],
        records: [NotificationRecord] = [],
        mergedLogIDs: [String] = [],
        filteredOutCount: Int = 0
    ) {
        self.notifications = notifications
        self.records = records
        self.mergedLogIDs = mergedLogIDs
        self.filteredOutCount = filteredOutCount
    }

    /// Notifications to show this query. Same as `notifications`.
    public var notificationsToSend: [NotificationRecord] { notifications }

    /// `true` when there is nothing to show.
    public var isEmpty: Bool { notifications.isEmpty }
}

/// Turns the new log entries of one query into notifications.
///
/// The planner is pure: it reads the settings, the injected "now" and the
/// records the app already sent, and returns what to show. Entries whose event
/// is off, or whose severity is below the threshold, are dropped. Entries of
/// the same kind (and the same line for WAN events) inside the merge window
/// become one notification.
public struct NotificationPlanner {
    public init() {}

    /// Plans the notifications of a batch of new entries.
    ///
    /// - Parameters:
    ///   - entries: entries that passed `SeenLogIDs`, in any order.
    ///   - settings: monitored events and notification rules.
    ///   - now: current time, injected so tests never read the clock.
    ///   - recentRecords: records already notified, used for merging.
    public func plan(
        entries: [SystemLogEntry],
        settings: MonitorSettings,
        now: Date,
        recentRecords: [NotificationRecord] = []
    ) -> NotificationPlan {
        let candidates = entries
            .compactMap { $0.monitoredLogEvent }
            .sorted { $0.timestamp < $1.timestamp }

        var filteredOutCount = 0
        var groups: [MergedGroup] = []
        /// Ids of the entries that entered a group, in order.
        var mergedLogIDs: [String] = []

        for candidate in candidates {
            guard settings.isEnabled(candidate.event) else {
                filteredOutCount += 1
                continue
            }
            guard settings.notifications.passesThreshold(candidate.severity, for: candidate.event) else {
                filteredOutCount += 1
                continue
            }

            let severity = NotificationSettings.effectiveSeverity(candidate.severity)
            // The merge switch covers both the entries of this query and the
            // records of the previous ones.
            let allowsMerging = settings.notifications.mergeSameKind

            if allowsMerging, let index = existingGroupIndex(
                for: candidate,
                in: groups,
                window: settings.notifications.mergeWindowSeconds
            ) {
                groups[index].add(
                    candidate,
                    severity: severity,
                    body: notificationBody(for: candidate)
                )
                mergedLogIDs.append(candidate.id)
                continue
            }

            if allowsMerging, let index = recentGroupIndex(
                for: candidate,
                in: recentRecords,
                now: now,
                window: settings.notifications.mergeWindowSeconds
            ) {
                groups.append(
                    MergedGroup(
                        event: candidate.event,
                        wanID: keyLine(candidate),
                        severity: severity,
                        newestBody: notificationBody(for: candidate),
                        newestTimestamp: candidate.timestamp,
                        logIDs: recentRecords[index].logIDs + [candidate.id],
                        mergedCount: recentRecords[index].mergedCount + 1,
                        wasNotified: true
                    )
                )
                mergedLogIDs.append(candidate.id)
                continue
            }

            groups.append(
                MergedGroup(
                    event: candidate.event,
                    wanID: keyLine(candidate),
                    severity: severity,
                    newestBody: notificationBody(for: candidate),
                    newestTimestamp: candidate.timestamp,
                    logIDs: [candidate.id],
                    mergedCount: 1,
                    wasNotified: false
                )
            )
        }

        let records = groups.map(\.record)
        let notifications = groups.filter { !$0.wasNotified }.map(\.record)

        // Entries that grew an existing group, sorted back into log order.
        let foldedLogIDs = mergedLogIDs.sorted { $0 < $1 }

        return NotificationPlan(
            notifications: notifications,
            records: records,
            mergedLogIDs: foldedLogIDs,
            filteredOutCount: filteredOutCount
        )
    }

    /// Title of a notification: event name, a space, then the severity squares.
    public func title(for event: MonitoredEvent, severity: LogSeverity) -> String {
        "\(event.displayName) \(severity.squares)"
    }

    /// Body of one monitored entry, in Chinese.
    ///
    /// The leading line comes from the event's parameters; a merged group adds
    /// its own count line on top of this.
    public func notificationBody(for event: MonitoredLogEvent) -> String {
        switch event.event {
        case .internetDown:
            return "\(lineText(event)) 已断开。"

        case .internetRestored:
            let duration = event.durationSeconds.map(ChineseDuration.text(seconds:))
                ?? event.durationText
                ?? "未知"
            return "\(lineText(event)) 已恢复，断网 \(duration)。"

        case .internetDownMultipleTimes:
            return "\(lineText(event)) 在过去 24 小时内多次中断。"

        case .internetDownTemporary:
            let duration = event.durationSeconds.map(ChineseDuration.text(seconds:))
                ?? event.durationText
                ?? "未知"
            return "\(lineText(event)) 临时中断后已恢复，断开 \(duration)。"

        case .packetLoss:
            return "\(lineText(event)) 检测到丢包。"

        case .highLatency:
            let latency = event.latencyMilliseconds.map(String.init) ?? "未知"
            return "\(lineText(event)) 延迟升高到 \(latency) ms。"

        case .threatDetected:
            // The gateway names the source and the destination from either a
            // client or a raw address; a missing one is shown as 未知.
            let source = event.source?.value ?? "未知"
            let destination = event.destination?.value ?? "未知"
            return "来自 \(source) 到 \(destination) 的入侵尝试。"
        }
    }

    /// `WAN1 (China Telecom)`, or `WAN1` when the gateway sent no provider.
    private func lineText(_ event: MonitoredLogEvent) -> String {
        let line = event.wanID ?? "未知线路"
        if let isp = event.ispName, !isp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(line) (\(isp))"
        }
        return line
    }

    /// Merge key of an event: its kind, plus the line for WAN events.
    ///
    /// 互联网中断 and 互联网已恢复 are different kinds, so they never merge
    /// with each other.
    private func mergeKey(event: MonitoredEvent, wanID: String?) -> String {
        switch event {
        case .internetDown,
             .internetRestored,
             .internetDownMultipleTimes,
             .internetDownTemporary,
             .packetLoss,
             .highLatency:
            return "\(event.rawValue)|\(wanID ?? "")"
        case .threatDetected:
            return event.rawValue
        }
    }

    private func keyLine(_ event: MonitoredLogEvent) -> String? {
        switch event.event {
        case .threatDetected:
            return nil
        default:
            return event.wanID
        }
    }

    private func existingGroupIndex(
        for event: MonitoredLogEvent,
        in groups: [MergedGroup],
        window: Int
    ) -> Int? {
        let key = mergeKey(event: event.event, wanID: keyLine(event))
        return groups.lastIndex { group in
            group.key == key && withinWindow(group.newestTimestamp, event.timestamp, window: window)
        }
    }

    private func recentGroupIndex(
        for event: MonitoredLogEvent,
        in records: [NotificationRecord],
        now: Date,
        window: Int
    ) -> Int? {
        let key = mergeKey(event: event.event, wanID: keyLine(event))
        return records.lastIndex { record in
            mergeKey(event: record.event, wanID: record.wanID) == key
                && withinWindow(record.timestamp, now, window: window)
                && withinWindow(record.timestamp, event.timestamp, window: window)
        }
    }

    /// `true` when both dates are inside one merge window of each other.
    private func withinWindow(_ first: Date, _ second: Date, window: Int) -> Bool {
        abs(second.timeIntervalSince(first)) <= TimeInterval(max(0, window))
    }

    /// One group under construction.
    private struct MergedGroup {
        let key: String
        let event: MonitoredEvent
        let wanID: String?
        var severity: LogSeverity
        /// Body of the newest entry of the group.
        var newestBody: String
        var newestTimestamp: Date
        var logIDs: [String]
        var mergedCount: Int
        /// `true` when the group only grew out of an already notified record.
        let wasNotified: Bool

        init(
            event: MonitoredEvent,
            wanID: String?,
            severity: LogSeverity,
            newestBody: String,
            newestTimestamp: Date,
            logIDs: [String],
            mergedCount: Int,
            wasNotified: Bool
        ) {
            self.key = "\(event.rawValue)|\(wanID ?? "")"
            self.event = event
            self.wanID = wanID
            self.severity = severity
            self.newestBody = newestBody
            self.newestTimestamp = newestTimestamp
            self.logIDs = logIDs
            self.mergedCount = mergedCount
            self.wasNotified = wasNotified
        }

        /// Folds a newer entry into the group: its body wins, the severity is
        /// the highest of the group.
        mutating func add(_ event: MonitoredLogEvent, severity: LogSeverity, body: String) {
            self.severity = max(self.severity, severity)
            newestBody = body
            logIDs.append(event.id)
            mergedCount += 1
            newestTimestamp = max(newestTimestamp, event.timestamp)
        }

        /// The group as a record. A single entry keeps its own body, a merged
        /// group appends the count line.
        var record: NotificationRecord {
            NotificationRecord(
                event: event,
                severity: severity,
                wanID: wanID,
                title: "\(event.displayName) \(severity.squares)",
                body: MergedGroup.body(newestBody, mergedCount: mergedCount),
                logIDs: logIDs,
                timestamp: newestTimestamp,
                mergedCount: mergedCount
            )
        }

        static func body(_ body: String, mergedCount: Int) -> String {
            guard mergedCount > 1 else { return body }
            return "\(body)\n\(countLine(mergedCount))"
        }

        static func countLine(_ count: Int) -> String {
            "10 分钟内同类 \(count) 条。"
        }
    }
}

extension MonitoredEvent {
    /// Title of a notification for this event at a severity: name plus squares.
    public func notificationTitle(severity: LogSeverity) -> String {
        "\(displayName) \(severity.squares)"
    }
}

extension LogSeverity {
    /// Severity squares used in notification titles.
    public var squares: String {
        switch self {
        case .low: return "🟩⬛⬛⬛"
        case .medium: return "🟨🟨⬛⬛"
        case .high: return "🟧🟧🟧⬛"
        case .veryHigh: return "🟥🟥🟥🟥"
        }
    }
}
