import XCTest
@testable import SentinelCore

/// The three filters of the 全部日志 page.
final class LogFilteringTests: XCTestCase {
    private let now = LogicFixture.now

    private func event(
        id: String,
        _ kind: MonitoredEvent,
        hoursAgo: Double,
        severity: LogSeverity?
    ) throws -> MonitoredLogEvent {
        try LogicFixture.monitoredEvent(
            id: id,
            event: kind,
            at: now.addingTimeInterval(-hoursAgo * 3_600),
            severity: severity
        )
    }

    /// A small log: two network events, one threat, one of them old.
    private func events() throws -> [MonitoredLogEvent] {
        try [
            event(id: "down", .internetDown, hoursAgo: 1, severity: .veryHigh),
            event(id: "restored", .internetRestored, hoursAgo: 1.5, severity: .low),
            event(id: "threat", .threatDetected, hoursAgo: 2, severity: .high),
            event(id: "old-threat", .threatDetected, hoursAgo: 30, severity: .veryHigh),
            event(id: "temp", .internetDownTemporary, hoursAgo: 48, severity: .medium),
        ]
    }

    // MARK: - Time range

    func testTheRangeKeepsOnlyTheGivenDays() throws {
        let log = try events()

        XCTAssertEqual(
            LogFilter(timeRange: .day1).apply(to: log, now: now).map(\.id),
            ["down", "restored", "threat"]
        )
        XCTAssertEqual(
            LogFilter(timeRange: .day7).apply(to: log, now: now).map(\.id),
            ["down", "restored", "threat", "old-threat", "temp"]
        )
        XCTAssertEqual(
            LogFilter(timeRange: .day30).apply(to: log, now: now).map(\.id),
            ["down", "restored", "threat", "old-threat", "temp"]
        )
    }

    func testAnEntryExactlyAtTheStartOfTheRangeIsKept() throws {
        let boundary = try event(id: "edge", .internetDown, hoursAgo: 24, severity: .high)

        XCTAssertTrue(LogFilter(timeRange: .day1).includes(boundary, now: now))
        XCTAssertTrue(LogFilter(timeRange: .day7).includes(boundary, now: now))
    }

    func testAnEntryOlderThanTheRangeIsDropped() throws {
        let old = try event(id: "old", .internetDown, hoursAgo: 24.1, severity: .high)

        XCTAssertFalse(LogFilter(timeRange: .day1).includes(old, now: now))
    }

    // MARK: - Category

    func testTheCategoryFilterSplitsNetworkAndThreats() throws {
        let log = try events()

        let network = LogFilter(timeRange: .day30, category: .network).apply(to: log, now: now)
        XCTAssertEqual(network.map(\.id), ["down", "restored", "temp"])
        XCTAssertFalse(network.contains { $0.event == .threatDetected })

        let threats = LogFilter(timeRange: .day30, category: .threat).apply(to: log, now: now)
        XCTAssertEqual(threats.map(\.id), ["threat", "old-threat"])
        XCTAssertTrue(threats.allSatisfy { $0.event == .threatDetected })

        XCTAssertEqual(LogFilter(timeRange: .day30, category: .all).apply(to: log, now: now).count, log.count)
    }

    // MARK: - Severity

    func testTheLowThresholdShowsEverything() throws {
        let log = try events()

        XCTAssertEqual(LogFilter(timeRange: .day30).apply(to: log, now: now).count, log.count)
    }

    func testTheThresholdShowsThatSeverityAndAbove() throws {
        let log = try events()

        XCTAssertEqual(
            LogFilter(timeRange: .day30, minimumSeverity: .high).apply(to: log, now: now).map(\.id),
            ["down", "threat", "old-threat"]
        )
        XCTAssertEqual(
            LogFilter(timeRange: .day30, minimumSeverity: .veryHigh).apply(to: log, now: now).map(\.id),
            ["down", "old-threat"]
        )
    }

    func testAnUnknownSeverityCountsAsLow() throws {
        let unknown = try event(id: "unknown", .internetDown, hoursAgo: 1, severity: nil)

        XCTAssertTrue(LogFilter(minimumSeverity: .low).includes(unknown, now: now))
        XCTAssertFalse(LogFilter(minimumSeverity: .medium).includes(unknown, now: now))
        XCTAssertFalse(LogFilter(minimumSeverity: .veryHigh).includes(unknown, now: now))
    }

    // MARK: - Order

    func testTheFilteredLogIsNewestFirst() throws {
        let log = try events()

        let filtered = LogFilter(timeRange: .day30).apply(to: log, now: now)

        for (newer, older) in zip(filtered, filtered.dropFirst()) {
            XCTAssertGreaterThanOrEqual(newer.timestamp, older.timestamp)
        }
    }
}
