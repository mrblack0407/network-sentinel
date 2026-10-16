import Foundation

/// Time range of the 全部日志 page: 1 天 / 7 天 / 30 天.
public enum LogTimeRange: String, CaseIterable, Identifiable {
    case day1
    case day7
    case day30

    public var id: String { rawValue }

    /// Chinese name of the segmented control.
    public var title: String {
        switch self {
        case .day1: return "1 天"
        case .day7: return "7 天"
        case .day30: return "30 天"
        }
    }

    /// Days the range reaches back.
    public var days: Int {
        switch self {
        case .day1: return 1
        case .day7: return 7
        case .day30: return 30
        }
    }

    /// The range as an interval, for the window ending at 「现在」.
    public var interval: TimeInterval {
        TimeInterval(days) * MonitorLogSpec.secondsPerDay
    }
}

/// Kind of event the 全部日志 page shows: 全部 / 网络 / 威胁.
public enum LogCategory: String, CaseIterable, Identifiable {
    case all
    case network
    case threat

    public var id: String { rawValue }

    /// Chinese name of the segmented control.
    public var title: String {
        switch self {
        case .all: return "全部"
        case .network: return "网络"
        case .threat: return "威胁"
        }
    }

    /// `true` when the event is shown with this filter.
    ///
    /// 网络 is the six monitored events that are not 检测到威胁.
    public func includes(_ event: MonitoredEvent) -> Bool {
        switch self {
        case .all: return true
        case .network: return event != .threatDetected
        case .threat: return event == .threatDetected
        }
    }
}

/// The three filters of the 全部日志 page.
///
/// Pure: the window ends at the injected `now`, and an unknown severity counts
/// as 低 like everywhere else.
public struct LogFilter: Equatable {
    public var timeRange: LogTimeRange
    public var category: LogCategory
    /// The lowest severity that still shows; 低 shows everything.
    public var minimumSeverity: LogSeverity

    public init(
        timeRange: LogTimeRange = .day7,
        category: LogCategory = .all,
        minimumSeverity: LogSeverity = .low
    ) {
        self.timeRange = timeRange
        self.category = category
        self.minimumSeverity = minimumSeverity
    }

    /// `true` when the entry passes all three filters.
    public func includes(_ event: MonitoredLogEvent, now: Date) -> Bool {
        let windowStart = now.addingTimeInterval(-timeRange.interval)
        guard event.timestamp >= windowStart, event.timestamp <= now else { return false }
        guard category.includes(event.event) else { return false }
        return NotificationSettings.effectiveSeverity(event.severity) >= minimumSeverity
    }

    /// The entries that pass the filters, newest first.
    public func apply(to events: [MonitoredLogEvent], now: Date) -> [MonitoredLogEvent] {
        events
            .filter { includes($0, now: now) }
            .sorted { $0.timestamp > $1.timestamp }
    }
}

/// One item of the page number row: a page, or the 「…」 between two of them.
public enum LogPageItem: Equatable, Identifiable {
    case page(Int)
    /// The gap before the given page number.
    case ellipsis(Int)

    public var id: String {
        switch self {
        case .page(let number): return "page-\(number)"
        case .ellipsis(let number): return "ellipsis-\(number)"
        }
    }

    /// The page number of a page item, `nil` for an ellipsis.
    public var pageNumber: Int? {
        if case .page(let number) = self { return number }
        return nil
    }
}

/// The page of the 全部日志 table: 25 entries per page.
///
/// Pure arithmetic: the caller hands in the number of entries of the current
/// filter and the page it wants, and reads the range text and the page numbers
/// back. The page number is clamped, so a filter that shrinks cannot leave the
/// table on a page that no longer exists.
public struct LogPagination: Equatable {
    /// Entries on one page, as in the mockup.
    public static let defaultPageSize = 25
    /// Below this number of pages every page number is shown as it is.
    public static let allPagesThreshold = 7

    /// Entries the current filter found.
    public let totalCount: Int
    public let pageSize: Int
    /// Pages the current filter has; never below one.
    public let pageCount: Int
    /// Current page, 1-based and clamped to the pages that exist.
    public let currentPage: Int

    public init(
        totalCount: Int,
        pageSize: Int = LogPagination.defaultPageSize,
        currentPage: Int = 1
    ) {
        let count = max(0, totalCount)
        let size = max(1, pageSize)
        let pages = max(1, Int((Double(count) / Double(size)).rounded(.up)))

        self.totalCount = count
        self.pageSize = size
        self.pageCount = pages
        self.currentPage = min(max(1, currentPage), pages)
    }

    /// `第 1–25 条，共 126 条`, or `共 0 条` when the filter found nothing.
    public var rangeText: String {
        guard totalCount > 0 else { return "共 0 条" }
        let first = (currentPage - 1) * pageSize + 1
        let last = min(totalCount, currentPage * pageSize)
        return "第 \(first)–\(last) 条，共 \(totalCount) 条"
    }

    /// The entries of the current page, in the order they came in.
    public func page<T>(of items: [T]) -> [T] {
        guard !items.isEmpty else { return [] }
        let lower = min(items.count, (currentPage - 1) * pageSize)
        let upper = min(items.count, lower + pageSize)
        return Array(items[lower..<upper])
    }

    /// The page numbers of the pager, with 「…」 where numbers are left out.
    ///
    /// The first and the last page are always there, plus the pages around the
    /// current one, so a log with hundreds of pages never draws a long row of
    /// buttons.
    public var pageItems: [LogPageItem] {
        guard pageCount > Self.allPagesThreshold else {
            return (1...pageCount).map { LogPageItem.page($0) }
        }

        var numbers: Set<Int> = [1, pageCount, currentPage]
        for delta in -1...1 {
            numbers.insert(currentPage + delta)
        }
        // Near either end the window grows inwards, so the first pages of a long
        // log are all reachable with one click.
        if currentPage <= 4 {
            numbers.formUnion(2...5)
        }
        if currentPage >= pageCount - 3 {
            numbers.formUnion((pageCount - 4)...(pageCount - 1))
        }

        let sorted = numbers.filter { $0 >= 1 && $0 <= pageCount }.sorted()
        var items: [LogPageItem] = []
        for (offset, number) in sorted.enumerated() {
            if offset > 0, number - sorted[offset - 1] > 1 {
                items.append(.ellipsis(number))
            }
            items.append(.page(number))
        }
        return items
    }
}
