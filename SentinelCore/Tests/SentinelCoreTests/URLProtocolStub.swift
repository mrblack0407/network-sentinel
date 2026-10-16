import Foundation

/// A `URLProtocol` stub so the client tests never touch the network.
final class URLProtocolStub: URLProtocol {
    /// A request the client sent, with the body read out of the body stream.
    struct RecordedRequest {
        let request: URLRequest
        let body: Data?
    }

    /// Answers a request, or fails it with an error.
    static var handler: ((URLRequest, Data?) -> Result<(HTTPURLResponse, Data), Error>)?
    /// Every request the client sent, in order.
    private(set) static var recorded: [RecordedRequest] = []

    static func reset() {
        handler = nil
        recorded = []
    }

    /// A session that routes every request into this stub.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    static func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.readBody(from: request.httpBodyStream)
        Self.recorded.append(RecordedRequest(request: request, body: body))

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        switch handler(request, body) {
        case .success(let (response, data)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// URLSession hands the body over as a stream, not as `httpBody`.
    private static func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4_096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }

        return data.isEmpty ? nil : data
    }
}
