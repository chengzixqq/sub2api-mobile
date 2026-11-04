import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 00 §2.4 request classes: which requests retry on their own and which may be resent after a token refresh.
public enum RequestClass: Sendable, Hashable {
    case read, readBatch, keyedWrite(key: UUID), unkeyedWrite, auth

    public static func inferred(method: String) -> RequestClass { method.uppercased() == "GET" ? .read : .unkeyedWrite }
    /// GET and the query-style batch POSTs listed in 00 §2.4.
    public var isRead: Bool {
        switch self {
        case .read, .readBatch: true
        case .keyedWrite, .unkeyedWrite, .auth: false
        }
    }
    public var defaultTimeout: TimeInterval {
        switch self {
        case .read, .readBatch: RequestTimeout.read
        case .keyedWrite: RequestTimeout.keyedWrite
        case .unkeyedWrite: RequestTimeout.unkeyedWrite
        case .auth: RequestTimeout.authentication
        }
    }
    /// Lowercased operation UUID; X-Request-ID carries the same value.
    public var idempotencyKey: String? {
        guard case .keyedWrite(let key) = self else { return nil }
        return key.uuidString.lowercased()
    }
    public var retriesAutomatically: Bool { isRead }
    /// Sign-in, second factor, refresh and logout never refresh a token to resend themselves.
    public var resendsAfterTokenRefresh: Bool { self != .auth }
    /// 1 second, then 3 seconds, each plus at most 500 ms of jitter; nil once two retries were spent or when this class does not retry.
    public func automaticRetryDelay(after failure: RequestFailure, attempt: Int, jitter: Duration) -> Duration? {
        guard retriesAutomatically, RequestPolicy.readRetryDelays.indices.contains(attempt) else { return nil }
        if case .status(let status, let marker) = failure, !RequestPolicy.isRetryableStatus(status, marker: marker) { return nil }
        return RequestPolicy.readRetryDelays[attempt] + min(max(jitter, .zero), RequestPolicy.maxJitter)
    }
}

/// What a retry decision looks at.
public enum RequestFailure: Sendable, Equatable {
    /// A transient transport error (timeout, lost connection, DNS).
    case network
    case status(Int, marker: String?)
    /// nil for a 2xx reply.
    public init?(response: HTTPResponse) {
        guard !(200..<300).contains(response.statusCode) else { return nil }
        self = .status(response.statusCode, marker: ErrorEnvelope.decode(response.data)?.marker)
    }
    /// nil unless the error is one of the transient transport errors of 00 §2.4.
    public init?(error: any Error) {
        guard RequestPolicy.isRetryableNetworkError(error) else { return nil }
        self = .network
    }
}

/// 00 §2.3 client timeouts in seconds (R07, U54).
public enum RequestTimeout {
    /// Public settings, admin/me, compliance and session lists.
    public static let probe: TimeInterval = 15
    /// Sign-in, second factor, token refresh and logout.
    public static let authentication: TimeInterval = 20
    /// Ordinary lists, details and batch read POSTs.
    public static let read: TimeInterval = 20
    public static let home: TimeInterval = 15
    /// dashboard/trend, snapshot-v2, ops/dashboard/*, usage/stats and the other statistics aggregates.
    public static let aggregate: TimeInterval = 45
    public static let dashboardStats: TimeInterval = 90
    public static let unkeyedWrite: TimeInterval = 30
    /// Server execution limit plus 5 seconds: money writes and ordinary edits.
    public static let keyedWrite: TimeInterval = 35
    /// bulk-update and single-account refresh.
    public static let keyedBulk: TimeInterval = 65
    public static let batchRefresh: TimeInterval = 125
}

/// Injectable time for token expiry, read-retry waits and jitter.
public struct RequestClock: Sendable {
    public let now: @Sendable () -> Date
    public let sleep: @Sendable (Duration) async throws -> Void
    public let jitter: @Sendable () -> Duration
    public init(now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                jitter: @escaping @Sendable () -> Duration = { .milliseconds(Int.random(in: 0...500)) }) {
        self.now = now; self.sleep = sleep; self.jitter = jitter
    }
    public static let live = RequestClock()
}

/// A decoded value with the reply's status and lowercased header names (00 §9.1).
public struct APIResponse<Value: Sendable>: Sendable {
    public let value: Value
    public let status: Int
    public let headers: [String: String]
    public init(value: Value, status: Int, headers: [String: String]) {
        self.value = value; self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }
    public func header(_ name: String) -> String? { headers[name.lowercased()] }
    public var requestID: String? { header("X-Request-ID") }
    public func map<U: Sendable>(_ transform: (Value) throws -> U) rethrows -> APIResponse<U> {
        APIResponse<U>(value: try transform(value), status: status, headers: headers)
    }
}

