import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor APIClient {
    public nonisolated let server: ServerProfile
    private var credential: Credential?
    private let store: (any CredentialStore)?
    private let transport: any HTTPTransport
    private var generation = UUID()
    private var cancellations: [UUID: @Sendable () -> Void] = [:]
    private var refreshTask: Task<TokenPair, any Error>?
    private var refreshID: UUID?
    public init(server: ServerProfile, credential: Credential? = nil, credentialStore: (any CredentialStore)? = nil, transport: any HTTPTransport = URLSessionTransport()) {
        self.server = server; self.credential = credential; store = credentialStore; self.transport = transport
    }
    public func currentCredential() -> Credential? { credential }
    public func cancelAll() async {
        generation = UUID()
        refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        let cancel = Array(cancellations.values); cancellations.removeAll()
        for action in cancel { action() }
    }
    public func publicSettings() async throws -> PublicSettings {
        try await request("settings/public", authenticated: false)
    }
    public func login(email: String, password: String, proof: CaptchaProof? = nil) async throws -> LoginResult {
        let snapshot = generation
        let body = LoginBody(email: email, password: password, turnstileToken: proof?.turnstileToken, tencentTicket: proof?.tencentTicket, tencentRandstr: proof?.tencentRandstr)
        let reply: LoginReply = try await request("auth/login", method: "POST", body: encode(body), authenticated: false)
        try check(snapshot)
        if reply.requires2FA == true {
            guard let token = reply.tempToken, !token.isEmpty else { throw APIError.invalidResponse }
            return .twoFactor(TwoFactorChallenge(tempToken: token, maskedEmail: reply.maskedEmail))
        }
        return .authenticated(try await acceptLogin(reply, generation: snapshot))
    }
    public func completeTOTP(tempToken: String, code: String) async throws -> AuthSession {
        guard validTOTP(code), !tempToken.isEmpty else {
            throw APIError(kind: .twoFactor, message: "请输入六位双因素验证码。")
        }
        let snapshot = generation
        let reply: LoginReply = try await request("auth/login/2fa", method: "POST", body: encode(["temp_token": tempToken, "totp_code": code]), authenticated: false)
        return try await acceptLogin(reply, generation: snapshot)
    }
    public func verifyAdministrator() async throws {
        let snapshot = generation
        guard let credential else { throw APIError.authenticationRequired }
        switch credential {
        case .adminKey(let key):
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.authenticationRequired }
            let _: EmptyReply = try await request("admin/dashboard/realtime")
        case .tokens:
            let user: AdminUser = try await request("auth/me")
            guard user.role == "admin" else { throw APIError.administratorRequired }
        }
        try check(snapshot)
        if let current = self.credential { try await persist(current, generation: snapshot) }
    }
    public func logout() async throws {
        let oldCredential = credential
        await cancelAll()
        credential = nil
        // Local erasure happens even when the station is unreachable.
        try await store?.remove(serverID: server.id)
        if case .tokens(let tokens) = oldCredential, !tokens.refreshToken.isEmpty {
            let _: EmptyReply = try await request("auth/logout", method: "POST", body: encode(["refresh_token": tokens.refreshToken]), authenticated: false)
        }
    }
    public func dashboard() async throws -> DashboardSummary {
        let snapshot = generation
        // Large stations can need longer to calculate an uncached aggregate. Optional
        // historical and operational queries must not delay these primary metrics.
        let stats: DashboardStats = try await request("admin/dashboard/stats", timeout: 90)
        try check(snapshot)
        return DashboardSummary(stats: stats, trend: [])
    }
    public func dashboardTrend() async throws -> [TrendPoint] {
        let snapshot = generation
        let reply: TrendReply = try await request("admin/dashboard/trend", query: dateRange(days: 1) + [URLQueryItem(name: "granularity", value: "hour")], timeout: 45)
        try check(snapshot)
        return reply.trend
    }
    public func dashboardMonitoring() async throws -> OpsSnapshot {
        let snapshot = generation
        let reply: OpsReply = try await request("admin/ops/dashboard/overview", query: [URLQueryItem(name: "time_range", value: "5m")], timeout: 15)
        try check(snapshot)
        return OpsSnapshot(errorRate: reply.errorRate, qps: reply.qps?.current, activeRequests: nil)
    }
    public func accounts(page: Int, search: String, status: String?, platform: String?) async throws -> Page<UpstreamAccount> {
        try await request("admin/accounts", query: pagination(page, search: search, status: status) + optionalQuery("platform", platform))
    }
    public func account(id: Int) async throws -> UpstreamAccount { try await request("admin/accounts/\(validID(id))") }
    public func accountTodayStats(id: Int) async throws -> AccountTodayStats { try await request("admin/accounts/\(validID(id))/today-stats") }
    public func setSchedulable(id: Int, enabled: Bool) async throws -> UpstreamAccount {
        try await request("admin/accounts/\(validID(id))/schedulable", method: "POST", body: encode(["schedulable": enabled]))
    }
    public func refreshAccount(id: Int) async throws {
        let _: EmptyReply = try await request("admin/accounts/\(validID(id))/refresh", method: "POST", body: Data("{}".utf8))
    }
    public func users(page: Int, search: String, status: String?) async throws -> Page<AdminUser> {
        try await request("admin/users", query: pagination(page, search: search, status: status))
    }
    public func user(id: Int) async throws -> AdminUser { try await request("admin/users/\(validID(id))") }
    public func userUsage(id: Int) async throws -> UserUsageSummary {
        // The legacy /admin/users/:id/usage endpoint currently returns mock zeros in this backend.
        // Query real monthly usage aggregates instead.
        try await request("admin/usage/stats", query: monthRange() + [URLQueryItem(name: "user_id", value: String(validID(id)))])
    }
    public func userKeys(id: Int, page: Int) async throws -> Page<UserAPIKey> {
        try await request("admin/users/\(validID(id))/api-keys", query: pagination(page, search: "", status: nil))
    }
    public func setUserStatus(id: Int, status: String) async throws -> AdminUser {
        guard ["active", "disabled"].contains(status) else { throw APIError(kind: .validation, message: "无效的用户状态。") }
        return try await request("admin/users/\(validID(id))", method: "PUT", body: encode(["status": status]))
    }
    public func updateBalance(_ operation: PendingBalanceOperation) async throws -> AdminUser {
        guard operation.serverID == server.id else { throw APIError.stationMismatch }
        return try await request("admin/users/\(validID(operation.userID))/balance", method: "POST", body: operation.requestBody(), headers: ["Idempotency-Key": operation.id.uuidString.lowercased()])
    }
    public func stepUp(code: String) async throws {
        guard validTOTP(code) else { throw APIError(kind: .twoFactor, message: "请输入六位双因素验证码。") }
        let reply: StepUpReply = try await request("user/totp/step-up", method: "POST", body: encode(["code": code]))
        guard reply.verified else { throw APIError(kind: .twoFactor, message: "二次验证未通过。") }
    }
    public func testAccount(id: Int, model: String?) async throws -> AsyncThrowingStream<AccountTestEvent, any Error> {
        let snapshot = generation
        let auth = try await validCredential()
        let body = try encode(["model_id": model ?? ""])
        let request = try makeRequest("admin/accounts/\(validID(id))/test", method: "POST", body: body, credential: auth, headers: ["Accept": "text/event-stream"])
        let response = try await openStream(request, generation: snapshot)
        guard (200..<300).contains(response.statusCode) else {
            let errorReadID = UUID()
            cancellations[errorReadID] = { response.cancel() }
            defer { cancellations[errorReadID] = nil; response.cancel() }
            var body = Data()
            for try await chunk in response.bytes {
                try check(snapshot)
                body.append(chunk); if body.count > 64 * 1_024 { break }
            }
            try check(snapshot)
            throw responseError(status: response.statusCode, data: body)
        }
        guard response.headers.first(where: { $0.key.lowercased() == "content-type" })?.value.lowercased().hasPrefix("text/event-stream") == true else {
            response.cancel(); throw APIError.malformedStream
        }
        let streamID = UUID()
        let pair = AsyncThrowingStream<AccountTestEvent, any Error>.makeStream()
        let task = Task { [weak self] in
            defer { response.cancel() }
            do {
                var parser = AccountSSEParser()
                for try await bytes in response.bytes {
                    try Task.checkCancellation()
                    guard let self else { throw CancellationError() }
                    try await self.check(snapshot)
                    for event in try parser.append(bytes) { pair.continuation.yield(event) }
                    if parser.receivedTerminal { break }
                }
                _ = try parser.finish()
                pair.continuation.finish()
            } catch is CancellationError { pair.continuation.finish(throwing: CancellationError()) }
            catch {
                if Task.isCancelled { pair.continuation.finish(throwing: CancellationError()) }
                else { pair.continuation.finish(throwing: APIError.transport(error)) }
            }
            await self?.removeCancellation(streamID)
        }
        cancellations[streamID] = { task.cancel(); response.cancel() }
        pair.continuation.onTermination = { _ in task.cancel(); response.cancel() }
        return pair.stream
    }

    private func acceptLogin(_ reply: LoginReply, generation snapshot: UUID) async throws -> AuthSession {
        try check(snapshot)
        guard let user = reply.user, let token = reply.accessToken, !token.isEmpty else { throw APIError.invalidResponse }
        guard user.role == "admin" else { throw APIError.administratorRequired }
        let pair = TokenPair(accessToken: token, refreshToken: reply.refreshToken ?? "", expiresAt: Date().addingTimeInterval(TimeInterval(reply.expiresIn ?? 300)))
        let current = Credential.tokens(pair)
        try await persist(current, generation: snapshot)
        credential = current
        return AuthSession(user: user, tokens: pair)
    }
    private func persist(_ value: Credential, generation snapshot: UUID) async throws {
        try check(snapshot)
        try await store?.save(value, serverID: server.id)
        if snapshot != generation {
            try await store?.remove(serverID: server.id)
            throw CancellationError()
        }
    }
    private func validCredential(forceRefresh: Bool = false, rejectedAccess: String? = nil) async throws -> Credential {
        try Task.checkCancellation()
        guard let current = credential else { throw APIError.authenticationRequired }
        guard case .tokens(let tokens) = current else { return current }
        if let rejectedAccess, rejectedAccess != tokens.accessToken { return current }
        if !forceRefresh && tokens.expiresAt > Date().addingTimeInterval(30) { return current }
        guard !tokens.refreshToken.isEmpty else { throw APIError.authenticationRequired }
        let snapshot = generation
        let flight: Task<TokenPair, any Error>
        if let existing = refreshTask, refreshID != nil { flight = existing }
        else {
            let request = try makeRequest("auth/refresh", method: "POST", body: encode(["refresh_token": tokens.refreshToken]), credential: nil)
            let transport = transport
            let newFlightID = UUID()
            flight = Task { [self] in
                do {
                    let response = try await transport.data(for: request)
                    let reply: RefreshReply = try Self.decode(response)
                    guard !reply.accessToken.isEmpty, !reply.refreshToken.isEmpty, reply.expiresIn > 0 else { throw APIError.invalidResponse }
                    let pair = TokenPair(accessToken: reply.accessToken, refreshToken: reply.refreshToken, expiresAt: Date().addingTimeInterval(TimeInterval(reply.expiresIn)))
                    try await commitRefresh(pair, flightID: newFlightID, generation: snapshot)
                    return pair
                } catch {
                    refreshFailed(newFlightID)
                    throw error
                }
            }
            refreshTask = flight; refreshID = newFlightID
        }
        do {
            let pair = try await flight.value
            try check(snapshot)
            return .tokens(pair)
        } catch {
            if snapshot != generation || Task.isCancelled { throw CancellationError() }
            if error is CancellationError { throw CancellationError() }
            throw APIError.transport(error)
        }
    }
    private func commitRefresh(_ pair: TokenPair, flightID: UUID, generation snapshot: UUID) async throws {
        try check(snapshot)
        guard refreshID == flightID else { throw CancellationError() }
        let value = Credential.tokens(pair)
        try await persist(value, generation: snapshot)
        try check(snapshot)
        credential = value; refreshTask = nil; refreshID = nil
    }
    private func refreshFailed(_ id: UUID) { if refreshID == id { refreshTask = nil; refreshID = nil } }
    private func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, headers: [String: String] = [:], authenticated: Bool = true, timeout: TimeInterval? = nil) async throws -> T {
        let snapshot = generation
        let auth: Credential?
        if authenticated { auth = try await validCredential() } else { auth = nil }
        try check(snapshot)
        let outgoing = try makeRequest(path, method: method, query: query, body: body, credential: auth, headers: headers, timeout: timeout)
        var response = try await execute(outgoing, generation: snapshot)
        // Only safe reads can be retried, and only an explicit expired-token response permits refresh.
        if authenticated, method == "GET", response.statusCode == 401,
           (try? JSONDecoder().decode(ErrorReply.self, from: response.data).reason) == "TOKEN_EXPIRED",
           let auth, case .tokens(let old) = auth {
            let fresh = try await validCredential(forceRefresh: true, rejectedAccess: old.accessToken)
            try check(snapshot)
            response = try await execute(makeRequest(path, method: method, query: query, body: body, credential: fresh, headers: headers, timeout: timeout), generation: snapshot)
        }
        return try Self.decode(response)
    }
    private func execute(_ request: URLRequest, generation snapshot: UUID) async throws -> HTTPResponse {
        try check(snapshot)
        let id = UUID(); let transport = transport
        let task = Task { try await transport.data(for: request) }
        cancellations[id] = { task.cancel() }
        defer { cancellations[id] = nil }
        do {
            let response = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try check(snapshot)
            return response
        } catch is CancellationError { throw CancellationError() }
        catch { if snapshot != generation || Task.isCancelled { throw CancellationError() }; throw APIError.transport(error) }
    }
    private func openStream(_ request: URLRequest, generation snapshot: UUID) async throws -> HTTPStreamResponse {
        let id = UUID(); let transport = transport
        let task = Task { try await transport.stream(for: request) }
        cancellations[id] = { task.cancel() }
        defer { cancellations[id] = nil }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            do { try check(snapshot) } catch { result.cancel(); throw error }
            return result
        } catch is CancellationError { throw CancellationError() }
        catch { if snapshot != generation || Task.isCancelled { throw CancellationError() }; throw APIError.transport(error) }
    }
    private func makeRequest(_ path: String, method: String, query: [URLQueryItem] = [], body: Data? = nil, credential: Credential?, headers: [String: String] = [:], timeout: TimeInterval? = nil) throws -> URLRequest {
        let base = try server.validatedURL()
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/" + path; components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.invalidServer }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        if let timeout { request.timeoutInterval = timeout }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Sub2Mobile/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        switch credential {
        case .adminKey(let key): request.setValue(key, forHTTPHeaderField: "x-api-key")
        case .tokens(let tokens): request.setValue("Bearer " + tokens.accessToken, forHTTPHeaderField: "Authorization")
        case nil: break
        }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }
    private static func decode<T: Decodable & Sendable>(_ response: HTTPResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else { throw responseError(status: response.statusCode, data: response.data) }
        do {
            if T.self == EmptyReply.self {
                let envelope = try JSONDecoder().decode(ErrorReply.self, from: response.data)
                guard envelope.code == 0 else { throw APIError.server(status: response.statusCode, reason: envelope.reason) }
                return EmptyReply() as! T
            }
            let envelope = try JSONDecoder().decode(Envelope<T>.self, from: response.data)
            guard envelope.code == 0 else { throw APIError.server(status: response.statusCode, reason: envelope.reason) }
            guard let result = envelope.data else { throw APIError.invalidResponse }
            return result
        } catch let error as APIError { throw error }
        catch { throw APIError.invalidResponse }
    }
    private func check(_ snapshot: UUID) throws { try Task.checkCancellation(); guard snapshot == generation else { throw CancellationError() } }
    private func removeCancellation(_ id: UUID) { cancellations[id] = nil }
    private func validTOTP(_ code: String) -> Bool { code.utf8.count == 6 && code.utf8.allSatisfy { (48...57).contains($0) } }
    private func validID(_ value: Int) throws -> Int {
        guard value > 0 else { throw APIError(kind: .validation, message: "无效的对象编号。") }; return value
    }
    private func pagination(_ page: Int, search: String, status: String?) throws -> [URLQueryItem] {
        guard page >= 1 else { throw APIError(kind: .validation, message: "页码必须从 1 开始。") }
        return [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "page_size", value: "20")]
            + optionalQuery("search", search.trimmingCharacters(in: .whitespacesAndNewlines)) + optionalQuery("status", status)
    }
    private func optionalQuery(_ name: String, _ value: String?) -> [URLQueryItem] {
        guard let value, !value.isEmpty else { return [] }; return [URLQueryItem(name: name, value: value)]
    }
    private func dateRange(days: Int) -> [URLQueryItem] {
        let today = Date(); let start = Calendar.current.date(byAdding: .day, value: -days, to: today) ?? today
        return dates(start: start, end: today)
    }
    private func monthRange() -> [URLQueryItem] {
        let now = Date(); let start = Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        return dates(start: start, end: now)
    }
    private func dates(start: Date, end: Date) -> [URLQueryItem] {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return [URLQueryItem(name: "start_date", value: f.string(from: start)), URLQueryItem(name: "end_date", value: f.string(from: end)), URLQueryItem(name: "timezone", value: TimeZone.current.identifier)]
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return try e.encode(value) }
}

