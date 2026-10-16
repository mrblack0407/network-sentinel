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
            return "无法连接到 UniFi 网关，请检查网关地址和网络。"
        case .unauthorized(let statusCode):
            return "API Key 无效或没有权限（HTTP \(statusCode)）。"
        case .notFound:
            return "网关没有这个接口（HTTP 404），可能固件版本不支持。"
        case .invalidResponse(let statusCode):
            return "网关返回了意外的状态码（HTTP \(statusCode)）。"
        case .decodingFailed(let detail):
            return "无法解析网关返回的内容（\(detail)）。"
        case .gatewayDeviceNotFound:
            return "网关状态里没有找到 UniFi 网关设备。"
        case .gatewayError(let message):
            return "网关返回错误：\(message)"
        case .tooManyPages(let limit):
            return "日志页数超过安全上限（\(limit) 页），已停止读取。"
        case .invalidURL:
            return "网关地址无效。"
        case .certificateChanged:
            return "UniFi 网关的证书变了，请在连接设置里重新测试连接。"
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
