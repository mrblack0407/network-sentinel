import Foundation

/// Everything that can go wrong while talking to the UniFi gateway.
///
/// The cases are kept apart on purpose: the app shows a different hint for a
/// gateway that cannot be reached, a bad API Key, a missing endpoint, an
/// unreadable response and any other HTTP status.
///
/// No case ever carries the API Key or the request headers.
public enum SentinelAPIError: Error, Equatable {
    /// The gateway could not be reached at all (offline, wrong address, TLS).
    case network(URLError)
    /// HTTP 401 or 403: the API Key is wrong or has no permission.
    case unauthorized(statusCode: Int)
    /// HTTP 404: the endpoint does not exist on this firmware.
    case notFound
    /// Any other unexpected HTTP status.
    case invalidResponse(statusCode: Int)
    /// The response body could not be decoded.
    case decodingFailed(String)
    /// `stat/device` returned no `udm` / `ugw` / `uxg` device.
    case gatewayDeviceNotFound
    /// The response carried `meta.rc == "error"`.
    case gatewayError(String)
    /// The log endpoint kept returning pages past the safety limit.
    case tooManyPages(Int)
    /// The configured gateway address could not be turned into a URL.
    case invalidURL
    /// The gateway presented a certificate that does not match the pinned one.
    ///
    /// A separate case on purpose: the app asks for a new 「测试连接」 instead
    /// of showing a generic network failure.
    case certificateChanged
}

extension SentinelAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network:
            return T(.errorNetwork)
        case .unauthorized(let statusCode):
            return T(.errorUnauthorized, statusCode)
        case .notFound:
            return T(.errorNotFound)
        case .invalidResponse(let statusCode):
            return T(.errorInvalidResponse, statusCode)
        case .decodingFailed(let detail):
            return T(.errorDecodingFailed, detail)
        case .gatewayDeviceNotFound:
            return T(.errorGatewayDeviceNotFound)
        case .gatewayError(let message):
            return T(.errorGatewayError, message)
        case .tooManyPages(let limit):
            return T(.errorTooManyPages, limit)
        case .invalidURL:
            return T(.errorInvalidURL)
        case .certificateChanged:
            return T(.errorCertificateChanged)
        }
    }

    public var failureReason: String? {
        switch self {
        case .network(let error):
            return error.localizedDescription
        default:
            return nil
        }
    }
}
