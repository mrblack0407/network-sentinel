import XCTest
@testable import SentinelCore

final class MonitoredEventDetectionTests: XCTestCase {
    private let wanCategory = "INTERNET_AND_WAN"

    func testAllSevenEventKindsAreDetected() {
        XCTAssertEqual(MonitoredEvent.detect(category: wanCategory, key: "NETWORK_WAN_FAILED_2"), .internetDown)
        XCTAssertEqual(MonitoredEvent.detect(category: wanCategory, key: "NETWORK_WAN_RESTORED_2"), .internetRestored)
        XCTAssertEqual(
            MonitoredEvent.detect(category: wanCategory, key: "NETWORK_WAN_FAILED_MULTIPLE_TIMES_2"),
            .internetDownMultipleTimes
        )
        XCTAssertEqual(
            MonitoredEvent.detect(category: wanCategory, key: "NETWORK_WAN_FAILED_TEMPORARY_2"),
            .internetDownTemporary
        )
        XCTAssertEqual(MonitoredEvent.detect(category: wanCategory, key: "ISP_PACKET_LOSS_2"), .packetLoss)
        XCTAssertEqual(MonitoredEvent.detect(category: wanCategory, key: "ISP_HIGH_LATENCY_2"), .highLatency)
        XCTAssertEqual(MonitoredEvent.detect(category: "SECURITY", key: "THREAT_DETECTED_V3"), .threatDetected)
    }

    func testVersionSuffixIsIgnored() {
        XCTAssertEqual(MonitoredEvent.normalizedKey("NETWORK_WAN_FAILED_3"), "NETWORK_WAN_FAILED")
        XCTAssertEqual(MonitoredEvent.normalizedKey("NETWORK_WAN_FAILED_V3"), "NETWORK_WAN_FAILED")
        XCTAssertEqual(MonitoredEvent.normalizedKey("THREAT_DETECTED_V3"), "THREAT_DETECTED")

        XCTAssertEqual(MonitoredEvent.detect(category: wanCategory, key: "NETWORK_WAN_FAILED_3"), .internetDown)
        XCTAssertEqual(MonitoredEvent.detect(category: wanCategory, key: "NETWORK_WAN_RESTORED_4"), .internetRestored)
        XCTAssertEqual(MonitoredEvent.detect(category: wanCategory, key: "ISP_PACKET_LOSS_V9"), .packetLoss)
        XCTAssertEqual(MonitoredEvent.detect(category: wanCategory, key: "ISP_HIGH_LATENCY_7"), .highLatency)
    }

    func testMultipleTimesAndTemporaryAreNotPlainInternetDown() {
        XCTAssertEqual(
            MonitoredEvent.detect(category: wanCategory, key: "NETWORK_WAN_FAILED_MULTIPLE_TIMES_2"),
            .internetDownMultipleTimes
        )
        XCTAssertEqual(
            MonitoredEvent.detect(category: wanCategory, key: "NETWORK_WAN_FAILED_TEMPORARY_2"),
            .internetDownTemporary
        )
        XCTAssertNotEqual(
            MonitoredEvent.detect(category: wanCategory, key: "NETWORK_WAN_FAILED_MULTIPLE_TIMES_2"),
            .internetDown
        )
        XCTAssertNotEqual(
            MonitoredEvent.detect(category: wanCategory, key: "NETWORK_WAN_FAILED_TEMPORARY_2"),
            .internetDown
        )
    }

    func testTheTypeFieldIsIrrelevant() throws {
        // WAN outages share `BACKUP_CONNECTION_IN_USE` with unmonitored entries.
        let outage = try SystemLogEntry.json([
            "id": "1",
            "timestamp": 1,
            "category": wanCategory,
            "key": "NETWORK_WAN_FAILED_2",
            "type": "BACKUP_CONNECTION_IN_USE",
        ])
        XCTAssertEqual(outage.monitoredEvent, .internetDown)
    }

    func testThreatsAreRecognizedByCategoryOnly() {
        XCTAssertEqual(MonitoredEvent.detect(category: "SECURITY", key: "SOMETHING_NEW_7"), .threatDetected)
        XCTAssertEqual(
            MonitoredEvent.detect(category: "security", key: "THREAT_DETECTED_KNOWN_SOURCE_CLIENT"),
            .threatDetected
        )
    }

    func testUnmonitoredEntries() {
        XCTAssertNil(MonitoredEvent.detect(category: "CLIENT_DEVICES", key: "CLIENT_CONNECTED_WIRED_2"))
        XCTAssertNil(MonitoredEvent.detect(category: "CLIENT_DEVICES", key: "CLIENT_DISCONNECTED_WIRELESS_2"))
        XCTAssertNil(MonitoredEvent.detect(category: "AUDIT", key: "ADMIN_ACCESS"))
        XCTAssertNil(MonitoredEvent.detect(category: "SOFTWARE_UPDATES", key: "NETWORK_UPDATED"))
        XCTAssertNil(MonitoredEvent.detect(category: "INTERNET_AND_WAN", key: "BACKUP_CONNECTION_IN_USE"))
    }

    func testChineseDisplayNames() {
        XCTAssertEqual(MonitoredEvent.internetDown.displayName, "互联网中断")
        XCTAssertEqual(MonitoredEvent.internetRestored.displayName, "互联网已恢复")
        XCTAssertEqual(MonitoredEvent.internetDownMultipleTimes.displayName, "多次互联网中断")
        XCTAssertEqual(MonitoredEvent.internetDownTemporary.displayName, "临时互联网中断")
        XCTAssertEqual(MonitoredEvent.packetLoss.displayName, "检测到丢包")
        XCTAssertEqual(MonitoredEvent.highLatency.displayName, "检测到高延迟")
        XCTAssertEqual(MonitoredEvent.threatDetected.displayName, "检测到威胁")
    }

    func testEventCount() {
        XCTAssertEqual(MonitoredEvent.allCases.count, 7)
    }
}
