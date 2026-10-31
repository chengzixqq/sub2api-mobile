import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

/// Always answers 304 with an ETag and no body; no shared mutable state, so parallel tests are safe.
private final class NotModifiedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 304, httpVersion: "HTTP/1.1", headerFields: ["ETag": "\"v1\""]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func urlSessionTransportPassesThroughNotModifiedWithEmptyBody() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NotModifiedProtocol.self]
    let transport = URLSessionTransport(configuration: configuration)
    let response = try await transport.data(for: URLRequest(url: URL(string: "https://cache.example.invalid/api/v1/admin/me")!))
    #expect(response.statusCode == 304); #expect(response.data.isEmpty)
    #expect(response.headers["etag"] == "\"v1\""); #expect(response.headers.keys.allSatisfy { $0 == $0.lowercased() })
}
