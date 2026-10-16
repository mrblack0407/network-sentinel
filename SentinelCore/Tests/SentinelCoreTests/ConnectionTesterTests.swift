import Foundation
import XCTest
@testable import SentinelCore

/// 「测试连接」 end to end, against the URL stub instead of a gateway.
final class ConnectionTesterTests: XCTestCase {
    private let apiKey = "SECRET-API-KEY-0123456789"
    private let certificateFingerprint = "f7ba5c80d600a7dd98578b683287373716d9afc04875f2d60f05b426ef7a500b"

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    /// A tester whose session routes into `URLProtocolStub`.
    ///
    /// The stub records the fingerprint the TLS handshake would have reported,
    /// so the certificate path is exercised without a server.
    private func makeTester() -> ConnectionTester {
        ConnectionTester { delegate, _ in
            delegate.simulateServerTrust(host: "192.168.8.254", fingerprint: self.certificateFingerprint)

            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [URLProtocolStub.self]
            return URLSession(configuration: configuration)
        }
    }

    /// The three successful answers of one test.
    private func respondSuccessfully() throws {
        let sites = try Fixture.data("sites.json")
        let device = try Fixture.data("stat-device.json")
        let log = try Fixture.data("system-log-empty.json")

        URLProtocolStub.handler = { request, _ in
            let path = request.url?.path ?? ""
            let data = path.hasSuffix("/sites") ? sites : (path.hasSuffix("/stat/device") ? device : log)
            return .success((URLProtocolStub.httpResponse(url: request.url!, statusCode: 200), data))
        }
    }

    private func respond(statusCode: Int, data: Data = Data()) {
        URLProtocolStub.handler = { request, _ in
            .success((URLProtocolStub.httpResponse(url: request.url!, statusCode: statusCode), data))
        }
    }

