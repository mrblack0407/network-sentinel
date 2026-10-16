import Foundation

/// The result of a successful 「测试连接」.
///
/// Carries everything the app has to remember: the normalized address, the
/// site, the gateway name and the certificate to pin. The API Key is not part
/// of the result.
public struct ConnectionTestResult: Equatable {
    /// Normalized gateway address, for example `https://192.168.8.254`.
    public let address: GatewayAddress
    /// `nil` only for the rare gateway that reports no site at all.
    public let site: Site?
    /// Gateway name from the gateway status, for example `Dream Machine Pro Max`.
    public let gatewayName: String
    /// The certificate to pin, so everyday queries accept only this gateway.
    public let certificate: PinnedCertificate

    public init(address: GatewayAddress, site: Site?, gatewayName: String, certificate: PinnedCertificate) {
        self.address = address
        self.site = site
        self.gatewayName = gatewayName
        self.certificate = certificate
    }

    /// Normalized address text.
    public var urlString: String { address.urlString }

    /// Site reference for the other endpoints; `default` when the gateway
    /// reported no site.
    public var siteReference: String { site?.internalReference ?? ConnectionTester.fallbackSiteReference }
}

extension ConnectionTestResult: CustomStringConvertible, CustomDebugStringConvertible {
    /// Address, gateway name and pinned fingerprint. Never the API Key.
    public var description: String {
        "ConnectionTestResult(address: \(urlString), gateway: \(gatewayName), "
            + "site: \(site?.name ?? "-"), sha256: \(certificate.sha256))"
    }

    public var debugDescription: String { description }
}

/// Why 「测试连接」 failed. Every case is ready to be shown in the app.
public enum ConnectionTestError: Error, Equatable {
    /// The typed address is empty.
    case emptyAddress
    /// The typed address is not a host name or an IP address.
    case invalidAddress
    /// The gateway could not be reached at this address.
    case cannotConnect(GatewayAddress)
    /// HTTP 401 or 403: the API Key is wrong or has no permission.
    case unauthorized
    /// HTTP 404 on an endpoint other than the log: the firmware does not have it.
    case notSupported
    /// HTTP 404 while reading the system log: the firmware has no log endpoint.
    case logNotSupported
    /// The response body could not be decoded.
    case unreadableResponse(String)
    /// The gateway answered `meta.rc != "ok"`.
    case gatewayRejected(String)
    /// The gateway status carries no UniFi gateway device.
    case gatewayNotFound
    /// The handshake succeeded but no certificate was reported.
    case certificateUnavailable
    /// The certificate does not match the pinned one.
    case certificateChanged
}

extension ConnectionTestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyAddress:
            return "请输入 UniFi 网关地址"
        case .invalidAddress:
            return "地址格式不对，请输入网关的 IP 地址或主机名，例如 192.168.8.254"
        case .cannotConnect(let address):
            return "连不上 UniFi 网关 \(address.urlString)，请检查地址和网络是否正常"
        case .unauthorized:
            return "API Key 不对或没有权限读取日志"
        case .notSupported:
            return "网关没有这个接口，固件版本可能不支持"
        case .logNotSupported:
            return "网关没有读取日志的接口，固件版本可能不支持"
        case .unreadableResponse(let detail):
            // The detail names a field or a coding path, never a response body.
            return "看不懂网关返回的内容（\(detail)）"
        case .gatewayRejected(let message):
            return "网关拒绝了这次请求：\(message)"
        case .gatewayNotFound:
            return "网关状态里没有找到 UniFi 网关设备"
        case .certificateUnavailable:
            return "没有读到 UniFi 网关的证书，请重新测试连接"
        case .certificateChanged:
            return "UniFi 网关的证书变了，请在连接设置里重新测试连接"
        }
    }
}

/// Runs 「测试连接」 against a UniFi gateway.
///
/// The order is fixed: normalize the address, read the sites, read the gateway
/// status, then read the last hour of the system log. Only when all three
/// queries work does the app remember the address, the API Key and the pinned
/// certificate.
public final class ConnectionTester: @unchecked Sendable {
    /// Site used when the gateway reports no site at all.
    public static let fallbackSiteReference = "default"

    /// How far back the log query goes: the last hour.
    public static let logWindow: TimeInterval = 60 * 60

    /// Builds the `URLSession` used for the test, with the trust delegate of
    /// this `ConnectionTester` attached.
    ///
    /// The default is `GatewayTrust.session`, so the real test pins the
    /// certificate. Tests inject a stub session.
    public typealias SessionProvider = (
        _ delegate: GatewayTrustDelegate,
        _ mode: GatewayTrustMode
    ) -> URLSession