private struct Envelope<T: Decodable & Sendable>: Decodable, Sendable { let code: Int; let reason: String?; let data: T? }
private struct ErrorReply: Decodable, Sendable { let code: Int?; let reason: String? }
private struct EmptyReply: Decodable, Sendable {}
private func responseError(status: Int, data: Data) -> APIError {
    APIError.server(status: status, reason: (try? JSONDecoder().decode(ErrorReply.self, from: data))?.reason)
}
private struct TrendReply: Decodable, Sendable { let trend: [TrendPoint] }
private struct StepUpReply: Decodable, Sendable { let verified: Bool }
private struct OpsReply: Decodable, Sendable {
    let errorRate: Double?
    let qps: Rate?
    struct Rate: Decodable, Sendable { let current: Double? }
    enum CodingKeys: String, CodingKey { case errorRate = "error_rate", qps }
}
private struct LoginBody: Encodable {
    let email: String; let password: String; let turnstileToken: String?; let tencentTicket: String?; let tencentRandstr: String?
    enum CodingKeys: String, CodingKey { case email, password, turnstileToken = "turnstile_token", tencentTicket = "tencent_captcha_ticket", tencentRandstr = "tencent_captcha_randstr" }
}
private struct LoginReply: Decodable, Sendable {
    let requires2FA: Bool?; let tempToken: String?; let maskedEmail: String?
    let accessToken: String?; let refreshToken: String?; let expiresIn: Int?; let user: AdminUser?
    enum CodingKeys: String, CodingKey {
        case requires2FA = "requires_2fa", tempToken = "temp_token", maskedEmail = "user_email_masked"
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", user
    }
}
private struct RefreshReply: Decodable, Sendable {
    let accessToken: String; let refreshToken: String; let expiresIn: Int
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in" }
}
