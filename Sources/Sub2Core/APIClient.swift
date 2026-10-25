import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DashboardCostSnapshot: Sendable {
    public let actual: Decimal
    public let account: Decimal
    public let totalActual: Decimal?
    public let totalAccount: Decimal?
    public init(actual: Decimal, account: Decimal, totalActual: Decimal? = nil, totalAccount: Decimal? = nil) {
        self.actual = actual; self.account = account
        // Never combine a partial cumulative pair with another response's value.
        self.totalActual = totalAccount == nil ? nil : totalActual
        self.totalAccount = totalActual == nil ? nil : totalAccount
    }
}

public actor APIClient {
    public nonisolated let server: ServerProfile
    /// The site's fixed Keychain value (00 §1.2), sent as X-Device-ID on every request and as the login's `client.device_id`.
    public nonisolated let deviceID: UUID
    private var credential: Credential?
    private let store: (any CredentialStore)?
    private let transport: any HTTPTransport
    let requestClock: RequestClock
    /// 00 §4.2 ETag cache; each client owns one unless a test injects a shared one.
    let conditionalCache: ConditionalCache
    /// Set by `me()`; while unknown, no request is conditional and nothing is cached.
    private(set) var cacheIdentity: ConditionalCache.Identity?
    /// `timezone=` and day boundaries for date parameters (00 §2.8); the phone's zone until the site reports one.
    private var serverZone: ServerTimeZone
    /// Date-header offset of this site (00 §6.3), recorded by `transmit` and `openStream`.
    public nonisolated let serverClock: ServerClock
    private var generation = UUID()
    /// Changed by `suspend()`: reads, waits and streams registered under an older epoch are dropped (D18).
    private var epoch = UUID()
    /// Between `suspend()` and `resume()` no wait starts, so keyed writes never retry in the background (00 §2.5.4).
    private var isSuspended = false
    private var cancellations: [UUID: Cancellation] = [:]
    private var refreshTask: Task<TokenPair, any Error>?
    private var refreshID: UUID?
    /// Consecutive transient refresh failures and the earliest next attempt (00 §1.7.2).
    private var refreshFailures = 0
    private var refreshRetryAt: Date?
    /// A refresh rejection ends the session: later requests fail with it and never reach the network.
    private var sessionEnded: APIError?
    /// The session owner's hook (AppModel); candidate, login and teardown clients pass nil (D13).
    private let onSessionInvalid: (@Sendable (SessionInvalidation) -> Void)?
    /// The generation already reported, so a burst of rejected requests reports once.
    private var reportedInvalidation: UUID?
    /// The session owner's compliance and step-up prompts (S0-13); candidate, login and teardown clients pass nil (D13).
    let securityInterceptor: SecurityInterceptor?
    /// `credentialStore` is a LeasedCredentialStore or nil, never the vault itself: `logout` and the persist fence call its
    /// `remove`, which must not delete the site's device ID (D07).
    public init(server: ServerProfile, credential: Credential? = nil, credentialStore: (any CredentialStore)? = nil, deviceID: UUID,
                transport: any HTTPTransport = URLSessionTransport(), requestClock: RequestClock = .live,
                cacheIdentity: ConditionalCache.Identity? = nil, conditionalCache: ConditionalCache = ConditionalCache(),
                serverTimeZone: ServerTimeZone = .device, serverClock: ServerClock = ServerClock(),
                onSessionInvalid: (@Sendable (SessionInvalidation) -> Void)? = nil, securityInterceptor: SecurityInterceptor? = nil) {
        self.server = server; self.credential = credential; store = credentialStore; self.deviceID = deviceID
        self.transport = transport; self.requestClock = requestClock
        self.cacheIdentity = cacheIdentity; self.conditionalCache = conditionalCache
        serverZone = serverTimeZone; self.serverClock = serverClock; self.onSessionInvalid = onSessionInvalid
        self.securityInterceptor = securityInterceptor
    }
    // Same parameters as the public init minus `deviceID` (D02): keep both lists in step. Only tests that do not care use it.
    init(server: ServerProfile, credential: Credential? = nil, credentialStore: (any CredentialStore)? = nil,
         transport: any HTTPTransport = URLSessionTransport(), requestClock: RequestClock = .live,
         cacheIdentity: ConditionalCache.Identity? = nil, conditionalCache: ConditionalCache = ConditionalCache(),
         serverTimeZone: ServerTimeZone = .device, serverClock: ServerClock = ServerClock(),
         onSessionInvalid: (@Sendable (SessionInvalidation) -> Void)? = nil, securityInterceptor: SecurityInterceptor? = nil) {
        self.init(server: server, credential: credential, credentialStore: credentialStore, deviceID: Self.testingDeviceID, transport: transport,
                  requestClock: requestClock, cacheIdentity: cacheIdentity, conditionalCache: conditionalCache,
                  serverTimeZone: serverTimeZone, serverClock: serverClock, onSessionInvalid: onSessionInvalid,
                  securityInterceptor: securityInterceptor)
    }
    static let testingDeviceID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    /// The one spelling of the device ID on the wire: X-Device-ID and `client.device_id` are byte for byte the same.
    nonisolated var deviceIDHeader: String { deviceID.uuidString.lowercased() }
    public func currentCredential() -> Credential? { credential }
    public func conditionalCacheIdentity() -> ConditionalCache.Identity? { cacheIdentity }
    /// `me()` applies the zone it reports; S0-10 also calls this when a site reload changes it.
    public func setServerTimeZone(_ zone: ServerTimeZone) { serverZone = zone }
    public func serverTimeZone() -> ServerTimeZone { serverZone }
    /// A different identity empties this site's entries (meta/catalog differs per caller, 00 §4.2).
    public func setConditionalCacheIdentity(_ identity: ConditionalCache.Identity?) async {
        guard identity != cacheIdentity else { return }
        cacheIdentity = identity
        await conditionalCache.clear(siteID: server.id)
    }
    /// Called when switching sites or ending a session (00 §0 rule 13).
    public func clearConditionalCache() async { await conditionalCache.clear(siteID: server.id) }
    public func cancelAll() async {
        generation = UUID()
        refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        let cancel = cancellations.values.map(\.cancel); cancellations.removeAll()
        for action in cancel { action() }
    }
    /// Going to the background (00 §4.6, D18): reads, read and keyed-write waits and the account-test stream stop. Unlike
    /// `cancelAll` the generation (the write identity), the refresh flight and writes already sent are left alone.
    public func suspend() {
        epoch = UUID(); isSuspended = true
        let suspended = cancellations.filter(\.value.suspendable)
        for id in suspended.keys { cancellations[id] = nil }
        for entry in suspended.values { entry.cancel() }
    }
    public func resume() { isSuspended = false }
    public func publicSettings() async throws -> PublicSettings {
        try await request("settings/public", authenticated: false, timeout: RequestTimeout.probe)
    }
    /// 00 §1.4 step 2. `declaresCaptchaProvider` is `PublicSettings.hasCaptchaProviderKey`; the second factor declares nothing
    /// (the server keeps the first step's client).
    public func login(email: String, password: String, proof: CaptchaProof? = nil, deviceName: String,
                      declaresCaptchaProvider: Bool) async throws -> LoginResult {
        let snapshot = generation
        let body = LoginBody(email: email, password: password, client: LoginClient(deviceID: deviceIDHeader, deviceName: deviceName),
                             proof: proof, declaresCaptchaProvider: declaresCaptchaProvider)
        let reply: LoginReply = try await request("auth/login", method: "POST", body: encode(body), requestClass: .auth, authenticated: false, context: .login)
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
        let reply: LoginReply = try await request("auth/login/2fa", method: "POST", body: encode(["temp_token": tempToken, "totp_code": code]),
                                                  requestClass: .auth, authenticated: false, context: .twoFactor)
        return try await acceptLogin(reply, generation: snapshot)
    }
    /// 00 §1.7.5: the local credential is gone before anything is sent, even when the site is unreachable. A JWT session then
    /// tells the server once through `postLogout` (no refresh, no session-invalid report); a key has nothing to sign out.
    public func logout() async throws {
        let oldCredential = credential
        await cancelAll()
        credential = nil; resetRefreshState(); cacheIdentity = nil
        await conditionalCache.clear(siteID: server.id)
        try await store?.remove(serverID: server.id)
        if case .tokens(let tokens) = oldCredential { try await postLogout(tokens) }
    }
    public func dashboard() async throws -> DashboardSummary {
        let snapshot = generation
        // Large stations can need longer to calculate an uncached aggregate. Optional
        // historical and operational queries must not delay these primary metrics.
        let stats: DashboardStats = try await request("admin/dashboard/stats", timeout: RequestTimeout.dashboardStats)
        try check(snapshot)
        return DashboardSummary(stats: stats, trend: [])
    }
    public func dashboardTrend() async throws -> DashboardTrendReply {
        // The zone is captured before the await so parsing matches the request even if the site zone changes meanwhile.
        let snapshot = generation, zone = serverZone
        let reply: TrendReply = try await request("admin/dashboard/trend", query: zone.lastDaysQueryItems(1, now: serverClock.now())
            + [URLQueryItem(name: "granularity", value: "hour")], timeout: RequestTimeout.aggregate)
        try check(snapshot)
        return DashboardTrendReply(points: reply.trend, timeZone: ServerTime.bucketTimeZone(reported: reply.query?.timezone, requested: zone))
    }
    public func dashboardCostSnapshot() async throws -> DashboardCostSnapshot {
        let snapshot = generation
        // Some servers omit today's and cumulative account cost from /stats. Request only snapshot stats,
        // independently from the cached overview and without chart queries.
        let reply: DashboardStatsSnapshotReply = try await request("admin/dashboard/snapshot-v2", query: dateRange(days: 0) + [
            URLQueryItem(name: "include_stats", value: "true"),
            URLQueryItem(name: "include_trend", value: "false"),
            URLQueryItem(name: "include_model_stats", value: "false"),
            URLQueryItem(name: "include_group_stats", value: "false"),
            URLQueryItem(name: "include_users_trend", value: "false")
        ], timeout: RequestTimeout.aggregate)
        try check(snapshot)
        guard let actual = reply.stats?.todayActualCost, let account = reply.stats?.todayAccountCost else {
            throw APIError(kind: .response, message: "站点未提供实际费用或账号成本，请在网页核对。")
        }
        return DashboardCostSnapshot(actual: actual, account: account, totalActual: reply.stats?.totalActualCost, totalAccount: reply.stats?.totalAccountCost)
    }
    public func dashboardMonitoring() async throws -> OpsSnapshot {
        let snapshot = generation
        let reply: OpsReply = try await request("admin/ops/dashboard/overview", query: [URLQueryItem(name: "time_range", value: "5m")], timeout: RequestTimeout.aggregate)
        try check(snapshot)
        return OpsSnapshot(errorRate: reply.errorRate, qps: reply.qps?.current, activeRequests: nil)
    }
    public func dashboardPerformanceTrend(start: Date? = nil, end: Date = Date()) async throws -> PerformanceTrend {
        let start = start ?? end.addingTimeInterval(-3_600)
        guard start < end, end.timeIntervalSince(start) <= 30 * 86_400 else {
            throw APIError(kind: .validation, message: "请选择 30 天以内的性能趋势范围。")
        }
        let snapshot = generation
        let result: PerformanceTrend = try await request("admin/ops/dashboard/throughput-trend", query: ServerTime.timeRangeItems(start: start, end: end) + [
            URLQueryItem(name: "mode", value: "auto")
        ], timeout: RequestTimeout.aggregate)
        try check(snapshot)
        return result
    }
    public func accounts(page: Int, search: String, status: String?, platform: String?, includeSchedulerScore: Bool = false) async throws -> Page<UpstreamAccount> {
        try await request("admin/accounts", query: pagination(page, search: search, status: status) + optionalQuery("platform", platform)
            + (includeSchedulerScore ? [URLQueryItem(name: "include_scheduler_score", value: "1")] : []))
    }
    public func account(id: Int) async throws -> UpstreamAccount { try await request("admin/accounts/\(validID(id))") }
    public func accountTodayStats(id: Int) async throws -> AccountTodayStats { try await request("admin/accounts/\(validID(id))/today-stats") }
    public func accountTodayStats(ids: [Int]) async throws -> [Int: AccountTodayStats] {
        let requested = Array(Set(ids.filter { $0 > 0 })).sorted()
        guard !requested.isEmpty else { return [:] }
        struct Batch: Decodable, Sendable { let stats: [String: AccountTodayStats] }
        let result: Batch = try await request("admin/accounts/today-stats/batch", method: "POST", body: encode(["account_ids": requested]), requestClass: .readBatch)
        let allowed = Set(requested)
        var stats = [Int: AccountTodayStats]()
        for (rawID, value) in result.stats {
            guard let id = Int(rawID), allowed.contains(id) else { continue }
            stats[id] = value
        }
        return stats
    }
    public func setSchedulable(id: Int, enabled: Bool) async throws -> UpstreamAccount {
        try await request("admin/accounts/\(validID(id))/schedulable", method: "POST", body: encode(["schedulable": enabled]))
    }
    public func refreshAccount(id: Int) async throws {
        let _: EmptyReply = try await request("admin/accounts/\(validID(id))/refresh", method: "POST", body: Data("{}".utf8), timeout: RequestTimeout.keyedBulk)
    }
    public func users(page: Int, search: String, status: String?) async throws -> Page<AdminUser> {
        try await request("admin/users", query: pagination(page, search: search, status: status))
    }
    public func user(id: Int) async throws -> AdminUser { try await request("admin/users/\(validID(id))") }
    public func userWriteIdentity() -> UUID { generation }
    /// With admin.idempotent_writes the frozen number is also the Idempotency-Key (00 §2.5.1); without it, X-Request-ID only.
    public func createUser(_ operation: PendingUserCreateOperation, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminUser> {
        guard operation.serverID == server.id else { throw APIError.stationMismatch }
        try check(operation.identity)
        guard operation.sendsIdempotencyKey else { return try await performUnkeyedWrite("admin/users", method: "POST", body: operation.body, requestID: operation.key) }
        return try await performKeyedWrite(KeyedWriteRequest(path: "admin/users", method: "POST", body: operation.body, key: operation.id), onEvent: onEvent)
    }
    public func updateUser(_ operation: PendingUserUpdateOperation, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminUser> {
        guard operation.serverID == server.id else { throw APIError.stationMismatch }
        try check(operation.identity)
        let path = "admin/users/\(try validID(operation.userID))"
        guard operation.supportsSafeRetry else { return try await performUnkeyedWrite(path, method: "PUT", body: operation.body, requestID: operation.key) }
        return try await performKeyedWrite(KeyedWriteRequest(path: path, method: "PUT", body: operation.body, key: operation.id), onEvent: onEvent)
    }
    public func userUsage(id: Int) async throws -> UserUsageSummary {
        // The legacy /admin/users/:id/usage endpoint currently returns mock zeros in this backend.
        // Query real monthly usage aggregates instead.
        try await request("admin/usage/stats", query: monthRange() + [URLQueryItem(name: "user_id", value: String(validID(id)))],
                          timeout: RequestTimeout.aggregate)
    }
    public func userKeys(id: Int, page: Int) async throws -> Page<UserAPIKey> {
        try await request("admin/users/\(validID(id))/api-keys", query: pagination(page, search: "", status: nil))
    }
    public func setUserStatus(id: Int, status: String) async throws -> AdminUser {
        guard ["active", "disabled"].contains(status) else { throw APIError(kind: .validation, message: "无效的用户状态。") }
        return try await request("admin/users/\(validID(id))", method: "PUT", body: encode(["status": status]))
    }
    /// Takes only a record already on disk; the body comes from the record and the key and X-Request-ID are its id (00 §9.1).
    public func updateBalance(_ write: PersistedMoneyWrite<PendingBalanceOperation>, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminUser> {
        let operation = write.record
        guard operation.serverID == server.id else { throw APIError.stationMismatch }
        return try await performKeyedWrite(KeyedWriteRequest(path: "admin/users/\(validID(operation.userID))/balance", method: "POST",
                                                             body: operation.requestBody(), key: operation.id), onEvent: onEvent)
    }
    public func testAccount(id: Int, model: String?) async throws -> AsyncThrowingStream<AccountTestEvent, any Error> {
        let snapshot = generation
        let spec = try OutgoingRequest(path: "admin/accounts/\(validID(id))/test", method: "POST", body: encode(["model_id": model ?? ""]),
                                       headers: ["Accept": "text/event-stream"])
        let response: HTTPStreamResponse
        do { response = try await openTestStream(spec, generation: snapshot) }
        catch let error as APIError { throw surfaced(await refusedWrite(error, generation: snapshot), context: .business, generation: snapshot) }
        guard response.headers.first(where: { $0.key.lowercased() == "content-type" })?.value.lowercased().hasPrefix("text/event-stream") == true else {
            response.cancel(); throw APIError.malformedStream
        }
        return events(from: response, generation: snapshot)
    }

    private func acceptLogin(_ reply: LoginReply, generation snapshot: UUID) async throws -> AuthSession {
        try check(snapshot)
        guard let user = reply.user, let token = reply.accessToken, !token.isEmpty else { throw APIError.invalidResponse }
        let pair = TokenPair(accessToken: token, refreshToken: reply.refreshToken ?? "", expiresAt: requestClock.now().addingTimeInterval(TimeInterval(reply.expiresIn ?? 300)))
        guard user.role == "admin" else {
            // 00 §1.4 step 4, §1.11: the session just issued is discarded on a best-effort basis before refusing.
            try? await postLogout(pair)
            throw APIError.administratorRequired
        }
        let current = Credential.tokens(pair)
        try await persist(current, generation: snapshot)
        credential = current; resetRefreshState()
        return AuthSession(user: user, tokens: pair, refreshTokenUnavailable: reply.refreshTokenUnavailable == true || pair.refreshToken.isEmpty)
    }
    /// The only auth/logout request (D15): `{"refresh_token": …}`, or `{}` without one, with that session's Bearer access and
    /// X-Device-ID. Sent once: no token refresh, no retry, no session-invalid report. `logout` reuses it.
    func postLogout(_ tokens: TokenPair) async throws {
        let snapshot = generation
        let body = try tokens.refreshToken.isEmpty ? Data("{}".utf8) : encode(["refresh_token": tokens.refreshToken])
        let spec = OutgoingRequest(path: "auth/logout", method: "POST", body: body, requestClass: .auth)
        let response: HTTPResponse
        do { response = try await transmit(makeRequest(spec, credential: .tokens(tokens)), generation: snapshot, requestClass: .auth) }
        catch is CancellationError { throw CancellationError() }
        catch { throw APIError.transport(error) }
        guard (200..<300).contains(response.statusCode) else { throw failure(response) }
    }
    private func persist(_ value: Credential, generation snapshot: UUID) async throws {
        try check(snapshot)
        try await store?.save(value, serverID: server.id)
        if snapshot != generation {
            try await store?.remove(serverID: server.id)
            throw CancellationError()
        }
    }

    // MARK: Token refresh (00 §1.7.2)

    /// Refreshes when under 60 seconds of access remain, or when a request's access was rejected; one flight per client.
    private func validCredential(forceRefresh: Bool = false, rejectedAccess: String? = nil) async throws -> Credential {
        try Task.checkCancellation()
        if let sessionEnded { throw sessionEnded }
        guard let current = credential else { throw APIError.authenticationRequired }
        guard case .tokens(let tokens) = current else { return current }
        if let rejectedAccess, rejectedAccess != tokens.accessToken { return current }
        let now = requestClock.now()
        if !forceRefresh && tokens.expiresAt.timeIntervalSince(now) >= RequestPolicy.refreshLeadTime { return current }
        guard !tokens.refreshToken.isEmpty else { throw APIError.authenticationRequired }
        let snapshot = generation
        let flight: Task<TokenPair, any Error>
        if let existing = refreshTask, refreshID != nil { flight = existing }
        else if let retryAt = refreshRetryAt, now < retryAt { return try deferredCredential(current, tokens, forceRefresh: forceRefresh) }
        else { flight = try startRefresh(tokens.refreshToken, generation: snapshot) }
        do {
            let pair = try await flight.value
            try check(snapshot)
            return .tokens(pair)
        } catch {
            if snapshot != generation || Task.isCancelled || error is CancellationError { throw CancellationError() }
            if let sessionEnded { throw sessionEnded }
            return try deferredCredential(current, tokens, forceRefresh: forceRefresh)
        }
    }
    /// A transient refresh failure keeps the session: an unexpired access still works, otherwise this request fails as transport.
    private func deferredCredential(_ current: Credential, _ tokens: TokenPair, forceRefresh: Bool) throws -> Credential {
        guard !forceRefresh, tokens.expiresAt > requestClock.now() else { throw APIError.refreshDeferred }
        return current
    }
    /// The refresh request carries UA and X-Device-ID but never Authorization; it goes through `transmit` like any request.
    private func startRefresh(_ refreshToken: String, generation snapshot: UUID) throws -> Task<TokenPair, any Error> {
        let spec = try OutgoingRequest(path: "auth/refresh", method: "POST", body: encode(["refresh_token": refreshToken]), requestClass: .auth, authenticated: false)
        let request = try makeRequest(spec, credential: nil)
        let flightID = UUID()
        let flight = Task { [self] in
            do {
                let response = try await transmit(request, generation: snapshot, requestClass: .auth)
                let pair = try refreshedPair(response)
                try await commitRefresh(pair, flightID: flightID, generation: snapshot)
                return pair
            } catch {
                refreshFailed(flightID, error: error)
                throw error
            }
        }
        refreshTask = flight; refreshID = flightID
        return flight
    }
    /// A missing or non-positive expires_in counts as 300 seconds (00 §1.7.1).
    private func refreshedPair(_ response: HTTPResponse) throws -> TokenPair {
        guard (200..<300).contains(response.statusCode) else { throw failure(response, context: .refresh) }
        let reply: RefreshReply = try Self.decode(response, context: .refresh)
        guard !reply.accessToken.isEmpty, !reply.refreshToken.isEmpty else { throw APIError.invalidResponse }
        let lifetime = reply.expiresIn.flatMap { $0 > 0 ? $0 : nil } ?? 300
        return TokenPair(accessToken: reply.accessToken, refreshToken: reply.refreshToken, expiresAt: requestClock.now().addingTimeInterval(TimeInterval(lifetime)))
    }
    private func commitRefresh(_ pair: TokenPair, flightID: UUID, generation snapshot: UUID) async throws {
        try check(snapshot)
        guard refreshID == flightID else { throw CancellationError() }
        let value = Credential.tokens(pair)
        try await persist(value, generation: snapshot)
        try check(snapshot)
        credential = value; refreshTask = nil; refreshID = nil; resetRefreshState()
    }
    /// One verdict per flight: a rejection ends the session, anything else backs off 2, 5, 15, then 30 seconds.
    private func refreshFailed(_ id: UUID, error: any Error) {
        guard refreshID == id else { return }
        refreshTask = nil; refreshID = nil
        guard !(error is CancellationError) else { return }
        if let rejected = error as? APIError, let status = rejected.statusCode,
           RequestPolicy.refreshVerdict(status: status, reason: rejected.reason) == .endSession {
            sessionEnded = rejected
            return
        }
        refreshFailures += 1
        refreshRetryAt = requestClock.now().addingTimeInterval(RequestPolicy.refreshBackoff(afterFailures: refreshFailures))
    }
    private func resetRefreshState() { sessionEnded = nil; refreshFailures = 0; refreshRetryAt = nil }

    // MARK: Request pipeline (D01). Later items add code at these hooks instead of splitting `request` again.

    func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, headers: [String: String] = [:],
                                          requestClass: RequestClass? = nil, authenticated: Bool = true, timeout: TimeInterval? = nil,
                                          context: ReasonCatalog.Context = .business) async throws -> T {
        try await requestWithHeaders(path, method: method, query: query, body: body, headers: headers, requestClass: requestClass,
                                     authenticated: authenticated, timeout: timeout, context: context).value
    }
    /// Value, status and lowercased headers (00 §9.1). The conditional cache (S0-05) wraps `send`: a 304 keeps its status and
    /// headers but carries the cached value. S0-13 intercepts between `failure` and `surfaced` (`resendAfterPrompt`).
    func requestWithHeaders<T: Decodable & Sendable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil,
                                                     headers: [String: String] = [:], requestClass: RequestClass? = nil, authenticated: Bool = true,
                                                     timeout: TimeInterval? = nil, context: ReasonCatalog.Context = .business,
                                                     requestID: String? = nil) async throws -> APIResponse<T> {
        let snapshot = generation
        let plan: ConditionalPlan?, spec: OutgoingRequest
        var received: HTTPResponse, response: HTTPResponse
        do {
            plan = try await conditionalPlan(path: path, method: method, query: query, body: body, authenticated: authenticated)
            spec = OutgoingRequest(path: path, method: method, query: query, body: body,
                                   headers: headers.merging(plan?.validatorHeaders ?? [:]) { _, validator in validator },
                                   requestClass: requestClass, timeout: timeout, authenticated: authenticated, requestID: requestID)
            received = try await send(spec, context: context, generation: snapshot)
            response = try await resolveConditional(received, plan: plan)
            if !(200..<300).contains(response.statusCode) {
                received = try await resendAfterPrompt(failure(response, context: context), spec: spec, context: context, generation: snapshot)
                response = try await resolveConditional(received, plan: plan)
            }
        }
        catch let error as APIError { throw surfaced(error, context: context, generation: snapshot) }
        catch is CancellationError { throw CancellationError() }
        catch { throw surfaced(APIError.transport(error), context: context, generation: snapshot) }
        guard (200..<300).contains(response.statusCode) else { throw surfaced(failure(response, context: context), context: context, generation: snapshot) }
        let value: T
        do { value = try Self.decode(response, context: context) }
        catch let error as APIError { throw surfaced(error, context: context, generation: snapshot) }
        await recordConditional(received, plan: plan)
        try check(snapshot)
        return APIResponse(value: value, status: received.statusCode, headers: response.headers)
    }
    /// 00 §0 rule 5: a read the prompt cleared is sent once more, with the credential current now (`sendAttempt`); every
    /// other refusal is thrown, a security one carrying the prompt's outcome. A write is never resent (`refusedWrite`).
    private func resendAfterPrompt(_ error: APIError, spec: OutgoingRequest, context: ReasonCatalog.Context, generation snapshot: UUID) async throws -> HTTPResponse {
        guard spec.requestClass.isRead else { throw await refusedWrite(error, generation: snapshot) }
        guard let outcome = try await securityOutcome(for: error, isRead: true, generation: snapshot) else { throw error }
        guard outcome == .passed else { throw error.withSecurityOutcome(outcome) }
        return try await sendAttempt(spec, context: context, generation: snapshot)
    }
    /// 00 §2.4: only reads retry on their own — at most twice, after 1 s and 3 s plus jitter — and each wait is bound to the generation.
    private func send(_ spec: OutgoingRequest, context: ReasonCatalog.Context, generation snapshot: UUID) async throws -> HTTPResponse {
        guard spec.requestClass.retriesAutomatically else { return try await sendAttempt(spec, context: context, generation: snapshot) }
        for attempt in RequestPolicy.readRetryDelays.indices {
            let delay: Duration
            do {
                let response = try await sendAttempt(spec, context: context, generation: snapshot)
                guard let wait = retryDelay(after: RequestFailure(response: response), of: spec, attempt: attempt) else { return response }
                delay = wait
            } catch {
                guard let wait = retryDelay(after: RequestFailure(error: error), of: spec, attempt: attempt) else { throw error }
                delay = wait
            }
            try await pause(delay, generation: snapshot)
        }
        return try await sendAttempt(spec, context: context, generation: snapshot)
    }
    private func retryDelay(after failure: RequestFailure?, of spec: OutgoingRequest, attempt: Int) -> Duration? {
        guard let failure else { return nil }
        return spec.requestClass.automaticRetryDelay(after: failure, attempt: attempt, jitter: requestClock.jitter())
    }
    /// One send with the credential current at that moment. A JWT rejected before the handler ran (TOKEN_EXPIRED or an
    /// unknown 401, 00 §1.7.2 / §3.3) is refreshed once and the same bytes, X-Request-ID and Idempotency-Key go out again.
    /// Non-2xx replies are returned and network errors thrown unchanged; S0-06's keyed executor and S0-13's resend call it directly.
    func sendAttempt(_ spec: OutgoingRequest, context: ReasonCatalog.Context, generation snapshot: UUID) async throws -> HTTPResponse {
        let auth: Credential?
        if spec.authenticated { auth = try await validCredential() } else { auth = nil }
        try check(snapshot)
        let response = try await transmit(makeRequest(spec, credential: auth), generation: snapshot, requestClass: spec.requestClass)
        guard let rejected = expiredAccess(response, credential: auth, requestClass: spec.requestClass, context: context) else { return response }
        let fresh = try await validCredential(forceRefresh: true, rejectedAccess: rejected)
        try check(snapshot)
        return try await transmit(makeRequest(spec, credential: fresh), generation: snapshot, requestClass: spec.requestClass)
    }
    /// The rejected JWT access when this reply calls for one refresh-and-resend; nil otherwise.
    private func expiredAccess(_ response: HTTPResponse, credential: Credential?, requestClass: RequestClass, context: ReasonCatalog.Context) -> String? {
        guard response.statusCode == 401, requestClass.resendsAfterTokenRefresh, case .tokens(let tokens)? = credential,
              RequestPolicy.requiresTokenRefresh(status: 401, marker: ErrorEnvelope.decode(response.data)?.marker, context: context) else { return nil }
        return tokens.accessToken
    }
    /// The only call into `transport.data(for:)`: registered for cancelAll, late replies fenced by the generation (and a
    /// read's by the suspend epoch), transport errors thrown unchanged for classification. Hooks: S0-07 Date header,
    /// S0-11 suspend, S0-19 request log (one line per attempt; cancelled attempts are not logged).
    func transmit(_ request: URLRequest, generation snapshot: UUID, requestClass: RequestClass) async throws -> HTTPResponse {
        try check(snapshot)
        let transport = transport
        let task = Task { try await transport.data(for: request) }
        let id = register(suspendable: requestClass.isRead) { task.cancel() }
        let started = epoch
        defer { removeCancellation(id) }
        do {
            let response = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            // Error replies and 304 carry a Date too; a reply after cancelAll still came from this site.
            serverClock.recordDateHeader(response.header("Date"), receivedAt: serverClock.localNow())
            RequestLog.record(request, response: response)
            try check(snapshot)
            if requestClass.isRead && started != epoch { throw CancellationError() }
            return response
        } catch {
            if snapshot != generation || Task.isCancelled || error is CancellationError || (requestClass.isRead && started != epoch) {
                throw CancellationError()
            }
            RequestLog.record(request, response: nil)
            throw error
        }
    }
    /// Waits on the request clock; cancelAll and suspend interrupt the wait, a changed generation fails it, and no wait
    /// starts while suspended (00 §2.4, D18).
    func pause(_ duration: Duration, generation snapshot: UUID) async throws {
        try check(snapshot)
        guard !isSuspended else { throw CancellationError() }
        let sleep = requestClock.sleep
        let task = Task { try await sleep(duration) }
        let id = register(suspendable: true) { task.cancel() }
        defer { removeCancellation(id) }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try check(snapshot)
    }
    /// The only HTTPResponse → APIError construction. A final TOKEN_EXPIRED means the one refresh-and-resend did not help, so it
    /// is the 00 §3.3 session-expired fallback; a 429 without seconds waits RetryAfter.rateLimitDefault (00 §2.7.2).
    func failure(_ response: HTTPResponse, context: ReasonCatalog.Context = .business) -> APIError {
        let error = APIError.from(response, context: context)
        if error.action == .refreshAndResend { return error.replacing(entry: ReasonCatalog.entry(status: 401, reason: nil)) }
        if error.statusCode == 429, error.retryAfter == nil { return error.replacing(retryAfter: RetryAfter.rateLimitDefault) }
        return error
    }
    /// Every APIError caused by a server reply or a refresh leaves through here, so this is the only place that reports an
    /// ended session (D06): once per generation, never for a generation already cancelled.
    func surfaced(_ error: APIError, context: ReasonCatalog.Context, generation snapshot: UUID) -> APIError {
        guard let onSessionInvalid, snapshot == generation, reportedInvalidation != snapshot,
              let invalidation = SessionInvalidation(error: error) else { return error }
        reportedInvalidation = snapshot
        onSessionInvalid(invalidation)
        return error
    }
    /// URL encoding lives only here, so S0-05 cache keys and real requests always agree.
    func endpointURL(_ path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: try server.validatedURL(), resolvingAgainstBaseURL: false) else { throw APIError.invalidServer }
        let items = RequestPolicy.sanitizedQuery(query)
        components.path = "/api/v1/" + path; components.queryItems = items.isEmpty ? nil : items
        // URLQueryItem leaves "+" as is and Go reads it as a space (00 §2.8), in a search term as much as in an offset.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw APIError.invalidServer }
        return url
    }
    /// 00 §2.2: caller headers first, then the identity, idempotency and credential headers that only the client may set.
    private func makeRequest(_ spec: OutgoingRequest, credential: Credential?) throws -> URLRequest {
        var request = URLRequest(url: try endpointURL(spec.path, query: spec.query))
        request.httpMethod = spec.method; request.httpBody = spec.body
        request.timeoutInterval = spec.timeout ?? spec.requestClass.defaultTimeout
        for (name, value) in spec.headers where !RequestPolicy.isReserved(name) { request.setValue(value, forHTTPHeaderField: name) }
        if request.value(forHTTPHeaderField: "Accept") == nil { request.setValue("application/json", forHTTPHeaderField: "Accept") }
        request.setValue(RequestPolicy.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        request.setValue(deviceIDHeader, forHTTPHeaderField: "X-Device-ID")
        if let requestID = spec.requestID { request.setValue(requestID, forHTTPHeaderField: "X-Request-ID") }
        if let key = spec.requestClass.idempotencyKey { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        if spec.body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        switch credential {
        case .adminKey(let key), .accessToken(let key): request.setValue(key, forHTTPHeaderField: "x-api-key")
        case .tokens(let tokens): request.setValue("Bearer " + tokens.accessToken, forHTTPHeaderField: "Authorization")
        case nil: break
        }
        return request
    }
    private func register(suspendable: Bool = false, _ cancel: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID(); cancellations[id] = Cancellation(suspendable: suspendable, cancel: cancel); return id
    }

    // MARK: Account test stream

    /// SSE goes through makeRequest too; a JWT expired before the handler ran is refreshed and the same bytes reopened once.
    private func openTestStream(_ spec: OutgoingRequest, generation snapshot: UUID) async throws -> HTTPStreamResponse {
        let auth = try await validCredential()
        try check(snapshot)
        let first = try await openStream(makeRequest(spec, credential: auth), generation: snapshot)
        guard let rejected = try await rejection(first, generation: snapshot) else { return first }
        guard let access = expiredAccess(rejected, credential: auth, requestClass: spec.requestClass, context: .business) else { throw failure(rejected) }
        let fresh = try await validCredential(forceRefresh: true, rejectedAccess: access)
        try check(snapshot)
        let second = try await openStream(makeRequest(spec, credential: fresh), generation: snapshot)
        if let rejectedAgain = try await rejection(second, generation: snapshot) { throw failure(rejectedAgain) }
        return second
    }
    /// nil for 2xx; otherwise the first 64 KB of the error body, read under the session generation.
    private func rejection(_ response: HTTPStreamResponse, generation snapshot: UUID) async throws -> HTTPResponse? {
        guard !(200..<300).contains(response.statusCode) else { return nil }
        let id = register(suspendable: true) { response.cancel() }
        defer { removeCancellation(id); response.cancel() }
        var body = Data()
        for try await chunk in response.bytes {
            try check(snapshot)
            body.append(chunk); if body.count > 64 * 1_024 { break }
        }
        try check(snapshot)
        return HTTPResponse(statusCode: response.statusCode, headers: response.headers, data: body)
    }
    private func events(from response: HTTPStreamResponse, generation snapshot: UUID) -> AsyncThrowingStream<AccountTestEvent, any Error> {
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
        cancellations[streamID] = Cancellation(suspendable: true) { task.cancel(); response.cancel() }
        pair.continuation.onTermination = { _ in task.cancel(); response.cancel() }
        return pair.stream
    }
    private func openStream(_ request: URLRequest, generation snapshot: UUID) async throws -> HTTPStreamResponse {
        let transport = transport
        let task = Task { try await transport.stream(for: request) }
        let id = register(suspendable: true) { task.cancel() }
        defer { removeCancellation(id) }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            serverClock.recordDateHeader(result.headers.headerValue("Date"), receivedAt: serverClock.localNow())
            RequestLog.record(request, response: HTTPResponse(statusCode: result.statusCode, headers: result.headers, data: Data()))
            do { try check(snapshot) } catch { result.cancel(); throw error }
            return result
        } catch is CancellationError { throw CancellationError() }
        catch {
            if snapshot != generation || Task.isCancelled { throw CancellationError() }
            RequestLog.record(request, response: nil)
            throw APIError.transport(error)
        }
    }

    /// Non-2xx and 2xx with a non-zero code become catalog errors; a success body is parsed exactly once.
    static func decode<T: Decodable & Sendable>(_ response: HTTPResponse, context: ReasonCatalog.Context = .business) throws -> T {
        guard (200..<300).contains(response.statusCode) else { throw APIError.from(response, context: context) }
        let envelope: Envelope<T>
        do { envelope = try JSONDecoder().decode(Envelope<T>.self, from: response.data) }
        catch let error as APIError { throw error } // Models may reject a payload with their own error (page counters).
        catch { throw APIError.invalidResponse }
        guard envelope.status.code != nil else { throw APIError.invalidResponse }
        guard envelope.status.isSuccess else { throw APIError.from(response, context: context) }
        if T.self == EmptyReply.self { return EmptyReply() as! T }
        guard let result = envelope.data else { throw APIError.invalidResponse }
        return result
    }
    func check(_ snapshot: UUID) throws { try Task.checkCancellation(); guard snapshot == generation else { throw CancellationError() } }
    func currentGeneration() -> UUID { generation }
    private func removeCancellation(_ id: UUID) { cancellations[id] = nil }
    private func validTOTP(_ code: String) -> Bool { OneTimeCode.isComplete(code) }
    func validID(_ value: Int) throws -> Int {
        guard value > 0 else { throw APIError(kind: .validation, message: "无效的对象编号。") }; return value
    }
    /// 00 §4.1: 1–1000; Debug asserts, Release clamps (the server would silently fall back to 20).
    func pagination(_ page: Int, pageSize: Int = PageSize.standard, search: String, status: String?) throws -> [URLQueryItem] {
        guard page >= 1 else { throw APIError(kind: .validation, message: "页码必须从 1 开始。") }
        assert((1...PageSize.maximum).contains(pageSize), "page_size must stay within 1...1000")
        return [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "page_size", value: String(PageSize.clamped(pageSize)))]
            + optionalQuery("search", search.trimmingCharacters(in: .whitespacesAndNewlines)) + optionalQuery("status", status)
    }
    func optionalQuery(_ name: String, _ value: String?) -> [URLQueryItem] {
        guard let value, !value.isEmpty else { return [] }; return [URLQueryItem(name: name, value: value)]
    }
    /// Day parameters follow the server's calendar and clock (00 §2.8, §6.3), never the phone's.
    private func dateRange(days: Int) -> [URLQueryItem] { serverZone.lastDaysQueryItems(days, now: serverClock.now()) }
    private func monthRange() -> [URLQueryItem] { serverZone.monthToDateQueryItems(now: serverClock.now()) }
    func encode<T: Encodable>(_ value: T) throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return try e.encode(value) }
}

