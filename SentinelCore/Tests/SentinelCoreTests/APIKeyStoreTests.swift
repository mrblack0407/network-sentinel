import Security
import XCTest
@testable import SentinelCore

/// The API Key store.
///
/// The tests only exercise the in-memory store and the shape of the keychain
/// query: nothing here writes to the system keychain.
final class APIKeyStoreTests: XCTestCase {
    private let apiKey = "SECRET-API-KEY-0123456789"

    // MARK: - In-memory store

    func testInitialStoreIsEmpty() throws {
        let store = APIKeyStoreInMemory()

        XCTAssertNil(try store.apiKey(forAccount: "192.168.8.254"))
    }

    func testSaveThenRead() throws {
        let store = APIKeyStoreInMemory()

        try store.save(apiKey, forAccount: "192.168.8.254")

        XCTAssertEqual(try store.apiKey(forAccount: "192.168.8.254"), apiKey)
    }

    func testSaveReplacesExistingValue() throws {
        let store = APIKeyStoreInMemory()

        try store.save("first-key", forAccount: "192.168.8.254")
        try store.save(apiKey, forAccount: "192.168.8.254")

        XCTAssertEqual(try store.apiKey(forAccount: "192.168.8.254"), apiKey)
        XCTAssertEqual(store.storedAccounts, ["192.168.8.254"])
    }

    func testRemoveForgetsTheValue() throws {
        let store = APIKeyStoreInMemory()
        try store.save(apiKey, forAccount: "192.168.8.254")

        XCTAssertTrue(try store.removeAPIKey(forAccount: "192.168.8.254"))
        XCTAssertNil(try store.apiKey(forAccount: "192.168.8.254"))
        XCTAssertTrue(store.storedAccounts.isEmpty)
    }

    func testRemovingAnUnknownAccountIsNotAnError() throws {
        let store = APIKeyStoreInMemory()

        XCTAssertFalse(try store.removeAPIKey(forAccount: "192.168.8.254"))
    }

    func testAccountsAreIndependent() throws {
        let store = APIKeyStoreInMemory()

        try store.save("key-one", forAccount: "192.168.8.254")
        try store.save("key-two", forAccount: "unifi.local")

        XCTAssertEqual(try store.apiKey(forAccount: "192.168.8.254"), "key-one")
        XCTAssertEqual(try store.apiKey(forAccount: "unifi.local"), "key-two")
    }

    // MARK: - Gateway address convenience

    func testStoreUsesTheNormalizedHostAsAccount() throws {
        let store = APIKeyStoreInMemory()
        let address = try GatewayAddress("https://UNIFI.local:443")

        try store.save(apiKey, for: address)

        XCTAssertEqual(try store.apiKey(forAccount: "unifi.local"), apiKey)
        XCTAssertEqual(try store.apiKey(for: address), apiKey)
        XCTAssertTrue(try store.removeAPIKey(for: address))
        XCTAssertNil(try store.apiKey(for: address))
    }

    // MARK: - Keychain query shape

    func testKeychainQueryCarriesClassServiceAndAccount() throws {
        let query = KeychainAPIKeyStore.baseQuery(forAccount: "192.168.8.254")

        XCTAssertEqual(query.count, 3)
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "com.mrblack0407.NetworkSentinel")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "192.168.8.254")
        XCTAssertNil(query[kSecAttrAccessible as String])
        XCTAssertNil(query[kSecValueData as String])
    }

    func testServiceIsTheAppBundleIdentifier() {
        XCTAssertEqual(KeychainAPIKeyStore.service, "com.mrblack0407.NetworkSentinel")
    }

    func testAccessibilityDoesNotSyncToICloud() {
        let accessible = KeychainAPIKeyStore.accessibility as String

        // The constant's raw value is an opaque short code, so compare constants only.
        XCTAssertEqual(accessible, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertNotEqual(accessible, kSecAttrAccessibleAfterFirstUnlock as String)
    }

    // MARK: - Errors

    func testKeychainErrorTextIsChineseAndCarriesTheStatus() {
        let error = APIKeyStoreError.keychain(status: errSecDuplicateItem)
        let description = error.localizedDescription

        XCTAssertTrue(description.contains("钥匙串"))
        XCTAssertTrue(description.contains("\(errSecDuplicateItem)"))
        XCTAssertFalse(description.contains(apiKey))
    }

    func testUnreadableValueErrorTextIsChinese() {
        let description = APIKeyStoreError.unreadableValue.localizedDescription

        XCTAssertTrue(description.contains("API Key"))
        XCTAssertFalse(description.contains(apiKey))
    }
}
