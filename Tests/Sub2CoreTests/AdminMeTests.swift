import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// Private stubs keep names clear of the shared request test support added later.
private actor AdminMeTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> HTTPResponse
    private let handler: Handler
    private var seen = [URLRequest]()
    init(handler: @escaping Handler) { self.handler = handler }
    func data(for request: URLRequest) async throws -> HTTPResponse { seen.append(request); return try await handler(request) }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { seen.append(request); throw APIError.invalidResponse }
    func requests() -> [URLRequest] { seen }
    func paths() -> [String] { seen.compactMap { $0.url?.path } }
}
/// Opens once the expected number of callers has arrived. A serial caller never gets there, so a watchdog
/// releases everyone after a deadline and records it; continuations ignore cancellation and would otherwise hang.
private actor ArrivalGate {
    private let expected: Int
    private var arrived = 0
    private var isOpen = false
    private(set) var expired = false
    private var waiters = [CheckedContinuation<Void, Never>]()
    init(expected: Int) { self.expected = expected }
    func arrive() async {
        arrived += 1
        if arrived >= expected { open() }
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func expire() { if !isOpen { expired = true; open() } }
    private func open() { isOpen = true; let pending = waiters; waiters.removeAll(); for waiter in pending { waiter.resume() } }
}
private actor MeGate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; let pending = waiters; waiters.removeAll(); for waiter in pending { waiter.resume() } }
}

private func meSuccess(_ json: String) -> HTTPResponse { HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":\(json)}".utf8)) }
private func meReply(_ status: Int, _ body: String, contentType: String = "application/json") -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: ["content-type": contentType], data: Data(body.utf8))
}
private let gatewayNotFound = meReply(404, "404 page not found", contentType: "text/plain")
private func meServer() -> ServerProfile { ServerProfile(name: "me", baseURL: URL(string: "https://me.example.invalid")!, authentication: .password) }
private func meTokens() -> Credential {
    .tokens(TokenPair(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: Date().addingTimeInterval(3_600)))
}
private func meError(_ operation: () async throws -> Void) async -> (any Error)? {
    do { try await operation(); return nil } catch { return error }
}