    private let makeSession: SessionProvider
    private let now: () -> Date
    /// Trust delegate of the last `test` call, so a caller can inspect the
    /// handshake afterwards.
    private let delegateLock = NSLock()
    private var testDelegate: GatewayTrustDelegate?

    public init(
        sessionProvider: @escaping SessionProvider = { delegate, _ in
            GatewayTrust.session(delegate: delegate)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.makeSession = sessionProvider
        self.now = now
    }

    /// Tests one gateway and returns what the app has to remember.
    ///
    /// - Parameters:
    ///   - addressText: what the user typed, for example `192.168.8.254`.
    ///   - apiKey: the API Key, sent as `X-API-Key`. Never part of the result
    ///     or of an error.
    /// - Throws: `ConnectionTestError` with Chinese text for the app.
    public func test(addressText: String, apiKey: String) async throws -> ConnectionTestResult {
        let address = try normalize(addressText)

        // 首次测试: the certificate the gateway presents is accepted and pinned.
        // The observer is unused here: the delegate keeps the fingerprint.
        let delegate = GatewayTrustDelegate(gatewayHost: address.host, mode: .firstUse)
        setTestDelegate(delegate)
        let session = makeSession(delegate, .firstUse)
        let client = UniFiGatewayClient(baseURL: address.url, apiKey: apiKey, session: session)

        do {
            let sites = try await client.fetchSites()
            let site = sites.first
            let siteReference = site?.internalReference ?? Self.fallbackSiteReference

            let status = try await client.fetchGatewayStatus(site: siteReference)

            let to = now()
            let from = to.addingTimeInterval(-Self.logWindow)
            try await runLog(address) { _ = try await client.fetchSystemLog(site: siteReference, from: from, to: to) }

            guard let certificate = delegate.observedCertificate else {
                // A stub session never sees a TLS handshake; the real one does.
                throw ConnectionTestError.certificateUnavailable
            }

            return ConnectionTestResult(
                address: address,
                site: site,
                gatewayName: status.name,
                certificate: certificate
            )
        } catch let error as SentinelAPIError {
            throw Self.map(error, address: address)
        } catch let error as ConnectionTestError {
            throw error
        } catch {
            throw ConnectionTestError.unreadableResponse("unexpected failure")
        }
    }

    /// The trust delegate used by the last `test` call, for the caller that
    /// wants to inspect the handshake.
    public var trustDelegate: GatewayTrustDelegate? {
        delegateLock.lock()
        defer { delegateLock.unlock() }
        return testDelegate
    }

    // MARK: - Steps

    private func setTestDelegate(_ delegate: GatewayTrustDelegate) {
        delegateLock.lock()
        testDelegate = delegate
        delegateLock.unlock()
    }

    /// Step 1: turn the typed address into the normalized one.
    private func normalize(_ addressText: String) throws -> GatewayAddress {
        do {
            return try GatewayAddress(addressText)
        } catch GatewayAddressError.empty {
            throw ConnectionTestError.emptyAddress
        } catch {
            throw ConnectionTestError.invalidAddress
        }
    }

    /// Runs the log query and keeps a missing log endpoint apart.
    ///
    /// 缺少日志接口 means an older firmware, while a missing integration API
    /// means the endpoints were never there; the two messages differ.
    private func runLog<T>(_ address: GatewayAddress, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as ConnectionTestError {
            throw error
        } catch let error as SentinelAPIError {
            if case .notFound = error {
                throw ConnectionTestError.logNotSupported
            }
            throw Self.map(error, address: address)
        } catch {
            throw ConnectionTestError.unreadableResponse("unexpected failure")
        }
    }

    /// Maps a client error to the reason the app shows.
    ///
    /// A changed certificate stays its own case: the app asks for a new
    /// 「测试连接」 instead of showing a network failure.
    static func map(_ error: SentinelAPIError, address: GatewayAddress) -> ConnectionTestError {
        switch error {
        case .network:
            return .cannotConnect(address)
        case .unauthorized:
            return .unauthorized
        case .notFound:
            // Only the log query has its own 404 message; both say the same.
            return .notSupported
        case .decodingFailed(let detail):
            return .unreadableResponse(detail)
        case .gatewayDeviceNotFound:
            return .gatewayNotFound
        case .gatewayError(let message):
            return .gatewayRejected(message)
        case .invalidResponse(let statusCode):
            return .unreadableResponse("HTTP \(statusCode)")
        case .tooManyPages(let limit):
            return .unreadableResponse("日志页数超过上限 \(limit)")
        case .invalidURL:
            return .invalidAddress
        case .certificateChanged:
            return .certificateChanged
        }
    }
}
