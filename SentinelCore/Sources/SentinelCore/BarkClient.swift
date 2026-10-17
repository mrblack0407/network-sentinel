import Foundation

// MARK: - Level

/// Delivery priority of one Bark push.
///
/// Bark knows four levels; the app uses two of them. `timeSensitive` breaks
/// through 专注模式, so it is kept for a 严重性：非常高 notification and for the
/// gateway state failures (连不上, API Key 无效, 证书变了).
public enum BarkLevel: String, Equatable, CaseIterable {
    /// An ordinary push.
    case active
    /// A push that is allowed to break through 专注模式.
    case timeSensitive

    /// The level of one 严重性: only 非常高 is time sensitive.
    public static func level(for severity: LogSeverity) -> BarkLevel {
        severity >= .veryHigh ? .timeSensitive : .active
    }

    /// The level of one 严重性; same as `level(for:)`.
    public init(severity: LogSeverity) {
        self = Self.level(for: severity)
    }
}

extension NotificationKind {
    /// The Bark level of this notification.
    ///
    /// A monitored event follows its 严重性. The gateway failures are time
    /// sensitive whatever they carry: the user has to act on them. 网关已恢复连接
    /// is good news and stays an ordinary push.
    public var barkLevel: BarkLevel {
        switch self {
        case .monitorEvent(let record):
            return BarkLevel(severity: record.severity)
        case .wakeSummary(let summary):
            return BarkLevel(severity: summary.severity)
        case .gatewayUnreachable, .apiKeyRejected, .certificateChanged:
            return .timeSensitive
        case .gatewayRestored:
            return .active
        }
    }
}

// MARK: - Configuration

/// Everything a Bark push needs: the server and the device Key.
///
/// The user may paste a whole push link from the Bark app
/// (`https://api.day.app/Key/`) instead of the Key alone; `parse` takes the Key
/// (and the server) out of it. The Key is a secret: it never appears in a log,
/// in an error or in `UserDefaults`.
public struct BarkConfiguration: Equatable {
    /// The public Bark server, used while the user types nothing else.
    public static let defaultServerAddress = "https://api.day.app"
    /// Keychain account of the Bark Key; the gateway API Key uses its host.
    public static let keychainAccount = "bark"
    /// Push group the Bark app files the notifications under.
    public static let group = "Network Sentinel"

    /// Normalized server, `https://host[:port][/path]`, without a trailing slash.
    public let serverAddress: String
    /// The device Key of the Bark app.
    public let deviceKey: String

    /// Builds a configuration out of a server and a Key.
    ///
    /// - Throws: `BarkConfigurationError.invalidServer` for a server that is not
    ///   an `http` / `https` address, `BarkConfigurationError.invalidKey` for a
    ///   Key that cannot be one.
    public init(serverAddress: String, deviceKey: String) throws {
        self.serverAddress = try Self.normalizedServerAddress(serverAddress)
        guard let key = Self.normalizedKey(deviceKey) else {
            throw BarkConfigurationError.invalidKey
        }
        self.deviceKey = key
    }

    /// The server as a `URL`.
    public var serverURL: URL {
        // Force unwrap is safe: `normalizedServerAddress` built the string.
        URL(string: serverAddress)!
    }

    /// The endpoint of `POST` pushes.
    public var pushURL: URL {
        serverURL.appendingPathComponent("push")
    }

    /// Reads what the user typed into the Key field.
    ///
    /// A whole push link wins over `defaultServerAddress` and also carries the
    /// server, so pasting `https://api.day.app/Key/` is enough. Anything else is
    /// taken as the Key alone.
    ///
    /// - Parameters:
    ///   - input: the Key, or a push link.
    ///   - defaultServerAddress: server to use for an input without one.
    /// - Throws: `BarkConfigurationError` with Chinese text for the 通知 page.
    public static func parse(
        input: String,
        defaultServerAddress: String = BarkConfiguration.defaultServerAddress
    ) throws -> BarkConfiguration {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BarkConfigurationError.missingKey }

