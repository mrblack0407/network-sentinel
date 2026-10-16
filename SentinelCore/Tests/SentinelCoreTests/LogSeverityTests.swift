import XCTest
@testable import SentinelCore

final class LogSeverityTests: XCTestCase {
    func testSeverityOrder() {
        XCTAssertLessThan(LogSeverity.low, .medium)
        XCTAssertLessThan(LogSeverity.medium, .high)
        XCTAssertLessThan(LogSeverity.high, .veryHigh)
        XCTAssertLessThan(LogSeverity.low, .veryHigh)
        XCTAssertFalse(LogSeverity.veryHigh < .low)
    }

    func testRanks() {
        XCTAssertEqual(LogSeverity.low.rank, 1)
        XCTAssertEqual(LogSeverity.medium.rank, 2)
        XCTAssertEqual(LogSeverity.high.rank, 3)
        XCTAssertEqual(LogSeverity.veryHigh.rank, 4)
    }

    func testChineseDisplayNames() {
        XCTAssertEqual(LogSeverity.low.displayName, "低")
        XCTAssertEqual(LogSeverity.medium.displayName, "中")
        XCTAssertEqual(LogSeverity.high.displayName, "高")
        XCTAssertEqual(LogSeverity.veryHigh.displayName, "非常高")
    }

    func testParsingIsCaseInsensitiveAndTrimsWhitespace() {
        XCTAssertEqual(LogSeverity(rawValueString: " high "), .high)
        XCTAssertEqual(LogSeverity(rawValueString: "very_high"), .veryHigh)
        XCTAssertEqual(LogSeverity(rawValueString: "LOW"), .low)
    }

    func testUnknownSeverityIsNil() {
        XCTAssertNil(LogSeverity(rawValueString: "CRITICAL"))
        XCTAssertNil(LogSeverity(rawValueString: ""))
    }

    func testUnknownSeverityDoesNotFailThePage() throws {
        let pageJSON: [String: Any] = [
            "page_number": 0,
            "total_element_count": 2,
            "total_page_count": 1,
            "data": [
                ["id": "a", "timestamp": 1, "category": "INTERNET_AND_WAN", "key": "NETWORK_WAN_FAILED_2", "severity": "CRITICAL"],
                ["id": "b", "timestamp": 2, "category": "INTERNET_AND_WAN", "key": "NETWORK_WAN_RESTORED_2", "severity": "VERY_HIGH"],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: pageJSON)
        let page = try JSONDecoder().decode(SystemLogPageResponse.self, from: data)

        XCTAssertEqual(page.data.count, 2)
        XCTAssertNil(page.data[0].severity)
        XCTAssertEqual(page.data[1].severity, .veryHigh)
        XCTAssertEqual(page.data[0].monitoredEvent, .internetDown)
    }

    func testMissingSeverityIsNil() throws {
        let entry = try SystemLogEntry.json([
            "id": "a",
            "timestamp": 1,
            "category": "AUDIT",
            "key": "ADMIN_ACCESS",
        ])
        XCTAssertNil(entry.severity)
    }
}