private let fullMeJSON = #"""
{"auth_method":"admin_access_token","user":{"id":1,"email":"owner@example.invalid","username":"站长","role":"admin"},"workspace":null,
"security":{"totp_enabled":true,"step_up_enabled":true,"step_up_available":false,"step_up_granted":false,"step_up_expires_in":0,"session_binding_enabled":true},
"compliance":{"required":true,"version":"2026-06"},
"features":{"ops_monitoring_enabled":false,"ops_realtime_monitoring_enabled":false,"ops_monitoring_disabled_reason":"setting_off","channel_monitor_enabled":true,
"channel_monitor_mode":"passive","backend_mode_enabled":false,"payment_enabled":true,"subscription_enabled":false},
"server":{"version":"0.9.0","run_mode":"simple","server_timezone":"Asia/Shanghai","server_utc_offset":"+08:00",
"capabilities":["dashboard.rates","admin.access_tokens","future.feature"]}}
"""#
private let legacyAuthMeJSON = #"{"id":7,"email":"admin@example.invalid","username":"管理员","role":"admin","balance":"1","status":"active","run_mode":"simple"}"#
private let legacySettingsJSON = #"""
{"version":"0.8.1","server_timezone":"Asia/Shanghai","server_utc_offset":"+08:00","channel_monitor_enabled":true,"channel_monitor_mode":"active",
"backend_mode_enabled":true,"payment_enabled":false,"subscription_enabled":true,"captcha_provider":""}
"""#
private let complianceJSON = #"{"required":true,"version":"2026-06","document_path_zh":"/legal/admin-zh","ack_phrase_zh":"我已阅读并同意"}"#

/// Copied verbatim from backend me_handler.go adminMeCapabilities (57) and adminMeEmbeddedWebCapabilities (1).
private let backendCapabilities: Set<String> = [
    "accounts.apply_oauth_preserve_status", "accounts.clear_error_preserve_inactive", "accounts.list_query", "accounts.mixed_channel_details",
    "accounts.oauth_error_reasons", "accounts.patch", "accounts.reauthorize", "accounts.recover_schedulable", "accounts.runtime_batch",
    "admin.access_tokens", "admin.idempotent_writes", "accounts.status_summary", "accounts.structured_error", "accounts.test_result",
    "accounts.test_runs", "accounts.today_stats_failures", "accounts.today_stats_group", "accounts.token_status",
    "announcements.idempotent_create", "announcements.read_stats", "api_keys.current_concurrency", "api_keys.effective_status",
    "api_keys.masked_view", "auth.captcha_provider", "dashboard.account_cost", "dashboard.accounts_ranking", "dashboard.home",
    "dashboard.rates", "dashboard.request_types", "dashboard.users_ranking_sort", "dashboard.users_trend_filtered_metric",
    "groups.account_buckets", "groups.capacity_filter", "groups.member_batch", "lists.etag", "logs.since_id", "meta.catalog",
    "ops.alert_event_counts", "ops.alert_event_details", "ops.alert_latency_metrics", "ops.dashboard_model_filter",
    "ops.ingress_reject_totals", "ops.job_heartbeat_status", "ops.monitoring_status", "ops.request_attempts",
    "ops.system_metrics_history", "ops.token_stats_custom_range", "proxies.fallback_accounts", "push.notifications",
    "redeem_codes.delete_guard", "redeem_codes.stats", "scheduled_tests.upstream_status", "usage.model_source",
    "users.balance_ledger", "users.platform_quota_item", "users.quick_topup", "users.rpm_tracked",
    "web.accounts_edit_deep_link"
]

@Test func adminMeDecodesEveryDocumentedField() throws {
    let me = try JSONDecoder().decode(AdminMe.self, from: Data(fullMeJSON.utf8))
    #expect(me.authMethod == .adminAccessToken)
    #expect(me.user?.email == "owner@example.invalid"); #expect(me.user?.role == "admin"); #expect(me.workspace == nil)
    #expect(me.security.stepUpExpiresIn == 0); #expect(me.security.sessionBindingEnabled == true); #expect(me.security.stepUpAvailable == false)
    #expect(me.compliance.required == true); #expect(me.compliance.version == "2026-06")
    #expect(me.features.opsMonitoringDisabledReason == "setting_off"); #expect(me.features.channelMonitorMode == "passive")
    #expect(me.features.paymentEnabled == true); #expect(me.features.subscriptionEnabled == false)
    #expect(me.server.runMode == "simple"); #expect(me.server.serverTimezone == "Asia/Shanghai"); #expect(me.server.serverUTCOffset == "+08:00")
    #expect(me.capabilities.count == 3); #expect(me.has(.dashboardRates)); #expect(me.has(.adminAccessTokens)); #expect(!me.has(.logsSinceID))
    #expect(!me.isLegacyServer)
}

@Test func adminMeDecodesEmptyObjectAsUnknownNotZero() throws {
    let me = try JSONDecoder().decode(AdminMe.self, from: Data("{}".utf8))
    #expect(me.authMethod == nil); #expect(me.user == nil); #expect(me.workspace == nil)
    #expect(me.security.totpEnabled == nil); #expect(me.security.stepUpExpiresIn == nil); #expect(me.compliance.required == nil)
    #expect(me.features.opsMonitoringEnabled == nil); #expect(me.features.backendModeEnabled == nil)
    #expect(me.server.version == nil); #expect(me.capabilities.isEmpty); #expect(!me.isLegacyServer)
    let nulls = try JSONDecoder().decode(AdminMe.self, from: Data(#"{"security":null,"features":null,"server":{"capabilities":null}}"#.utf8))
    #expect(nulls.capabilities.isEmpty); #expect(nulls.security == AdminMe.Security())
}

@Test func adminMeKeepsUnknownCapabilityAndAuthMethod() throws {
    let me = try JSONDecoder().decode(AdminMe.self, from: Data(fullMeJSON.utf8))
    #expect(me.capabilities.contains("future.feature")); #expect(Capability(rawValue: "future.feature") == nil)
    let passkey = try JSONDecoder().decode(AdminMe.self, from: Data(#"{"auth_method":"passkey"}"#.utf8))
    #expect(passkey.authMethod == .other("passkey")); #expect(passkey.authMethod?.isMachineCredential == false)
    #expect(AdminAuthMethod(rawValue: "admin_api_key").isMachineCredential); #expect(AdminAuthMethod(rawValue: "admin_access_token").isMachineCredential)
    #expect(!AdminAuthMethod.jwt.isMachineCredential); #expect(AdminAuthMethod.adminAPIKey.rawValue == "admin_api_key")
}

@Test func capabilityEnumMatchesBackendListOf58() {
    let raw = Capability.allCases.map(\.rawValue)
    #expect(raw.count == 58); #expect(Set(raw).count == 58)
    #expect(Set(raw) == backendCapabilities)
}

@Test func administratorRuleFollowsRoleWorkspaceAndMachineCredential() {
    let admin = AdminMe.User(id: 1, email: "a@example.invalid", role: "admin")
    let workspace = AdminMe.Workspace(id: 3, name: "代运营")
    let cases: [(AdminMe, Bool)] = [
        (AdminMe(authMethod: .jwt, user: admin), true),
        (AdminMe(authMethod: .jwt, user: AdminMe.User(id: 2, role: "vendor"), workspace: workspace), false),
        (AdminMe(authMethod: .jwt, user: admin, workspace: workspace), false),
        (AdminMe(authMethod: .jwt), false),
        (AdminMe(authMethod: .adminAPIKey), true),
        (AdminMe(authMethod: .adminAccessToken, user: admin), true),
        (AdminMe(authMethod: .adminAccessToken, user: AdminMe.User(id: 4, role: "user")), false),
        (AdminMe(authMethod: .adminAPIKey, user: AdminMe.User(id: 5)), false),
        (AdminMe(), false)
    ]
    for (index, item) in cases.enumerated() { #expect(item.0.isAdministrator == item.1, "case \(index)") }
}

@Test func meRequestsAdminMeOnceWithBearerAndNoRealtimeProbe() async throws {
    let transport = AdminMeTransport { request in
        guard request.url?.path == "/api/v1/admin/me" else { throw URLError(.badURL) }
        return meSuccess(fullMeJSON)
    }
    let me = try await APIClient(server: meServer(), credential: meTokens(), transport: transport).me()
    let requests = await transport.requests()
    #expect(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.httpMethod == "GET"); #expect(request.timeoutInterval == 15)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
    #expect(!me.isLegacyServer); #expect(me.has(.dashboardRates))
}

@Test(arguments: [Credential.adminKey("fixture-key"), .accessToken("sat_fixture")])
func meSendsAPIKeyCredentialsOnlyInXAPIKeyHeader(credential: Credential) async throws {
    let transport = AdminMeTransport { _ in meSuccess(fullMeJSON) }
    _ = try await APIClient(server: meServer(), credential: credential, transport: transport).me()
    let request = try #require(await transport.requests().first)
    let expected: String
    switch credential { case .adminKey(let key), .accessToken(let key): expected = key; case .tokens: expected = "" }
    #expect(request.url?.path == "/api/v1/admin/me")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == expected)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func meRejectsBlankAPIKeyWithoutNetwork() async {
    for credential in [Credential.adminKey("  \n"), .accessToken(""), nil] {
        let transport = AdminMeTransport { _ in meSuccess(fullMeJSON) }
        let error = await meError { _ = try await APIClient(server: meServer(), credential: credential, transport: transport).me() }
        #expect(error as? APIError == .authenticationRequired)
        #expect(await transport.requests().isEmpty)
    }
}

@Test func legacyJWTFallbackRequestsThreeProbesConcurrently() async throws {
    let gate = ArrivalGate(expected: 3)
    let watchdog = Task { try await Task.sleep(for: .seconds(10)); await gate.expire() }
    defer { watchdog.cancel() }
    let transport = AdminMeTransport { request in
        switch request.url?.path {
        case "/api/v1/admin/me": return gatewayNotFound
        case "/api/v1/auth/me": await gate.arrive(); return meSuccess(legacyAuthMeJSON)
        case "/api/v1/settings/public": await gate.arrive(); return meSuccess(legacySettingsJSON)
        case "/api/v1/admin/compliance": await gate.arrive(); return meSuccess(complianceJSON)
        default: throw URLError(.badURL)
        }
    }
    let me = try await APIClient(server: meServer(), credential: meTokens(), transport: transport).me()
    #expect(await gate.expired == false, "the three legacy probes must be in flight together")
    let requests = await transport.requests()
    #expect(Set(requests.dropFirst().compactMap { $0.url?.path }) == ["/api/v1/auth/me", "/api/v1/settings/public", "/api/v1/admin/compliance"])
    #expect(requests.count == 4)
    let settings = try #require(requests.first { $0.url?.path == "/api/v1/settings/public" })
    #expect(settings.value(forHTTPHeaderField: "Authorization") == nil); #expect(settings.value(forHTTPHeaderField: "x-api-key") == nil)
    #expect(requests.first { $0.url?.path == "/api/v1/auth/me" }?.value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
    #expect(me.isLegacyServer); #expect(me.authMethod == .jwt); #expect(me.isAdministrator)
    #expect(me.user?.role == "admin"); #expect(me.user?.id == 7); #expect(me.server.runMode == "simple")
    #expect(me.server.version == "0.8.1"); #expect(me.server.serverTimezone == "Asia/Shanghai"); #expect(me.server.serverUTCOffset == "+08:00")
    #expect(me.features.channelMonitorEnabled == true); #expect(me.features.channelMonitorMode == "active"); #expect(me.features.backendModeEnabled == true)
    #expect(me.features.paymentEnabled == false); #expect(me.features.subscriptionEnabled == true)
    #expect(me.compliance.required == true); #expect(me.compliance.version == "2026-06")
    #expect(me.capabilities.isEmpty); #expect(me.features.opsMonitoringEnabled == true); #expect(me.features.opsRealtimeMonitoringEnabled == true)
    #expect(me.security == AdminMe.Security())
}

@Test func legacyJWTFallbackToleratesSettingsFailureAndPreComplianceServer() async throws {
    let transport = AdminMeTransport { request in
        switch request.url?.path {
        case "/api/v1/admin/me", "/api/v1/admin/compliance": return gatewayNotFound
        case "/api/v1/auth/me": return meSuccess(legacyAuthMeJSON)
        case "/api/v1/settings/public": return meReply(500, #"{"code":500,"reason":"INTERNAL_ERROR"}"#)
        default: throw URLError(.badURL)
        }
    }
    let me = try await APIClient(server: meServer(), credential: meTokens(), transport: transport).me()
    #expect(me.user?.email == "admin@example.invalid"); #expect(me.server.version == nil); #expect(me.compliance.required == nil)
    let paths = await transport.paths()
    #expect(me.isLegacyServer); #expect(!paths.contains("/api/v1/admin/dashboard/realtime"))
}

@Test func legacyJWTFallbackPropagatesAuthMeAndComplianceFailures() async {
    for (failingPath, reason) in [("/api/v1/auth/me", "INVALID_TOKEN"), ("/api/v1/admin/compliance", "FORBIDDEN")] {
        let transport = AdminMeTransport { request in
            let path = request.url?.path
            if path == "/api/v1/admin/me" { return gatewayNotFound }
            if path == failingPath { return meReply(failingPath.hasSuffix("auth/me") ? 401 : 403, "{\"code\":\"\(reason)\",\"reason\":\"\(reason)\"}") }
            if path == "/api/v1/auth/me" { return meSuccess(legacyAuthMeJSON) }
            if path == "/api/v1/settings/public" { return meSuccess(legacySettingsJSON) }
            return meSuccess(complianceJSON)
        }
        let error = await meError { _ = try await APIClient(server: meServer(), credential: meTokens(), transport: transport).me() }
        #expect((error as? APIError)?.reason == reason)
    }
}

@Test func legacyAdminKeyFallbackUsesComplianceProbe() async throws {
    let transport = AdminMeTransport { request in
        switch request.url?.path {
        case "/api/v1/admin/me": return gatewayNotFound
        case "/api/v1/admin/compliance": return meSuccess(complianceJSON)
        case "/api/v1/settings/public": return meSuccess(legacySettingsJSON)
        default: throw URLError(.badURL)
        }
    }
    let me = try await APIClient(server: meServer(), credential: .adminKey("fixture-key"), transport: transport).me()
    let requests = await transport.requests()
    let compliance = try #require(requests.first { $0.url?.path == "/api/v1/admin/compliance" })
    #expect(compliance.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
    #expect(!requests.contains { ["/api/v1/auth/me", "/api/v1/admin/dashboard/realtime"].contains($0.url?.path ?? "") })
    #expect(me.authMethod == .adminAPIKey); #expect(me.user == nil); #expect(me.isAdministrator); #expect(me.isLegacyServer)
    #expect(me.compliance.required == true); #expect(me.capabilities.isEmpty); #expect(me.server.serverTimezone == "Asia/Shanghai")
}

@Test func legacyAccessTokenOnOldServerSurfacesInvalidAdminKey() async {
    let transport = AdminMeTransport { request in
        switch request.url?.path {
        case "/api/v1/admin/me": return gatewayNotFound
        case "/api/v1/admin/compliance": return meReply(401, #"{"code":"INVALID_ADMIN_KEY","reason":"INVALID_ADMIN_KEY"}"#)
        default: return meSuccess(legacySettingsJSON)
        }
    }
    let error = await meError { _ = try await APIClient(server: meServer(), credential: .accessToken("sat_fixture"), transport: transport).me() }
    let paths = await transport.paths()
    #expect((error as? APIError)?.reason == "INVALID_ADMIN_KEY"); #expect(!paths.contains("/api/v1/admin/dashboard/realtime"))
}

@Test func legacyPreComplianceServerFallsBackToRealtimeProbe() async throws {
    for accepted in [true, false] {
        let transport = AdminMeTransport { request in
            switch request.url?.path {
            case "/api/v1/admin/me", "/api/v1/admin/compliance": return gatewayNotFound
            case "/api/v1/admin/dashboard/realtime":
                return accepted ? meSuccess(#"{"requests":0}"#) : meReply(401, #"{"code":"INVALID_ADMIN_KEY","reason":"INVALID_ADMIN_KEY"}"#)
            case "/api/v1/settings/public": return meSuccess(legacySettingsJSON)
            default: throw URLError(.badURL)
            }
        }
        let client = APIClient(server: meServer(), credential: .adminKey("fixture-key"), transport: transport)
        if accepted {
            let me = try await client.me()
            #expect(me.compliance.required == nil); #expect(me.isAdministrator); #expect(me.isLegacyServer)
            let realtime = try #require(await transport.requests().first { $0.url?.path == "/api/v1/admin/dashboard/realtime" })
            #expect(realtime.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
        } else {
            let error = await meError { _ = try await client.me() }
            #expect((error as? APIError)?.reason == "INVALID_ADMIN_KEY")
        }
    }
}

@Test(arguments: [(404, #"{"code":404,"reason":"NOT_FOUND"}"#), (403, #"{"code":"FORBIDDEN","reason":"FORBIDDEN"}"#),
                  (401, #"{"code":"INVALID_ADMIN_KEY","reason":"INVALID_ADMIN_KEY"}"#)])
func meDoesNotFallBackOnJSON404OrAuthErrors(status: Int, body: String) async {
    let transport = AdminMeTransport { _ in meReply(status, body) }
    let error = await meError { _ = try await APIClient(server: meServer(), credential: .adminKey("fixture-key"), transport: transport).me() }
    #expect((error as? APIError)?.statusCode == status)
    #expect(await transport.requests().count == 1)
}

@Test func meRejectsLateLegacyResultAfterCancelAll() async throws {
    let started = MeGate(), release = MeGate()
    let transport = AdminMeTransport { request in
        switch request.url?.path {
        case "/api/v1/admin/me": return gatewayNotFound
        case "/api/v1/auth/me": await started.open(); await release.wait(); return meSuccess(legacyAuthMeJSON)
        case "/api/v1/settings/public": return meSuccess(legacySettingsJSON)
        default: return meSuccess(complianceJSON)
        }
    }
    let client = APIClient(server: meServer(), credential: meTokens(), transport: transport)
    let pending = Task { try await client.me() }
    // If me() finishes without reaching auth/me, open the gate so the test fails instead of hanging.
    let watcher = Task { _ = try? await pending.value; await started.open() }
    await started.wait(); await client.cancelAll(); await release.open()
    _ = await watcher.value
    await #expect(throws: CancellationError.self) { _ = try await pending.value }
}

@Test func legacyAssemblyWithoutSourcesIsUnknownButAssumesMonitoringOn() {
    let me = AdminMe.legacy(authMethod: .adminAccessToken, authMe: nil, settings: nil, compliance: nil)
    #expect(me.isLegacyServer); #expect(me.user == nil); #expect(me.isAdministrator); #expect(me.capabilities.isEmpty)
    #expect(me.features.opsMonitoringEnabled == true); #expect(me.features.opsRealtimeMonitoringEnabled == true)
    #expect(me.features.backendModeEnabled == nil); #expect(me.server.version == nil); #expect(me.compliance == AdminMe.Compliance())
}

@Test func complianceStatusDecodesDocumentAndPhraseFields() async throws {
    let body = #"""
    {"required":true,"version":"2026-06","document_path_zh":"/legal/zh","document_path_en":"/legal/en","document_url_zh":"https://docs.example.invalid/zh",
    "document_url_en":"","ack_phrase_zh":"我已阅读并同意","ack_phrase_en":"I agree","acknowledgement":{"version":"2026-05","admin_user_id":1,"accepted_at":"2026-05-01T08:00:00Z"}}
    """#
    let transport = AdminMeTransport { _ in meSuccess(body) }
    let status = try await APIClient(server: meServer(), credential: .adminKey("fixture-key"), transport: transport).complianceStatus()
    let request = try #require(await transport.requests().first)
    #expect(request.url?.path == "/api/v1/admin/compliance"); #expect(request.httpMethod == "GET"); #expect(request.timeoutInterval == 15)
    #expect(status.required == true); #expect(status.version == "2026-06"); #expect(status.documentPathZH == "/legal/zh")
    #expect(status.documentURLZH == "https://docs.example.invalid/zh"); #expect(status.documentURLEN == ""); #expect(status.ackPhraseZH == "我已阅读并同意")
    #expect(status.ackPhraseEN == "I agree"); #expect(status.acknowledgement?.acceptedAt == "2026-05-01T08:00:00Z")
    let empty = try JSONDecoder().decode(AdminComplianceStatus.self, from: Data("{}".utf8))
    #expect(empty.required == nil); #expect(empty.ackPhraseZH == nil); #expect(empty.acknowledgement == nil)
}

@Test func accessTokensDecodeListAndCurrentReadScope() async throws {
    let body = #"""
    {"items":[{"id":11,"name":"监控","prefix":"sat_ab12","last4":"wxyz","scope":"read","expires_at":"2027-01-01T00:00:00Z","last_used_at":null,
    "last_used_ip":"","created_at":"2026-10-01T00:00:00Z","current":true},{"id":12,"name":"运维","scope":"write"}]}
    """#
    let transport = AdminMeTransport { _ in meSuccess(body) }
    let tokens = try await APIClient(server: meServer(), credential: .accessToken("sat_fixture"), transport: transport).accessTokens()
    let request = try #require(await transport.requests().first)
    #expect(request.url?.path == "/api/v1/admin/access-tokens"); #expect(request.value(forHTTPHeaderField: "x-api-key") == "sat_fixture")
    #expect(request.timeoutInterval == 15)
    #expect(tokens.count == 2); #expect(tokens.first { $0.current }?.isReadOnly == true); #expect(tokens.first?.lastUsedAt == nil)
    #expect(tokens.first?.prefix == "sat_ab12"); #expect(tokens.first?.expiresAt == "2027-01-01T00:00:00Z")
    #expect(tokens[1].current == false); #expect(tokens[1].isReadOnly == false); #expect(tokens[1].id == 12)
    for empty in [#"{"items":[]}"#, "{}"] {
        let client = APIClient(server: meServer(), credential: .accessToken("sat_fixture"), transport: AdminMeTransport { _ in meSuccess(empty) })
        #expect(try await client.accessTokens().isEmpty)
    }
}

@Test func accessTokenScopeFollowsBackendReadOnlyRule() throws {
    let decode = { (json: String) in try JSONDecoder().decode(AdminAccessToken.self, from: Data(json.utf8)) }
    #expect(try decode(#"{"id":1,"scope":"read"}"#).isReadOnly)
    #expect(try decode(#"{"id":1,"scope":"admin"}"#).isReadOnly)
    #expect(try decode(#"{"id":1,"scope":"write"}"#).isReadOnly == false)
    // Unknown scope is treated as writable until the server says ACCESS_TOKEN_READ_ONLY (00 §1.6).
    #expect(try decode(#"{"id":1}"#).isReadOnly == false)
}
