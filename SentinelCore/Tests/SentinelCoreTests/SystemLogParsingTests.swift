import XCTest
@testable import SentinelCore

final class SystemLogParsingTests: XCTestCase {
    func testBothPagesParseAndMatchTotalElementCount() throws {
        let page0 = try Fixture.logPage("system-log-page0.json")
        let page1 = try Fixture.logPage("system-log-page1.json")

        XCTAssertEqual(page0.pageNumber, 0)
        XCTAssertEqual(page1.pageNumber, 1)
        XCTAssertEqual(page0.totalPageCount, 2)
        XCTAssertEqual(page0.totalElementCount, 140)
        XCTAssertEqual(page0.data.count, 70)
        XCTAssertEqual(page1.data.count, 70)
        XCTAssertEqual(page0.data.count + page1.data.count, page0.totalElementCount)
    }

    func testEmptyPageParses() throws {
        let page = try Fixture.logPage("system-log-empty.json")

        XCTAssertEqual(page.pageNumber, 0)
        XCTAssertEqual(page.totalElementCount, 0)
        XCTAssertEqual(page.totalPageCount, 0)
        XCTAssertTrue(page.data.isEmpty)
    }

    func testEveryMonitoredEventKindAppearsWithTheExpectedCount() throws {
        let entries = try Fixture.allLogEntries()
        XCTAssertEqual(entries.count, 140)

        let monitored = entries.compactMap { $0.monitoredEvent }
        let counts = Dictionary(grouping: monitored, by: { $0 }).mapValues { $0.count }

        XCTAssertEqual(Set(counts.keys), Set(MonitoredEvent.allCases))
        XCTAssertEqual(counts[.internetDown], 30)
        XCTAssertEqual(counts[.internetRestored], 30)
        XCTAssertEqual(counts[.internetDownMultipleTimes], 7)
        XCTAssertEqual(counts[.internetDownTemporary], 8)
        XCTAssertEqual(counts[.packetLoss], 22)
        XCTAssertEqual(counts[.highLatency], 1)
        XCTAssertEqual(counts[.threatDetected], 18)
        XCTAssertEqual(monitored.count, 116)

        // Everything else is not monitored: clients, AUDIT, firmware update.
        XCTAssertEqual(entries.count - monitored.count, 24)
    }

    func testMonitoredLogEventsCarryTheEventAndTheEntry() throws {
        let entries = try Fixture.allLogEntries()
        let events = SystemLogEntry.monitoredLogEvents(in: entries)

        XCTAssertEqual(events.count, 116)
        XCTAssertEqual(events.count, entries.compactMap { $0.monitoredLogEvent }.count)

        let firstMonitored = try XCTUnwrap(entries.first { $0.monitoredEvent != nil })
        XCTAssertEqual(events.first?.entry, firstMonitored)
        XCTAssertEqual(events.first?.event, firstMonitored.monitoredEvent)
        XCTAssertEqual(events.first?.entry.id, firstMonitored.id)
    }

    func testInternetDownTitleAndMessageAreFilled() throws {
        let entry = try XCTUnwrap(try Fixture.allLogEntries().first { $0.id == "000000000000000000000021" })

        XCTAssertEqual(entry.key, "NETWORK_WAN_FAILED_2")
        XCTAssertEqual(entry.monitoredEvent, .internetDown)
        XCTAssertEqual(entry.titleRaw, "{WAN_ID} Internet Down")
        XCTAssertEqual(entry.title, "WAN1 Internet Down")
        XCTAssertEqual(
            entry.message,
            "Internet connection WAN1 China Telecom on port 10 is down."
        )
        XCTAssertEqual(entry.wanID, "WAN1")
        XCTAssertEqual(entry.ispName, "China Telecom")
        XCTAssertEqual(entry.severity, .veryHigh)
        XCTAssertEqual(entry.severity?.displayName, "非常高")
        XCTAssertTrue(entry.showOnDashboard)
    }

