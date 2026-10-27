import Foundation
import Sub2Core

// Fixtures are reachable only through the explicit -ui-testing launch argument.
enum DemoData {
    /// The only server zone in UI fixtures (D30); trend buckets and the AdminMe fixture use it.
    static let serverTimeZone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
    /// The password login's fixture session; it never expires, so nothing is refreshed. R18 (S1-09): `-ui-refresh-unavailable`
    /// signs in without a refresh token, its access valid for two hours, so the overview shows the renewal banner.
    static var passwordTokens: TokenPair {
        guard ProcessInfo.processInfo.arguments.contains("-ui-refresh-unavailable") else {
            return TokenPair(accessToken: "ui-test-access", refreshToken: "ui-test-refresh", expiresAt: .distantFuture)
        }
        return TokenPair(accessToken: "ui-test-access", refreshToken: "", expiresAt: Date().addingTimeInterval(2 * 3_600))
    }
    static let passwordCredential = Credential.tokens(passwordTokens)
    /// Every capability, compliance accepted and step-up off, so all gated entries show (D30 zone). S0-13's launch
    /// arguments require compliance (`-ui-compliance-required`) or turn step-up on with TOTP (`-ui-step-up-required`) or
    /// without it (`-ui-step-up-no-totp`).
    static func adminMe(authMethod: AdminAuthMethod) -> AdminMe {
        let arguments = ProcessInfo.processInfo.arguments
        let totp = arguments.contains("-ui-step-up-required"), stepUp = totp || arguments.contains("-ui-step-up-no-totp")
        let compliance = arguments.contains("-ui-compliance-required")
        // S1-08: -ui-ops-disabled (setting_off) and -ui-ops-config-off (config_off), as FixtureLiveOpsSource starts.
        let ops = OpsFixtureSwitch.from(arguments: arguments)
        return AdminMe(authMethod: authMethod, user: .init(id: 1, email: "admin@example.com", username: "管理员", role: "admin"),
                security: .init(totpEnabled: totp, stepUpEnabled: stepUp, stepUpAvailable: totp && authMethod == .jwt, stepUpGranted: false,
                                sessionBindingEnabled: false),
                compliance: .init(required: compliance, version: compliance ? complianceStatus.version : nil),
                features: .init(opsMonitoringEnabled: ops == .on, opsRealtimeMonitoringEnabled: ops == .on,
                                opsMonitoringDisabledReason: ops.disabledReason, channelMonitorEnabled: false,
                                backendModeEnabled: false, paymentEnabled: false, subscriptionEnabled: false),
                server: .init(version: "ui-test", runMode: "standard", serverTimezone: serverTimeZone.identifier,
                              serverUTCOffset: serverTimeZone.rawUTCOffset,
                              capabilities: Set(Capability.allCases.map(\.rawValue)).subtracting(withheldCapabilities(arguments: arguments))))
    }
    /// X05: `-ui-without-capabilities a,b` takes those raw values out of the fixture site's capabilities; chapters build
    /// their old-server and missing-capability fixtures with it instead of adding arguments here.
    static func withheldCapabilities(arguments: [String]) -> Set<String> { UITestArguments.withheldCapabilities(arguments: arguments) }
    /// `GET admin/compliance` of the compliance fixture; the document is never opened by the tests.
    static let complianceStatus = AdminComplianceStatus(required: true, version: "2026-06", documentPathZH: "docs/legal/admin-compliance.zh.md",
                                                        documentURLZH: "https://example.invalid/admin-compliance.zh.md",
                                                        ackPhraseZH: "我已阅读、理解并同意 Sub2API 部署与运营合规承诺")
    /// The simulator never shows the system prompt: checks pass unless `-ui-biometric-deny`, and `-ui-biometric-unavailable`
    /// stands for a phone without Face ID or a lock screen code. `-ui-faceid-on` starts with the switch on.
    @MainActor static func biometricAuthenticator(_ preferences: AppPreferences) -> FixedBiometricAuthenticator {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-faceid-on") { preferences.storeFaceIDRequirement(true) }
        return FixedBiometricAuthenticator(isAvailable: !arguments.contains("-ui-biometric-unavailable"),
                                           succeeds: !arguments.contains("-ui-biometric-deny"))
    }
    /// Settings → 当前站点 counts (60 §3.6); the fixture sends no request.
    static let authSessionCount = 3
    static let accessTokenCount = 2
    /// `-ui-pending-money` (60 §3.3 柒): a refund and a redeem batch of the first connected site, and a compensation of a
    /// deleted site that is kept for its record. `-ui-pending-unreadable` also marks the batch file unreadable.
    static let archivedPendingSite = ServerProfile(id: UUID(uuidString: "6B1F3C2A-0D4E-4F5A-8B9C-1D2E3F4A5B6C")!, name: "旧站点",
                                                   baseURL: URL(string: "https://old.example.invalid")!, authentication: .password)
    static func pendingLedger(serverID: UUID, now: Date) -> PendingMoneyLedger? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ui-pending-money") else { return nil }
        let created = now.addingTimeInterval(-300)
        // D17: the fixture administrator is user 1; `-ui-pending-other-actor` and `-ui-pending-actor-unknown` change the sender.
        let actor: Int? = arguments.contains("-ui-pending-actor-unknown") ? nil : arguments.contains("-ui-pending-other-actor") ? 2 : 1
        let refund = PendingBalanceOperation(id: UUID(uuidString: "0A000000-0000-4000-8000-000000000001")!, serverID: serverID, userID: 1,
                                             amount: Decimal(string: "12.5")!, operation: .subtract, actorUserID: actor, createdAt: created,
                                             userDisplayName: "Alice", userEmail: "alice@example.com")
        let batch = PendingRedeemBatch(id: UUID(uuidString: "0A000000-0000-4000-8000-000000000002")!, serverID: serverID, actorUserID: 1,
                                       createdAt: created, spec: RedeemGenerateSpec(type: .balance, value: 10, count: 20))
        let grant = PendingCompensation(id: UUID(uuidString: "0A000000-0000-4000-8000-000000000003")!, serverID: archivedPendingSite.id,
                                        actorUserID: 1, createdAt: created, userID: 3, userDisplayName: "王小明", userEmail: "wang@example.com",
                                        code: "FIXTURE-GRANT-0001", type: .balance, value: 10)
        let unreadable: Set<PendingMoneyKind> = arguments.contains("-ui-pending-unreadable") ? [.redeemBatch] : []
        return PendingMoneyLedger(balances: [refund], redeemBatches: unreadable.isEmpty ? [batch] : [], compensations: [grant],
                                  unreadable: unreadable)
    }
    /// Access tokens write unless `-ui-readonly-token` is passed (kept for S0-13 and S0-19).
    static func siteSession(credential: Credential) -> SiteSession {
        let method = AdminAuthMethod.resolved(reported: nil, credential: credential) ?? .jwt
        let scope = ProcessInfo.processInfo.arguments.contains("-ui-readonly-token") ? "read" : "write"
        return SiteSession(me: adminMe(authMethod: method), credential: credential, accessTokenScope: scope,
                           serverTimeZone: serverTimeZone, clockOffset: 0, probedAt: Date())
    }
    /// `-ui-switch-rejected` (S0-19): switching sites is refused with a permission error that keeps the session, so the root
    /// alert shows it with its details.
    static var switchRefusal: APIError? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-switch-rejected") else { return nil }
        return APIError.server(status: 403, envelope: ErrorEnvelope(reason: "FORBIDDEN"), requestID: "ui-fixture-request-id")
    }
    /// `-ui-slow-teardown` (D19): a deleted site's server steps take two seconds, so the settings row in progress shows.
    static var teardownDelay: Duration? {
        ProcessInfo.processInfo.arguments.contains("-ui-slow-teardown") ? .seconds(2) : nil
    }
    static let dashboard = DashboardSummary(
        stats: DashboardStats(
            todayRequests: 128, todayTokens: 1_234_567, todayCost: Decimal(string: "99.99")!,
            totalUsers: 22, totalAccounts: 8, errorAccounts: 1, rpm: 1234, tpm: 987_654,
            todayActualCost: Decimal(string: "12.34")!, todayAccountCost: Decimal(string: "4.56")!,
            totalActualCost: Decimal(string: "1234.56")!, totalAccountCost: Decimal(string: "456.78")!,
            totalTokens: 9_876_543_210, averageDurationMs: 1250, totalRequests: 213_009_545, rpmAvailable: true),
        trend: [
            TrendPoint(date: "2026-10-14 22:00", requests: 90, totalTokens: 32_000, cost: Decimal(string: "0.80")!, actualCost: Decimal(string: "0.31")!),
            TrendPoint(date: "2026-10-15 00:00", requests: 128, totalTokens: 54_000, cost: Decimal(string: "1.25")!, actualCost: Decimal(string: "0.52")!),
            TrendPoint(date: "2026-10-15 02:00", requests: 64, totalTokens: 27_000, cost: Decimal(string: "0.63")!, actualCost: Decimal(string: "0.27")!)])
    static let longHourlyTrend: [TrendPoint] = (0..<36).map { hour in
        let date = String(format: "2026-10-%02d %02d:00", 14 + hour / 24, hour % 24)
        let actual = Decimal(string: "0.10000001")! + Decimal(hour) / 1_000
        return TrendPoint(date: date, requests: 100 + hour * 3, totalTokens: 1_000_000 + hour * 12_345,
                          cost: actual + 9, actualCost: actual)
    }
}

