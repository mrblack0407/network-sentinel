import XCTest
@testable import SentinelCore

final class OutagePairingTests: XCTestCase {
    // MARK: - Real samples

    func testTheSamplesPairEveryOutageWithItsRestore() throws {
        let events = SystemLogEntry.monitoredLogEvents(in: try Fixture.allLogEntries())

        let downs = events.filter { $0.event == .internetDown }
        let restores = events.filter { $0.event == .internetRestored }
        XCTAssertEqual(downs.count, 30)
        XCTAssertEqual(restores.count, 30)

        let outages = OutagePairer.outages(in: events)

        XCTAssertEqual(outages.count, 30)
        XCTAssertTrue(outages.allSatisfy { !$0.isOngoing })
        XCTAssertTrue(outages.allSatisfy { $0.endLogID != nil })
        XCTAssertTrue(outages.allSatisfy { $0.wanID == "WAN1" })
        XCTAssertTrue(outages.allSatisfy { $0.ispName == "China Telecom" })
    }

    func testTheSamplesArePairedInOrder() throws {
        let events = SystemLogEntry.monitoredLogEvents(in: try Fixture.allLogEntries())

        let outages = OutagePairer.outages(in: events)

        // Oldest first, whatever the order of the pages.
        XCTAssertEqual(outages.map(\.start), outages.map(\.start).sorted())
        for (index, outage) in outages.enumerated() where index + 1 < outages.count {
            XCTAssertLessThan(outage.start, outages[index + 1].start)
            XCTAssertLessThanOrEqual(outage.end ?? outage.start, outages[index + 1].start)
        }
    }

    func testTheOldestSampleOutageUsesTheReportedDuration() throws {
        let events = SystemLogEntry.monitoredLogEvents(in: try Fixture.allLogEntries())

        let outage = try XCTUnwrap(OutagePairer.outages(in: events).first)

        XCTAssertEqual(outage.wanID, "WAN1")
        XCTAssertEqual(outage.ispName, "China Telecom")
        // The gateway reported `1m 27s`.
        XCTAssertEqual(outage.durationSeconds, 87)
        XCTAssertEqual(outage.durationText, "1 分 27 秒")
        // The timestamps differ by the logging delay, so the reported duration wins.
        let fromTimestamps = try XCTUnwrap(outage.end).timeIntervalSince(outage.start)
        XCTAssertLessThan(abs(fromTimestamps - 30.46), 0.001)
        XCTAssertEqual(outage.duration ?? 0, 87)
    }

    func testAnOutageOfAPageBoundaryIsStillPaired() throws {
        // The newest 互联网中断 of page 0 and its 互联网已恢复 are the last complete
        // pair of the first page, so a query that stops between the two pages
        // hands them over in jumbled order.
        let page0 = try Fixture.logPage("system-log-page0.json").data
        let down = try XCTUnwrap(page0.first { $0.monitoredEvent == .internetDown })
        let restore = try XCTUnwrap(
            page0
                .filter { $0.monitoredEvent == .internetRestored && $0.timestamp > down.timestamp }
                .filter { candidate in
                    !page0.contains {
                        ($0.monitoredEvent == .internetDown)
                            && $0.timestamp > down.timestamp
                            && $0.timestamp < candidate.timestamp
                    }
                }
                .min { $0.timestamp < $1.timestamp }
        )
        XCTAssertLessThan(down.timestamp, restore.timestamp)

        let pages = try Fixture.logPage("system-log-page1.json").data
        let outages = OutagePairer.outages(in: [down] + pages + [restore]).filter { $0.startLogID == down.id }

        XCTAssertEqual(outages.count, 1)
        XCTAssertEqual(outages.first?.endLogID, restore.id)
        XCTAssertFalse(outages.first?.isOngoing ?? true)
    }

    func testARestoreBeforeTheOutageIsNotPaired() throws {
        // A restore that no 互联网中断 precedes is ignored, and the 互联网中断 that
        // has no restore after it stays open.
        let events = try [
            LogicFixture.monitoredEvent(id: "restore", event: .internetRestored, at: LogicFixture.time(0), duration: "1m"),
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(600)),
        ]

        let outages = OutagePairer.outages(in: events)