    func testThreatTitleAndMessageAreFilled() throws {
        let entry = try XCTUnwrap(try Fixture.allLogEntries().first { $0.id == "000000000000000000000056" })
        let event = try XCTUnwrap(entry.monitoredLogEvent)

        XCTAssertEqual(entry.category, "SECURITY")
        XCTAssertEqual(entry.key, "THREAT_DETECTED_V3")
        XCTAssertEqual(event.event, .threatDetected)
        XCTAssertEqual(entry.title, "Threat Detected")
        XCTAssertEqual(
            entry.message,
            "A network intrusion attempt from 10.20.0.2 to 203.0.113.20 has been detected."
        )
        XCTAssertEqual(event.source, ThreatEndpoint(value: "10.20.0.2", isClient: false))
        XCTAssertEqual(event.destination, ThreatEndpoint(value: "203.0.113.20", isClient: false))
    }

    func testThreatWithClientsUsesTheClientNames() throws {
        let entry = try XCTUnwrap(
            try Fixture.allLogEntries().first { $0.key == "THREAT_DETECTED_KNOWN_SOURCE_AND_DESTINATION_CLIENTS" }
        )
        let event = try XCTUnwrap(entry.monitoredLogEvent)

        XCTAssertEqual(event.source, ThreatEndpoint(value: "Client 13", isClient: true))
        XCTAssertEqual(event.destination, ThreatEndpoint(value: "Client 13", isClient: true))
        XCTAssertEqual(
            event.message,
            "A network intrusion attempt from Client 13 to Client 13 has been detected."
        )
    }

    func testRestoredEventCarriesDurationInSeconds() throws {
        let entry = try XCTUnwrap(try Fixture.allLogEntries().first { $0.id == "000000000000000000000020" })
        let event = try XCTUnwrap(entry.monitoredLogEvent)

        XCTAssertEqual(event.event, .internetRestored)
        XCTAssertEqual(event.wanID, "WAN1")
        XCTAssertEqual(event.ispName, "China Telecom")
        XCTAssertEqual(event.durationText, "1m 25s")
        XCTAssertEqual(event.durationSeconds, 85)
        XCTAssertEqual(event.title, "WAN1 Internet Restored")
    }

    func testHighLatencyEventCarriesLatencyInMilliseconds() throws {
        let entry = try XCTUnwrap(
            try Fixture.allLogEntries().first { $0.key == "ISP_HIGH_LATENCY_2" }
        )
        let event = try XCTUnwrap(entry.monitoredLogEvent)

        XCTAssertEqual(event.event, .highLatency)
        XCTAssertEqual(event.latencyMilliseconds, 45)
        XCTAssertNil(event.durationText)
    }

    func testPacketLossEvent() throws {
        let entry = try XCTUnwrap(try Fixture.allLogEntries().first { $0.key == "ISP_PACKET_LOSS_2" })
        let event = try XCTUnwrap(entry.monitoredLogEvent)

        XCTAssertEqual(event.event, .packetLoss)
        XCTAssertEqual(event.wanID, "WAN1")
        XCTAssertEqual(event.ispName, "China Telecom")
    }

    func testUnmonitoredEntryHasNoMonitoredLogEvent() throws {
        let entry = try XCTUnwrap(
            try Fixture.allLogEntries().first { $0.category == "CLIENT_DEVICES" }
        )

        XCTAssertNil(entry.monitoredEvent)
        XCTAssertNil(entry.monitoredLogEvent)
    }

    func testTimestampIsReadAsMilliseconds() throws {
        let entry = try XCTUnwrap(try Fixture.allLogEntries().first { $0.id == "000000000000000000000020" })

        XCTAssertEqual(entry.timestampMilliseconds, 1_792_103_589_801)
        XCTAssertEqual(entry.timestamp.timeIntervalSince1970, 1_792_103_589.801, accuracy: 0.001)
    }
}
