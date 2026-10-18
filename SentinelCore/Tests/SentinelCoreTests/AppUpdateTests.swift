import XCTest
@testable import SentinelCore

/// The version comparison and the GitHub answer of the update check.
final class AppUpdateTests: XCTestCase {
    // MARK: - Version comparison

    func testANewerReleaseIsNewer() {
        XCTAssertTrue(AppUpdate.isNewer("0.3", than: "0.2"))
        XCTAssertTrue(AppUpdate.isNewer("v0.3", than: "0.2"))
        XCTAssertTrue(AppUpdate.isNewer("v0.3", than: "v0.2"))
        XCTAssertTrue(AppUpdate.isNewer("0.10", than: "0.2"))
        XCTAssertTrue(AppUpdate.isNewer("v0.10", than: "0.2"))
        XCTAssertTrue(AppUpdate.isNewer(" 0.3 ", than: "0.2"))
    }

    func testTheSameOrAnOlderReleaseIsNotNewer() {
        XCTAssertFalse(AppUpdate.isNewer("0.2", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("v0.2", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("0.1", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("v0.1", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("v0.03", than: "0.3"))
    }

    func testAMissingSegmentCountsAsZero() {
        XCTAssertFalse(AppUpdate.isNewer("0.2.0", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("0.2", than: "0.2.0"))
        XCTAssertTrue(AppUpdate.isNewer("0.2.1", than: "0.2"))
        XCTAssertTrue(AppUpdate.isNewer("0.3", than: "0.2.9"))
        XCTAssertTrue(AppUpdate.isNewer("1.0", than: "0.9.9"))
    }

    func testTextsThatAreNoVersionAreNeverNewer() {
        XCTAssertFalse(AppUpdate.isNewer("", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("v", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("0.3-beta", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("0..3", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("0.3.", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer(".0.3", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("0,3", than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer("Next", than: "0.2"))
        // A local version the app cannot read cannot be improved on either.
        XCTAssertFalse(AppUpdate.isNewer("0.3", than: "0.2-beta"))
    }

    // MARK: - Endpoint

    func testTheEndpointComesFromTheRepositoryAddress() {
        let endpoint = AppUpdate.latestReleaseEndpoint(
            for: URL(string: "https://github.com/example/network-sentinel")!
        )

        XCTAssertEqual(
            endpoint?.absoluteString,
            "https://api.github.com/repos/example/network-sentinel/releases/latest"
        )
    }

    func testATrailingSlashIsTheSameRepository() {
        let endpoint = AppUpdate.latestReleaseEndpoint(
            for: URL(string: "https://github.com/example/network-sentinel/")!
        )

        XCTAssertEqual(
            endpoint?.absoluteString,
            "https://api.github.com/repos/example/network-sentinel/releases/latest"
        )
    }

    func testAnAddressWithoutARepositoryHasNoEndpoint() {
        XCTAssertNil(AppUpdate.latestReleaseEndpoint(for: URL(string: "https://github.com/example")!))
        XCTAssertNil(AppUpdate.latestReleaseEndpoint(for: URL(string: "https://github.com")!))
    }

    // MARK: - Answer

    func testTheAnswerGivesTheVersionAndTheReleasePage() throws {
        let release = try XCTUnwrap(AppUpdate.release(fromLatestRelease: releaseJSON(tag: "v0.10")))

        XCTAssertEqual(release.version, "0.10")
        XCTAssertEqual(
            release.pageURL.absoluteString,
            "https://github.com/example/network-sentinel/releases/tag/v0.10"
        )
    }

    func testTheTagMayComeWithoutTheV() throws {
        let release = try XCTUnwrap(AppUpdate.release(fromLatestRelease: releaseJSON(tag: "0.3")))

        XCTAssertEqual(release.version, "0.3")
    }

    func testAnAnswerWithoutTheFlagsIsNoDraft() throws {
        let data = Data(
            #"{"tag_name":"v0.3","html_url":"https://github.com/example/network-sentinel/releases/tag/v0.3"}"#.utf8
        )

        let release = try XCTUnwrap(AppUpdate.release(fromLatestRelease: data))
        XCTAssertEqual(release.version, "0.3")
    }

    func testADraftIsNoRelease() {
        XCTAssertNil(AppUpdate.release(fromLatestRelease: releaseJSON(draft: true)))
    }

    func testAPrereleaseIsNoRelease() {
        XCTAssertNil(AppUpdate.release(fromLatestRelease: releaseJSON(prerelease: true)))
    }

    func testAnAnswerWithoutTheReadableFieldsIsNoRelease() {
        XCTAssertNil(AppUpdate.release(fromLatestRelease: Data(#"{"html_url":"https://example.com/release"}"#.utf8)))
        XCTAssertNil(AppUpdate.release(fromLatestRelease: Data(#"{"tag_name":"v0.3"}"#.utf8)))
        XCTAssertNil(AppUpdate.release(fromLatestRelease: Data(#"{"tag_name":"vNext","html_url":"https://example.com/release"}"#.utf8)))
        XCTAssertNil(AppUpdate.release(fromLatestRelease: Data(#"{"tag_name":"v0.3","html_url":"not a page"}"#.utf8)))
        XCTAssertNil(AppUpdate.release(fromLatestRelease: Data(#"{"tag_name":"v0.3","html_url":"ftp://example.com/release"}"#.utf8)))
    }

    func testAnAnswerThatIsNoJSONIsNoRelease() {
        XCTAssertNil(AppUpdate.release(fromLatestRelease: Data("not JSON".utf8)))
        XCTAssertNil(AppUpdate.release(fromLatestRelease: Data()))
    }

    func testTheAnswerDecidesTheUpdateAgainstTheLocalVersion() throws {
        let release = try XCTUnwrap(AppUpdate.release(fromLatestRelease: releaseJSON(tag: "v0.3")))

        XCTAssertTrue(AppUpdate.isNewer(release.version, than: "0.2"))
        XCTAssertFalse(AppUpdate.isNewer(release.version, than: "0.3"))
    }

    // MARK: - Helpers

    /// The answer of `releases/latest` with the fields the app reads.
    ///
    /// The addresses are examples, so no real host is needed for the check.
    private func releaseJSON(
        tag: String = "v0.3",
        draft: Bool = false,
        prerelease: Bool = false
    ) -> Data {
        Data(
            """
            {
              "tag_name": "\(tag)",
              "html_url": "https://github.com/example/network-sentinel/releases/tag/\(tag)",
              "draft": \(draft),
              "prerelease": \(prerelease)
            }
            """.utf8
        )
    }
}
