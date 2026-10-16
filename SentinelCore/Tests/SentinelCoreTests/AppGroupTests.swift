import XCTest
@testable import SentinelCore

final class AppGroupTests: XCTestCase {
    func testIdentifier() {
        XCTAssertEqual(AppGroup.identifier, "group.com.mrblack0407.NetworkSentinel")
    }

    func testIdentifierIsAValidAppGroupIdentifier() {
        XCTAssertTrue(AppGroup.identifier.hasPrefix("group."))
    }
}