    private func assertThrows(
        _ expected: ConnectionTestError,
        addressText: String = "192.168.8.254",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            let result = try await makeTester().test(addressText: addressText, apiKey: apiKey)
            XCTFail("expected \(expected), got \(result)", file: file, line: line)
        } catch let error as ConnectionTestError {
            XCTAssertEqual(error, expected, "message: \(error.localizedDescription)", file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    // MARK: - Success

    func testSuccessReadsSitesStatusAndLog() async throws {
        try respondSuccessfully()

        let result = try await makeTester().test(addressText: "  https://192.168.8.254/  ", apiKey: apiKey)

        XCTAssertEqual(result.urlString, "https://192.168.8.254")
        XCTAssertEqual(result.address.host, "192.168.8.254")
        XCTAssertNil(result.address.port)
        XCTAssertEqual(result.site?.internalReference, "default")
        XCTAssertEqual(result.siteReference, "default")
        XCTAssertEqual(result.gatewayName, "Dream Machine Pro Max")
        XCTAssertEqual(result.certificate, PinnedCertificate(host: "192.168.8.254", sha256: certificateFingerprint))

        XCTAssertEqual(URLProtocolStub.recorded.count, 3)
        XCTAssertEqual(
            URLProtocolStub.recorded.map { $0.request.url?.path },
            [
                "/proxy/network/integration/v1/sites",
                "/proxy/network/api/s/default/stat/device",
                "/proxy/network/v2/api/site/default/system-log/all",
            ]
        )
    }

    func testLogQueryCoversTheLastHour() async throws {
        try respondSuccessfully()
        let testTime = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try await ConnectionTester(
            sessionProvider: { delegate, _ in
                delegate.simulateServerTrust(host: "192.168.8.254", fingerprint: self.certificateFingerprint)
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [URLProtocolStub.self]
                return URLSession(configuration: configuration)
            },
            now: { testTime }
        ).test(addressText: "192.168.8.254", apiKey: apiKey)

        let logRequest = try XCTUnwrap(URLProtocolStub.recorded.last)
        let body = try XCTUnwrap(logRequest.body)
        let page = try JSONDecoder().decode(SystemLogPageRequest.self, from: body)

        XCTAssertEqual(page.timestampTo, 1_700_000_000_000)
        XCTAssertEqual(page.timestampFrom, 1_700_000_000_000 - 3_600_000)
        XCTAssertEqual(page.pageNumber, 0)
        XCTAssertEqual(page.pageSize, UniFiGatewayClient.logPageSize)
    }

    // MARK: - Address

    func testEmptyAddressFails() async throws {
        await assertThrows(.emptyAddress, addressText: "   ")
        XCTAssertTrue(URLProtocolStub.recorded.isEmpty)
    }

    func testBadAddressFails() async throws {
        await assertThrows(.invalidAddress, addressText: "192.168.8")
        await assertThrows(.invalidAddress, addressText: "gateway")
        XCTAssertTrue(URLProtocolStub.recorded.isEmpty)
    }

    // MARK: - Failures

    func testUnreachableGatewayNamesTheAddress() async throws {
        URLProtocolStub.handler = { _, _ in .failure(URLError(.cannotConnectToHost)) }

        do {
            _ = try await makeTester().test(addressText: "unifi.local", apiKey: apiKey)
            XCTFail("expected a failure")
        } catch let error as ConnectionTestError {
            guard case .cannotConnect(let address) = error else {
                XCTFail("expected .cannotConnect, got \(error)")
                return
            }
            XCTAssertEqual(address.urlString, "https://unifi.local")
            XCTAssertTrue(error.localizedDescription.contains("https://unifi.local"))
            XCTAssertTrue(error.localizedDescription.contains("连不上 UniFi 网关"))
            XCTAssertFalse(error.localizedDescription.contains(apiKey))
        }
    }

    func testUnauthorizedSaysTheAPIKeyIsWrong() async throws {
        respond(statusCode: 401, data: try Fixture.data("error-401.json"))

        await assertThrows(.unauthorized)
    }

    func testForbiddenSaysTheAPIKeyIsWrong() async throws {
        respond(statusCode: 403)

        await assertThrows(.unauthorized)
    }

    func testNotFoundOnTheStatusEndpointSaysTheFirmwareIsOld() async throws {
        try respondSuccessfully()
        let sites = try Fixture.data("sites.json")
        let notFound = try Fixture.data("error-404.json")
        URLProtocolStub.handler = { request, _ in
            let path = request.url?.path ?? ""
            let data = path.hasSuffix("/sites") ? sites : notFound
            let status = path.hasSuffix("/sites") ? 200 : 404
            return .success((URLProtocolStub.httpResponse(url: request.url!, statusCode: status), data))
        }

        await assertThrows(.notSupported)
    }

    func testNotFoundOnTheLogEndpointSaysSo() async throws {
        try respondSuccessfully()
        let sites = try Fixture.data("sites.json")
        let device = try Fixture.data("stat-device.json")
        let notFound = try Fixture.data("error-404.json")
        URLProtocolStub.handler = { request, _ in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/sites") {
                return .success((URLProtocolStub.httpResponse(url: request.url!, statusCode: 200), sites))
            }
            if path.hasSuffix("/stat/device") {
                return .success((URLProtocolStub.httpResponse(url: request.url!, statusCode: 200), device))
            }
            return .success((URLProtocolStub.httpResponse(url: request.url!, statusCode: 404), notFound))
        }

        await assertThrows(.logNotSupported)
    }

    func testUnreadableResponseIsReported() async throws {
        respond(statusCode: 200, data: Data("not json at all".utf8))

        do {
            _ = try await makeTester().test(addressText: "192.168.8.254", apiKey: apiKey)
            XCTFail("expected an unreadable response")
        } catch let error as ConnectionTestError {
            guard case .unreadableResponse(let detail) = error else {
                XCTFail("expected .unreadableResponse, got \(error)")
                return
            }
            XCTAssertFalse(detail.isEmpty)
            XCTAssertFalse(detail.contains("not json at all"))
            XCTAssertTrue(error.localizedDescription.hasPrefix("看不懂网关返回的内容"))
        }
    }

    func testChangedCertificateIsItsOwnFailure() async throws {
        // Polling uses the pinned mode. A different certificate is rejected, and
        // URLSession then fails the request with `.cancelled`.
        let pinned = PinnedCertificate(host: "192.168.8.254", sha256: String(repeating: "a", count: 64))
        let otherFingerprint = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let delegate = GatewayTrustDelegate(gatewayHost: "192.168.8.254", mode: .pinned(pinned))
        XCTAssertEqual(delegate.simulateServerTrust(host: "192.168.8.254", fingerprint: otherFingerprint), .reject)
        XCTAssertTrue(delegate.didRejectCertificate)

        URLProtocolStub.handler = { _, _ in .failure(URLError(.cancelled)) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let client = UniFiGatewayClient(baseURL: URL(string: "https://192.168.8.254")!, apiKey: apiKey, session: session)

        do {
            _ = try await client.fetchSites()
            XCTFail("expected a certificate failure")
        } catch let error as SentinelAPIError {
            XCTAssertEqual(error, .certificateChanged)
            XCTAssertEqual(ConnectionTestError.certificateChanged.localizedDescription, "UniFi 网关的证书变了，请在连接设置里重新测试连接")
        }
    }

    func testCancelledRequestWithoutRejectionIsANetworkFailure() async throws {
        URLProtocolStub.handler = { _, _ in .failure(URLError(.cancelled)) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let delegate = GatewayTrustDelegate(gatewayHost: "192.168.8.254", mode: .firstUse)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let client = UniFiGatewayClient(baseURL: URL(string: "https://192.168.8.254")!, apiKey: apiKey, session: session)

        do {
            _ = try await client.fetchSites()
            XCTFail("expected a failure")
        } catch SentinelAPIError.network(let urlError) {
            XCTAssertEqual(urlError.code, .cancelled)
        }
    }

    func testMissingCertificateIsReportedSeparately() async throws {
        try respondSuccessfully()
        // A session that records no certificate, as if the TLS handshake never
        // reported one.
        let tester = ConnectionTester { _, _ in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [URLProtocolStub.self]
            return URLSession(configuration: configuration)
        }

        do {
            _ = try await tester.test(addressText: "192.168.8.254", apiKey: apiKey)
            XCTFail("expected a missing certificate")
        } catch let error as ConnectionTestError {
            XCTAssertEqual(error, .certificateUnavailable)
            XCTAssertTrue(error.localizedDescription.contains("证书"))
        }
    }

    func testGatewayErrorIsReported() async throws {
        try respondSuccessfully()
        let sites = try Fixture.data("sites.json")
        let gatewayError = try Fixture.data("error-404.json")
        URLProtocolStub.handler = { request, _ in
            let path = request.url?.path ?? ""
            let data = path.hasSuffix("/sites") ? sites : gatewayError
            return .success((URLProtocolStub.httpResponse(url: request.url!, statusCode: 200), data))
        }

        await assertThrows(.gatewayRejected("api.err.NotFound"))
    }

    // MARK: - Chinese text and API Key handling

    func testEveryFailureHasChineseTextWithoutTheAPIKey() {
        let address = try! GatewayAddress("192.168.8.254")
        let errors: [ConnectionTestError] = [
            .emptyAddress,
            .invalidAddress,
            .cannotConnect(address),
            .unauthorized,
            .notSupported,
            .logNotSupported,
            .unreadableResponse("missing field data"),
            .gatewayRejected("api.err.NotFound"),
            .gatewayNotFound,
            .certificateUnavailable,
            .certificateChanged,
        ]

        for error in errors {
            let message = error.localizedDescription
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(message.contains(where: { $0.unicodeScalars.contains { $0.value > 127 } }), message)
            XCTAssertFalse(message.contains(apiKey))
            XCTAssertFalse(String(describing: error).contains(apiKey))
            XCTAssertFalse(String(reflecting: error).contains(apiKey))
        }
    }

    func testErrorMappingCoversEveryClientError() throws {
        let address = try GatewayAddress("192.168.8.254")
        let expected: [(SentinelAPIError, ConnectionTestError)] = [
            (.network(URLError(.cannotConnectToHost)), .cannotConnect(address)),
            (.unauthorized(statusCode: 401), .unauthorized),
            (.notFound, .notSupported),
            (.invalidResponse(statusCode: 502), .unreadableResponse("HTTP 502")),
            (.decodingFailed("missing field data"), .unreadableResponse("missing field data")),
            (.gatewayDeviceNotFound, .gatewayNotFound),
            (.gatewayError("api.err.NotFound"), .gatewayRejected("api.err.NotFound")),
            (.tooManyPages(50), .unreadableResponse("日志页数超过上限 50")),
            (.invalidURL, .invalidAddress),
            (.certificateChanged, .certificateChanged),
        ]

        for (clientError, testError) in expected {
            XCTAssertEqual(ConnectionTester.map(clientError, address: address), testError, "\(clientError)")
        }
    }

    func testSuccessResultNeverCarriesTheAPIKey() async throws {
        try respondSuccessfully()

        let result = try await makeTester().test(addressText: "192.168.8.254", apiKey: apiKey)

        XCTAssertFalse(String(describing: result).contains(apiKey))
        XCTAssertFalse(String(reflecting: result).contains(apiKey))
        XCTAssertTrue(String(describing: result).contains("https://192.168.8.254"))
        XCTAssertTrue(String(describing: result).contains("Dream Machine Pro Max"))
    }
}