        if let fromLink = try link(trimmed) { return fromLink }
        return try BarkConfiguration(serverAddress: defaultServerAddress, deviceKey: trimmed)
    }

    /// Reads the Key field next to a server field.
    ///
    /// The Key field may still hold a whole push link; when it does, the server
    /// of the link wins over the server field.
    public static func parse(server: String, key: String) throws -> BarkConfiguration {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromLink = try link(trimmed) { return fromLink }
        guard !trimmed.isEmpty else { throw BarkConfigurationError.missingKey }
        return try BarkConfiguration(serverAddress: server, deviceKey: trimmed)
    }

    // MARK: - Normalization

    /// The configuration inside a push link, or `nil` when the input is no link.
    ///
    /// Only the first path component is the Key: the rest of the path is the
    /// optional title / body of a Bark link and is dropped.
    private static func link(_ text: String) throws -> BarkConfiguration? {
        guard text.contains("://") else { return nil }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw BarkConfigurationError.invalidServer
        }
        guard let rawHost = components.host else {
            throw BarkConfigurationError.invalidServer
        }
        let host = unbracketed(rawHost)
        guard isValidHost(host) else {
            throw BarkConfigurationError.invalidServer
        }
        if let port = components.port, !(1...65_535).contains(port) {
            throw BarkConfigurationError.invalidServer
        }

        let server = origin(scheme: scheme, host: host, port: components.port)
        guard let first = components.path.split(separator: "/").first,
              let key = normalizedKey(String(first)) else {
            // A link without a Key (`https://api.day.app` pasted alone) carries
            // no device to push to.
            throw BarkConfigurationError.missingKey
        }
        return try BarkConfiguration(serverAddress: server, deviceKey: key)
    }

    /// `https://host[:port][/path]`, without a trailing slash.
    ///
    /// A self-hosted server may speak `http` and may sit under a subpath
    /// (`https://example.com/bark`); both are kept. A missing scheme becomes
    /// `https`. Public so the address field of 通知 can be checked while the
    /// user types.
    public static func normalizedServerAddress(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultServerAddress }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let rawHost = components.host else {
            throw BarkConfigurationError.invalidServer
        }
        let host = unbracketed(rawHost)
        guard isValidHost(host) else { throw BarkConfigurationError.invalidServer }
        if let port = components.port, !(1...65_535).contains(port) {
            throw BarkConfigurationError.invalidServer
        }

        let path = components.path
            .split(separator: "/")
            .map(String.init)
            .joined(separator: "/")

        var address = origin(scheme: scheme, host: host, port: components.port)
        if !path.isEmpty {
            address += "/\(path)"
        }
        // `serverURL` is force unwrapped, so the address must be a URL here.
        guard let url = URL(string: address), url.host != nil else {
            throw BarkConfigurationError.invalidServer
        }
        return address
    }

    /// `scheme://host[:port]`, with IPv6 hosts bracketed again.
    private static func origin(scheme: String, host: String, port: Int?) -> String {
        let displayHost = host.contains(":") ? "[\(host)]" : host
        return "\(scheme)://\(displayHost)\(port.map { ":\($0)" } ?? "")"
    }

    /// The host without the brackets `URLComponents` keeps around an IPv6 address.
    private static func unbracketed(_ host: String) -> String {
        guard host.hasPrefix("["), host.hasSuffix("]"), host.count > 2 else { return host }
        return String(host.dropFirst().dropLast())
    }

    /// The Key of the input, or `nil` when the text cannot be one.
    ///
    /// A Bark Key is ASCII letters, digits, `-` and `_`; anything else is a
    /// mistyped paste and is refused before it reaches the keychain. Public so
    /// the Key field of 通知 can be checked while the user types.
    public static func normalizedKey(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }
        guard trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            return nil
        }
        return trimmed
    }

    /// `true` for a host name, an IPv4 address or a bracketed IPv6 address.
    private static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        // A host of punctuation alone (`:`, `...`) is not a host.
        guard host.contains(where: { $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
        return host.allSatisfy { character in
            character.isASCII
                && (character.isLetter || character.isNumber || character == "." || character == "-" || character == ":" || character == "_")
        }
    }
}

/// Why the text of the Key field was refused.
///
/// The text follows the language: the 通知 page shows it as it is. No case
/// carries the Key.
public enum BarkConfigurationError: Error, Equatable {
    /// The field is empty, and so is a link without a Key.
    case missingKey
    /// The text is neither a Key nor a push link.
    case invalidKey
    /// The server is not an `http` / `https` address.
    case invalidServer
}

extension BarkConfigurationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return T(.barkErrorMissingKey)
        case .invalidKey:
            return T(.barkErrorInvalidKey)
        case .invalidServer:
            return T(.barkErrorInvalidServer)
        }
    }
}

// MARK: - Client

/// Sends one push to a Bark server.
///
/// The client is pure logic: it builds the request of the Bark HTTP API and
/// reads the answer. The `URLSession` is injected, so the tests never touch the
/// network. No error and no log line ever carries the device Key.
public struct BarkClient {
    private let configuration: BarkConfiguration
    private let session: URLSession

