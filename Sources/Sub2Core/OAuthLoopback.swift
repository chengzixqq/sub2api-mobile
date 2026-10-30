import Foundation

/// The callback address a link sends the browser back to (20 §7.4-6), read from its `redirect_uri` rather than a fixed table: Gemini
/// AI Studio also lands on localhost:1455, and Grok's address can be configured on the server.
public struct OAuthLoopbackEndpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt16
    public let path: String
    public init(host: String, port: UInt16, path: String) { self.host = host; self.port = port; self.path = path }
    /// “localhost:1455”, as the browser step names it.
    public var address: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }
}

/// The App's own callback listener, without the network: which request is the callback, and the page it gets back. The page never
/// repeats anything from the request.
public enum OAuthLoopback {
    public static let maxHeadBytes = 8_192
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]
    private static let headEnd = Data("\r\n\r\n".utf8)
    private static let page = #"<!doctype html><html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">"#
        + "<title>已交给 App</title></head><body><p>已交给 App，可以回到 App 继续。</p></body></html>"

    public enum Head: Sendable, Equatable {
        /// The blank line has not arrived yet.
        case incomplete
        /// The whole callback address, its query exactly as sent; a refusal (`error=`) too, for OAuthCallback to read.
        case callback(URL)
        case rejected
    }

    /// Plain http on a loopback host with a port and a path; nil for a code shown on the provider's page.
    public static func endpoint(authURL: URL) -> OAuthLoopbackEndpoint? {
        guard let raw = URLComponents(url: authURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "redirect_uri" })?.value,
              let redirect = URLComponents(string: raw), redirect.scheme?.lowercased() == "http",
              let host = redirect.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")), loopbackHosts.contains(host),
              let port = redirect.port, (1...65_535).contains(port), !redirect.path.isEmpty else { return nil }
        return OAuthLoopbackEndpoint(host: host, port: UInt16(port), path: redirect.path)
    }

    /// One HTTP/1.x request head: only `GET {path}[?query]` is the callback.
    public static func parse(head data: Data, endpoint: OAuthLoopbackEndpoint) -> Head {
        guard let end = data.range(of: headEnd) else { return data.count >= maxHeadBytes ? .rejected : .incomplete }
        guard end.lowerBound <= maxHeadBytes, let text = String(data: data[..<end.lowerBound], encoding: .utf8) else { return .rejected }
        let parts = (text.split(separator: "\r\n", omittingEmptySubsequences: false).first ?? "").split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[2].hasPrefix("HTTP/1.") else { return .rejected }
        let target = String(parts[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard path == endpoint.path, let url = URL(string: "http://\(endpoint.address)\(target)") else { return .rejected }
        return .callback(url)
    }

    /// A fixed page for the callback and a bare 404 for anything else; neither is cached, and the connection closes.
    public static func response(for head: Head) -> Data {
        let (status, body): (String, String) = if case .callback = head { ("200 OK", page) } else { ("404 Not Found", "") }
        let bytes = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + bytes
    }
}
