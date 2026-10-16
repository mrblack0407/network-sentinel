import Foundation

/// Reads the UniFi gateway with an API Key only.
///
/// Every request carries the `X-API-Key` header. The gateway uses a self-signed
/// certificate, so the caller injects the `URLSession` (certificate handling is
/// a later task; tests inject a stub session).
///
/// The API Key is never logged: the client has no logging, the errors carry no
/// request data, and `description` / `debugDescription` redact the key.
public struct UniFiGatewayClient {
    /// Gateway base address, for example `https://192.168.8.254`.
    public let baseURL: URL
    /// The API Key, sent as the `X-API-Key` header. Never printed.
    private let apiKey: String
    private let session: URLSession
    /// Safety limit for the log pagination loop.
    private let maxLogPages: Int
    /// Page size used for the system log endpoint.
    public static let logPageSize = 500
    /// Default safety limit for the log pagination loop.
    public static let defaultMaxLogPages = 50

    public init(
        baseURL: URL,
        apiKey: String,
        session: URLSession = .shared,
        maxLogPages: Int = UniFiGatewayClient.defaultMaxLogPages
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.maxLogPages = maxLogPages
    }

    // MARK: - Endpoints

    /// Reads the sites and returns their internal references for the other URLs.
    public func fetchSites() async throws -> [Site] {
        let data = try await get(path: "/proxy/network/integration/v1/sites")
        return try Self.decode(SiteListResponse.self, from: data).data
    }

    /// Reads the gateway device: name, model, firmware version and WAN state.
    public func fetchGatewayStatus(site: String) async throws -> GatewayStatus {
        let path = "/proxy/network/api/s/\(Self.pathComponent(site))/stat/device"
        let data = try await get(path: path)
        let response = try Self.decode(StatDeviceResponse.self, from: data)

        if let rc = response.meta?.rc?.lowercased(), rc != "ok" {
            throw SentinelAPIError.gatewayError(response.meta?.msg ?? "unknown error")
        }
        guard let device = response.data.first(where: { $0.isGateway }) else {
            throw SentinelAPIError.gatewayDeviceNotFound
        }
        return device.status
    }

    /// Reads every system log entry between two dates.
    ///
    /// Paging is automatic: pages are requested with `pageSize` 500 until the
    /// last page. A safety limit stops a gateway that never reports a last page.
    public func fetchSystemLog(site: String, from: Date, to: Date) async throws -> [SystemLogEntry] {
        let path = "/proxy/network/v2/api/site/\(Self.pathComponent(site))/system-log/all"
        let timestampFrom = Self.milliseconds(from: from)
        let timestampTo = Self.milliseconds(from: to)

        var entries: [SystemLogEntry] = []
        var pageNumber = 0

        while true {
            guard pageNumber < maxLogPages else {
                throw SentinelAPIError.tooManyPages(maxLogPages)
            }

            let body = SystemLogPageRequest(
                timestampFrom: timestampFrom,
                timestampTo: timestampTo,
                pageNumber: pageNumber,
                pageSize: Self.logPageSize
            )
            let data = try await post(path: path, body: try JSONEncoder().encode(body))
            let page = try Self.decode(SystemLogPageResponse.self, from: data)

            entries.append(contentsOf: page.data)

            let hasNextPage = pageNumber + 1 < page.totalPageCount
            pageNumber += 1
            if !hasNextPage || page.data.isEmpty { break }
        }

        return entries
    }

    // MARK: - Requests

    private func get(path: String) async throws -> Data {
        try await send(makeRequest(path: path, method: "GET", body: nil))
    }

    private func post(path: String, body: Data) async throws -> Data {
        try await send(makeRequest(path: path, method: "POST", body: body))
    }

    private func makeRequest(path: String, method: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SentinelAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw SentinelAPIError.network(error)
        } catch {
            throw SentinelAPIError.network(URLError(.unknown))
        }

        guard let http = response as? HTTPURLResponse else {
            throw SentinelAPIError.invalidResponse(statusCode: -1)
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw SentinelAPIError.unauthorized(statusCode: http.statusCode)
        case 404:
            throw SentinelAPIError.notFound
        default:
            throw SentinelAPIError.invalidResponse(statusCode: http.statusCode)
        }
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SentinelAPIError.decodingFailed(safeDescription(of: error))
        }
    }

    /// Summarizes a decoding failure without copying the response body.
    private static func safeDescription(of error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return "unexpected response format"
        }

        switch decodingError {
        case .keyNotFound(let key, _):
            return "missing field \(key.stringValue)"
        case .typeMismatch(_, let context):
            return "wrong type at \(codingPath(context.codingPath))"
        case .valueNotFound(_, let context):
            return "missing value at \(codingPath(context.codingPath))"
        case .dataCorrupted(let context):
            return "corrupted data at \(codingPath(context.codingPath))"
        @unknown default:
            return "unexpected response format"
        }
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        path.isEmpty ? "root" : path.map { $0.stringValue }.joined(separator: ".")
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

extension UniFiGatewayClient: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacts the API Key so the client can never leak it into a log.
    public var description: String {
        "UniFiGatewayClient(baseURL: \(baseURL.absoluteString), apiKey: <redacted>)"
    }

    public var debugDescription: String {
        description
    }
}

/// Request body of the system log endpoint.
struct SystemLogPageRequest: Codable, Equatable {
    let timestampFrom: Int64
    let timestampTo: Int64
    let pageNumber: Int
    let pageSize: Int
}

/// One page of the system log endpoint.
struct SystemLogPageResponse: Decodable {
    let pageNumber: Int
    let totalElementCount: Int
    let totalPageCount: Int
    let data: [SystemLogEntry]

    private enum CodingKeys: String, CodingKey {
        case pageNumber = "page_number"
        case totalElementCount = "total_element_count"
        case totalPageCount = "total_page_count"
        case data
    }
}
