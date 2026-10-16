import XCTest
@testable import SentinelCore

/// The Bark HTTP API, against the URL stub instead of a real server.
final class BarkClientTests: XCTestCase {
    /// A fake device Key, shaped like the 22 characters Bark generates.
    private let key = "abcdEFGH1234"
    private var configuration: BarkConfiguration!

    override func setUpWithError() throws {
        try super.setUpWithError()
        URLProtocolStub.reset()
        configuration = try BarkConfiguration(serverAddress: "https://api.day.app", deviceKey: key)
    }

    override func tearDown() {
        URLProtocolStub.reset()
        configuration = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeClient() -> BarkClient {
        BarkClient(configuration: configuration, session: URLProtocolStub.makeSession())
    }

    /// Answers every request with one status and one body.
    private func respond(statusCode: Int, body: String) {
        URLProtocolStub.handler = { request, _ in
            .success((URLProtocolStub.httpResponse(url: request.url!, statusCode: statusCode), Data(body.utf8)))
        }
    }

    /// Fails every request with one network error.
    private func respondWithNetworkFailure(_ code: URLError.Code) {
        URLProtocolStub.handler = { _, _ in .failure(URLError(code)) }
    }

    /// The JSON object of a recorded request body.
    private func payload(of request: URLProtocolStub.RecordedRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.body, "the request carried no body")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Sends one push and expects a `BarkError`.
    private func assertThrows(
        _ expected: BarkError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await makeClient().send(title: "标题", body: "正文", level: .active)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as BarkError {
            XCTAssertEqual(error, expected, "message: \(error.localizedDescription)", file: file, line: line)
            XCTAssertFalse(
                error.localizedDescription.contains(key),
                "the error carries the Key: \(error.localizedDescription)",
                file: file,
                line: line
            )
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    /// Sends one push and expects a network failure with one code.
    ///
    /// The code is compared, not the whole `URLError`: `URLSession` may add its
    /// own `userInfo` to the error of the stub.
    private func assertNetworkFailure(
        _ code: URLError.Code,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await makeClient().send(title: "标题", body: "正文", level: .active)
            XCTFail("expected a network failure", file: file, line: line)
        } catch let error as BarkError {
            guard case .network(let urlError) = error else {
                XCTFail("expected a network failure, got \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(urlError.code, code, file: file, line: line)
            XCTAssertFalse(
                error.localizedDescription.contains(key),
                "the error carries the Key",
                file: file,
                line: line
            )
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    // MARK: - Request

    func testPushPostsTheBarkPayload() async throws {
        respond(statusCode: 200, body: #"{"code":200,"message":"success"}"#)

        try await makeClient().send(
            title: "互联网中断 🟥🟥🟥🟥",
            body: "WAN1 (China Telecom) 已断开。",
            level: .timeSensitive
        )

        let recorded = try XCTUnwrap(URLProtocolStub.recorded.first)
        XCTAssertEqual(URLProtocolStub.recorded.count, 1)
        XCTAssertEqual(recorded.request.url?.absoluteString, "https://api.day.app/push")
        XCTAssertEqual(recorded.request.httpMethod, "POST")
        XCTAssertEqual(
            recorded.request.value(forHTTPHeaderField: "Content-Type"),
            "application/json; charset=utf-8"
        )

        let payload = try payload(of: recorded)
        XCTAssertEqual(payload["device_key"] as? String, key)
        XCTAssertEqual(payload["title"] as? String, "互联网中断 🟥🟥🟥🟥")
        XCTAssertEqual(payload["body"] as? String, "WAN1 (China Telecom) 已断开。")
        XCTAssertEqual(payload["group"] as? String, "Network Sentinel")
        XCTAssertEqual(payload["level"] as? String, "timeSensitive")
        XCTAssertEqual(payload["isArchive"] as? Int, 1)
        XCTAssertEqual(payload.count, 6)
    }

    func testAnActivePushCarriesTheActiveLevel() async throws {
        respond(statusCode: 200, body: #"{"code":200}"#)

        try await makeClient().send(title: "标题", body: "正文", level: .active)

        let recorded = try XCTUnwrap(URLProtocolStub.recorded.first)
        XCTAssertEqual(try payload(of: recorded)["level"] as? String, "active")
    }

    func testASelfHostedServerUsesItsOwnPushURL() async throws {
        configuration = try BarkConfiguration(serverAddress: "http://192.168.1.10:8080", deviceKey: key)
        respond(statusCode: 200, body: #"{"code":200}"#)

        try await makeClient().send(title: "标题", body: "正文", level: .active)

        XCTAssertEqual(
            URLProtocolStub.recorded.first?.request.url?.absoluteString,
            "http://192.168.1.10:8080/push"
        )
    }

    // MARK: - Success

    func testCodeTwoHundredSucceeds() async throws {
        respond(statusCode: 200, body: #"{"code":200,"message":"success","timestamp":1}"#)

        try await makeClient().send(title: "标题", body: "正文", level: .active)
    }

    func testACodeAsTextIsRead() async throws {
        respond(statusCode: 200, body: #"{"code":"200"}"#)

        try await makeClient().send(title: "标题", body: "正文", level: .active)
    }

    // MARK: - Refused Key

    func testHTTPFourHundredMeansTheKeyIsWrong() async {
        respond(statusCode: 400, body: #"{"code":400,"message":"device key is invalid"}"#)

        await assertThrows(.invalidKey)
    }

    func testCodeFourHundredMeansTheKeyIsWrong() async {
        respond(statusCode: 200, body: #"{"code":400,"message":"device key is invalid"}"#)

        await assertThrows(.invalidKey)
    }

    func testHTTPFourHundredWithAnUnreadableBodyStillMeansTheKeyIsWrong() async {
        respond(statusCode: 400, body: "device key is invalid")

        await assertThrows(.invalidKey)
    }

    // MARK: - Server errors

    func testHTTPFiveHundredCarriesTheServerMessage() async {
        respond(statusCode: 500, body: #"{"code":500,"message":"internal error"}"#)

        await assertThrows(.server("internal error"))
    }

    func testHTTPFiveHundredWithoutAMessageNamesTheStatus() async {
        respond(statusCode: 500, body: "")

        await assertThrows(.server("HTTP 500"))
    }

    func testAnErrorCodeCarriesTheServerMessage() async {
        respond(statusCode: 200, body: #"{"code":500,"message":"push failed"}"#)

        await assertThrows(.server("push failed"))
    }

    func testAnErrorCodeWithoutAMessageNamesTheCode() async {
        respond(statusCode: 200, body: #"{"code":500}"#)

        await assertThrows(.server("code 500"))
    }

    func testAServerMessageWithTheKeyIsRedacted() async {
        respond(statusCode: 500, body: #"{"code":500,"message":"device key abcdEFGH1234 rejected"}"#)

        do {
            try await makeClient().send(title: "标题", body: "正文", level: .active)
            XCTFail("expected a server error")
        } catch let error as BarkError {
            XCTAssertEqual(error, .server("device key *** rejected"))
            XCTAssertFalse(error.localizedDescription.contains(key))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Network

    func testANetworkFailureIsReported() async {
        respondWithNetworkFailure(.cannotConnectToHost)

        await assertNetworkFailure(.cannotConnectToHost)
    }

    func testATimeoutIsReported() async {
        respondWithNetworkFailure(.timedOut)

        await assertNetworkFailure(.timedOut)
    }

    // MARK: - Unreadable answers

    func testANonJSONBodyIsUnreadable() async {
        respond(statusCode: 200, body: "<html>hello</html>")

        await assertThrows(.unreadableResponse)
    }

    func testAJSONBodyWithoutACodeIsUnreadable() async {
        respond(statusCode: 200, body: #"{"message":"ok"}"#)

        await assertThrows(.unreadableResponse)
    }

    func testAnEmptyBodyIsUnreadable() async {
        respond(statusCode: 200, body: "")

        await assertThrows(.unreadableResponse)
    }

    // MARK: - Messages

    func testTheMessagesAreChinese() {
        XCTAssertEqual(
            BarkError.invalidKey.errorDescription,
            "Bark Key 不对，请在「通知」里重新填。"
        )
        XCTAssertEqual(
            BarkError.server("boom").errorDescription,
            "Bark 服务器返回错误：boom"
        )
        XCTAssertEqual(
            BarkError.network(URLError(.timedOut)).errorDescription,
            "连不上 Bark 服务器，请检查服务器地址和网络。"
        )
        XCTAssertEqual(
            BarkError.unreadableResponse.errorDescription,
            "看不懂 Bark 服务器返回的内容。"
        )
    }
}