/// 00 §4.1: the server accepts 1–1000 and silently falls back to 20 for anything else.
public enum PageSize {
    public static let standard = 20
    public static let maximum = 1_000
    public static func clamped(_ requested: Int) -> Int { min(max(requested, 1), maximum) }
}

public enum RefreshVerdict: Sendable, Equatable { case endSession, keepSession }

public enum RequestPolicy {
    public static let userAgent = "Sub2Mobile-iOS"
    /// Refresh when less than this many seconds of access remain (00 §1.7.2).
    public static let refreshLeadTime: TimeInterval = 60
    public static let readRetryDelays: [Duration] = [.seconds(1), .seconds(3)]
    public static let maxJitter: Duration = .milliseconds(500)
    static let refreshBackoffSteps: [TimeInterval] = [2, 5, 15, 30]
    static let transientNetworkErrors: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                                                             .cannotFindHost, .dnsLookupFailed]
    /// Identity, credential and idempotency headers come only from the client, never from a caller's header list.
    static let reservedHeaders: Set<String> = ["authorization", "x-api-key", "x-device-id", "user-agent", "accept-language", "x-request-id", "idempotency-key"]

    public static func isRetryableNetworkError(_ error: any Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return transientNetworkErrors.contains(code)
    }
    /// 502 and 504 usually come from a proxy. A 503 with its own reason (ACCOUNT_STATS_UNAVAILABLE, PUSH_NOT_CONFIGURED…)
    /// is handled by its section on the next cycle instead.
    public static func isRetryableStatus(_ status: Int, marker: String?) -> Bool {
        switch status {
        case 502, 504: true
        case 503: marker == nil || marker == "SERVICE_UNAVAILABLE"
        default: false
        }
    }
    /// 401 TOKEN_EXPIRED, or a 401 the catalog does not know (00 §3.3): both happen before the handler runs.
    public static func requiresTokenRefresh(status: Int, marker: String?, context: ReasonCatalog.Context = .business) -> Bool {
        guard status == 401 else { return false }
        return marker == "TOKEN_EXPIRED" || ReasonCatalog.lookup(status: 401, reason: marker, context: context) == nil
    }
    /// The refresh rows of the catalog are the only source (D06); network errors and undecodable replies keep the session.
    public static func refreshVerdict(status: Int, reason: String?) -> RefreshVerdict {
        ReasonCatalog.entry(status: status, reason: reason, context: .refresh).action == .clearSession ? .endSession : .keepSession
    }
    /// Seconds before the next refresh attempt after `count` consecutive transient failures: 2, 5, 15, then 30.
    public static func refreshBackoff(afterFailures count: Int) -> TimeInterval {
        refreshBackoffSteps[min(max(count, 1), refreshBackoffSteps.count) - 1]
    }
    /// Safety net for 00 §4.1: a page_size above 1000 would silently become 20 on the server.
    static func sanitizedQuery(_ items: [URLQueryItem]) -> [URLQueryItem] {
        items.map { item in
            guard item.name == "page_size", let size = item.value.flatMap({ Int($0) }), size > PageSize.maximum else { return item }
            return URLQueryItem(name: item.name, value: String(PageSize.maximum))
        }
    }
    static func isReserved(_ header: String) -> Bool { reservedHeaders.contains(header.lowercased()) }
}

/// One logical request. Body bytes and X-Request-ID stay fixed across the token resend and automatic retries.
struct OutgoingRequest: Sendable {
    let path: String
    let method: String
    let query: [URLQueryItem]
    let body: Data?
    /// Caller headers such as Accept or If-None-Match; reserved names are dropped when the request is built.
    let headers: [String: String]
    let requestClass: RequestClass
    let timeout: TimeInterval?
    /// Keyed writes reuse the key; a frozen unkeyed write passes its operation number; other non-GET requests get a fresh
    /// lowercased UUID; GET leaves it to the server.
    let requestID: String?
    let authenticated: Bool
    init(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, headers: [String: String] = [:],
         requestClass: RequestClass? = nil, timeout: TimeInterval? = nil, authenticated: Bool = true, requestID: String? = nil) {
        let resolved = requestClass ?? .inferred(method: method)
        self.path = path; self.method = method; self.query = query; self.body = body; self.headers = headers
        self.requestClass = resolved; self.timeout = timeout; self.authenticated = authenticated
        self.requestID = resolved.idempotencyKey ?? requestID ?? (method.uppercased() == "GET" ? nil : UUID().uuidString.lowercased())
    }
}
