import XCTest
@testable import SentinelCore

final class LogTemplateTests: XCTestCase {
    func testNameWinsOverID() {
        let parameters: [String: LogParameter] = [
            "WAN_ID": LogParameter(id: "WAN", name: "WAN1"),
            "PORT": LogParameter(id: "10", name: "10"),
        ]

        XCTAssertEqual(
            LogTemplate.render("{WAN_ID} Internet Down on port {PORT}", parameters: parameters),
            "WAN1 Internet Down on port 10"
        )
    }

    func testIDIsTheFallbackWhenNameIsMissing() {
        let parameters: [String: LogParameter] = [
            "A": LogParameter(id: "only-id"),
            "B": LogParameter(id: "id", name: "name"),
            "C": LogParameter(id: "id", name: ""),
        ]

        XCTAssertEqual(LogTemplate.render("{A} {B} {C}", parameters: parameters), "only-id name id")
    }

    func testMissingPlaceholderIsKeptAsWritten() {
        let parameters: [String: LogParameter] = ["WAN_ID": LogParameter(name: "WAN1")]

        XCTAssertEqual(
            LogTemplate.render("{WAN_ID} down on {MISSING}", parameters: parameters),
            "WAN1 down on {MISSING}"
        )
        XCTAssertEqual(LogTemplate.render("no tokens", parameters: parameters), "no tokens")
        XCTAssertEqual(LogTemplate.render("{}", parameters: parameters), "{}")
        XCTAssertEqual(LogTemplate.render("{unclosed", parameters: parameters), "{unclosed")
    }

    func testParameterIgnoresExtraFields() throws {
        let entry = try SystemLogEntry.json([
            "id": "1",
            "timestamp": 1_000,
            "category": "INTERNET_AND_WAN",
            "key": "NETWORK_WAN_FAILED_2",
            "title_raw": "{WAN_ID} down",
            "message_raw": "{WAN_ID} on {PORT}",
            "parameters": [
                "WAN_ID": [
                    "id": "WAN",
                    "name": "WAN1",
                    "not_actionable": true,
                    "nested": ["unexpected": 1],
                ],
                "PORT": ["id": 10, "fingerprint_source": 0],
            ],
        ])

        XCTAssertEqual(entry.title, "WAN1 down")
        XCTAssertEqual(entry.message, "WAN1 on 10")
        XCTAssertEqual(entry.parameterValue("WAN_ID"), "WAN1")
        XCTAssertEqual(entry.parameterValue("PORT"), "10")
    }

    func testParameterWithoutIDOrNameIsIgnored() throws {
        let entry = try SystemLogEntry.json([
            "id": "1",
            "timestamp": 1_000,
            "category": "AUDIT",
            "key": "ADMIN_ACCESS",
            "title_raw": "{ADMIN} logged in",
            "parameters": ["ADMIN": ["not_actionable": true]],
        ])

        XCTAssertEqual(entry.title, "{ADMIN} logged in")
        XCTAssertNil(entry.parameterValue("ADMIN"))
    }

    func testNullParameterDoesNotFailTheEntry() throws {
        let entry = try SystemLogEntry.json([
            "id": "1",
            "timestamp": 1_000,
            "category": "AUDIT",
            "key": "ADMIN_ACCESS",
            "parameters": ["ADMIN": NSNull()],
        ])

        XCTAssertTrue(entry.parameters.isEmpty)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        let entry = try SystemLogEntry.json(["id": "1", "timestamp": 2])

        XCTAssertEqual(entry.category, "")
        XCTAssertEqual(entry.key, "")
        XCTAssertEqual(entry.title, "")
        XCTAssertEqual(entry.message, "")
        XCTAssertNil(entry.severity)
        XCTAssertFalse(entry.showOnDashboard)
        XCTAssertNil(entry.monitoredEvent)
    }
}