/// The login page's `-ui-testing` site (60 §4). `settings/public` needs no captcha and names the site “Sub2 演示站” unless
/// `-ui-login-captcha` (turnstile, no packaged page), `-ui-login-captcha-conflict`, `-ui-login-agreement-checkbox`,
/// `-ui-login-agreement-modal`, `-ui-login-backend-mode` or `-ui-login-no-site-name` say otherwise. The email prefixes 2fa@,
/// wrong@, busy@ and disabled@ pick the answer; the second factor takes 123456, refuses 000000, expires on 999999 and is
/// rate limited for 5 seconds on 429429.
struct DemoLoginGateway: LoginGateway {
    private let arguments: [String]
    init(arguments: [String] = ProcessInfo.processInfo.arguments) { self.arguments = arguments }

    func publicSettings() async throws -> PublicSettings {
        var fields: [String: Any] = ["version": "ui-fixture", "site_name": arguments.contains("-ui-login-no-site-name") ? "" : "Sub2 演示站",
                                     "captcha_provider": "", "mobile_verify_path": "/mobile/verify",
                                     "backend_mode_enabled": arguments.contains("-ui-login-backend-mode")]
        if arguments.contains("-ui-login-captcha") { fields["captcha_provider"] = "turnstile"; fields["mobile_verify_path"] = "" }
        if arguments.contains("-ui-login-captcha-conflict") { fields["captcha_provider"] = "conflict" }
        let checkbox = arguments.contains("-ui-login-agreement-checkbox")
        if checkbox || arguments.contains("-ui-login-agreement-modal") {
            fields["login_agreement_enabled"] = true
            fields["login_agreement_mode"] = checkbox ? "checkbox" : "modal"
            fields["login_agreement_revision"] = "ui-r1"
            fields["login_agreement_documents"] = [["id": "terms", "title": "服务条款", "content_md": "**欢迎使用**\n\n请遵守站点规则。"]]
        }
        return try JSONDecoder().decode(PublicSettings.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func login(email: String, password: String, proof: CaptchaProof?, deviceName: String, declaresCaptchaProvider: Bool) async throws -> LoginResult {
        let name = email.lowercased()
        if name.hasPrefix("2fa@") { return .twoFactor(TwoFactorChallenge(tempToken: "ui-temp", maskedEmail: "2***@example.com")) }
        if name.hasPrefix("wrong@") { throw Self.failure(401, "INVALID_CREDENTIALS") }
        if name.hasPrefix("busy@") { throw Self.failure(429, "RATE_LIMITED", retryAfter: 3) }
        if name.hasPrefix("disabled@") { throw Self.failure(403, "USER_NOT_ACTIVE") }
        if arguments.contains("-ui-login-captcha"), proof == nil { throw Self.failure(400, "TURNSTILE_VERIFICATION_FAILED") }
        return .authenticated(Self.session)
    }
    func completeTOTP(tempToken: String, code: String) async throws -> AuthSession {
        switch code {
        case "123456": return Self.session
        case "999999": throw Self.failure(400, "TOTP_LOGIN_SESSION_EXPIRED", context: .twoFactor)
        case "429429": throw Self.failure(429, "RATE_LIMITED", context: .twoFactor, retryAfter: 5)
        default: throw Self.failure(400, "TOTP_INVALID_CODE", context: .twoFactor)
        }
    }
    func cancelAll() async {}

    private static let session = AuthSession(user: AdminUser(id: 1, email: "admin@example.com", username: "管理员", role: "admin"),
                                             tokens: DemoData.passwordTokens)
    private static func failure(_ status: Int, _ reason: String, context: ReasonCatalog.Context = .login, retryAfter: Int? = nil) -> APIError {
        APIError.server(status: status, envelope: ErrorEnvelope(reason: reason, retryAfter: retryAfter), context: context, retryAfter: retryAfter)
    }
}
