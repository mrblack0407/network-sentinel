import XCTest
@testable import SentinelCore

final class NotificationPlannerTests: XCTestCase {
    private let planner = NotificationPlanner()

    /// Settings with every event on, so a test only changes what it checks.
    private func allEventsSettings(
        minimumSeverity: LogSeverity = .high,
        alwaysNotifyOnRestore: Bool = true,
        mergeSameKind: Bool = true,
        mergeWindowSeconds: Int = 600
    ) -> MonitorSettings {
        MonitorSettings(
            monitoredEvents: Set(MonitoredEvent.allCases),
            notifications: NotificationSettings(
                minimumSeverity: minimumSeverity,
                alwaysNotifyOnRestore: alwaysNotifyOnRestore,
                mergeSameKind: mergeSameKind,
                mergeWindowSeconds: mergeWindowSeconds
            )
        )
    }

    // MARK: - Threshold

    func testEntriesBelowTheThresholdAreNotNotified() throws {
        let entries = try [
            LogicFixture.entry(id: "low", event: .internetDown, at: LogicFixture.time(0), severity: .low),
            LogicFixture.entry(id: "medium", event: .internetDown, at: LogicFixture.time(60), severity: .medium),
        ]

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(minimumSeverity: .high, alwaysNotifyOnRestore: false),
            now: LogicFixture.now
        )

