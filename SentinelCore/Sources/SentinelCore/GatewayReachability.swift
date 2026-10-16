import Foundation

/// Whether the app can talk to the UniFi gateway.
///
/// A single failed query is normal: the gateway may be busy, the Wi-Fi may
/// blink, a query may time out. The app only warns after three failures in a
/// row. A successful query clears the counter, and a wrong API Key is a
/// separate problem: the gateway answered, so it is not unreachable.
public enum GatewayConnectionState: String, Codable {
    case connected
    case reconnecting
    case apiKeyRejected
    /// The gateway presented a certificate that is not the pinned one.
    ///
    /// Not a plain network failure: the app answers it with 「测试连接」 instead
    /// of waiting, so it has its own state.
    case certificateChanged

    /// Chinese text for the app.
    public var displayName: String {
        switch self {
        case .connected: return "已连接"
        case .reconnecting: return "网关连不上"
        case .apiKeyRejected: return "API Key 无效"
        case .certificateChanged: return "证书变了"
        }
    }

    /// `true` while the gateway itself answers on the network.
    ///
    /// A rejected API Key and a changed certificate are answers: the gateway is
    /// reachable, and only the 状态文件 cares about the difference.
    public var isGatewayReachable: Bool {
        self != .reconnecting && self != .certificateChanged
    }
}

/// A probe result, kept apart from the client so tests need no network.
public struct GatewayProbe: Equatable {
    public let isReachable: Bool
    public let error: SentinelAPIError?

    public init(isReachable: Bool, error: SentinelAPIError? = nil) {
        self.isReachable = isReachable
        self.error = error
    }

    /// The gateway answered a query.
    public static let success = GatewayProbe(isReachable: true)

    /// The query failed with this error.
    public static func failure(_ error: SentinelAPIError) -> GatewayProbe {
        GatewayProbe(isReachable: false, error: error)
    }
}

/// Tracks how a series of query results changes the gateway state.
///
/// The type is `Codable` so the app can remember it and keep counting after a
/// restart. Feed it one `GatewayProbe` per query and look at `state` and
/// `stateDidChange`: the app shows its one-time hint when the state changes.
public struct GatewayReachability: Codable, Equatable {
    /// Failures in a row that turn the state into 网关连不上.
    public static let defaultFailureThreshold = 3

    /// `network` failures in a row, reset by any success.
    public private(set) var consecutiveFailureCount: Int
    public private(set) var state: GatewayConnectionState
    public let failureThreshold: Int

    /// `true` when the last probe changed the state.
    ///
    /// Set by `record(_:)`; a fresh value is `false`, so a restored state does
    /// not warn again.
    public private(set) var stateDidChange: Bool

    public init(failureThreshold: Int = GatewayReachability.defaultFailureThreshold) {
        // A threshold below one would warn on every query.
        self.failureThreshold = max(1, failureThreshold)
        self.consecutiveFailureCount = 0
        self.state = .connected
        self.stateDidChange = false
    }

    /// Builds a value with a state that was already reached, for a caller that
    /// restores the state from a file instead of folding probes in.
    public init(
        consecutiveFailureCount: Int,
        state: GatewayConnectionState,
        failureThreshold: Int = GatewayReachability.defaultFailureThreshold
    ) {
        self.failureThreshold = max(1, failureThreshold)
        self.consecutiveFailureCount = max(0, consecutiveFailureCount)
        self.state = state
        self.stateDidChange = false
    }

    /// `true` while the app treats the gateway as unreachable.
    public var isGatewayUnreachable: Bool { state == .reconnecting }

    /// `true` when the API Key was rejected.
    public var isAPIKeyRejected: Bool { state == .apiKeyRejected }

    /// `true` when the gateway presented a changed certificate.
    public var isCertificateChanged: Bool { state == .certificateChanged }

    /// Folds one query result in. Returns `true` when the state changed.
    @discardableResult
    public mutating func record(_ probe: GatewayProbe) -> Bool {
        let previous = state

        if probe.isReachable {
            // A success clears the counter, whichever state came before.
            consecutiveFailureCount = 0
            state = .connected
        } else {
            switch probe.error {
            case .unauthorized:
                // The gateway answered with 401/403: reachable, key wrong.
                // The network counter belongs to another problem, so it is cleared.
                consecutiveFailureCount = 0
                state = .apiKeyRejected
            case .network:
                consecutiveFailureCount += 1
                if consecutiveFailureCount >= failureThreshold {
                    state = .reconnecting
                }
            default:
                // Any other error is neither a network failure nor a key problem.
                break
            }
        }

        stateDidChange = state != previous
        return stateDidChange
    }

    /// Folds a thrown query error in.
    @discardableResult
    public mutating func record(error: Error) -> Bool {
        if let apiError = error as? SentinelAPIError {
            return record(GatewayProbe.failure(apiError))
        }
        // Anything that is not a `SentinelAPIError` came from the transport.
        return record(GatewayProbe.failure(.network(URLError(.unknown))))
    }

    /// Folds a certificate change in. Returns `true` when the state changed.
    ///
    /// The failure counter of the network is kept: the gateway itself is
    /// reachable, its certificate is not the pinned one.
    @discardableResult
    public mutating func recordCertificateChanged() -> Bool {
        let previous = state
        state = .certificateChanged
        stateDidChange = state != previous
        return stateDidChange
    }

    /// Forgets the counter and goes back to 已连接, for a settings change.
    public mutating func reset() {
        consecutiveFailureCount = 0
        state = .connected
        stateDidChange = false
    }
}

extension GatewayReachability {
    private enum CodingKeys: String, CodingKey {
        case consecutiveFailureCount
        case state
        case failureThreshold
    }

    /// Tolerant decoding: a stored value from an older version still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedThreshold = (try? container.decode(Int.self, forKey: .failureThreshold))
            ?? Self.defaultFailureThreshold
        failureThreshold = max(1, storedThreshold)
        consecutiveFailureCount = (try? container.decode(Int.self, forKey: .consecutiveFailureCount)) ?? 0
        state = (try? container.decode(GatewayConnectionState.self, forKey: .state)) ?? .connected
        stateDidChange = false
    }
}
