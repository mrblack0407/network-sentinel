import Foundation

/// One internet outage of one WAN interface.
///
/// Built by pairing a 互联网中断 entry with the 互联网已恢复 entry that follows
/// it on the same line. `end` stays `nil` while no restore was seen, so the
/// outage is still open.
public struct Outage: Equatable, Identifiable {
    /// The 互联网中断 entry.
    public let startLogID: String
    /// The 互联网已恢复 entry, or `nil` while the outage is open.
    public let endLogID: String?
    /// `WAN1` / `WAN2`, or `nil` when the gateway logged no line.
    public let wanID: String?
    public let ispName: String?
    public let start: Date
    public let end: Date?
    /// `DURATION` of the restore entry when it was readable.
    public let durationSeconds: Int?

    public init(
        startLogID: String,
        endLogID: String?,
        wanID: String?,
        ispName: String?,
        start: Date,
        end: Date?,
        durationSeconds: Int?
    ) {
        self.startLogID = startLogID
        self.endLogID = endLogID
        self.wanID = wanID
        self.ispName = ispName
        self.start = start
        self.end = end
        self.durationSeconds = durationSeconds
    }

    /// A stable id for lists: the id of the 互联网中断 entry.
    public var id: String { startLogID }

    /// `true` while no restore was seen.
    public var isOngoing: Bool { end == nil }

    /// Length in seconds: `DURATION` of the restore entry first, otherwise
    /// `end - start`. `nil` while the outage is open.
    public var duration: TimeInterval? {
        if let durationSeconds {
            return TimeInterval(max(0, durationSeconds))
        }
        guard let end else { return nil }
        return max(0, end.timeIntervalSince(start))
    }

    /// Length rounded to whole seconds, for the Chinese duration text.
    public var durationWholeSeconds: Int? {
        guard let duration else { return nil }
        return Int(duration.rounded())
    }

    /// `DURATION` in its Chinese form, or `nil` while the outage is open.
    public var durationText: String? {
        durationWholeSeconds.map(ChineseDuration.text(seconds:))
    }

    /// `true` when the date falls inside this outage, open end included.
    public func contains(_ date: Date) -> Bool {
        guard date >= start else { return false }
        guard let end else { return true }
        return date <= end
    }
}

/// Pairs 互联网中断 with the following 互联网已恢复 entry of the same line.
///
/// The log pages arrive newest first, so everything is sorted by timestamp
/// first. Lines are paired independently: a `WAN2` restore can never close a
/// `WAN1` outage. A 互联网中断 entry that is not followed by a restore stays
/// open instead of being paired with a later outage's restore.
public enum OutagePairer {
    /// All outages of the batch, oldest first.
    public static func outages(in events: [MonitoredLogEvent]) -> [Outage] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var downByLine: [String: [MonitoredLogEvent]] = [:]
        var outages: [Outage] = []

        for event in sorted {
            let line = lineKey(event.wanID)

            switch event.event {
            case .internetDown:
                downByLine[line, default: []].append(event)
            case .internetRestored:
                // Without a pending 互联网中断 the restore has nothing to close.
                guard var pending = downByLine[line], !pending.isEmpty else { continue }
                let down = pending.removeFirst()
                downByLine[line] = pending
                outages.append(pair(down: down, restore: event))
            default:
                continue
            }
        }

        // Whatever is left never saw a restore and is still open.
        for (_, pending) in downByLine {
            outages.append(contentsOf: pending.map { pair(down: $0, restore: nil) })
        }

        return outages.sorted { $0.start < $1.start }
    }

    /// All outages of a batch of log entries, oldest first.
    public static func outages(in entries: [SystemLogEntry]) -> [Outage] {
        outages(in: SystemLogEntry.monitoredLogEvents(in: entries))
    }

    /// The open outage of one line, or `nil` when the line is up.
    ///
    /// `wanID` of `nil` matches outages that carried no line.
    public static func ongoingOutage(forWAN wanID: String?, in outages: [Outage]) -> Outage? {
        let line = lineKey(wanID)
        return outages
            .filter { $0.isOngoing && lineKey($0.wanID) == line }
            .max { $0.start < $1.start }
    }

    /// The outage that contains the date, the open one included, or `nil`.
    public static func outage(containing date: Date, in outages: [Outage]) -> Outage? {
        outages
            .filter { $0.contains(date) }
            .max { $0.start < $1.start }
    }

    private static func pair(down: MonitoredLogEvent, restore: MonitoredLogEvent?) -> Outage {
        let end = restore?.timestamp
        // The gateway's own DURATION is preferred over the timestamps, which
        // differ by the logging delay of the two entries.
        let durationSeconds: Int?
        if let restore, let reported = restore.durationSeconds {
            durationSeconds = max(0, reported)
        } else if let end {
            durationSeconds = Int(max(0, end.timeIntervalSince(down.timestamp)).rounded())
        } else {
            durationSeconds = nil
        }

        return Outage(
            startLogID: down.id,
            endLogID: restore?.id,
            wanID: down.wanID ?? restore?.wanID,
            ispName: down.ispName ?? restore?.ispName,
            start: down.timestamp,
            end: end,
            durationSeconds: durationSeconds
        )
    }

    /// Key of a line: entries without a `WAN_ID` share one bucket.
    private static func lineKey(_ wanID: String?) -> String {
        wanID ?? ""
    }
}
