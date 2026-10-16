import Foundation
import SentinelCore

/// Everything the app remembers about the UniFi gateway and the monitoring.
///
/// Only the API Key lives in the keychain (`KeychainAPIKeyStore`); the
/// normalized address, the site, the gateway name, the pinned certificate and
/// the monitoring settings live in `UserDefaults`. No API Key ever reaches
/// `UserDefaults`, a log line or the text of a view.
///
/// The Bark Key is a secret as well: it lives under the keychain account
/// `BarkConfiguration.keychainAccount` and is read once, then kept in memory.
@MainActor
final class AppConfiguration: ObservableObject {
    /// `UserDefaults` keys, one per stored value.
    private enum DefaultsKey {
        static let gatewayAddress = "gatewayAddress"
        static let siteReference = "siteReference"
        static let gatewayName = "gatewayName"
        static let pinnedCertificateHost = "pinnedCertificateHost"
        static let pinnedCertificateSHA256 = "pinnedCertificateSHA256"
        static let monitorSettings = "monitorSettings"
        static let barkEnabled = "barkEnabled"
        static let barkServerAddress = "barkServerAddress"
    }

    private let defaults: UserDefaults
    private let keyStore: APIKeyStoring

    /// Normalized address of the configured UniFi gateway.
    @Published private(set) var gatewayAddress: GatewayAddress?
    /// Site reference used by the other endpoints.
    @Published private(set) var siteReference: String?
    /// Gateway name from the last successful 「测试连接」.
    @Published private(set) var gatewayName: String?
    /// Certificate pinned on the last successful 「测试连接」.
    @Published private(set) var pinnedCertificate: PinnedCertificate?
    /// `true` when the keychain holds an API Key for the configured address.
    @Published private(set) var hasAPIKey: Bool = false

    /// `true` when every system notification also goes to Bark. Off by default.
    @Published var barkEnabled: Bool {
        didSet { defaults.set(barkEnabled, forKey: DefaultsKey.barkEnabled) }
    }

    /// Bark server address, the public one until the user types another.
    ///
    /// Stored as the user typed it: the address is normalized when a push is
    /// built, so a half-typed address never blocks the field.
    @Published var barkServerAddress: String {
        didSet { defaults.set(barkServerAddress, forKey: DefaultsKey.barkServerAddress) }
    }

    /// `true` when the keychain holds a Bark Key.
    @Published private(set) var hasBarkKey: Bool = false

    /// The Bark Key, read from the keychain at most once.
    private var cachedBarkKey: String?
    /// `true` once the keychain was asked for the Bark Key.
    private var isBarkKeyLoaded = false

    /// What the app monitors and when it notifies. Every change is saved at
    /// once: there is no 「保存」 button.
    @Published var monitorSettings: MonitorSettings {
        didSet { persistMonitorSettings() }
    }

    /// The app is configured once it has an address, a site, a fingerprint and
    /// the matching API Key in the keychain.
    var isConfigured: Bool {
        gatewayAddress != nil && siteReference != nil && pinnedCertificate != nil && hasAPIKey
    }

    init(defaults: UserDefaults = .standard, keyStore: APIKeyStoring = KeychainAPIKeyStore()) {
        self.defaults = defaults
        self.keyStore = keyStore
        self.monitorSettings = Self.loadMonitorSettings(from: defaults)
        self.gatewayAddress = defaults
            .string(forKey: DefaultsKey.gatewayAddress)
            .flatMap { try? GatewayAddress($0) }
        self.siteReference = defaults.string(forKey: DefaultsKey.siteReference)
        self.gatewayName = defaults.string(forKey: DefaultsKey.gatewayName)
        self.pinnedCertificate = Self.loadPinnedCertificate(from: defaults)
        self.barkEnabled = defaults.bool(forKey: DefaultsKey.barkEnabled)
        let storedBarkServer = defaults.string(forKey: DefaultsKey.barkServerAddress) ?? ""
        self.barkServerAddress = storedBarkServer.isEmpty
            ? BarkConfiguration.defaultServerAddress
            : storedBarkServer
        refreshAPIKeyPresence()
        loadBarkKeyIfNeeded()
    }

    // MARK: - API Key

    /// The API Key of the configured gateway, straight from the keychain.
    ///
    /// The value is handed to the caller for one request or one keychain write;
    /// it is never stored in a property of this type.
    func apiKey() throws -> String? {
        guard let gatewayAddress else { return nil }
        return try keyStore.apiKey(for: gatewayAddress)
    }

    // MARK: - Bark

    /// The Bark Key, from the keychain the first time and from memory after.
    ///
    /// The keychain may ask for a confirmation on every read, so a push must not
    /// read it again and again; the cache is dropped when the Key changes.
    func barkKey() -> String? {
        loadBarkKeyIfNeeded()
        return cachedBarkKey
    }

    /// The Bark settings as `BarkClient` takes them.
    ///
    /// - Throws: `BarkConfigurationError` with Chinese text: 「请输入 Bark Key」
    ///   while no Key is saved, 「服务器地址格式不对」 for a server that cannot
    ///   be a Bark server.
    func barkConfiguration() throws -> BarkConfiguration {
        guard let key = barkKey() else { throw BarkConfigurationError.missingKey }
        return try BarkConfiguration(serverAddress: barkServerAddress, deviceKey: key)
    }

    /// Parses what the user typed and saves the Bark Key to the keychain.
    ///
    /// The input may be the Key alone or a whole push link; a link also sets the
    /// server address. The Key never reaches `UserDefaults`.
    ///
    /// - Returns: the parsed configuration, for the message of the 通知 page.
    @discardableResult
    func saveBarkKey(_ input: String) throws -> BarkConfiguration {
        let configuration = try BarkConfiguration.parse(
            input: input,
            defaultServerAddress: barkServerAddress
        )
        try keyStore.save(configuration.deviceKey, forAccount: BarkConfiguration.keychainAccount)

        cachedBarkKey = configuration.deviceKey
        isBarkKeyLoaded = true
        hasBarkKey = true
        barkServerAddress = configuration.serverAddress
        return configuration
    }

