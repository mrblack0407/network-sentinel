import Foundation
import Security

/// Stores the API Key of one UniFi gateway.
///
/// The API Key only ever lives in the keychain. Everything the app talks to is
/// this protocol, so tests and previews use `APIKeyStoreInMemory` and never
/// touch the system keychain.
public protocol APIKeyStoring {
    /// The stored API Key, or `nil` when the account has none.
    func apiKey(forAccount account: String) throws -> String?
    /// Stores the API Key, replacing the value of an existing account.
    func save(_ apiKey: String, forAccount account: String) throws
    /// Removes the stored API Key. Removing an unknown account is not an error.
    @discardableResult
    func removeAPIKey(forAccount account: String) throws -> Bool
}

extension APIKeyStoring {
    /// The account used for a gateway address: its normalized host.
    public func apiKey(for address: GatewayAddress) throws -> String? {
        try apiKey(forAccount: address.displayHost)
    }

    /// Stores the API Key of a gateway address.
    public func save(_ apiKey: String, for address: GatewayAddress) throws {
        try save(apiKey, forAccount: address.displayHost)
    }

    /// Forgets the API Key of a gateway address.
    @discardableResult
    public func removeAPIKey(for address: GatewayAddress) throws -> Bool {
        try removeAPIKey(forAccount: address.displayHost)
    }
}

/// Why a keychain operation failed.
///
/// The case never carries the API Key, so an error can be shown or logged.
public enum APIKeyStoreError: Error, Equatable {
    /// The Security framework refused the operation.
    case keychain(status: OSStatus)
    /// The stored value could not be read as UTF-8 text.
    case unreadableValue
}

extension APIKeyStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? T(.keychainErrorUnknown)
            return T(.keychainErrorReadWrite, Int(status), message)
        case .unreadableValue:
            return T(.keychainErrorUnreadableValue)
        }
    }
}

/// The keychain implementation of `APIKeyStoring`.
///
/// One generic password item per gateway host: the service is fixed, the
/// account is the normalized host, and the item is
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it never travels to
/// another device through iCloud Keychain.
public struct KeychainAPIKeyStore: APIKeyStoring {
    /// Keychain service of the app.
    public static let service = "com.mrblack0407.NetworkSentinel"

    /// Accessibility of every item this store writes.
    public static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    public init() {}

    public func apiKey(forAccount account: String) throws -> String? {
        var query = Self.baseQuery(forAccount: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw APIKeyStoreError.unreadableValue
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw APIKeyStoreError.keychain(status: status)
        }
    }

    public func save(_ apiKey: String, forAccount account: String) throws {
        let data = Data(apiKey.utf8)
        let query = Self.baseQuery(forAccount: account)

        // Update first: a second save for the same gateway must not fail with
        // `errSecDuplicateItem`, and must not create a second item.
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = Self.accessibility
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw APIKeyStoreError.keychain(status: addStatus)
            }
        default:
            throw APIKeyStoreError.keychain(status: updateStatus)
        }
    }

    @discardableResult
    public func removeAPIKey(forAccount account: String) throws -> Bool {
        let status = SecItemDelete(Self.baseQuery(forAccount: account) as CFDictionary)

        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw APIKeyStoreError.keychain(status: status)
        }
    }

    /// The class, service and account of an item, without the value.
    ///
    /// Exposed so the tests can check the query without touching the system
    /// keychain.
    public static func baseQuery(forAccount account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// A store that keeps API Keys in memory, for tests and previews.
///
/// The type is a reference type so a caller can hold it while another value
/// writes through the protocol.
public final class APIKeyStoreInMemory: APIKeyStoring {
    private var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    /// Everything currently stored. Only for tests.
    public var storedAccounts: Set<String> { Set(values.keys) }

    public func apiKey(forAccount account: String) throws -> String? {
        values[account]
    }

    public func save(_ apiKey: String, forAccount account: String) throws {
        values[account] = apiKey
    }

    @discardableResult
    public func removeAPIKey(forAccount account: String) throws -> Bool {
        values.removeValue(forKey: account) != nil
    }
}
