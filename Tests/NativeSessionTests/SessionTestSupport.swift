import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Sub2Core
@testable import NativeSessionSupport

// Shared stubs for NativeSessionTests (the Sub2CoreTests helpers are not visible from this target).

/// Records every request and answers through a closure.
actor SessionTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> HTTPResponse
    private let handler: Handler
    private(set) var requests = [URLRequest]()
    init(_ handler: @escaping Handler) { self.handler = handler }
    func data(for request: URLRequest) async throws -> HTTPResponse { requests.append(request); return try await handler(request) }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { requests.append(request); throw URLError(.unsupportedURL) }
    func paths() -> [String] { requests.compactMap { $0.url?.path } }
}

/// Opens once; later waiters pass straight through. `arrived` reports whether anyone has waited yet.
actor SessionGate {
    private var isOpen = false
    private(set) var arrived = false
    private var waiters = [CheckedContinuation<Void, Never>]()
    func wait() async {
        arrived = true
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; let pending = waiters; waiters.removeAll(); for waiter in pending { waiter.resume() } }
}

/// Keychain stand-in whose reads or writes fail for accounts matching `failing`.
final class FailingSecureItems: SecureItems {
    enum Operation: Sendable { case read, write }
    private let base = MemorySecureItems()
    private let operation: Operation
    private let failing: @Sendable (String) -> Bool
    private let writes = Mutex(0)
    init(_ operation: Operation, when failing: @escaping @Sendable (String) -> Bool) { self.operation = operation; self.failing = failing }
    var writeCount: Int { writes.withLock { $0 } }
    func read(account: String) throws -> Data? {
        if operation == .read, failing(account) { throw URLError(.cannotOpenFile) }
        return try base.read(account: account)
    }
    func write(_ data: Data, account: String) throws {
        if operation == .write, failing(account) { throw URLError(.cannotWriteToFile) }
        writes.withLock { $0 += 1 }
        try base.write(data, account: account)
    }
    func delete(account: String) throws { try base.delete(account: account) }
}

let sessionDeviceID = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
let sessionDevice = sessionDeviceID.uuidString.lowercased()

func sessionServer() -> ServerProfile {
    ServerProfile(name: "会话", baseURL: URL(string: "https://session.example.invalid")!, authentication: .password)
}
func sessionTokens(refresh: String = "fixture-refresh", expiresAt: Date = Date().addingTimeInterval(3_600)) -> Credential {
    .tokens(TokenPair(accessToken: "fixture-access", refreshToken: refresh, expiresAt: expiresAt))
}
/// Waits never sleep, so read retries after a 5xx stay fast.
func sessionClient(_ transport: SessionTransport, credential: Credential = sessionTokens(), deviceID: UUID = sessionDeviceID,
                   serverClock: ServerClock = ServerClock()) -> APIClient {
    APIClient(server: sessionServer(), credential: credential, deviceID: deviceID, transport: transport,
              requestClock: RequestClock(sleep: { _ in }, jitter: { .zero }), serverClock: serverClock)
}

func sessionOK(_ json: String, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(statusCode: 200, headers: headers, data: Data("{\"code\":0,\"data\":\(json)}".utf8))
}
func sessionFailure(_ status: Int, reason: String? = nil) -> HTTPResponse {
    let reasonField = reason.map { ",\"reason\":\"\($0)\"" } ?? ""
    return HTTPResponse(statusCode: status, headers: ["content-type": "application/json"], data: Data("{\"code\":\(status)\(reasonField)}".utf8))
}
let gatewayNotFound = HTTPResponse(statusCode: 404, headers: ["content-type": "text/plain"], data: Data("404 page not found".utf8))

/// An `/admin/me` reply; nil drops a field so old or partial servers can be modelled.
func meJSON(authMethod: String? = "jwt", role: String = "admin", email: String = "admin@example.invalid", workspace: String = "null",
            complianceRequired: Bool = false, timezone: String? = "Asia/Shanghai", offset: String? = "+08:00",
            capabilities: [String] = ["dashboard.rates", "dashboard.rates", "admin.access_tokens"]) -> String {
    let method = authMethod.map { "\"auth_method\":\"\($0)\"," } ?? ""
    let zone = timezone.map { "\"server_timezone\":\"\($0)\"," } ?? ""
    let utc = offset.map { "\"server_utc_offset\":\"\($0)\"," } ?? ""
    let list = capabilities.map { "\"\($0)\"" }.joined(separator: ",")
    return """
    {\(method)"user":{"id":7,"email":"\(email)","username":"管理员","role":"\(role)"},"workspace":\(workspace),
     "security":{"totp_enabled":true,"step_up_enabled":false},"compliance":{"required":\(complianceRequired)},
     "features":{"ops_monitoring_enabled":true},"server":{"version":"1.0.0",\(zone)\(utc)"capabilities":[\(list)]}}
    """
}
func tokensJSON(_ items: [(current: Bool, scope: String)]) -> String {
    let rows = items.enumerated().map { "{\"id\":\($0.offset + 1),\"scope\":\"\($0.element.scope)\",\"current\":\($0.element.current)}" }
    return "{\"items\":[\(rows.joined(separator: ","))]}"
}
