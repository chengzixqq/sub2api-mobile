import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One upstream try of a request (40 §7.2). Failed tries come from `upstream_errors` events and the billed one from the usage
/// record (code 200, start estimated as created_at − duration); tries recorded before the deployment have no `started_at` /
/// `duration_ms`. The message is redacted like every ops message; fields are read one by one, so a stray type is nil.
public struct RequestAttempt: Decodable, Identifiable, Sendable, Equatable {
    public enum Source: String, Sendable { case upstreamError = "upstream_error", usage, unknown }
    /// `partial`: billed, but the request failed in the end.
    public enum Outcome: String, Sendable { case failed, success, partial, unknown }
    /// 1-based; a missing one is the position in the chain.
    public fileprivate(set) var index: Int
    public let source: Source
    public let outcome: Outcome
    public let platform: String?
    public let accountID: Int?
    public let accountName: String?
    public let proxyID: Int?
    public let proxyName: String?
    public let upstreamStatusCode: Int?
    public let upstreamRequestID: String?
    public let kind: String?
    public let stage: String?
    public let message: String?
    public let startedAt: Date?
    public let endedAt: Date?
    public let durationMs: Int?
    public let firstTokenMs: Int?
    public let errorLogID: Int?
    public let usageID: Int?
    public var id: Int { index }

    enum CodingKeys: String, CodingKey {
        case index, source, outcome, platform, kind, stage, message
        case accountID = "account_id", accountName = "account_name", proxyID = "proxy_id", proxyName = "proxy_name"
        case upstreamStatusCode = "upstream_status_code", upstreamRequestID = "upstream_request_id", startedAt = "started_at", endedAt = "ended_at"
        case durationMs = "duration_ms", firstTokenMs = "first_token_ms", errorLogID = "error_log_id", usageID = "usage_id"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys) -> Int? { try? c.decodeIfPresent(Int.self, forKey: key) }
        func text(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0.isEmpty ? nil : $0 } }
        index = number(.index) ?? 0
        source = text(.source).flatMap(Source.init(rawValue:)) ?? .unknown
        outcome = text(.outcome).flatMap(Outcome.init(rawValue:)) ?? .unknown
        platform = text(.platform); accountID = number(.accountID); accountName = text(.accountName)
        proxyID = number(.proxyID); proxyName = text(.proxyName); upstreamStatusCode = number(.upstreamStatusCode)
        upstreamRequestID = text(.upstreamRequestID); kind = text(.kind); stage = text(.stage)
        message = text(.message).map(RequestLogPresentation.safeMessage)
        startedAt = try c.optionalTimestamp(.startedAt); endedAt = try c.optionalTimestamp(.endedAt)
        durationMs = number(.durationMs); firstTokenMs = number(.firstTokenMs); errorLogID = number(.errorLogID); usageID = number(.usageID)
    }
}

/// The merged retry chain of `GET admin/ops/requests/:id/attempts`, oldest first.
public struct RequestAttempts: Decodable, Sendable, Equatable {
    public let requestID: String?
    public let clientRequestID: String?
    /// The latest failure's code, else the recovered row's, else 200.
    public let clientStatusCode: Int?
    public let attempts: [RequestAttempt]
    public let errorLogIDs: [Int]
    public let droppedEarlierAttempts: Int

    enum CodingKeys: String, CodingKey {
        case attempts
        case requestID = "request_id", clientRequestID = "client_request_id", clientStatusCode = "client_status_code"
        case errorLogIDs = "error_log_ids", droppedEarlierAttempts = "dropped_earlier_attempts"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0.isEmpty ? nil : $0 } }
        requestID = text(.requestID); clientRequestID = text(.clientRequestID)
        clientStatusCode = try? c.decodeIfPresent(Int.self, forKey: .clientStatusCode)
        let listed = (try? c.decodeIfPresent(LossyList<RequestAttempt>.self, forKey: .attempts))?.items ?? []
        attempts = listed.enumerated().map { offset, attempt in
            guard attempt.index <= 0 else { return attempt }
            var numbered = attempt
            numbered.index = offset + 1
            return numbered
        }
        errorLogIDs = (try? c.decodeIfPresent(LossyList<Int>.self, forKey: .errorLogIDs))?.items ?? []
        droppedEarlierAttempts = max(0, (try? c.decodeIfPresent(Int.self, forKey: .droppedEarlierAttempts)) ?? 0)
    }
}

