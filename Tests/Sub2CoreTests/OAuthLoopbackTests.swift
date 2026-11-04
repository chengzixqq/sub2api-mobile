import Foundation
import Testing
@testable import Sub2Core

private func authURL(redirect: String?) -> URL {
    var components = URLComponents(string: "https://auth.example.invalid/oauth/authorize")!
    components.queryItems = [URLQueryItem(name: "client_id", value: "fixture")] + (redirect.map { [URLQueryItem(name: "redirect_uri", value: $0)] } ?? [])
    return components.url!
}
private let openAIEndpoint = OAuthLoopbackEndpoint(host: "localhost", port: 1455, path: "/auth/callback")
private func head(_ text: String) -> Data { Data(text.utf8) }

@Test func endpointComesFromRedirectURI() throws {
    let openAI = try #require(OAuthLoopback.endpoint(authURL: authURL(redirect: "http://localhost:1455/auth/callback")))
    #expect(openAI == openAIEndpoint && openAI.address == "localhost:1455")
    #expect(OAuthLoopback.endpoint(authURL: authURL(redirect: "http://localhost:8085/callback"))?.address == "localhost:8085")
    #expect(OAuthLoopback.endpoint(authURL: authURL(redirect: "http://127.0.0.1:56121/callback"))?.address == "127.0.0.1:56121")
    #expect(OAuthLoopback.endpoint(authURL: authURL(redirect: "http://[::1]:1455/auth/callback"))?.port == 1455)
    for refused in ["https://platform.claude.com/oauth/code/callback", "https://codeassist.google.com/authcode", "https://localhost:1455/x",
                    "http://example.com:1455/x", "http://localhost/callback", "http://localhost:0/callback", "http://localhost:70000/callback",
                    "http://localhost:1455", "not a url"] {
        #expect(OAuthLoopback.endpoint(authURL: authURL(redirect: refused)) == nil, "\(refused)")
    }
    #expect(OAuthLoopback.endpoint(authURL: authURL(redirect: nil)) == nil)
}

@Test func parseAcceptsOnlyTheCallbackGet() {
    let request = "GET /auth/callback?code=a%2Fb&state=s HTTP/1.1\r\nHost: localhost:1455\r\n\r\n"
    #expect(OAuthLoopback.parse(head: head(request), endpoint: openAIEndpoint)
        == .callback(URL(string: "http://localhost:1455/auth/callback?code=a%2Fb&state=s")!))
    #expect(OAuthLoopback.parse(head: head("GET /auth/callback?code=a HTTP/1.1\r\nHost: localhost"), endpoint: openAIEndpoint) == .incomplete)
    for refused in ["POST /auth/callback?code=a HTTP/1.1\r\n\r\n", "GET /favicon.ico HTTP/1.1\r\n\r\n",
                    "GET /auth/callbackX?code=a HTTP/1.1\r\n\r\n", "GET /auth/callback?code=a SPDY/3\r\n\r\n"] {
        #expect(OAuthLoopback.parse(head: head(refused), endpoint: openAIEndpoint) == .rejected, "\(refused)")
    }
    #expect(OAuthLoopback.parse(head: Data([0x47, 0x45, 0x54, 0x20, 0xFF, 0xFE, 0x0D, 0x0A, 0x0D, 0x0A]), endpoint: openAIEndpoint) == .rejected)
    let endless = head("GET /auth/callback?code=" + String(repeating: "a", count: OAuthLoopback.maxHeadBytes))
    #expect(OAuthLoopback.parse(head: endless, endpoint: openAIEndpoint) == .rejected)
    #expect(OAuthLoopback.parse(head: head("GET /auth/callback?error=access_denied&state=s HTTP/1.1\r\n\r\n"), endpoint: openAIEndpoint)
        == .callback(URL(string: "http://localhost:1455/auth/callback?error=access_denied&state=s")!))
    #expect(OAuthLoopback.maxHeadBytes == 8_192)
}

@Test func responsesNeverEchoTheRequest() throws {
    let callback = OAuthLoopback.Head.callback(URL(string: "http://localhost:1455/auth/callback?code=secret-code&state=secret-state")!)
    let ok = String(decoding: OAuthLoopback.response(for: callback), as: UTF8.self)
    #expect(ok.hasPrefix("HTTP/1.1 200 "))
    for header in ["Content-Type: text/html; charset=utf-8", "Cache-Control: no-store", "Connection: close"] {
        #expect(ok.contains(header + "\r\n"), "\(header)")
    }
    let parts = ok.components(separatedBy: "\r\n\r\n")
    let body = try #require(parts.last)
    #expect(body.contains("已交给 App"))
    #expect(ok.contains("Content-Length: \(body.utf8.count)\r\n"))
    let refused = String(decoding: OAuthLoopback.response(for: .rejected), as: UTF8.self)
    #expect(refused.hasPrefix("HTTP/1.1 404 "))
    for reply in [ok, refused] {
        #expect(!reply.contains("secret-code") && !reply.contains("secret-state"))
    }
}
