import XCTest
@testable import SentinelCore

/// 严重性 → Bark 推送级别, and what each kind of notification becomes.
final class BarkLevelTests: XCTestCase {
    // MARK: - 严重性

    func testVeryHighIsTimeSensitive() {
        XCTAssertEqual(BarkLevel.level(for: .veryHigh), .timeSensitive)
        XCTAssertEqual(BarkLevel(severity: .veryHigh), .timeSensitive)
    }

    func testLowerSeveritiesAreActive() {
        for severity in [LogSeverity.low, .medium, .high] {
            XCTAssertEqual(BarkLevel.level(for: severity), .active, "\(severity)")
            XCTAssertEqual(BarkLevel(severity: severity), .active, "\(severity)")
        }
    }

    func testRawValuesAreTheBarkLevels() {
        XCTAssertEqual(BarkLevel.active.rawValue, "active")
        XCTAssertEqual(BarkLevel.timeSensitive.rawValue, "timeSensitive")
    }

    // MARK: - Notifications

    func testGatewayFailuresAreTimeSensitive() {
        XCTAssertEqual(NotificationKind.gatewayUnreachable(reason: "无法连接到 https://192.168.8.254").barkLevel, .timeSensitive)
        XCTAssertEqual(NotificationKind.apiKeyRejected.barkLevel, .timeSensitive)
        XCTAssertEqual(NotificationKind.certificateChanged.barkLevel, .timeSensitive)
    }

    func testGatewayRestoredIsAnOrdinaryPush() {
        XCTAssertEqual(NotificationKind.gatewayRestored.barkLevel, .active)
    }

    func testAMonitoredEventFollowsItsSeverity() throws {
        let ordinary = NotificationKind.monitorEvent(record(severity: .high, event: .internetDown))
        let severe = NotificationKind.monitorEvent(record(severity: .veryHigh, event: .threatDetected))

        XCTAssertEqual(ordinary.barkLevel, .active)
        XCTAssertEqual(severe.barkLevel, .timeSensitive)
    }

    func testAWakeSummaryFollowsItsMostSevereEntry() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "a", event: .packetLoss, at: LogicFixture.time(-300), severity: .low),
            LogicFixture.monitoredEvent(id: "b", event: .threatDetected, at: LogicFixture.time(-200), wanID: nil, ispName: nil, severity: .veryHigh),
            LogicFixture.monitoredEvent(id: "c", event: .internetRestored, at: LogicFixture.time(-100), severity: .medium),
            LogicFixture.monitoredEvent(id: "d", event: .highLatency, at: LogicFixture.time(-50), severity: .high),
        ]

        let summary = try XCTUnwrap(MonitorLogSpec.wakeSummary(for: events) { _ in "09:30" })

        XCTAssertEqual(summary.severity, .veryHigh)
        XCTAssertEqual(NotificationKind.wakeSummary(summary).barkLevel, .timeSensitive)
    }

    func testAQuietWakeSummaryIsActive() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "a", event: .packetLoss, at: LogicFixture.time(-300), severity: .low),
            LogicFixture.monitoredEvent(id: "b", event: .highLatency, at: LogicFixture.time(-200), severity: .medium),
            LogicFixture.monitoredEvent(id: "c", event: .internetDown, at: LogicFixture.time(-100), severity: .high),
            LogicFixture.monitoredEvent(id: "d", event: .internetRestored, at: LogicFixture.time(-50), severity: .medium),
        ]

        let summary = try XCTUnwrap(MonitorLogSpec.wakeSummary(for: events) { _ in "09:30" })

        XCTAssertEqual(summary.severity, .high)
        XCTAssertEqual(NotificationKind.wakeSummary(summary).barkLevel, .active)
    }

    func testAWakeSummaryOfAnUnknownSeverityCountsAsLow() {
        let summary = MonitorLogSpec.WakeSummary(title: "t", body: "b", count: 4)

        XCTAssertEqual(summary.severity, .low)
        XCTAssertEqual(NotificationKind.wakeSummary(summary).barkLevel, .active)
    }

    // MARK: - Helpers

    private func record(severity: LogSeverity, event: MonitoredEvent) -> NotificationRecord {
        NotificationRecord(
            event: event,
            severity: severity,
            wanID: "WAN1",
            title: "\(event.displayName) \(severity.squares)",
            body: "正文",
            logIDs: ["entry-1"],
            timestamp: LogicFixture.time(-100),
            mergedCount: 1
        )
    }
}
