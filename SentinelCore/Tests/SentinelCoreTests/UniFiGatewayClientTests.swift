import XCTest
@testable import SentinelCore

final class UniFiGatewayClientTests: XCTestCase {
    private let baseURL = URL(string: "https://192.168.8.254")!
    private let apiKey = "SECRET-API-KEY-0123456789"

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func makeClient(maxLogPages: Int = UniFiGatewayClient.defaultMaxLogPages) -> UniFiGatewayClient {
        UniFiGatewayClient(
            baseURL: baseURL,
            apiKey: apiKey,
            session: URLProtocolStub.makeSession(),
            maxLogPages: maxLogPages
        )
    }

    private func respond(
        statusCode: Int,
        data: Data
    ) -> (URLRequest, Data?) -> Result<(HTTPURLResponse, Data), Error> {
        { request, _ in
            let url = request.url ?? self.baseURL
            return .success((URLProtocolStub.httpResponse(url: url, statusCode: statusCode), data))
        }
    }

    // MARK: - Requests

    func testFetchSitesSendsTheExpectedRequest() async throws {
        let body = try Fixture.data("sites.json")
        URLProtocolStub.handler = respond(statusCode: 200, data: body)

        let sites = try await makeClient().fetchSites()

        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(sites[0].internalReference, "default")
        XCTAssertEqual(sites[0].name, "Default")

        let recorded = try XCTUnwrap(URLProtocolStub.recorded.first)
        XCTAssertEqual(URLProtocolStub.recorded.count, 1)
        XCTAssertEqual(
            recorded.request.url?.absoluteString,
            "https://192.168.8.254/proxy/network/integration/v1/sites"
        )
        XCTAssertEqual(recorded.request.httpMethod, "GET")
        XCTAssertEqual(recorded.request.value(forHTTPHeaderField: "X-API-Key"), apiKey)
        XCTAssertNil(recorded.body)
    }

    func testFetchGatewayStatusSendsTheExpectedRequest() async throws {
        let body = try Fixture.data("stat-device.json")
        URLProtocolStub.handler = respond(statusCode: 200, data: body)

        let status = try await makeClient().fetchGatewayStatus(site: "default")

        XCTAssertEqual(status.name, "Dream Machine Pro Max")
        XCTAssertEqual(status.wanInterfaces.count, 1)
        XCTAssertEqual(status.wan1?.state, .online)

        let recorded = try XCTUnwrap(URLProtocolStub.recorded.first)
        XCTAssertEqual(
            recorded.request.url?.absoluteString,
            "https://192.168.8.254/proxy/network/api/s/default/stat/device"
        )
        XCTAssertEqual(recorded.request.httpMethod, "GET")
        XCTAssertEqual(recorded.request.value(forHTTPHeaderField: "X-API-Key"), apiKey)
    }

