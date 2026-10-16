import XCTest
@testable import SentinelCore

/// The three columns of a 概览 线路卡片 and the 检测到威胁 card.
final class OverviewStatisticsTests: XCTestCase {
    private let now = LogicFixture.now

    /// A finished outage of WAN1.
    private func outage(
        _ id: String,
        wanID: String? = "WAN1",
        from start: TimeInterval,
        to end: TimeInterval?,
        durationSeconds: Int? = nil
    ) -> Outage {
        Outage(
            startLogID: id,
            endLogID: end == nil ? nil : "\(id)-restored",
            wanID: wanID,
            ispName: "China Telecom",
            start: now.addingTimeInterval(start),
            end: end.map { now.addingTimeInterval($0) },
            durationSeconds: durationSeconds
        )
    }

    // MARK: - 线路卡片

    func testTheCardSumsTheOutagesOfTheWindow() {
        let outages = [
            outage("a", from: -7_200, to: -7_100, durationSeconds: 100),
            outage("b", from: -3_600, to: -3_500, durationSeconds: 100),
        ]

        let statistics = WANLineStatisticsBuilder.statistics(outages: outages, wanID: "WAN1", now: now)

        XCTAssertEqual(statistics.outageCount, 2)
        XCTAssertEqual(statistics.totalOutageSeconds, 200)
        XCTAssertEqual(statistics.longestOutageSeconds, 100)
        XCTAssertEqual(statistics.totalText, "3 分 20 秒")
        XCTAssertEqual(statistics.longestText, "1 分 40 秒")
    }

    func testAnOutageWithoutAGatewayDurationUsesItsTimestamps() {
        let outages = [outage("a", from: -600, to: -540)]

        let statistics = WANLineStatisticsBuilder.statistics(outages: outages, wanID: "WAN1", now: now)

        XCTAssertEqual(statistics.totalOutageSeconds, 60)
        XCTAssertEqual(statistics.longestOutageSeconds, 60)
    }

    func testAWholeOutageKeepsTheGatewayDuration() {
        // The two entries are a minute apart, but the gateway reported 24 秒.
        let outages = [outage("a", from: -600, to: -540, durationSeconds: 24)]

        let statistics = WANLineStatisticsBuilder.statistics(outages: outages, wanID: "WAN1", now: now)

        XCTAssertEqual(statistics.totalOutageSeconds, 24)
        XCTAssertEqual(statistics.longestOutageSeconds, 24)
    }

    func testAnOpenOutageCountsUpToNow() {
        let outages = [outage("a", from: -12 * 3_600, to: nil, durationSeconds: nil)]

        let statistics = WANLineStatisticsBuilder.statistics(outages: outages, wanID: "WAN1", now: now)

        XCTAssertEqual(statistics.outageCount, 1)
        XCTAssertEqual(statistics.totalOutageSeconds, 12 * 3_600)
        XCTAssertEqual(statistics.longestText, "12 小时")
    }

    func testAnOutageIsClippedToTheWindow() {
        // 30 hours old and still open: only the last 24 hours count.
        let outages = [outage("a", from: -30 * 3_600, to: nil, durationSeconds: nil)]

        let statistics = WANLineStatisticsBuilder.statistics(outages: outages, wanID: "WAN1", now: now)

        XCTAssertEqual(statistics.outageCount, 1)
        XCTAssertEqual(statistics.totalOutageSeconds, 24 * 3_600)
        XCTAssertEqual(statistics.longestText, "1 天")
    }

    func testAnOutageBeforeTheWindowIsNotCounted() {
        let outages = [outage("a", from: -30 * 3_600, to: -26 * 3_600, durationSeconds: 4 * 3_600)]

        let statistics = WANLineStatisticsBuilder.statistics(outages: outages, wanID: "WAN1", now: now)

        XCTAssertEqual(statistics.outageCount, 0)
        XCTAssertEqual(statistics.totalOutageSeconds, 0)
        XCTAssertNil(statistics.longestOutageSeconds)
        XCTAssertEqual(statistics.longestText, "—")
    }

    func testOnlyTheLineOfTheCardIsCounted() {
        let outages = [
            outage("wan1", wanID: "WAN1", from: -600, to: -540, durationSeconds: 60),
            outage("wan2", wanID: "WAN2", from: -600, to: -540, durationSeconds: 300),
        ]

        let first = WANLineStatisticsBuilder.statistics(outages: outages, wanID: "WAN1", now: now)
        let second = WANLineStatisticsBuilder.statistics(outages: outages, wanID: "WAN2", now: now)

        XCTAssertEqual(first.totalOutageSeconds, 60)
        XCTAssertEqual(first.longestOutageSeconds, 60)
        XCTAssertEqual(second.totalOutageSeconds, 300)
        XCTAssertEqual(second.longestOutageSeconds, 300)
    }

    func testAnEmptyWindowReadsAsZero() {
        let statistics = WANLineStatistics.none

        XCTAssertEqual(statistics.outageCount, 0)
        XCTAssertEqual(statistics.totalText, "0 秒")
        XCTAssertEqual(statistics.longestText, "—")
        XCTAssertEqual(statistics.accessibilityText, "24 小时中断 0 次，累计断网 0 秒，最长一次 —")
    }

    func testTheLinesArePairedFromTheLogOfTheOverview() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: now.addingTimeInterval(-3_600)),
            LogicFixture.monitoredEvent(id: "up", event: .internetRestored, at: now.addingTimeInterval(-3_500), duration: "1m 40s"),
        ]

        let statistics = WANLineStatisticsBuilder.statistics(
            outages: OutagePairer.outages(in: events),
            wanID: "WAN1",
            now: now
        )

        XCTAssertEqual(statistics.outageCount, 1)
        XCTAssertEqual(statistics.longestText, "1 分 40 秒")
    }

    // MARK: - 威胁卡片

    func testTheThreatCardSplitsTheWindowBySeverity() throws {
        let threats = try [
            LogicFixture.monitoredEvent(id: "t1", event: .threatDetected, at: now.addingTimeInterval(-600), severity: .veryHigh),
            LogicFixture.monitoredEvent(id: "t2", event: .threatDetected, at: now.addingTimeInterval(-900), severity: .high),
            LogicFixture.monitoredEvent(id: "t3", event: .threatDetected, at: now.addingTimeInterval(-1_200), severity: .medium),
            LogicFixture.monitoredEvent(id: "t4", event: .threatDetected, at: now.addingTimeInterval(-1_500), severity: .low),
            LogicFixture.monitoredEvent(id: "t5", event: .threatDetected, at: now.addingTimeInterval(-1_800), severity: nil),
            // Old, and not a threat: neither may reach the card.
            LogicFixture.monitoredEvent(id: "old", event: .threatDetected, at: now.addingTimeInterval(-25 * 3_600), severity: .veryHigh),
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: now.addingTimeInterval(-600), severity: .veryHigh),
        ]

        let statistics = ThreatStatisticsBuilder.statistics(events: threats, now: now)

        XCTAssertEqual(statistics.veryHigh, 1)
        XCTAssertEqual(statistics.high, 1)
        XCTAssertEqual(statistics.mediumAndBelow, 3)
        XCTAssertEqual(statistics.total, 5)
    }

    func testTheEmptyThreatCard() {
        XCTAssertEqual(ThreatStatisticsBuilder.statistics(events: [], now: now), .none)
        XCTAssertEqual(ThreatStatistics.none.total, 0)
    }
}
