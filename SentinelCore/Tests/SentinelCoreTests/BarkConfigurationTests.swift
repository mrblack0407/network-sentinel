import XCTest
@testable import SentinelCore

/// Reading what the user pasted into the Bark field of the 通知 page.
///
/// The Key is a secret: every error text is checked to be free of it.
final class BarkConfigurationTests: XCTestCase {
    /// A fake device Key, shaped like the 22 characters Bark generates.
    private let key = "abcdEFGH1234"

    // MARK: - Key alone

    func testKeyAloneUsesTheDefaultServer() throws {
        let configuration = try BarkConfiguration.parse(input: "  \(key)\n")

        XCTAssertEqual(configuration.deviceKey, key)
        XCTAssertEqual(configuration.serverAddress, "https://api.day.app")
        XCTAssertEqual(configuration.pushURL.absoluteString, "https://api.day.app/push")
    }

    func testKeyAloneKeepsTheConfiguredServer() throws {
        let configuration = try BarkConfiguration.parse(
            input: key,
            defaultServerAddress: "http://192.168.1.10:8080"
        )

        XCTAssertEqual(configuration.deviceKey, key)
        XCTAssertEqual(configuration.serverAddress, "http://192.168.1.10:8080")
        XCTAssertEqual(configuration.pushURL.absoluteString, "http://192.168.1.10:8080/push")
    }

    // MARK: - Whole push link

    func testPushLinkWithTrailingSlashIsRead() throws {
        let configuration = try BarkConfiguration.parse(input: "https://api.day.app/\(key)/")

        XCTAssertEqual(configuration.deviceKey, key)
        XCTAssertEqual(configuration.serverAddress, "https://api.day.app")
    }

    func testPushLinkWithoutTrailingSlashIsRead() throws {
        let configuration = try BarkConfiguration.parse(input: "https://api.day.app/\(key)")

        XCTAssertEqual(configuration.deviceKey, key)
        XCTAssertEqual(configuration.serverAddress, "https://api.day.app")
    }

    func testPushLinkWithTitlePathKeepsOnlyTheKey() throws {
        let configuration = try BarkConfiguration.parse(
            input: "https://api.day.app/\(key)/Internet%20Down/WAN1%20is%20down"
        )

        XCTAssertEqual(configuration.deviceKey, key)
        XCTAssertEqual(configuration.serverAddress, "https://api.day.app")
    }

    func testPushLinkOverridesTheTypedServer() throws {
        let configuration = try BarkConfiguration.parse(
            input: "https://api.day.app/\(key)/",
            defaultServerAddress: "https://bark.example.com/base"
        )

        XCTAssertEqual(configuration.serverAddress, "https://api.day.app")
    }

    // MARK: - Self-hosted server

    func testSelfHostedLinkKeepsSchemeAndPort() throws {
        let configuration = try BarkConfiguration.parse(input: "http://192.168.1.10:8080/\(key)")

        XCTAssertEqual(configuration.deviceKey, key)
        XCTAssertEqual(configuration.serverAddress, "http://192.168.1.10:8080")
        XCTAssertEqual(configuration.pushURL.absoluteString, "http://192.168.1.10:8080/push")
    }

    func testServerFieldWithSubpathAndSlashIsNormalized() throws {
        let configuration = try BarkConfiguration.parse(
            server: "https://bark.example.com/base/",
            key: key
        )

        XCTAssertEqual(configuration.serverAddress, "https://bark.example.com/base")
        XCTAssertEqual(configuration.pushURL.absoluteString, "https://bark.example.com/base/push")
    }

    func testServerFieldWithoutSchemeBecomesHTTPS() throws {
        let configuration = try BarkConfiguration.parse(server: "bark.example.com", key: key)

        XCTAssertEqual(configuration.serverAddress, "https://bark.example.com")
    }

    func testEmptyServerFieldFallsBackToTheDefaultServer() throws {
        let configuration = try BarkConfiguration.parse(server: "   ", key: key)

        XCTAssertEqual(configuration.serverAddress, BarkConfiguration.defaultServerAddress)
    }