    func testFetchSystemLogSendsTheExpectedRequest() async throws {
        // Only the first page, so the client asks once.
        var page = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Fixture.data("system-log-page0.json")) as? [String: Any]
        )
        page["total_page_count"] = 1
        page["total_element_count"] = 70
        URLProtocolStub.handler = respond(
            statusCode: 200,
            data: try JSONSerialization.data(withJSONObject: page)
        )

        let from = Date(timeIntervalSince1970: 1_700_000_000)
        let to = Date(timeIntervalSince1970: 1_700_086_400)
        let entries = try await makeClient().fetchSystemLog(site: "default", from: from, to: to)

        XCTAssertEqual(entries.count, 70)

        let recorded = try XCTUnwrap(URLProtocolStub.recorded.first)
        XCTAssertEqual(
            recorded.request.url?.absoluteString,
            "https://192.168.8.254/proxy/network/v2/api/site/default/system-log/all"
        )
        XCTAssertEqual(recorded.request.httpMethod, "POST")
        XCTAssertEqual(recorded.request.value(forHTTPHeaderField: "X-API-Key"), apiKey)
        XCTAssertEqual(recorded.request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let requestBody = try XCTUnwrap(recorded.body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["timestampFrom", "timestampTo", "pageNumber", "pageSize"])
        XCTAssertEqual(json["timestampFrom"] as? Int, 1_700_000_000_000)
        XCTAssertEqual(json["timestampTo"] as? Int, 1_700_086_400_000)
        XCTAssertEqual(json["pageNumber"] as? Int, 0)
        XCTAssertEqual(json["pageSize"] as? Int, 500)
    }

    func testSiteNameIsPercentEncoded() async throws {
        URLProtocolStub.handler = respond(statusCode: 200, data: try Fixture.data("stat-device.json"))

        _ = try await makeClient().fetchGatewayStatus(site: "my site")

        let recorded = try XCTUnwrap(URLProtocolStub.recorded.first)
        XCTAssertEqual(
            recorded.request.url?.absoluteString,
            "https://192.168.8.254/proxy/network/api/s/my%20site/stat/device"
        )
    }

    // MARK: - Pagination

    func testFetchSystemLogFollowsEveryPage() async throws {
        let page0 = try Fixture.data("system-log-page0.json")
        let page1 = try Fixture.data("system-log-page1.json")

        URLProtocolStub.handler = { request, body in
            let requestedPage = try! JSONDecoder().decode(SystemLogPageRequest.self, from: XCTUnwrap(body))
            let data = requestedPage.pageNumber == 0 ? page0 : page1
            return .success((URLProtocolStub.httpResponse(url: request.url!, statusCode: 200), data))
        }

        let entries = try await makeClient().fetchSystemLog(
            site: "default",
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_700_086_400)
        )

        XCTAssertEqual(entries.count, 140)
        XCTAssertEqual(entries.compactMap { $0.monitoredEvent }.count, 116)
        XCTAssertEqual(URLProtocolStub.recorded.count, 2)

        let requestedPages = try URLProtocolStub.recorded.map { recorded -> Int in
            let body = try XCTUnwrap(recorded.body)
            return try JSONDecoder().decode(SystemLogPageRequest.self, from: body).pageNumber
        }
        XCTAssertEqual(requestedPages, [0, 1])
    }

    func testEmptyLogNeedsOnlyOneRequest() async throws {
        URLProtocolStub.handler = respond(statusCode: 200, data: try Fixture.data("system-log-empty.json"))

        let entries = try await makeClient().fetchSystemLog(
            site: "default",
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_700_086_400)
        )

        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(URLProtocolStub.recorded.count, 1)
    }

    func testPaginationStopsAtTheSafetyLimit() async throws {
        let singleEntryPage: [String: Any] = [
            "page_number": 0,
            "total_element_count": 10_000,
            "total_page_count": 99,
            "data": [[
                "id": "a",
                "timestamp": 1_000,
                "category": "INTERNET_AND_WAN",
                "key": "NETWORK_WAN_FAILED_2",
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: singleEntryPage)
        URLProtocolStub.handler = respond(statusCode: 200, data: data)

        await assertThrows(.tooManyPages(3)) {
            _ = try await self.makeClient(maxLogPages: 3).fetchSystemLog(
                site: "default",
                from: Date(timeIntervalSince1970: 1_700_000_000),
                to: Date(timeIntervalSince1970: 1_700_086_400)
            )
        }

        XCTAssertEqual(URLProtocolStub.recorded.count, 3)
    }

    // MARK: - Errors

    func testUnauthorizedIsMapped() async throws {
        URLProtocolStub.handler = respond(statusCode: 401, data: try Fixture.data("error-401.json"))

        await assertThrows(.unauthorized(statusCode: 401)) {
            _ = try await self.makeClient().fetchSites()
        }
    }

    func testForbiddenIsMapped() async throws {
        URLProtocolStub.handler = respond(statusCode: 403, data: Data())

        await assertThrows(.unauthorized(statusCode: 403)) {
            _ = try await self.makeClient().fetchSites()
        }
    }

    func testNotFoundIsMapped() async throws {
        URLProtocolStub.handler = respond(statusCode: 404, data: try Fixture.data("error-404.json"))

        await assertThrows(.notFound) {
            _ = try await self.makeClient().fetchGatewayStatus(site: "default")
        }
    }

    func testOtherHTTPStatusIsMapped() async throws {
        URLProtocolStub.handler = respond(statusCode: 502, data: Data())

        await assertThrows(.invalidResponse(statusCode: 502)) {
            _ = try await self.makeClient().fetchSites()
        }
    }

    func testNetworkErrorIsMapped() async {
        URLProtocolStub.handler = { _, _ in .failure(URLError(.cannotConnectToHost)) }

        do {
            _ = try await makeClient().fetchSites()
            XCTFail("expected a network error")
        } catch let error as SentinelAPIError {
            guard case .network(let urlError) = error else {
                XCTFail("expected .network, got \(error)")
                return
            }
            XCTAssertEqual(urlError.code, .cannotConnectToHost)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testDecodingFailureIsMapped() async throws {
        URLProtocolStub.handler = respond(statusCode: 200, data: Data("not json at all".utf8))

        do {
            _ = try await makeClient().fetchSites()
            XCTFail("expected a decoding error")
        } catch let error as SentinelAPIError {
            guard case .decodingFailed(let detail) = error else {
                XCTFail("expected .decodingFailed, got \(error)")
                return
            }
            XCTAssertFalse(detail.isEmpty)
            XCTAssertFalse(detail.contains(apiKey))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testGatewayDeviceNotFoundIsMapped() async throws {
        URLProtocolStub.handler = respond(statusCode: 200, data: try Fixture.data("error-404.json"))

        await assertThrows(.gatewayError("api.err.NotFound")) {
            _ = try await self.makeClient().fetchGatewayStatus(site: "default")
        }
    }

    func testEmptyDeviceListIsMapped() async throws {
        let data = try JSONSerialization.data(withJSONObject: ["meta": ["rc": "ok"], "data": []] as [String: Any])
        URLProtocolStub.handler = respond(statusCode: 200, data: data)

        await assertThrows(.gatewayDeviceNotFound) {
            _ = try await self.makeClient().fetchGatewayStatus(site: "default")
        }
    }

    // MARK: - API Key handling

    func testErrorDescriptionsNeverContainTheAPIKey() async throws {
        URLProtocolStub.handler = respond(statusCode: 401, data: try Fixture.data("error-401.json"))

        var thrown: SentinelAPIError?
        do {
            _ = try await makeClient().fetchSites()
        } catch let error as SentinelAPIError {
            thrown = error
        }

        let error = try XCTUnwrap(thrown)
        XCTAssertFalse(error.localizedDescription.contains(apiKey))
        XCTAssertFalse((error as NSError).localizedDescription.contains(apiKey))
        XCTAssertFalse(String(describing: error).contains(apiKey))
        XCTAssertFalse(String(reflecting: error).contains(apiKey))
    }

    func testEveryErrorCaseHasAKeyFreeChineseDescription() {
        let errors: [SentinelAPIError] = [
            .network(URLError(.cannotConnectToHost)),
            .unauthorized(statusCode: 401),
            .unauthorized(statusCode: 403),
            .notFound,
            .invalidResponse(statusCode: 502),
            .decodingFailed("missing field data"),
            .gatewayDeviceNotFound,
            .gatewayError("api.err.NotFound"),
            .tooManyPages(50),
            .invalidURL,
        ]

        for error in errors {
            let description = error.localizedDescription
            XCTAssertFalse(description.isEmpty)
            XCTAssertFalse(description.contains(apiKey))
            XCTAssertFalse(String(describing: error).contains(apiKey))
            XCTAssertFalse(String(reflecting: error).contains(apiKey))
        }
    }

    func testClientDescriptionRedactsTheAPIKey() {
        let client = makeClient()

        XCTAssertFalse(String(describing: client).contains(apiKey))
        XCTAssertFalse(String(reflecting: client).contains(apiKey))
        XCTAssertTrue(String(describing: client).contains("<redacted>"))
        XCTAssertTrue(String(describing: client).contains("https://192.168.8.254"))
    }

    // MARK: - Helpers

    private func assertThrows<T>(
        _ expected: SentinelAPIError,
        from operation: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("expected \(expected), but the call succeeded", file: file, line: line)
        } catch let error as SentinelAPIError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