    public init(configuration: BarkConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// The endpoint this client posts to.
    public var pushURL: URL { configuration.pushURL }

    /// Sends one push.
    ///
    /// - Parameters:
    ///   - title: notification title.
    ///   - body: notification body.
    ///   - level: `active`, or `timeSensitive` for 严重性：非常高.
    /// - Throws: `BarkError` with Chinese text. A Key that Bark refuses becomes
    ///   `BarkError.invalidKey`, a server message becomes `BarkError.server`
    ///   with the Key taken out of the text.
    /// - Parameter sound: a Bark ringtone name; `nil` or blank keeps the
    ///   default sound of the Bark App.
    public func send(title: String, body: String, level: BarkLevel, sound: String? = nil) async throws {
        do {
            let request = try makeRequest(title: title, body: body, level: level, sound: sound)
            let (data, response) = try await session.data(for: request)
            try Self.validate(data: data, response: response, deviceKey: configuration.deviceKey)
        } catch let error as BarkError {
            throw error
        } catch let error as BarkConfigurationError {
            throw error
        } catch let error as URLError {
            throw BarkError.network(error)
        } catch {
            throw BarkError.unreadableResponse
        }
    }

    // MARK: - Request

    /// The `POST` the Bark API expects.
    private func makeRequest(title: String, body: String, level: BarkLevel, sound: String?) throws -> URLRequest {
        let trimmedSound = sound?.trimmingCharacters(in: .whitespacesAndNewlines)
        var request = URLRequest(url: configuration.pushURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PushPayload(
                deviceKey: configuration.deviceKey,
                title: title,
                body: body,
                group: BarkConfiguration.group,
                level: level.rawValue,
                isArchive: 1,
                sound: (trimmedSound?.isEmpty ?? true) ? nil : trimmedSound
            )
        )
        return request
    }

    /// The body of `POST /push`.
    private struct PushPayload: Encodable {
        let deviceKey: String
        let title: String
        let body: String
        let group: String
        let level: String
        let isArchive: Int
        /// Left out of the JSON when `nil`, so Bark plays its default sound.
        let sound: String?

        enum CodingKeys: String, CodingKey {
            case deviceKey = "device_key"
            case title
            case body
            case group
            case level
            case isArchive
            case sound
        }
    }

    /// The answer of a successful push: `{"code":200,"message":"success"}`.
    private struct PushResponse: Decodable {
        let code: Int?
        let message: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // A self-hosted server may answer the code as text; both are read.
            if let value = try? container.decode(Int.self, forKey: .code) {
                code = value
            } else if let text = try? container.decode(String.self, forKey: .code) {
                code = Int(text)
            } else {
                code = nil
            }
            message = try? container.decode(String.self, forKey: .message)
        }

        private enum CodingKeys: String, CodingKey {
            case code
            case message
        }
    }

    // MARK: - Answer

    /// Turns the answer into a `BarkError`, or returns on success.
    private static func validate(data: Data, response: URLResponse, deviceKey: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw BarkError.unreadableResponse
        }
        let payload = try? JSONDecoder().decode(PushResponse.self, from: data)

        switch http.statusCode {
        case 400, 401:
            // Bark answers 400 for a device key it does not know.
            throw BarkError.invalidKey
        case 200...299:
            guard let payload, let code = payload.code else {
                throw BarkError.unreadableResponse
            }
            switch code {
            case 200:
                return
            case 400, 401:
                throw BarkError.invalidKey
            default:
                throw BarkError.server(sanitized(payload.message, deviceKey: deviceKey) ?? "code \(code)")
            }
        default:
            throw BarkError.server(sanitized(payload?.message, deviceKey: deviceKey) ?? "HTTP \(http.statusCode)")
        }
    }

    /// The `message` of the server, fit to be shown: no Key, not a wall of text.
    private static func sanitized(_ message: String?, deviceKey: String) -> String? {
        guard let message else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var text = trimmed
        var secrets = [deviceKey]
        if let encoded = deviceKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            secrets.append(encoded)
        }
        for secret in secrets where !secret.isEmpty {
            text = text.replacingOccurrences(of: secret, with: "***")
        }
        return text.count > 200 ? String(text.prefix(200)) + "…" : text
    }
}

// MARK: - Errors

/// Why a Bark push did not arrive.
///
/// No case carries the device Key, so every case can be shown and logged.
public enum BarkError: Error, Equatable {
    /// The server could not be reached at all (offline, wrong address, TLS).
    case network(URLError)
    /// Bark refused the Key (HTTP 400 / 401, or `code` 400 / 401).
    case invalidKey
    /// The server answered an error; the text is its `message`, without the Key.
    case server(String)
    /// The answer was not the JSON the Bark API sends.
    case unreadableResponse
}

extension BarkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network:
            return T(.barkErrorNetwork)
        case .invalidKey:
            return T(.barkErrorRejectedKey)
        case .server(let message):
            return T(.barkErrorServer, message)
        case .unreadableResponse:
            return T(.barkErrorUnreadableResponse)
        }
    }

    public var failureReason: String? {
        switch self {
        case .network(let error):
            return error.localizedDescription
        case .invalidKey, .server, .unreadableResponse:
            return nil
        }
    }
}

// MARK: - Result

/// What the last Bark push did, for the 通知 page.
public struct BarkResult: Equatable {
    /// `true` when the push was accepted by the server.
    public let succeeded: Bool
    /// When the push was attempted.
    public let date: Date
    /// Reason of a failed push, in the language of the moment of the push;
    /// never the Key. `nil` on success.
    public let failureReason: String?

    private init(succeeded: Bool, date: Date, failureReason: String?) {
        self.succeeded = succeeded
        self.date = date
        self.failureReason = failureReason
    }

    /// A push the server accepted.
    public static func success(at date: Date) -> BarkResult {
        BarkResult(succeeded: true, date: date, failureReason: nil)
    }

    /// A push that failed, with the reason the page shows.
    public static func failure(_ reason: String, at date: Date) -> BarkResult {
        BarkResult(succeeded: false, date: date, failureReason: reason)
    }
}