/// 409 OPS_REQUEST_AMBIGUOUS (40 §7.2, only when looked up by `request_id`): `metadata` lists up to five client_request_ids,
/// newest first, each with the created_at of its newest ops row. The caller asks again once with `closest(to:)`.
public struct AmbiguousRequest: Sendable, Equatable {
    public struct Candidate: Sendable, Equatable {
        public let clientRequestID: String
        public let latestAt: Date?
    }
    public let candidates: [Candidate]

    public init?(error: APIError) {
        guard error.statusCode == 409, error.reason == "OPS_REQUEST_AMBIGUOUS" else { return nil }
        self.init(metadata: error.metadata)
    }
    /// Both lists are comma separated in the same order; when their lengths differ no time is trusted.
    public init(metadata: [String: String]) {
        let ids = Self.items(metadata["client_request_ids"]), times = Self.items(metadata["client_request_id_times"])
        let aligned = ids.count == times.count
        candidates = ids.indices.compactMap { index in
            guard !ids[index].isEmpty else { return nil }
            return Candidate(clientRequestID: ids[index], latestAt: aligned ? ServerTime.parseTimestamp(times[index]) : nil)
        }
    }
    /// The candidate whose time is nearest the row's `created_at`; a tie keeps the newer one, and without times the newest.
    public func closest(to createdAt: Date?) -> String? {
        guard let createdAt else { return candidates.first?.clientRequestID }
        let timed = candidates.compactMap { candidate in candidate.latestAt.map { (candidate.clientRequestID, abs($0.timeIntervalSince(createdAt))) } }
        return timed.min { $0.1 < $1.1 }?.0 ?? candidates.first?.clientRequestID
    }
    private static func items(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// How a failed chain read continues (40 §7.2, §7.5).
public enum AttemptsFailure: Sendable, Equatable {
    /// Ask again once with `closest(to:)`; never resend the same id.
    case ambiguous(AmbiguousRequest)
    /// Nothing to read for this id (not found, an id the route cannot take, a plain-text 404): the failed looks read
    /// `upstream_errors`, the success hides the section.
    case useFallback
    case opsDisabled
    /// Transport, server or permission failures.
    case failed

    public init(_ error: any Error) {
        guard let error = error as? APIError else { self = .failed; return }
        guard error != .unqueryableRequestID else { self = .useFallback; return }
        switch (error.statusCode, error.reason) {
        case (404?, "OPS_DISABLED"?): self = .opsDisabled
        case (409?, "OPS_REQUEST_AMBIGUOUS"?):
            let ambiguous = AmbiguousRequest(metadata: error.metadata)
            self = ambiguous.candidates.isEmpty ? .useFallback : .ambiguous(ambiguous)
        case (404?, _), (400?, "INVALID_REQUEST_ID"?), (400?, "INVALID_AROUND"?): self = .useFallback
        default: self = .failed
        }
    }
}

public enum RequestAttemptsLookup {
    /// The backend's bound on the path parameter (ops_request_attempts.go).
    public static let maximumIDBytes = 256
    /// Whether the id can be the one path segment the route matches: 1–256 bytes of UTF-8 without NUL, not blank, not “.” or
    /// “..”, and without “/” (gin matches the decoded path, so even %2F misses, and its plain-text 404 would read as an old
    /// site). URLComponents percent-encodes the rest (“?”, “#”, “%”, spaces).
    public static func isQueryable(_ id: String) -> Bool {
        let bytes = id.utf8
        guard (1...maximumIDBytes).contains(bytes.count), !bytes.contains(0), !bytes.contains(UInt8(ascii: "/")) else { return false }
        return id != "." && id != ".." && !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension APIError {
    /// Raised before sending for an id `RequestAttemptsLookup` refuses; `AttemptsFailure` reads it as `.useFallback`.
    public static let unqueryableRequestID = APIError(kind: .validation, message: "这个请求 ID 不能用来查询重试链。")
}

extension APIClient {
    /// R19: the only retry-chain read (40 §7.2; `ops.request_attempts` with ops monitoring on). `around` is the row's
    /// created_at, sent in UTC Z, and narrows the lookup to ±1 hour. A 409 is thrown for `AmbiguousRequest`.
    public func requestAttempts(id: String, around: Date?) async throws -> RequestAttempts {
        guard RequestAttemptsLookup.isQueryable(id) else { throw APIError.unqueryableRequestID }
        let query = around.map { [URLQueryItem(name: "around", value: ServerTime.utcTimestamp($0))] } ?? []
        return try await request("admin/ops/requests/\(id)/attempts", query: query, timeout: RequestTimeout.read)
    }
}