    /// Removes the Bark Key from the keychain. The switch and the server stay.
    func removeBarkKey() throws {
        _ = try keyStore.removeAPIKey(forAccount: BarkConfiguration.keychainAccount)
        cachedBarkKey = nil
        isBarkKeyLoaded = true
        hasBarkKey = false
    }

    /// Asks the keychain for the Bark Key once and remembers the answer.
    private func loadBarkKeyIfNeeded() {
        guard !isBarkKeyLoaded else { return }
        isBarkKeyLoaded = true

        let key: String? = (try? keyStore.apiKey(forAccount: BarkConfiguration.keychainAccount)) ?? nil
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedBarkKey = trimmed?.isEmpty == false ? trimmed : nil
        hasBarkKey = cachedBarkKey != nil
    }

    // MARK: - Saving

    /// Remembers a successful 「测试连接」.
    ///
    /// The API Key goes to the keychain under the normalized address. When the
    /// address changed, the key of the old gateway is removed: the app keeps at
    /// most one gateway.
    func saveConnection(result: ConnectionTestResult, apiKey: String) throws {
        let previousAddress = gatewayAddress

        try keyStore.save(apiKey, for: result.address)
        if let previousAddress, previousAddress.host != result.address.host {
            _ = try? keyStore.removeAPIKey(for: previousAddress)
        }

        gatewayAddress = result.address
        siteReference = result.siteReference
        gatewayName = result.gatewayName
        pinnedCertificate = result.certificate
        hasAPIKey = true

        defaults.set(result.address.urlString, forKey: DefaultsKey.gatewayAddress)
        defaults.set(result.siteReference, forKey: DefaultsKey.siteReference)
        defaults.set(result.gatewayName, forKey: DefaultsKey.gatewayName)
        defaults.set(result.certificate.host, forKey: DefaultsKey.pinnedCertificateHost)
        defaults.set(result.certificate.sha256, forKey: DefaultsKey.pinnedCertificateSHA256)
    }

    // MARK: - Settings

    /// Turns one monitored event on or off.
    func setMonitored(_ event: MonitoredEvent, enabled: Bool) {
        updateSettings { settings in
            if enabled {
                settings.monitoredEvents.insert(event)
            } else {
                settings.monitoredEvents.remove(event)
            }
        }
    }

    /// Sets the seconds between two log queries.
    func setQueryInterval(seconds: Int) {
        updateSettings { $0.queryIntervalSeconds = seconds }
    }

    /// Sets the days of log history the app keeps.
    func setLogRetention(days: Int) {
        updateSettings { $0.logRetentionDays = days }
    }

    /// Sets the lowest severity that still produces a notification.
    func setMinimumSeverity(_ severity: LogSeverity) {
        updateSettings { $0.notifications.minimumSeverity = severity }
    }

    /// Sends 互联网已恢复 no matter its severity, or stops doing so.
    func setAlwaysNotifyOnRestore(_ enabled: Bool) {
        updateSettings { $0.notifications.alwaysNotifyOnRestore = enabled }
    }

    /// Merges same-kind events of the merge window into one notification.
    func setMergeSameKind(_ enabled: Bool) {
        updateSettings { $0.notifications.mergeSameKind = enabled }
    }

    /// Applies one change to the settings and saves the result.
    private func updateSettings(_ change: (inout MonitorSettings) -> Void) {
        var settings = monitorSettings
        change(&settings)
        monitorSettings = settings
    }

    // MARK: - Persistence

    private func persistMonitorSettings() {
        guard let data = try? JSONEncoder().encode(monitorSettings) else { return }
        defaults.set(data, forKey: DefaultsKey.monitorSettings)
    }

    private func refreshAPIKeyPresence() {
        guard let gatewayAddress else {
            hasAPIKey = false
            return
        }
        let key: String? = (try? keyStore.apiKey(for: gatewayAddress)) ?? nil
        hasAPIKey = !(key ?? "").isEmpty
    }

    /// Reads the settings, falling back to the defaults of `MonitorSettings`.
    ///
    /// `MonitorSettings` decodes leniently, so a configuration written by an
    /// older version keeps working. A value outside the offered options is
    /// replaced by the default, so the segmented control always has a selection.
    private static func loadMonitorSettings(from defaults: UserDefaults) -> MonitorSettings {
        guard let data = defaults.data(forKey: DefaultsKey.monitorSettings),
              var settings = try? JSONDecoder().decode(MonitorSettings.self, from: data) else {
            return MonitorSettings()
        }
        if !MonitorSettings.queryIntervalOptions.contains(settings.queryIntervalSeconds) {
            settings.queryIntervalSeconds = MonitorSettings.defaultQueryIntervalSeconds
        }
        if !MonitorSettings.logRetentionOptions.contains(settings.logRetentionDays) {
            settings.logRetentionDays = MonitorSettings.defaultLogRetentionDays
        }
        return settings
    }

    /// The pinned certificate, or `nil` when either half is missing.
    private static func loadPinnedCertificate(from defaults: UserDefaults) -> PinnedCertificate? {
        guard let host = defaults.string(forKey: DefaultsKey.pinnedCertificateHost),
              let sha256 = defaults.string(forKey: DefaultsKey.pinnedCertificateSHA256),
              !host.isEmpty, !sha256.isEmpty else {
            return nil
        }
        return PinnedCertificate(host: host, sha256: sha256)
    }
}
