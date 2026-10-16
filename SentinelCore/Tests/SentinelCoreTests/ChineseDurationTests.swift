import XCTest
@testable import SentinelCore

final class ChineseDurationTests: XCTestCase {
    func testSeconds() {
        XCTAssertEqual(ChineseDuration.text(seconds: 48), "48 秒")
        XCTAssertEqual(ChineseDuration.text(seconds: 1), "1 秒")
        XCTAssertEqual(ChineseDuration.text(seconds: 59), "59 秒")
    }

    func testMinutesAndSeconds() {
        XCTAssertEqual(ChineseDuration.text(seconds: 85), "1 分 25 秒")
        XCTAssertEqual(ChineseDuration.text(seconds: 60), "1 分")
        XCTAssertEqual(ChineseDuration.text(seconds: 114), "1 分 54 秒")
        XCTAssertEqual(ChineseDuration.text(seconds: 3_599), "59 分 59 秒")
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(ChineseDuration.text(seconds: 7_380), "2 小时 3 分")
        XCTAssertEqual(ChineseDuration.text(seconds: 3_600), "1 小时")
        XCTAssertEqual(ChineseDuration.text(seconds: 23_760), "6 小时 36 分")
        // Seconds are dropped once the value reaches an hour.
        XCTAssertEqual(ChineseDuration.text(seconds: 3_661), "1 小时 1 分")
    }

    func testDaysAndHours() {
        XCTAssertEqual(ChineseDuration.text(seconds: 93_600), "1 天 2 小时")
        XCTAssertEqual(ChineseDuration.text(seconds: 86_400), "1 天")
        // Minutes are dropped once the value reaches a day.
        XCTAssertEqual(ChineseDuration.text(seconds: 90_120), "1 天 1 小时")
    }

    func testZeroAndNegative() {
        XCTAssertEqual(ChineseDuration.text(seconds: 0), "0 秒")
        XCTAssertEqual(ChineseDuration.text(seconds: -5), "0 秒")
    }

    func testIntervalsAreRoundedToWholeSeconds() {
        XCTAssertEqual(ChineseDuration.text(87), "1 分 27 秒")
        XCTAssertEqual(ChineseDuration.text(87.4), "1 分 27 秒")
        XCTAssertEqual(ChineseDuration.text(87.6), "1 分 28 秒")
        XCTAssertEqual(ChineseDuration.text(-3), "0 秒")
    }
}
