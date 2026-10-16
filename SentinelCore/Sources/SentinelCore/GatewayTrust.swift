import CryptoKit
import Foundation
import Security

/// The certificate the app pinned for one gateway.
///
/// The fingerprint is not a secret, so the app may keep it in `UserDefaults`.
/// The value type is `Codable` for exactly that reason.
public struct PinnedCertificate: Codable, Equatable {
    /// Gateway host, without brackets and without a port.
    public let host: String
    /// SHA-256 of the leaf certificate DER, lowercase hexadecimal text.
    public let sha256: String

    public init(host: String, sha256: String) {
        self.host = host
        self.sha256 = sha256
    }
}

/// Fingerprints a certificate.
public enum CertificateFingerprint {
    /// SHA-256 of the DER bytes as lowercase hexadecimal text.
    ///
    /// - Parameter der: the DER encoding of the leaf certificate, which is what
    ///   `SecCertificateCopyData` returns.
    public static func sha256(ofDER der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 of a certificate, or `nil` when it cannot be encoded.
    public static func sha256(of certificate: SecCertificate) -> String? {
        guard let der = SecCertificateCopyData(certificate) as Data? else { return nil }
        return sha256(ofDER: der)
    }
}

/// Trust On First Use for a self-signed gateway certificate.
///
/// The UniFi gateway signs its own certificate, so the system trust store
/// rejects it. The app accepts it once, during 「测试连接」, remembers the
/// leaf fingerprint and accepts only that certificate afterwards.
public enum GatewayTrustMode: Equatable {
    /// 首次测试: accept the certificate the gateway presents and report it.
    case firstUse
    /// Everyday queries: accept only this pinned certificate.
    case pinned(PinnedCertificate)
}

/// What to do with a `NSURLAuthenticationMethodServerTrust` challenge.
///
/// A pure value, so the accept / reject rule is testable without a server.
public enum CertificateTrustDecision: Equatable {
    /// Let the system decide; the challenge is not for our gateway.
    case systemDefault
    /// Accept the certificate and pin its fingerprint.
    case accept(pinning: PinnedCertificate)
    /// Refuse: the certificate is not the pinned one.
    case reject
}

/// The accept / reject rule, kept away from `URLSession`.
public enum GatewayTrustPolicy {
    /// Decides one server trust challenge.
    ///
    /// - Parameters:
    ///   - host: host of the challenge.
    ///   - gatewayHost: host of the configured gateway.
    ///   - mode: 首次测试 or pinned.
    ///   - fingerprint: SHA-256 of the presented leaf certificate, `nil` when
    ///     it could not be computed.
    public static func decision(
        host: String,
        gatewayHost: String,
        mode: GatewayTrustMode,
        fingerprint: String?
    ) -> CertificateTrustDecision {
        guard host.caseInsensitiveCompare(gatewayHost) == .orderedSame else {
            return .systemDefault
        }
        guard let fingerprint else { return .reject }

        switch mode {
        case .firstUse:
            // 首次信任: the fingerprint is remembered, not checked.
            return .accept(pinning: PinnedCertificate(host: gatewayHost, sha256: fingerprint))
        case .pinned(let pinned):
            let matches = pinned.sha256.caseInsensitiveCompare(fingerprint) == .orderedSame
            return matches ? .accept(pinning: PinnedCertificate(host: gatewayHost, sha256: fingerprint)) : .reject
        }
    }
}

/// `URLSession` delegate that applies `GatewayTrustPolicy`.
///
/// Challenges of any other host go back to the system, so the delegate only
/// ever loosens trust for the one gateway the user configured.
public final class GatewayTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let gatewayHost: String
    private let mode: GatewayTrustMode
    private let observer: CertificateFingerprintObserver?
    private let lock = NSLock()
    private var observed: PinnedCertificate?
    private var rejected = false

    /// - Parameters:
    ///   - gatewayHost: host of the configured gateway.
    ///   - mode: 首次测试 or pinned.
    ///   - observer: called with the pinned certificate of a 首次测试
    ///     challenge. The connection tester uses it to report the fingerprint.
    public init(
        gatewayHost: String,
        mode: GatewayTrustMode,
        observer: CertificateFingerprintObserver? = nil
    ) {
        self.gatewayHost = gatewayHost
        self.mode = mode
        self.observer = observer
    }

    /// The certificate seen during a 首次测试 handshake, once it happened.
    public var observedCertificate: PinnedCertificate? {
        lock.lock()
        defer { lock.unlock() }
        return observed
    }

    /// `true` once the gateway presented a certificate that did not match the
    /// pinned one. URLSession then fails the request with `.cancelled`, so the
    /// client reads this flag to tell a changed certificate from a cancelled task.
    public var didRejectCertificate: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rejected
    }

    private func markRejected() {
        lock.lock()
        rejected = true
        lock.unlock()
    }

    /// Applies the same rule as a real challenge without a server.
    ///
    /// A stub session never performs a TLS handshake, so tests use this to feed
    /// the fingerprint the handshake would have reported.
    @discardableResult
    func simulateServerTrust(host: String, fingerprint: String?) -> CertificateTrustDecision {
        let decision = GatewayTrustPolicy.decision(
            host: host,
            gatewayHost: gatewayHost,
            mode: mode,
            fingerprint: fingerprint
        )

        if case .accept(let pinning) = decision {
            lock.lock()
            observed = pinning
            lock.unlock()
            observer?(pinning)
        } else if decision == .reject {
            markRejected()
        }

        return decision
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let certificate = Self.leafCertificate(of: serverTrust) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let decision = GatewayTrustPolicy.decision(
            host: challenge.protectionSpace.host,
            gatewayHost: gatewayHost,
            mode: mode,
            fingerprint: CertificateFingerprint.sha256(of: certificate)
        )

        switch decision {
        case .systemDefault:
            completionHandler(.performDefaultHandling, nil)
        case .accept(let pinning):
            lock.lock()
            observed = pinning
            lock.unlock()
            observer?(pinning)
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        case .reject:
            markRejected()
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// The leaf (end entity) certificate of a server trust, or `nil`.
    static func leafCertificate(of trust: SecTrust) -> SecCertificate? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return nil }
        return chain.first
    }
}

/// Called with the certificate a 首次测试 handshake pinned.
public typealias CertificateFingerprintObserver = (PinnedCertificate) -> Void

/// Builds the `URLSession` the `UniFiGatewayClient` talks through.
public enum GatewayTrust {
    /// Creates a session with `delegate` attached.
    ///
    /// The delegate carries the Trust On First Use mode, so the caller decides
    /// between 「测试连接」 and everyday queries. `URLSession` keeps the
    /// delegate alive, and the delegate keeps its observer alive, so nothing
    /// has to be retained by the caller.
    public static func session(delegate: GatewayTrustDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false

        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    /// Creates a session that applies Trust On First Use for one gateway.
    ///
    /// - Parameters:
    ///   - gatewayHost: host of the configured gateway, for example
    ///     `192.168.8.254`.
    ///   - mode: `.firstUse` for 「测试连接」, `.pinned(...)` for everyday
    ///     queries.
    ///   - observer: reports the pinned certificate of a `.firstUse` handshake.
    public static func session(
        gatewayHost: String,
        mode: GatewayTrustMode,
        observer: CertificateFingerprintObserver? = nil
    ) -> URLSession {
        session(delegate: GatewayTrustDelegate(gatewayHost: gatewayHost, mode: mode, observer: observer))
    }
}
