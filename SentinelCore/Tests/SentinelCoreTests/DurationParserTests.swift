import XCTest
@testable import SentinelCore

final class DurationParserTests: XCTestCase {
    func testFormatsSeenOnTheGateway() {
        XCTAssertEqual(DurationParser.seconds(from: "48s"), 48)
        XCTAssertEqual(DurationParser.seconds(from: "1m 25s"), 85)
        XCTAssertEqual(DurationParser.seconds(from: "22m 42s"), 1_362)
        XCTAssertEqual(DurationParser.seconds(from: "2h 3m"), 7_380)
        XCTAssertEqual(DurationParser.seconds(from: "6h 36m"), 23_760)
    }

    func testLongerAndShorterUnits() {
        XCTAssertEqual(DurationParser.seconds(from: "1d 2h"), 93_600)
        XCTAssertEqual(DurationParser.seconds(from: "2d"), 172_800)
        XCTAssertEqual(DurationParser.seconds(from: "1h"), 3_600)
        XCTAssertEqual(DurationParser.seconds(from: "5m"), 300)
        XCTAssertEqual(DurationParser.seconds(from: "0s"), 0)
    }

    func testExtraWhitespaceAndCase() {
        XCTAssertEqual(DurationParser.seconds(from: "  2H 3M "), 7_380)
        XCTAssertEqual(DurationParser.seconds(from: "1m,25s"), 85)
    }

    func testUnreadableValuesAreNil() {
        XCTAssertNil(DurationParser.seconds(from: ""))
        XCTAssertNil(DurationParser.seconds(from: "   "))
        XCTAssertNil(DurationParser.seconds(from: "soon"))
        XCTAssertNil(DurationParser.seconds(from: "5x"))
        XCTAssertNil(DurationParser.seconds(from: "m"))
    }

    func testEveryFixtureDurationParses() throws {
        var seen: Set<String> = []
        for entry in try Fixture.allLogEntries() {
            guard let text = entry.durationText else { continue }
            seen.insert(text)
            XCTAssertNotNil(entry.durationSeconds, "duration \(text) did not parse")
        }
        XCTAssertFalse(seen.isEmpty)
        XCTAssertTrue(seen.contains("48s"))
        XCTAssertTrue(seen.contains("1m 25s"))
        XCTAssertTrue(seen.contains("22m 42s"))
        XCTAssertTrue(seen.contains("2h 3m"))
        XCTAssertTrue(seen.contains("6h 36m"))
    }
}
