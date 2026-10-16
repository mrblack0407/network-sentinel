import XCTest
@testable import SentinelCore

/// The pager of the 日志 table: 25 entries per page.
final class LogPaginationTests: XCTestCase {
    func testOneHundredAndTwentySixEntriesMakeSixPages() {
        let pagination = LogPagination(totalCount: 126)

        XCTAssertEqual(pagination.pageSize, 25)
        XCTAssertEqual(pagination.pageCount, 6)
        XCTAssertEqual(pagination.currentPage, 1)
    }

    func testTheRangeTextOfTheFirstPage() {
        XCTAssertEqual(LogPagination(totalCount: 126).rangeText, "第 1–25 条，共 126 条")
    }

    func testTheRangeTextOfAMiddlePage() {
        XCTAssertEqual(LogPagination(totalCount: 126, currentPage: 2).rangeText, "第 26–50 条，共 126 条")
        XCTAssertEqual(LogPagination(totalCount: 126, currentPage: 5).rangeText, "第 101–125 条，共 126 条")
    }

    func testTheRangeTextOfTheLastPageStopsAtTheTotal() {
        XCTAssertEqual(LogPagination(totalCount: 126, currentPage: 6).rangeText, "第 126–126 条，共 126 条")
    }

    func testAnEmptyLogHasOneEmptyPage() {
        let pagination = LogPagination(totalCount: 0)

        XCTAssertEqual(pagination.pageCount, 1)
        XCTAssertEqual(pagination.currentPage, 1)
        XCTAssertEqual(pagination.rangeText, "共 0 条")
        XCTAssertEqual(pagination.pageItems, [.page(1)])
    }

    func testTheCurrentPageIsClamped() {
        XCTAssertEqual(LogPagination(totalCount: 126, currentPage: 99).currentPage, 6)
        XCTAssertEqual(LogPagination(totalCount: 126, currentPage: 0).currentPage, 1)
        XCTAssertEqual(LogPagination(totalCount: 126, currentPage: -3).currentPage, 1)
    }

    func testThePageHoldsAtMostTwentyFiveEntries() {
        let items = Array(0..<126)
        let pagination = LogPagination(totalCount: items.count, currentPage: 2)

        let page = pagination.page(of: items)

        XCTAssertEqual(page.count, 25)
        XCTAssertEqual(page.first, 25)
        XCTAssertEqual(page.last, 49)
    }

    func testTheLastPageHoldsWhatIsLeft() {
        let items = Array(0..<126)

        let page = LogPagination(totalCount: items.count, currentPage: 6).page(of: items)

        XCTAssertEqual(page, [125])
    }

    func testAPageOfAnEmptyLogIsEmpty() {
        XCTAssertTrue(LogPagination(totalCount: 0).page(of: [Int]()).isEmpty)
    }

    // MARK: - Page numbers

    func testAShortLogShowsEveryPageNumber() {
        XCTAssertEqual(
            LogPagination(totalCount: 126).pageItems,
            [.page(1), .page(2), .page(3), .page(4), .page(5), .page(6)]
        )
    }

    func testNinePagesShowEveryNumber() {
        let pagination = LogPagination(totalCount: 9 * 25, currentPage: 5)
        XCTAssertEqual(pagination.pageItems, (1...9).map { LogPageItem.page($0) })
    }

    func testTheStartOfALongLogShowsTheFirstFiveAndTheLastTwo() {
        for page in 1...4 {
            XCTAssertEqual(
                LogPagination(totalCount: 10 * 25, currentPage: page).pageItems,
                [.page(1), .page(2), .page(3), .page(4), .page(5), .ellipsis(9), .page(9), .page(10)],
                "page \(page)"
            )
        }
    }

    func testTheMiddleOfALongLogShowsTheCurrentBlock() {
        XCTAssertEqual(
            LogPagination(totalCount: 20 * 25, currentPage: 7).pageItems,
            [.page(1), .page(2), .ellipsis(6), .page(6), .page(7), .page(8), .ellipsis(19), .page(19), .page(20)]
        )
        // Page 5 has nothing hidden between 2 and its block except page 3.
        XCTAssertEqual(
            LogPagination(totalCount: 20 * 25, currentPage: 5).pageItems,
            [.page(1), .page(2), .ellipsis(4), .page(4), .page(5), .page(6), .ellipsis(19), .page(19), .page(20)]
        )
    }

    func testTheEndOfALongLogShowsTheFirstTwoAndTheLastFive() {
        for page in 17...20 {
            XCTAssertEqual(
                LogPagination(totalCount: 20 * 25, currentPage: page).pageItems,
                [.page(1), .page(2), .ellipsis(16), .page(16), .page(17), .page(18), .page(19), .page(20)],
                "page \(page)"
            )
        }
    }

    func testEveryPageNumberAppearsOnceAndInOrder() {
        for page in 1...40 {
            let items = LogPagination(totalCount: 1_000, currentPage: page).pageItems
            let numbers = items.compactMap(\.pageNumber)

            XCTAssertEqual(numbers, numbers.sorted(), "page \(page) is out of order")
            XCTAssertEqual(Set(numbers).count, numbers.count, "page \(page) repeats a number")
            XCTAssertTrue(numbers.contains(page), "page \(page) is missing from its own pager")
            XCTAssertEqual(numbers.first, 1)
            XCTAssertEqual(numbers.last, 40)
            XCTAssertLessThanOrEqual(numbers.count, 7, "page \(page) draws too many buttons")
        }
    }

    func testTheArrowsStopAtBothEnds() {
        let first = LogPagination(totalCount: 100, pageSize: 25, currentPage: 1)
        XCTAssertFalse(first.canGoBack)
        XCTAssertTrue(first.canGoForward)

        let middle = LogPagination(totalCount: 100, pageSize: 25, currentPage: 2)
        XCTAssertTrue(middle.canGoBack)
        XCTAssertTrue(middle.canGoForward)

        let last = LogPagination(totalCount: 100, pageSize: 25, currentPage: 4)
        XCTAssertTrue(last.canGoBack)
        XCTAssertFalse(last.canGoForward)

        let single = LogPagination(totalCount: 10, pageSize: 25)
        XCTAssertFalse(single.canGoBack)
        XCTAssertFalse(single.canGoForward)
    }
}
