import XCTest
@testable import SentinelCore

final class GatewayReachabilityTests: XCTestCase {
    /// The error the client throws when it cannot reach the gateway at all.
    private var networkError: SentinelAPIError {
        .network(URLError(.cannotConnectToHost))
    }

    // MARK: - Threshold

    func testTheGatewayIsUnreachableOnlyOnTheThirdFailure() {
        var reachability = GatewayReachability()

        XCTAssertEqual(reachability.state, .connected)

        XCTAssertFalse(reachability.record(.failure(networkError)))
        XCTAssertEqual(reachability.consecutiveFailureCount, 1)
        XCTAssertEqual(reachability.state, .connected)

        XCTAssertFalse(reachability.record(.failure(networkError)))
        XCTAssertEqual(reachability.consecutiveFailureCount, 2)
        XCTAssertEqual(reachability.state, .connected)

        XCTAssertTrue(reachability.record(.failure(networkError)))
        XCTAssertEqual(reachability.consecutiveFailureCount, 3)
        XCTAssertEqual(reachability.state, .reconnecting)
        XCTAssertTrue(reachability.isGatewayUnreachable)
        XCTAssertTrue(reachability.stateDidChange)

        // Staying unreachable is not a state change.
        XCTAssertFalse(reachability.record(.failure(networkError)))
        XCTAssertEqual(reachability.consecutiveFailureCount, 4)
        XCTAssertFalse(reachability.stateDidChange)
    }

    func testASuccessClearsTheCounter() {
        var reachability = GatewayReachability()

        reachability.record(.failure(networkError))
        reachability.record(.failure(networkError))
        XCTAssertEqual(reachability.consecutiveFailureCount, 2)

        XCTAssertFalse(reachability.record(.success))
        XCTAssertEqual(reachability.consecutiveFailureCount, 0)
        XCTAssertEqual(reachability.state, .connected)

        // The counter starts over, so two more failures are not enough.
        reachability.record(.failure(networkError))
        XCTAssertFalse(reachability.record(.failure(networkError)))
        XCTAssertEqual(reachability.state, .connected)
    }

    func testTheStateChangeIsReportedWhenTheGatewayComesBack() {
        var reachability = GatewayReachability()

        for _ in 0..<3 {
            reachability.record(.failure(networkError))
        }
        XCTAssertEqual(reachability.state, .reconnecting)

        XCTAssertTrue(reachability.record(.success))
        XCTAssertEqual(reachability.state, .connected)
        XCTAssertFalse(reachability.isGatewayUnreachable)
    }

    func testAThresholdOfOneWarnsOnTheFirstFailure() {
        var reachability = GatewayReachability(failureThreshold: 1)

        XCTAssertTrue(reachability.record(.failure(networkError)))
        XCTAssertEqual(reachability.state, .reconnecting)
    }

    func testAThresholdBelowOneIsRaisedToOne() {
        var reachability = GatewayReachability(failureThreshold: 0)

        XCTAssertEqual(reachability.failureThreshold, 1)
        reachability.record(.failure(networkError))
        XCTAssertEqual(reachability.state, .reconnecting)
    }

    // MARK: - API Key

    func testUnauthorizedIsAPIKeyRejectedAndNotUnreachable() {
        for statusCode in [401, 403] {
            var reachability = GatewayReachability()

            for _ in 0..<5 {
                reachability.record(.failure(.unauthorized(statusCode: statusCode)))
            }

            XCTAssertEqual(reachability.state, .apiKeyRejected)
            XCTAssertTrue(reachability.isAPIKeyRejected)
            XCTAssertFalse(reachability.isGatewayUnreachable)
            XCTAssertEqual(reachability.consecutiveFailureCount, 0)
        }
    }

    func testAnUnauthorizedAfterANetworkFailureIsAStateChange() {
        var reachability = GatewayReachability()

        reachability.record(.failure(networkError))
        reachability.record(.failure(networkError))
        XCTAssertEqual(reachability.state, .connected)

        XCTAssertTrue(reachability.record(.failure(.unauthorized(statusCode: 401))))
        XCTAssertEqual(reachability.state, .apiKeyRejected)
        XCTAssertEqual(reachability.consecutiveFailureCount, 0)
    }

