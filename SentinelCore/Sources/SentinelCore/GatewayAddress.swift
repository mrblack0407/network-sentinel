import Foundation

/// A UniFi gateway address that the user typed, made fit for the client.
///
/// The user may type `192.168.8.254`, `https://192.168.8.254/`,
/// `https://192.168.8.254:443` or `unifi.local`. All of them become
/// `https://主机[:端口]`: the scheme is always `https` (the gateway only speaks
/// HTTPS), the trailing slash and any path are dropped, and the default port
/// 443 is left out.
public struct GatewayAddress: Equatable {
    /// Host only: IPv4, IPv6 or a host name such as `unifi.local`.
    public let host: String
    /// Port from the input, `nil` when the user did not type one.
    public let port: Int?

    /// Normalized address, for example `https://192.168.8.254`.
    public var urlString: String {
        "https://\(displayHost)\(port.map { ":\($0)" } ?? "")"
    }

    /// The address as a `URL`, which is what the client takes.
    public var url: URL {
        // Force unwrap is safe: `normalize` validated the host and the port.
        URL(string: urlString)!
    }

    /// Host in the spelling used for URLs and the keychain account.
    ///
    /// IPv6 addresses keep their brackets, so the value is a valid URL host and
    /// stays stable as the keychain account.
    public var displayHost: String {
        host.contains(":") ? "[\(host)]" : host
    }

    /// Reads a user-typed address.
    ///
    /// - Throws: `GatewayAddressError.empty` for an empty or whitespace-only
    ///   input, `GatewayAddressError.invalid` when the rest is not a host name
    ///   with an optional port.
    public init(_ input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GatewayAddressError.empty }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { throw GatewayAddressError.invalid }

        let withoutScheme = try Self.withoutScheme(trimmed)
        // One trailing slash is what people type or paste; it is dropped.
        let authority = withoutScheme.hasSuffix("/") ? String(withoutScheme.dropLast()) : withoutScheme
        // Any other path, a query or a fragment never belongs to a gateway
        // address: `https://192.168.8.254/proxy/network` is a mistake.
        guard !authority.contains("/"), !authority.contains("?"), !authority.contains("#") else {
            throw GatewayAddressError.invalid
        }

        let (host, port) = try Self.splitHostAndPort(authority)
        self.host = host.lowercased()
        self.port = port == Self.httpsPort ? nil : port
    }

    /// The authority part, with any scheme removed.
    ///
    /// A missing scheme and `http` both end up as `https`: the UniFi gateway
    /// only serves HTTPS, so the scheme is never taken from the input. Any
    /// other scheme (`ftp://`) is not a gateway address.
    private static func withoutScheme(_ input: String) throws -> String {
        guard let separator = input.range(of: "://") else { return input }

        let scheme = input[input.startIndex..<separator.lowerBound].lowercased()
        guard scheme == "http" || scheme == "https" else { throw GatewayAddressError.invalid }
        return String(input[separator.upperBound...])
    }

    /// Splits `host`, `host:port` or `[IPv6]:port`.
    private static func splitHostAndPort(_ input: String) throws -> (host: String, port: Int?) {
        guard !input.isEmpty else { throw GatewayAddressError.invalid }

        let host: String
        let portText: String?

        if input.hasPrefix("[") {
            // Bracketed IPv6, with an optional port after the bracket.
            guard let closing = input.firstIndex(of: "]") else { throw GatewayAddressError.invalid }
            host = String(input[input.index(after: input.startIndex)..<closing])
            let remainder = String(input[input.index(after: closing)...])
            if remainder.isEmpty {
                portText = nil
            } else if remainder.hasPrefix(":") {
                portText = String(remainder.dropFirst())
            } else {
                throw GatewayAddressError.invalid
            }
        } else {
            let parts = input.split(separator: ":", omittingEmptySubsequences: false)
            switch parts.count {
            case 1:
                host = String(parts[0])
                portText = nil
            case 2:
                host = String(parts[0])
                portText = String(parts[1])
            default:
                // More than one colon without brackets: not a host name.
                throw GatewayAddressError.invalid
            }
        }

        guard !host.isEmpty, Self.isValidHost(host) else { throw GatewayAddressError.invalid }

        guard let portText else {
            return (host, nil)
        }
        guard let port = Int(portText), (1...65_535).contains(port) else {
            throw GatewayAddressError.invalid
        }
        return (host, port)
    }

    /// `true` for an IPv4 address, an IPv6 address or a host name.
    private static func isValidHost(_ host: String) -> Bool {
        if isIPv4(host) || isIPv6(host) {
            return true
        }
        // `192.168.8.999` is a mistyped address, not a host name.
        guard !looksLikeIPv4(host) else { return false }
        guard host.count <= 253 else { return false }
        // At least two labels: a single label is not routable for the gateway.
        guard let regex = try? Regex("[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+") else {
            return false
        }
        return host.wholeMatch(of: regex) != nil
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else { return false }
            // Reject leading zeros such as `010`, which are ambiguous.
            return part.count == 1 || part.first != "0"
        }
    }

    /// `true` when every character is a digit or a dot, so the input was meant
    /// as an IPv4 address even if it is not a valid one.
    private static func looksLikeIPv4(_ host: String) -> Bool {
        guard host.contains(".") else { return false }
        guard host.contains(where: { $0.isNumber }) else { return false }
        return host.allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func isIPv6(_ host: String) -> Bool {
        guard host.contains(":") else { return false }
        var address = in6_addr()
        return host.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }

    /// The HTTPS port, left out of the normalized address.
    private static let httpsPort = 443
}

/// Why a user-typed gateway address was rejected.
///
/// The text is Chinese: the connection settings window shows it as it is.
public enum GatewayAddressError: Error, Equatable {
    /// Empty input.
    case empty
    /// Not a host name, an IP address or a host with a port.
    case invalid
}

extension GatewayAddressError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .empty:
            return "请输入 UniFi 网关地址"
        case .invalid:
            return "地址格式不对，请输入网关的 IP 地址或主机名，例如 192.168.8.254"
        }
    }
}

/// What the connection settings window shows for the typed address: the
/// normalized address, or the Chinese text next to the field.
public enum GatewayAddressInput: Equatable {
    /// The input was readable.
    case valid(GatewayAddress)
    /// The input has to be corrected; the error carries the Chinese text.
    case invalid(GatewayAddressError)

    /// Reads a user-typed address without throwing.
    public init(_ input: String) {
        do {
            self = .valid(try GatewayAddress(input))
        } catch let error as GatewayAddressError {
            self = .invalid(error)
        } catch {
            self = .invalid(.invalid)
        }
    }

    /// Normalized address such as `https://192.168.8.254`, or `nil` on error.
    public var address: GatewayAddress? {
        guard case .valid(let address) = self else { return nil }
        return address
    }

    /// Normalized URL string, or `nil` on error.
    public var urlString: String? {
        address?.urlString
    }

    /// Chinese text for the window, or `nil` when the input is usable.
    public var message: String? {
        guard case .invalid(let error) = self else { return nil }
        return error.errorDescription
    }
}
