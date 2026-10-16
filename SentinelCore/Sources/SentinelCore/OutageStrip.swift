import Foundation

/// State of one half-hour cell of the 过去 24 小时 色条 of a 概览 线路卡片.
public enum OutageStripState: String, CaseIterable {
    /// No outage inside the half hour.
    case normal
    /// Only a 临时互联网中断: the line came back by itself.
    case temporary
    /// 互联网中断, from a log entry or from a paired outage covering the cell.
    case down

    /// Chinese name, for the tests and the read-out.
    public var displayName: String {
        switch self {
        case .normal: return "正常"
        case .temporary: return "临时中断"
        case .down: return "中断"
        }
    }
}

/// One half-hour cell of the strip. The last cell of a strip is 「现在」.
public struct OutageStripCell: Equatable, Identifiable {
    /// `0` is the oldest cell, `OutageStripBuilder.cellCount - 1` is 「现在」.
    public let index: Int
    /// Start of the half hour, inclusive.
    public let start: Date
    /// End of the half hour; the end of the last cell is 「现在」.
    public let end: Date
    public let state: OutageStripState

    public init(index: Int, start: Date, end: Date, state: OutageStripState) {
        self.index = index
        self.start = start
        self.end = end
        self.state = state
    }

    public var id: Int { index }

    /// `true` for the rightmost cell, the one that ends at 「现在」.
    public var isCurrent: Bool { index == OutageStripBuilder.cellCount - 1 }
}

/// The 过去 24 小时 色条 of one 线路卡片.
public struct OutageStrip: Equatable {
    /// Cells of a strip: 48 half hours.
    public static let cellCount = OutageStripBuilder.cellCount
    /// Length of one cell in seconds.
    public static let cellInterval = OutageStripBuilder.cellInterval

    /// Oldest first; the last cell ends at 「现在」.
    public let cells: [OutageStripCell]
    /// Outages of the line that overlap the window, as the 24 小时中断 column counts them.
    public let outageCount: Int
    /// 临时互联网中断 entries inside the window.
    public let temporaryCount: Int
    /// Start of the window, 24 hours before 「现在」.
    public let start: Date
    /// 「现在」, the end of the last cell.
    public let end: Date

    public init(
        cells: [OutageStripCell],
        outageCount: Int,
        temporaryCount: Int,
        start: Date,
        end: Date
    ) {
        self.cells = cells
        self.outageCount = max(0, outageCount)
        self.temporaryCount = max(0, temporaryCount)
        self.start = start
        self.end = end
    }

    /// Read-out of the strip, for example 「过去 24 小时中断 4 次」.
    public var accessibilityText: String {
        var parts = ["过去 24 小时中断 \(outageCount) 次"]
        if temporaryCount > 0 {
            parts.append("临时中断 \(temporaryCount) 次")
        }
        return parts.joined(separator: "，")
    }
}

/// Builds the 过去 24 小时 色条 of one WAN line.
///
/// Pure: the events, the paired outages and the clock all come in as values, so
/// the page stays a thin shell and the cell rules are tested without a gateway.
public enum OutageStripBuilder {
    /// Cells of a strip: 48 half hours.
    public static let cellCount = 48
    /// Length of one cell, half an hour.
    public static let cellInterval: TimeInterval = 30 * 60

    /// The strip of one line, oldest cell first.
    ///
    /// - Parameters:
    ///   - events: the local log, in any order.
    ///   - outages: the outages paired from those events.
    ///   - wanID: the line to draw; `nil` matches the entries that carried no line.
    ///   - now: the current time, the end of the last cell.
    public static func strip(
        events: [MonitoredLogEvent],
        outages: [Outage],
        wanID: String?,
        now: Date
    ) -> OutageStrip {
        let windowStart = now.addingTimeInterval(-TimeInterval(cellCount) * cellInterval)
        let key = WANLineKey.of(wanID)
        let lineEvents = events.filter { WANLineKey.of($0.wanID) == key }
        let lineOutages = WANLineStatisticsBuilder.overlappingOutages(outages, wanID: wanID, now: now)

        let cells = (0..<cellCount).map { index -> OutageStripCell in
            let start = windowStart.addingTimeInterval(TimeInterval(index) * cellInterval)
            let end = start.addingTimeInterval(cellInterval)
            let isCurrent = index == cellCount - 1

            return OutageStripCell(
                index: index,
                start: start,
                end: end,
                state: state(
                    start: start,
                    end: end,
                    isCurrent: isCurrent,
                    events: lineEvents,
                    outages: lineOutages,
                    now: now
                )
            )
        }

        let temporaryCount = lineEvents.filter {
            $0.event == .internetDownTemporary && $0.timestamp >= windowStart && $0.timestamp <= now
        }.count

        return OutageStrip(
            cells: cells,
            outageCount: lineOutages.count,
            temporaryCount: temporaryCount,
            start: windowStart,
            end: now
        )
    }

    /// The state of one cell: 中断 wins over 临时中断, which wins over 正常.
    private static func state(
        start: Date,
        end: Date,
        isCurrent: Bool,
        events: [MonitoredLogEvent],
        outages: [Outage],
        now: Date
    ) -> OutageStripState {
        let isInside = { (date: Date) in
            contains(date: date, start: start, end: end, isCurrent: isCurrent)
        }

        let hasDown = events.contains { $0.event == .internetDown && isInside($0.timestamp) }
        if hasDown { return .down }

        // A paired outage colors every cell it covers, so a 断网 that spans
        // several half hours paints all of them, not only its first entry.
        let isCovered = outages.contains { outage in
            let outageEnd = outage.end ?? now
            let startsInsideCell = isCurrent ? outage.start <= end : outage.start < end
            return startsInsideCell && outageEnd > start
        }
        if isCovered { return .down }

        let hasTemporary = events.contains {
            $0.event == .internetDownTemporary && isInside($0.timestamp)
        }
        return hasTemporary ? .temporary : .normal
    }

    /// `true` when the date falls in the cell.
    ///
    /// All cells are half-open `[start, end)`, except 「现在」: the last cell also
    /// holds an entry stamped exactly `now`.
    private static func contains(date: Date, start: Date, end: Date, isCurrent: Bool) -> Bool {
        guard date >= start else { return false }
        return isCurrent ? date <= end : date < end
    }
}