        XCTAssertTrue(plan.notifications.isEmpty)
        XCTAssertEqual(plan.filteredOutCount, 2)
    }

    func testAnEntryAtTheThresholdIsNotified() throws {
        let entries = try [
            LogicFixture.entry(id: "high", event: .internetRestored, at: LogicFixture.time(0), severity: .high)
        ]

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(minimumSeverity: .high, alwaysNotifyOnRestore: false),
            now: LogicFixture.now
        )

        XCTAssertEqual(plan.notifications.count, 1)
        XCTAssertEqual(plan.notifications.first?.severity, .high)
        XCTAssertEqual(plan.filteredOutCount, 0)
    }

    func testAnUnknownSeverityCountsAsLow() throws {
        let entries = try [
            LogicFixture.entry(id: "unknown", event: .packetLoss, at: LogicFixture.time(0), severity: nil)
        ]

        let belowThreshold = planner.plan(
            entries: entries,
            settings: allEventsSettings(minimumSeverity: .high),
            now: LogicFixture.now
        )
        XCTAssertTrue(belowThreshold.notifications.isEmpty)

        let atLow = planner.plan(
            entries: entries,
            settings: allEventsSettings(minimumSeverity: .low),
            now: LogicFixture.now
        )
        XCTAssertEqual(atLow.notifications.first?.severity, .low)
    }

    // MARK: - Restore

    func testARestoreIsAlwaysNotifiedWhileTheSettingIsOn() throws {
        let entries = try [
            LogicFixture.entry(id: "restore", event: .internetRestored, at: LogicFixture.time(0), severity: .low, duration: "1m 25s")
        ]

        let always = planner.plan(
            entries: entries,
            settings: allEventsSettings(minimumSeverity: .veryHigh, alwaysNotifyOnRestore: true),
            now: LogicFixture.now
        )
        XCTAssertEqual(always.notifications.count, 1)
        XCTAssertEqual(always.notifications.first?.severity, .low)

        let strict = planner.plan(
            entries: entries,
            settings: allEventsSettings(minimumSeverity: .veryHigh, alwaysNotifyOnRestore: false),
            now: LogicFixture.now
        )
        XCTAssertTrue(strict.notifications.isEmpty)
        XCTAssertEqual(strict.filteredOutCount, 1)
    }

    // MARK: - Disabled events

    func testADisabledEventIsNotNotified() throws {
        let entries = try [
            LogicFixture.entry(id: "down", event: .internetDown, at: LogicFixture.time(0), severity: .veryHigh),
            LogicFixture.entry(id: "restore", event: .internetRestored, at: LogicFixture.time(100), severity: .high),
            LogicFixture.entry(id: "loss", event: .packetLoss, at: LogicFixture.time(120), severity: .veryHigh),
            LogicFixture.entry(id: "latency", event: .highLatency, at: LogicFixture.time(140), severity: .veryHigh),
        ]

        let plan = planner.plan(
            entries: entries,
            settings: MonitorSettings(),
            now: LogicFixture.now
        )

        // Defaults: 互联网中断 and 互联网已恢复 are on, 丢包 and 高延迟 are off.
        XCTAssertEqual(plan.notifications.map(\.event), [.internetDown, .internetRestored])
        XCTAssertEqual(plan.filteredOutCount, 2)
        XCTAssertFalse(plan.notifications.contains { $0.event == .packetLoss })
        XCTAssertFalse(plan.notifications.contains { $0.event == .highLatency })
    }

    func testAnUnmonitoredEntryIsIgnored() throws {
        let audit = try SystemLogEntry.json([
            "id": "audit",
            "timestamp": Int64(LogicFixture.now.timeIntervalSince1970 * 1_000),
            "category": "AUDIT",
            "key": "ADMIN_ACCESS",
            "severity": "VERY_HIGH",
        ])

        let plan = planner.plan(entries: [audit], settings: MonitorSettings(), now: LogicFixture.now)

        XCTAssertTrue(plan.notifications.isEmpty)
        XCTAssertEqual(plan.filteredOutCount, 0)
    }

    // MARK: - Title

    func testTitleIsTheEventNameAndTheSeveritySquares() {
        XCTAssertEqual(planner.title(for: .internetDown, severity: .veryHigh), "互联网中断 🟥🟥🟥🟥")
        XCTAssertEqual(planner.title(for: .internetDown, severity: .high), "互联网中断 🟧🟧🟧⬛")
        XCTAssertEqual(planner.title(for: .internetDown, severity: .medium), "互联网中断 🟨🟨⬛⬛")
        XCTAssertEqual(planner.title(for: .internetDown, severity: .low), "互联网中断 🟩⬛⬛⬛")
        XCTAssertEqual(planner.title(for: .threatDetected, severity: .high), "检测到威胁 🟧🟧🟧⬛")
    }

    func testTheNotificationCarriesTitleBodyEventSeverityAndLogIDs() throws {
        let entries = try [
            LogicFixture.entry(id: "down-1", event: .internetDown, at: LogicFixture.time(0), severity: .veryHigh)
        ]

        let plan = planner.plan(entries: entries, settings: allEventsSettings(), now: LogicFixture.now)
        let notification = try XCTUnwrap(plan.notifications.first)

        XCTAssertEqual(notification.title, "互联网中断 🟥🟥🟥🟥")
        XCTAssertEqual(notification.body, "WAN1 (China Telecom) 已断开。")
        XCTAssertEqual(notification.event, .internetDown)
        XCTAssertEqual(notification.severity, .veryHigh)
        XCTAssertEqual(notification.wanID, "WAN1")
        XCTAssertEqual(notification.logIDs, ["down-1"])
        XCTAssertEqual(notification.mergedCount, 1)
    }

    // MARK: - Bodies

    func testInternetDownBody() throws {
        let withISP = try LogicFixture.monitoredEvent(id: "d1", event: .internetDown, at: LogicFixture.now)
        XCTAssertEqual(planner.notificationBody(for: withISP), "WAN1 (China Telecom) 已断开。")

        let withoutISP = try LogicFixture.monitoredEvent(
            id: "d2",
            event: .internetDown,
            at: LogicFixture.now,
            ispName: nil
        )
        XCTAssertEqual(planner.notificationBody(for: withoutISP), "WAN1 已断开。")

        let wan2 = try LogicFixture.monitoredEvent(
            id: "d3",
            event: .internetDown,
            at: LogicFixture.now,
            wanID: "WAN2",
            ispName: "China Unicom"
        )
        XCTAssertEqual(planner.notificationBody(for: wan2), "WAN2 (China Unicom) 已断开。")
    }

    func testInternetRestoredBody() throws {
        let event = try LogicFixture.monitoredEvent(
            id: "r1",
            event: .internetRestored,
            at: LogicFixture.now,
            duration: "1m 25s"
        )

        XCTAssertEqual(planner.notificationBody(for: event), "WAN1 (China Telecom) 已恢复，断网 1 分 25 秒。")
    }

    func testInternetRestoredBodyWithoutADuration() throws {
        let event = try LogicFixture.monitoredEvent(
            id: "r1",
            event: .internetRestored,
            at: LogicFixture.now,
            ispName: nil
        )

        XCTAssertEqual(planner.notificationBody(for: event), "WAN1 已恢复，断网 未知。")
    }

    func testMultipleOutagesBody() throws {
        let event = try LogicFixture.monitoredEvent(
            id: "m1",
            event: .internetDownMultipleTimes,
            at: LogicFixture.now
        )

        XCTAssertEqual(planner.notificationBody(for: event), "WAN1 (China Telecom) 在过去 24 小时内多次中断。")
    }

    func testTemporaryOutageBody() throws {
        let event = try LogicFixture.monitoredEvent(
            id: "t1",
            event: .internetDownTemporary,
            at: LogicFixture.now,
            duration: "48s"
        )

        XCTAssertEqual(planner.notificationBody(for: event), "WAN1 (China Telecom) 临时中断后已恢复，断开 48 秒。")
    }

    func testPacketLossBody() throws {
        let event = try LogicFixture.monitoredEvent(
            id: "p1",
            event: .packetLoss,
            at: LogicFixture.now,
            wanID: "WAN2",
            ispName: "China Unicom"
        )

        XCTAssertEqual(planner.notificationBody(for: event), "WAN2 (China Unicom) 检测到丢包。")
    }

    func testHighLatencyBody() throws {
        let event = try LogicFixture.monitoredEvent(
            id: "h1",
            event: .highLatency,
            at: LogicFixture.now,
            latency: "45"
        )

        XCTAssertEqual(planner.notificationBody(for: event), "WAN1 (China Telecom) 延迟升高到 45 ms。")
    }

    func testHighLatencyBodyWithoutALatency() throws {
        let event = try LogicFixture.monitoredEvent(
            id: "h1",
            event: .highLatency,
            at: LogicFixture.now
        )

        XCTAssertEqual(planner.notificationBody(for: event), "WAN1 (China Telecom) 延迟升高到 未知 ms。")
    }

    func testThreatBodyPrefersTheClientOverTheAddress() throws {
        let fromClient = try LogicFixture.monitoredEvent(
            id: "s1",
            event: .threatDetected,
            at: LogicFixture.now,
            wanID: nil,
            ispName: nil,
            source: ThreatEndpoint(value: "Laptop", isClient: true),
            destination: ThreatEndpoint(value: "203.0.113.20", isClient: false)
        )

        XCTAssertEqual(
            planner.notificationBody(for: fromClient),
            "来自 Laptop 到 203.0.113.20 的入侵尝试。"
        )
    }

    func testThreatBodyFallsBackToTheAddress() throws {
        let fromAddress = try LogicFixture.monitoredEvent(
            id: "s1",
            event: .threatDetected,
            at: LogicFixture.now,
            wanID: nil,
            ispName: nil,
            source: ThreatEndpoint(value: "10.20.0.2", isClient: false),
            destination: ThreatEndpoint(value: "203.0.113.20", isClient: false)
        )

        XCTAssertEqual(
            planner.notificationBody(for: fromAddress),
            "来自 10.20.0.2 到 203.0.113.20 的入侵尝试。"
        )
    }

    func testEveryEventOfTheFixturesHasABody() throws {
        let events = SystemLogEntry.monitoredLogEvents(in: try Fixture.allLogEntries())

        for event in events {
            XCTAssertFalse(event.event.displayName.isEmpty)
            XCTAssertFalse(planner.notificationBody(for: event).isEmpty)
        }
    }

    // MARK: - Merging

    func testThreeEntriesOfOneKindOnOneLineBecomeOneNotification() throws {
        let entries = try [
            LogicFixture.entry(id: "loss-1", event: .packetLoss, at: LogicFixture.time(0), severity: .medium),
            LogicFixture.entry(id: "loss-2", event: .packetLoss, at: LogicFixture.time(120), severity: .high),
            LogicFixture.entry(id: "loss-3", event: .packetLoss, at: LogicFixture.time(300), severity: .low),
        ]

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(minimumSeverity: .low),
            now: LogicFixture.time(300)
        )

        XCTAssertEqual(plan.notifications.count, 1)
        let notification = try XCTUnwrap(plan.notifications.first)
        XCTAssertEqual(notification.mergedCount, 3)
        XCTAssertTrue(notification.isMerged)
        XCTAssertEqual(notification.logIDs, ["loss-1", "loss-2", "loss-3"])
        // Highest severity of the group wins.
        XCTAssertEqual(notification.severity, .high)
        XCTAssertEqual(notification.title, "检测到丢包 🟧🟧🟧⬛")
        // Body of the newest entry, then the count line on its own line.
        XCTAssertEqual(
            notification.body,
            "WAN1 (China Telecom) 检测到丢包。\n10 分钟内同类 3 条。"
        )
        XCTAssertEqual(notification.timestamp, LogicFixture.time(300))
        // The two older entries were folded into the first notification.
        XCTAssertEqual(plan.mergedLogIDs, ["loss-2", "loss-3"])
    }

    func testTheMergedBodyUsesTheNewestEntry() throws {
        let entries = try [
            LogicFixture.entry(id: "down-1", event: .internetDown, at: LogicFixture.time(0), wanID: "WAN1", severity: .high),
            LogicFixture.entry(id: "down-2", event: .internetDown, at: LogicFixture.time(60), wanID: "WAN2", ispName: "China Unicom", severity: .veryHigh),
        ]

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(),
            now: LogicFixture.time(60)
        )

        // Different lines: two groups, not one.
        XCTAssertEqual(plan.notifications.count, 2)
        let wan2 = try XCTUnwrap(plan.notifications.first { $0.wanID == "WAN2" })
        XCTAssertEqual(wan2.body, "WAN2 (China Unicom) 已断开。")
        XCTAssertFalse(wan2.isMerged)
    }

    func testDifferentLinesDoNotMerge() throws {
        let entries = try [
            LogicFixture.entry(id: "loss-1", event: .packetLoss, at: LogicFixture.time(0), wanID: "WAN1", severity: .high),
            LogicFixture.entry(id: "loss-2", event: .packetLoss, at: LogicFixture.time(60), wanID: "WAN2", severity: .high),
            LogicFixture.entry(id: "loss-3", event: .packetLoss, at: LogicFixture.time(120), wanID: "WAN1", severity: .high),
        ]

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(),
            now: LogicFixture.time(120)
        )

        XCTAssertEqual(plan.notifications.count, 2)
        let wan1 = try XCTUnwrap(plan.notifications.first { $0.wanID == "WAN1" })
        XCTAssertEqual(wan1.mergedCount, 2)
        XCTAssertEqual(
            wan1.body,
            "WAN1 (China Telecom) 检测到丢包。\n10 分钟内同类 2 条。"
        )
        let wan2 = try XCTUnwrap(plan.notifications.first { $0.wanID == "WAN2" })
        XCTAssertEqual(wan2.mergedCount, 1)
    }

    func testEntriesMoreThanTenMinutesApartDoNotMerge() throws {
        let entries = try [
            LogicFixture.entry(id: "loss-1", event: .packetLoss, at: LogicFixture.time(0), severity: .high),
            LogicFixture.entry(id: "loss-2", event: .packetLoss, at: LogicFixture.time(601), severity: .high),
        ]

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(),
            now: LogicFixture.time(601)
        )

        XCTAssertEqual(plan.notifications.count, 2)
        XCTAssertTrue(plan.notifications.allSatisfy { !$0.isMerged })
        XCTAssertTrue(plan.mergedLogIDs.isEmpty)
    }

    func testEntriesExactlyOneWindowApartMerge() throws {
        let entries = try [
            LogicFixture.entry(id: "loss-1", event: .packetLoss, at: LogicFixture.time(0), severity: .high),
            LogicFixture.entry(id: "loss-2", event: .packetLoss, at: LogicFixture.time(600), severity: .high),
        ]

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(),
            now: LogicFixture.time(600)
        )

        XCTAssertEqual(plan.notifications.count, 1)
        XCTAssertEqual(plan.notifications.first?.mergedCount, 2)
    }

    func testOutageAndRestoreNeverMerge() throws {
        let entries = try [
            LogicFixture.entry(id: "down", event: .internetDown, at: LogicFixture.time(0), severity: .veryHigh),
            LogicFixture.entry(id: "restore", event: .internetRestored, at: LogicFixture.time(60), severity: .low, duration: "1m"),
        ]

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(),
            now: LogicFixture.time(60)
        )

        XCTAssertEqual(plan.notifications.count, 2)
        XCTAssertEqual(plan.notifications.map(\.event), [.internetDown, .internetRestored])
        XCTAssertTrue(plan.notifications.allSatisfy { !$0.isMerged })
    }

    func testMergingCanBeSwitchedOff() throws {
        let entries = try [
            LogicFixture.entry(id: "loss-1", event: .packetLoss, at: LogicFixture.time(0), severity: .high),
            LogicFixture.entry(id: "loss-2", event: .packetLoss, at: LogicFixture.time(60), severity: .high),
        ]

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(mergeSameKind: false),
            now: LogicFixture.time(60)
        )

        XCTAssertEqual(plan.notifications.count, 2)
        XCTAssertTrue(plan.notifications.allSatisfy { !$0.isMerged })
    }

    func testAWindowLengthFromTheSettingsIsUsed() throws {
        let entries = try [
            LogicFixture.entry(id: "loss-1", event: .packetLoss, at: LogicFixture.time(0), severity: .high),
            LogicFixture.entry(id: "loss-2", event: .packetLoss, at: LogicFixture.time(120), severity: .high),
        ]

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(mergeWindowSeconds: 60),
            now: LogicFixture.time(120)
        )

        XCTAssertEqual(plan.notifications.count, 2)
    }

    func testTheCountLineUsesTheNumberOfMergedEntries() throws {
        let entries = try (1...5).map { index in
            try LogicFixture.entry(
                id: "loss-\(index)",
                event: .packetLoss,
                at: LogicFixture.time(TimeInterval(index * 60)),
                severity: .high
            )
        }

        let plan = planner.plan(
            entries: entries,
            settings: allEventsSettings(),
            now: LogicFixture.time(300)
        )

        let notification = try XCTUnwrap(plan.notifications.first)
        XCTAssertEqual(notification.mergedCount, 5)
        XCTAssertTrue(notification.body.hasSuffix("\n10 分钟内同类 5 条。"))
        XCTAssertEqual(notification.body.split(separator: "\n").count, 2)
    }

    // MARK: - Merging with what was notified before

    func testAnEntryInsideAWindowOfAnAlreadyNotifiedRecordOnlyGrowsThatRecord() throws {
        let earlier = try LogicFixture.entry(
            id: "loss-1",
            event: .packetLoss,
            at: LogicFixture.time(0),
            severity: .medium
        )
        let earlierPlan = planner.plan(
            entries: [earlier],
            settings: allEventsSettings(minimumSeverity: .low),
            now: LogicFixture.time(0)
        )
        let sent = try XCTUnwrap(earlierPlan.records.first)

        let later = try LogicFixture.entry(
            id: "loss-2",
            event: .packetLoss,
            at: LogicFixture.time(120),
            severity: .high
        )
        let plan = planner.plan(
            entries: [later],
            settings: allEventsSettings(minimumSeverity: .low),
            now: LogicFixture.time(120),
            recentRecords: [sent]
        )

        // Nothing new is shown, but the record grew so the count keeps going up.
        XCTAssertTrue(plan.notifications.isEmpty)
        let record = try XCTUnwrap(plan.records.first)
        XCTAssertEqual(record.mergedCount, 2)
        XCTAssertEqual(record.severity, .high)
        XCTAssertEqual(record.logIDs, ["loss-1", "loss-2"])
        XCTAssertEqual(record.body, "WAN1 (China Telecom) 检测到丢包。\n10 分钟内同类 2 条。")
        XCTAssertEqual(plan.mergedLogIDs, ["loss-2"])
    }

    func testAnAlreadyNotifiedRecordOutsideTheWindowIsNotMerged() throws {
        let earlier = try LogicFixture.entry(
            id: "loss-1",
            event: .packetLoss,
            at: LogicFixture.time(0),
            severity: .high
        )
        let earlierPlan = planner.plan(entries: [earlier], settings: allEventsSettings(), now: LogicFixture.time(0))
        let sent = try XCTUnwrap(earlierPlan.records.first)

        let later = try LogicFixture.entry(
            id: "loss-2",
            event: .packetLoss,
            at: LogicFixture.time(900),
            severity: .high
        )
        let plan = planner.plan(
            entries: [later],
            settings: allEventsSettings(),
            now: LogicFixture.time(900),
            recentRecords: [sent]
        )

        XCTAssertEqual(plan.notifications.count, 1)
        XCTAssertEqual(plan.notifications.first?.mergedCount, 1)
        XCTAssertTrue(plan.mergedLogIDs.isEmpty)
    }

    func testWithMergingOffARepeatedEventIsNotifiedAgain() throws {
        let earlier = try LogicFixture.entry(
            id: "loss-1",
            event: .packetLoss,
            at: LogicFixture.time(0),
            severity: .high
        )
        let earlierPlan = planner.plan(entries: [earlier], settings: allEventsSettings(), now: LogicFixture.time(0))
        let sent = try XCTUnwrap(earlierPlan.records.first)

        let later = try LogicFixture.entry(
            id: "loss-2",
            event: .packetLoss,
            at: LogicFixture.time(60),
            severity: .high
        )
        let plan = planner.plan(
            entries: [later],
            settings: allEventsSettings(mergeSameKind: false),
            now: LogicFixture.time(60),
            recentRecords: [sent]
        )

        XCTAssertEqual(plan.notifications.count, 1)
        XCTAssertEqual(plan.notifications.first?.mergedCount, 1)
        XCTAssertTrue(plan.mergedLogIDs.isEmpty)
    }

    func testARecordOfAnotherLineIsNotMerged() throws {        let earlier = try LogicFixture.entry(
            id: "loss-1",
            event: .packetLoss,
            at: LogicFixture.time(0),
            wanID: "WAN1",
            severity: .high
        )
        let earlierPlan = planner.plan(entries: [earlier], settings: allEventsSettings(), now: LogicFixture.time(0))
        let sent = try XCTUnwrap(earlierPlan.records.first)

        let later = try LogicFixture.entry(
            id: "loss-2",
            event: .packetLoss,
            at: LogicFixture.time(60),
            wanID: "WAN2",
            severity: .high
        )
        let plan = planner.plan(
            entries: [later],
            settings: allEventsSettings(),
            now: LogicFixture.time(60),
            recentRecords: [sent]
        )

        XCTAssertEqual(plan.notifications.count, 1)
        XCTAssertEqual(plan.notifications.first?.wanID, "WAN2")
    }

    // MARK: - Order

    func testNotificationsAreOrderedByTimeWhateverTheInputOrder() throws {
        let entries = try [
            LogicFixture.entry(id: "later", event: .internetDown, at: LogicFixture.time(600), severity: .veryHigh),
            LogicFixture.entry(id: "earlier", event: .threatDetected, at: LogicFixture.time(0), wanID: nil, ispName: nil, severity: .veryHigh),
            LogicFixture.entry(id: "middle", event: .highLatency, at: LogicFixture.time(300), severity: .veryHigh),
        ]

        let plan = planner.plan(entries: entries, settings: allEventsSettings(), now: LogicFixture.time(600))

        XCTAssertEqual(plan.notifications.map(\.timestamp), [
            LogicFixture.time(0),
            LogicFixture.time(300),
            LogicFixture.time(600),
        ])
    }

    func testThePlanOfAnEmptyQueryIsEmpty() {
        let plan = planner.plan(entries: [], settings: MonitorSettings(), now: LogicFixture.now)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.records, [])
        XCTAssertEqual(plan.filteredOutCount, 0)
    }

    // MARK: - Records

    func testARecordCanBeStoredAndRestored() throws {
        let entries = try [
            LogicFixture.entry(id: "down", event: .internetDown, at: LogicFixture.time(0), severity: .veryHigh)
        ]

        let plan = planner.plan(entries: entries, settings: allEventsSettings(), now: LogicFixture.time(0))
        let record = try XCTUnwrap(plan.records.first)

        let data = try JSONEncoder().encode(record)
        let restored = try JSONDecoder().decode(NotificationRecord.self, from: data)

        XCTAssertEqual(restored, record)
        XCTAssertEqual(restored.id, "down")
    }

    func testARecordOfTheFixturesKeepsItsLogIDs() throws {
        let entries = Array(try Fixture.allLogEntries().prefix(20))

        let plan = planner.plan(
            entries: entries,
            settings: MonitorSettings(),
            now: LogicFixture.now
        )

        let knownIDs = Set(entries.map(\.id))
        for record in plan.records {
            XCTAssertFalse(record.logIDs.isEmpty)
            XCTAssertTrue(record.logIDs.allSatisfy { knownIDs.contains($0) })
        }
        XCTAssertEqual(plan.notifications.count, plan.records.count)
    }
}