    func testSelfHostedIPv6ServerKeepsOnePairOfBrackets() throws {
        let configuration = try BarkConfiguration.parse(server: "http://[fe80::1]:8080", key: key)

        XCTAssertEqual(configuration.serverAddress, "http://[fe80::1]:8080")
        XCTAssertEqual(configuration.pushURL.absoluteString, "http://[fe80::1]:8080/push")
    }

    func testServerQueryAndTrailingSlashAreDropped() throws {
        let configuration = try BarkConfiguration.parse(
            server: "https://bark.example.com/?token=1#top",
            key: key
        )

        XCTAssertEqual(configuration.serverAddress, "https://bark.example.com")
    }

    // MARK: - Refused input

    func testEmptyInputAsksForAKey() {
        assertParseFails(.missingKey, input: "")
        assertParseFails(.missingKey, input: "   \n")
    }

    func testLinkWithoutAKeyAsksForAKey() {
        assertParseFails(.missingKey, input: "https://api.day.app")
        assertParseFails(.missingKey, input: "https://api.day.app/")
    }

    func testGarbageIsNotAKey() {
        assertParseFails(.invalidKey, input: "这不是 key")
        assertParseFails(.invalidKey, input: "!!!")
        assertParseFails(.invalidKey, input: "ab cd")
        assertParseFails(.invalidKey, input: "key/with/slash")
        assertParseFails(.invalidKey, input: "\(key)==")
    }

    func testUnsupportedSchemeIsNotAServer() {
        assertParseFails(.invalidServer, input: "ftp://api.day.app/\(key)")
    }

    func testALinkWithoutAHostIsNotAServer() {
        assertParseFails(.invalidServer, input: "https:///\(key)")
        assertParseFails(.invalidServer, input: "https://:/\(key)")
        assertParseFails(.invalidServer, input: "https://.../\(key)")
    }

    func testAnAddressThatIsNoURLIsNotAServer() {
        assertParseFails(.invalidServer, input: "https://api.day.app:99999/\(key)")
    }

    func testKeyFieldWithAServerWithoutKeyAsksForAKey() {
        assertParseFails(.missingKey, input: "https://api.day.app/")
    }

    // MARK: - Chinese messages

    func testMessagesAreChinese() {
        XCTAssertEqual(BarkConfigurationError.missingKey.errorDescription, "请输入 Bark Key")
        XCTAssertEqual(BarkConfigurationError.invalidServer.errorDescription, "服务器地址格式不对")
        XCTAssertNotNil(BarkConfigurationError.invalidKey.errorDescription)
        XCTAssertTrue(
            (BarkConfigurationError.invalidKey.errorDescription ?? "").contains("格式不对")
        )
    }

    func testErrorTextNeverCarriesTheKey() {
        let secrets = [
            "https://api.day.app/",
            "not-a-key!\(key)",
            "https://api.day.app:99999/\(key)",
        ]

        for input in secrets {
            do {
                let configuration = try BarkConfiguration.parse(input: input)
                XCTAssertFalse(
                    configuration.serverAddress.contains(key) || configuration.deviceKey.contains("!"),
                    "unexpected success for \(input)"
                )
            } catch {
                XCTAssertFalse(
                    error.localizedDescription.contains(key),
                    "error of \(input) carries the Key: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Keychain account

    func testTheKeychainAccountIsBark() throws {
        XCTAssertEqual(BarkConfiguration.keychainAccount, "bark")

        let store = APIKeyStoreInMemory()
        try store.save(key, forAccount: BarkConfiguration.keychainAccount)

        XCTAssertEqual(try store.apiKey(forAccount: "bark"), key)
        XCTAssertEqual(store.storedAccounts, ["bark"])
    }

    // MARK: - Helpers

    /// Asserts that a parse fails with one reason.
    private func assertParseFails(
        _ expected: BarkConfigurationError,
        input: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let configuration = try BarkConfiguration.parse(input: input)
            XCTFail("expected \(expected), got \(configuration)", file: file, line: line)
        } catch let error as BarkConfigurationError {
            XCTAssertEqual(error, expected, "message: \(error.localizedDescription)", file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