    func testAFixedAPIKeyIsAStateChange() {
        var reachability = GatewayReachability()

        reachability.record(.failure(.unauthorized(statusCode: 401)))
        XCTAssertTrue(reachability.record(.success))
        XCTAssertEqual(reachability.state, .connected)
    }

    // MARK: - Other errors

    func testOtherErrorsDoNotCountAsFailures() {
        var reachability = GatewayReachability()

        for _ in 0..<5 {
            reachability.record(.failure(.notFound))
            reachability.record(.failure(.invalidResponse(statusCode: 502)))
            reachability.record(.failure(.decodingFailed("missing field data")))
            reachability.record(.failure(.gatewayError("api.err.NotFound")))
            reachability.record(.failure(.gatewayDeviceNotFound))
            reachability.record(.failure(.tooManyPages(50)))
            reachability.record(.failure(.invalidURL))
        }

        XCTAssertEqual(reachability.consecutiveFailureCount, 0)
        XCTAssertEqual(reachability.state, .connected)
    }

    // MARK: - Errors thrown by the client

    func testAThrownSentinelErrorIsRecorded() {
        var reachability = GatewayReachability()

        for _ in 0..<3 {
            reachability.record(error: networkError)
        }

        XCTAssertEqual(reachability.state, .reconnecting)
    }

    func testAThrownUnauthorizedIsRecorded() {
        var reachability = GatewayReachability()

        reachability.record(error: SentinelAPIError.unauthorized(statusCode: 403))

        XCTAssertEqual(reachability.state, .apiKeyRejected)
    }

    func testAThrownForeignErrorCountsAsANetworkFailure() {
        struct Unexpected: Error {}

        var reachability = GatewayReachability()
        for _ in 0..<3 {
            reachability.record(error: Unexpected())
        }

        XCTAssertEqual(reachability.state, .reconnecting)
        XCTAssertEqual(reachability.consecutiveFailureCount, 3)
    }

    // MARK: - Persistence

    func testTheCounterSurvivesARestart() throws {
        var reachability = GatewayReachability()
        reachability.record(.failure(networkError))
        reachability.record(.failure(networkError))

        let data = try JSONEncoder().encode(reachability)
        var restored = try JSONDecoder().decode(GatewayReachability.self, from: data)

        XCTAssertEqual(restored.consecutiveFailureCount, 2)
        XCTAssertEqual(restored.state, .connected)
        // A restored state is never a state change, so the app does not warn again.
        XCTAssertFalse(restored.stateDidChange)

        // The third failure of the whole series flips the state.
        XCTAssertTrue(restored.record(.failure(networkError)))
        XCTAssertEqual(restored.state, .reconnecting)
    }

    func testAStoredUnreachableStateSurvivesARestart() throws {
        var reachability = GatewayReachability()
        for _ in 0..<3 {
            reachability.record(.failure(networkError))
        }

        let data = try JSONEncoder().encode(reachability)
        let restored = try JSONDecoder().decode(GatewayReachability.self, from: data)

        XCTAssertEqual(restored.state, .reconnecting)
        XCTAssertTrue(restored.isGatewayUnreachable)
    }

    func testResetGoesBackToConnected() {
        var reachability = GatewayReachability()
        for _ in 0..<3 {
            reachability.record(.failure(networkError))
        }

        reachability.reset()

        XCTAssertEqual(reachability.state, .connected)
        XCTAssertEqual(reachability.consecutiveFailureCount, 0)
        XCTAssertFalse(reachability.stateDidChange)
    }

    func testTheStatesHaveChineseNames() {
        XCTAssertEqual(GatewayConnectionState.connected.displayName, "已连接")
        XCTAssertEqual(GatewayConnectionState.reconnecting.displayName, "网关连不上")
        XCTAssertEqual(GatewayConnectionState.apiKeyRejected.displayName, "API Key 无效")
    }
}