        XCTAssertEqual(outages.count, 1)
        XCTAssertEqual(outages.first?.startLogID, "down")
        XCTAssertNil(outages.first?.endLogID)
    }

    func testTheSeverityOfTheSamplesIsReadable() throws {
        let events = SystemLogEntry.monitoredLogEvents(in: try Fixture.allLogEntries())

        XCTAssertTrue(events.contains { $0.severity == .veryHigh })
        // A restore can be low or medium: whether it notifies does not depend on it.
        XCTAssertTrue(events.filter { $0.event == .internetRestored }.allSatisfy { $0.severity != nil })
    }

    // MARK: - Built cases

    func testOnlyTheFollowedRestoreClosesAnOutage() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down2", event: .internetDown, at: LogicFixture.time(300)),
            LogicFixture.monitoredEvent(id: "restore2", event: .internetRestored, at: LogicFixture.time(400), duration: "1m 40s"),
            LogicFixture.monitoredEvent(id: "down1", event: .internetDown, at: LogicFixture.time(0), severity: .veryHigh),
            LogicFixture.monitoredEvent(id: "restore1", event: .internetRestored, at: LogicFixture.time(100), duration: "1m 40s"),
        ]

        let outages = OutagePairer.outages(in: events)

        XCTAssertEqual(outages.count, 2)
        XCTAssertEqual(outages.first?.startLogID, "down1")
        XCTAssertEqual(outages.first?.endLogID, "restore1")
        XCTAssertEqual(outages.first?.durationSeconds, 100)
        XCTAssertEqual(outages.last?.startLogID, "down2")
        XCTAssertEqual(outages.last?.endLogID, "restore2")
    }

    func testADownWithoutARestoreStaysOpen() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(0))
        ]

        let outage = try XCTUnwrap(OutagePairer.outages(in: events).first)

        XCTAssertTrue(outage.isOngoing)
        XCTAssertNil(outage.end)
        XCTAssertNil(outage.endLogID)
        XCTAssertNil(outage.duration)
        XCTAssertNil(outage.durationWholeSeconds)
        XCTAssertNil(outage.durationText)
    }

    func testTwoDownsAndOneRestoreDoNotMismatch() throws {
        // The first outage never saw a restore and must not borrow the second one's.
        let events = try [
            LogicFixture.monitoredEvent(id: "down1", event: .internetDown, at: LogicFixture.time(0)),
            LogicFixture.monitoredEvent(id: "down2", event: .internetDown, at: LogicFixture.time(60)),
            LogicFixture.monitoredEvent(id: "restore2", event: .internetRestored, at: LogicFixture.time(120), duration: "1m"),
        ]

        let outages = OutagePairer.outages(in: events)

        XCTAssertEqual(outages.count, 2)

        let closed = try XCTUnwrap(outages.first { !$0.isOngoing })
        XCTAssertEqual(closed.startLogID, "down1")
        XCTAssertEqual(closed.endLogID, "restore2")

        let open = try XCTUnwrap(outages.first { $0.isOngoing })
        XCTAssertEqual(open.startLogID, "down2")
        XCTAssertNil(open.end)
    }

    func testOutagesOfDifferentLinesNeverPair() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down2", event: .internetDown, at: LogicFixture.time(0), wanID: "WAN2"),
            LogicFixture.monitoredEvent(id: "restore1", event: .internetRestored, at: LogicFixture.time(60), wanID: "WAN1", duration: "1m"),
        ]

        let outages = OutagePairer.outages(in: events)

        XCTAssertEqual(outages.count, 1)
        XCTAssertEqual(outages.first?.wanID, "WAN2")
        XCTAssertTrue(outages.first?.isOngoing ?? false)
    }

    func testARestoreWithoutADownIsIgnored() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "restore", event: .internetRestored, at: LogicFixture.time(0), duration: "1m")
        ]

        XCTAssertTrue(OutagePairer.outages(in: events).isEmpty)
    }

    func testOnlyTheDownAndTheRestoreEntriesMatter() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "threat", event: .threatDetected, at: LogicFixture.time(10), wanID: nil),
            LogicFixture.monitoredEvent(id: "loss", event: .packetLoss, at: LogicFixture.time(20)),
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(30)),
            LogicFixture.monitoredEvent(id: "restore", event: .internetRestored, at: LogicFixture.time(90), duration: "1m 10s"),
        ]

        let outages = OutagePairer.outages(in: events)

        XCTAssertEqual(outages.count, 1)
        XCTAssertEqual(outages.first?.durationSeconds, 70)
    }

    func testTheDurationFallsBackToTheTimestamps() throws {
        // A restore entry without a readable DURATION: end minus start.
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(0)),
            LogicFixture.monitoredEvent(id: "restore", event: .internetRestored, at: LogicFixture.time(95)),
        ]

        let outage = try XCTUnwrap(OutagePairer.outages(in: events).first)

        XCTAssertEqual(outage.durationSeconds, 95)
        XCTAssertEqual(outage.durationText, "1 分 35 秒")
    }

    func testAnUnreadableGatewayDurationFallsBackToTheTimestamps() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(0)),
            LogicFixture.monitoredEvent(id: "restore", event: .internetRestored, at: LogicFixture.time(200), duration: "??"),
        ]

        let outage = try XCTUnwrap(OutagePairer.outages(in: events).first)

        XCTAssertEqual(outage.durationSeconds, 200)
    }

    func testTheOpenOutageOfALineIsTheNewestOne() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down1", event: .internetDown, at: LogicFixture.time(0), wanID: "WAN1"),
            LogicFixture.monitoredEvent(id: "restore1", event: .internetRestored, at: LogicFixture.time(60), wanID: "WAN1", duration: "1m"),
            LogicFixture.monitoredEvent(id: "down2", event: .internetDown, at: LogicFixture.time(120), wanID: "WAN1"),
            LogicFixture.monitoredEvent(id: "down3", event: .internetDown, at: LogicFixture.time(180), wanID: "WAN2"),
        ]

        let outages = OutagePairer.outages(in: events)

        XCTAssertEqual(OutagePairer.ongoingOutage(forWAN: "WAN1", in: outages)?.startLogID, "down2")
        XCTAssertEqual(OutagePairer.ongoingOutage(forWAN: "WAN2", in: outages)?.startLogID, "down3")
        XCTAssertEqual(OutagePairer.ongoingOutage(forWAN: "WAN3", in: outages)?.startLogID, nil)
    }

    func testAnOutageContainsItsOwnTimeRange() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(0)),
            LogicFixture.monitoredEvent(id: "restore", event: .internetRestored, at: LogicFixture.time(100), duration: "1m 40s"),
            LogicFixture.monitoredEvent(id: "open", event: .internetDown, at: LogicFixture.time(200)),
        ]

        let outages = OutagePairer.outages(in: events)

        XCTAssertEqual(OutagePairer.outage(containing: LogicFixture.time(50), in: outages)?.startLogID, "down")
        XCTAssertNil(OutagePairer.outage(containing: LogicFixture.time(150), in: outages))
        XCTAssertEqual(OutagePairer.outage(containing: LogicFixture.time(400), in: outages)?.startLogID, "open")
    }

}