/// Reads `code` / `reason` through `ErrorEnvelope`; `data` is decoded only for a successful, non-empty reply.
private struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
    let status: ErrorEnvelope
    let data: T?
    init(from decoder: any Decoder) throws {
        status = try ErrorEnvelope(from: decoder)
        guard status.isSuccess, T.self != EmptyReply.self else { data = nil; return }
        data = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(T.self, forKey: .data)
    }
    private enum CodingKeys: String, CodingKey { case data }
}
struct EmptyReply: Decodable, Sendable {}
/// A registered in-flight request, wait or stream; `suspend()` stops only the suspendable ones.
private struct Cancellation: Sendable {
    let suspendable: Bool
    let cancel: @Sendable () -> Void
}
/// `query.timezone` decides how the offset-less buckets are read (00 §6.4); a malformed block is ignored.
private struct TrendReply: Decodable, Sendable {
    let trend: [TrendPoint]
    let query: QueryMetadata?
    enum CodingKeys: String, CodingKey { case trend, query }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trend = try c.decode([TrendPoint].self, forKey: .trend)
        query = try? c.decodeIfPresent(QueryMetadata.self, forKey: .query)
    }
}
private struct DashboardStatsSnapshotReply: Decodable, Sendable { let stats: DashboardStats? }
private struct OpsReply: Decodable, Sendable {
    let errorRate: Double?
    let qps: Rate?
    struct Rate: Decodable, Sendable { let current: Double? }
    enum CodingKeys: String, CodingKey { case errorRate = "error_rate", qps }
}
private struct RefreshReply: Decodable, Sendable {
    let accessToken: String; let refreshToken: String; let expiresIn: Int?
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in" }
}
