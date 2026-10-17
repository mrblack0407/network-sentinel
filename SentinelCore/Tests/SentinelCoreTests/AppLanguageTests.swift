import XCTest
@testable import SentinelCore

final class AppLanguageTests: XCTestCase {
    func testAFixedLanguageIgnoresTheMac() {
        XCTAssertEqual(AppLanguage.chinese.resolved(preferredLanguages: ["en-US"]), .chinese)
        XCTAssertEqual(AppLanguage.english.resolved(preferredLanguages: ["zh-Hans-CN"]), .english)
    }

    func testSystemFollowsTheMostPreferredLanguage() {
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-Hans-CN", "en-US"]), .chinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-Hant-TW"]), .chinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["en-US", "zh-Hans-CN"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: []), .english)
    }
}
