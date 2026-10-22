import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
@testable import Sub2Core

// Shared request-layer stubs (D12): later APIClient tests extend this file instead of adding private copies.
// Names stay clear of the private helpers in older test files (ok, server, token, Gate, MockTransport…).

/// Records every request and answers through a closure, or through a script whose last step repeats.
actor ScriptedTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> HTTPResponse
    typealias StreamHandler = @Sendable (URLRequest) async throws -> HTTPStreamResponse
    private let handler: Handler
    private let streamHandler: StreamHandler?
    private(set) var requests = [URLRequest]()
    init(stream: StreamHandler? = nil, _ handler: @escaping Handler) { self.handler = handler; streamHandler = stream }
    init(script steps: [ScriptStep]) {
        let counter = CallCounter()
        self.init { _ in try steps[min(counter.next(), steps.count) - 1].resolve() }
    }
    func data(for request: URLRequest) async throws -> HTTPResponse { requests.append(request); return try await handler(request) }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse {
        requests.append(request)
        guard let streamHandler else { throw URLError(.unsupportedURL) }
        return try await streamHandler(request)
    }
    func requests(path suffix: String) -> [URLRequest] { requests.filter { $0.url?.path.hasSuffix(suffix) == true } }
}

enum ScriptStep: Sendable {
    case reply(HTTPResponse), fail(URLError)
    func resolve() throws -> HTTPResponse {
        switch self {
        case .reply(let response): return response
        case .fail(let error): throw error
        }
    }
}

final class CallCounter: Sendable {
    private let count = Mutex(0)
    func next() -> Int { count.withLock { $0 += 1; return $0 } }
}

/// Collects the waits a RequestClock was asked for; `onSleep` runs inside the wait (for example to call cancelAll).
actor SleepRecorder {
    private(set) var durations = [Duration]()
    func record(_ duration: Duration) { durations.append(duration) }
}

/// A settable wall clock for token expiry and refresh backoff; it never sleeps.
final class ManualClock: Sendable {
    let start: Date
    private let current: Mutex<Date>
    init(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { self.start = start; current = Mutex(start) }
    func now() -> Date { current.withLock { $0 } }
    func advance(by seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
    var requestClock: RequestClock { RequestClock(now: { [self] in now() }, sleep: { _ in }, jitter: { .zero }) }
}

actor StubCredentialStore: CredentialStore {
    private(set) var values = [UUID: Credential]()
    func load(serverID: UUID) async throws -> Credential? { values[serverID] }
    func save(_ credential: Credential, serverID: UUID) async throws { values[serverID] = credential }
    func remove(serverID: UUID) async throws { values[serverID] = nil }
}

/// Opens once; later waiters pass straight through.
actor OpenGate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; let pending = waiters; waiters.removeAll(); for waiter in pending { waiter.resume() } }
}

extension RequestClock {
    /// No waiting and no jitter, so read retries in tests do not sleep for real.
    static let immediate = RequestClock(sleep: { _ in }, jitter: { .zero })
    static func recording(_ recorder: SleepRecorder, jitter: Duration = .zero, now: @escaping @Sendable () -> Date = { Date() },
                          onSleep: (@Sendable (Duration) async throws -> Void)? = nil) -> RequestClock {
        RequestClock(now: now, sleep: { duration in
            await recorder.record(duration)
            try await onSleep?(duration)
        }, jitter: { jitter })
    }
}

let stubDeviceID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
let stubUserJSON = #"{"id":7,"email":"admin@example.invalid","username":"管理员","balance":"1","status":"active","role":"admin","concurrency":5}"#
let stubRefreshJSON = #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}"#

func okReply(_ json: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: headers, data: Data("{\"code\":0,\"data\":\(json)}".utf8))
}
func errorReply(_ status: Int, reason: String? = nil, headers: [String: String] = [:], extra: String = "") -> HTTPResponse {
    let reasonField = reason.map { ",\"reason\":\"\($0)\"" } ?? ""
    return HTTPResponse(statusCode: status, headers: headers, data: Data("{\"code\":\(status)\(reasonField)\(extra)}".utf8))
}
func stubServer() -> ServerProfile { ServerProfile(name: "请求层", baseURL: URL(string: "https://requests.example.invalid")!, authentication: .password) }
func stubTokens(access: String = "old-access", expiresAt: Date = Date().addingTimeInterval(3_600)) -> Credential {
    .tokens(TokenPair(accessToken: access, refreshToken: "old-refresh", expiresAt: expiresAt))
}
func isRefresh(_ request: URLRequest) -> Bool { request.url?.path == "/api/v1/auth/refresh" }
func sentHeader(_ request: URLRequest?, _ name: String) -> String? { request?.value(forHTTPHeaderField: name) }
func thrownAPIError(_ operation: () async throws -> Void) async -> APIError? {
    do { try await operation(); return nil } catch { return error as? APIError }
}
