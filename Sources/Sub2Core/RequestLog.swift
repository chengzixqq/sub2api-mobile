import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(os)
import os
#endif

/// 00 §3.4 rule 3: one line per attempt with the method, the path template, status, reason and X-Request-ID. Query strings,
/// headers, bodies and metadata never reach it; the reason and request ID come from the server and are filtered first.
enum RequestLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "api")
    #endif
    private static let apiPrefix = "/api/v1/"
    private static let maxFieldBytes = 64

    /// Receives each line; `failed` is true for a transport failure or a status outside 200–399.
    typealias Sink = @Sendable (_ line: String, _ failed: Bool) -> Void
    /// The unified log: failures as errors, the rest as debug.
    static let system: Sink = { line, failed in
        #if canImport(os)
        if failed { logger.error("\(line, privacy: .public)") } else { logger.debug("\(line, privacy: .public)") }
        #endif
    }

    /// Called once per attempt; `response` is nil when the attempt failed in transport.
    static func record(_ request: URLRequest, response: HTTPResponse?, to sink: Sink) {
        let failed = response.map { !(200..<400).contains($0.statusCode) } ?? true
        sink(line(for: request, response: response), failed)
    }

    /// The reason is read only from an error body; the request ID is the server's, else the one this request sent.
    static func line(for request: URLRequest, response: HTTPResponse?) -> String {
        let failed = response.map { !(200..<300).contains($0.statusCode) && $0.statusCode != 304 } ?? false
        let reason = failed ? response.flatMap { ErrorEnvelope.decode($0.data)?.marker } : nil
        let requestID = response?.header("X-Request-ID") ?? request.value(forHTTPHeaderField: "X-Request-ID")
        return line(method: request.httpMethod ?? "GET", path: request.url?.path ?? "", status: response?.statusCode,
                    reason: reason, requestID: requestID)
    }

    static func line(method: String, path: String, status: Int?, reason: String?, requestID: String?) -> String {
        let fields = [method, pathTemplate(path), status.map(String.init), kept(reason, isAllowed: isCodeByte),
                      kept(requestID, isAllowed: isVisibleASCII)]
        return fields.map { $0 ?? "-" }.joined(separator: " ")
    }

    /// Numeric and UUID segments, the hex id after `sessions` and the request ID after `ops/requests` become `:id`; the query
    /// is dropped.
    static func pathTemplate(_ path: String) -> String {
        var bare = path.prefix { $0 != "?" }
        if bare.hasPrefix(apiPrefix) { bare = bare.dropFirst(apiPrefix.count) }
        let segments = bare.split(separator: "/", omittingEmptySubsequences: false)
        return segments.indices.map { index in
            let afterSessions = index > 0 && segments[index - 1] == "sessions"
            let afterOpsRequests = index > 1 && segments[index - 2] == "ops" && segments[index - 1] == "requests"
            return afterSessions || afterOpsRequests || isIdentifier(segments[index]) ? ":id" : String(segments[index])
        }.joined(separator: "/")
    }

    private static func isIdentifier(_ segment: Substring) -> Bool {
        (!segment.isEmpty && segment.utf8.allSatisfy { (0x30...0x39).contains($0) }) || UUID(uuidString: String(segment)) != nil
    }
    /// Reasons are stable codes such as `IDEMPOTENCY_IN_PROGRESS`; anything else may be text and is dropped.
    private static func isCodeByte(_ byte: UInt8) -> Bool {
        (0x41...0x5A).contains(byte) || (0x30...0x39).contains(byte) || byte == 0x5F
    }
    private static func isVisibleASCII(_ byte: UInt8) -> Bool { (0x21...0x7E).contains(byte) }
    private static func kept(_ value: String?, isAllowed: (UInt8) -> Bool) -> String? {
        guard let value, (1...maxFieldBytes).contains(value.utf8.count), value.utf8.allSatisfy(isAllowed) else { return nil }
        return value
    }
}
