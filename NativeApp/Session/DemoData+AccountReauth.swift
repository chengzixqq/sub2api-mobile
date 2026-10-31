import Foundation
import Sub2Core

// S2-17 重新授权 fixtures: the session's AccountDemoStore answers generate-auth-url, reauthorize, and the exchange-code →
// apply-oauth-credentials fallback. Links point at made-up hosts; the callback platforms keep their real loopback redirects.

/// The authorization sessions one demo session has opened.
struct AccountOAuthFixtureState {
    /// session_id → platform.
    var sessions: [String: OAuthPlatform] = [:]
    /// Saved once: a replay returns the account, like the server's done mark (account_reauth_stash.go).
    var saved: Set<String> = []
    /// Sessions whose first save already failed under `reauthPersistFail`.
    var failedOnce: Set<String> = []
}

extension AccountDemoStore {
    /// Claude-官方-02 with a refused token (`tokenError`, stopped when it failed) or stopped (`tokenInactive`, switch on).
    static func tokenFixtures(_ rows: [UpstreamAccount], base: Date, arguments: [String]) -> [UpstreamAccount] {
        let refused = arguments.contains(DemoData.AccountFixture.tokenError), stopped = arguments.contains(DemoData.AccountFixture.tokenInactive)
        guard refused || stopped else { return rows }
        return rows.map { row in
            guard row.id == 2 else { return row }
            var account = row
            guard refused else { account.status = "inactive"; return account }
            account.status = "error"; account.schedulable = false
            account.errorKind = "auth"; account.errorStatusCode = 401
            account.errorMessage = "令牌已失效（401）"; account.errorSummary = "令牌已失效（401）"
            account.errorAt = ServerTime.utcTimestamp(base.addingTimeInterval(-120))
            return account
        }
    }

    /// `POST …/auth-url`: Claude's and Gemini Code Assist's pages show the code, the others call back to their loopback address.
    func authLink(_ request: OAuthLinkRequest) -> OAuthLink {
        let number = oauthSessions.sessions.count + 1
        let session = "demo-session-\(number)", state = "demo-state-\(number)"
        oauthSessions.sessions[session] = request.platform
        var components = URLComponents(string: "https://auth.example.invalid/\(request.platform.rawValue)/authorize")!
        components.queryItems = [URLQueryItem(name: "redirect_uri", value: Self.demoRedirect(request)), URLQueryItem(name: "state", value: state)]
        return OAuthLink(request: request, authURL: components.url!, sessionID: session, state: request.platform == .anthropic ? nil : state,
                         lifetime: OAuthLinkLifetime(generatedAt: .now))
    }

    /// `POST :id/reauthorize`, checked like prepareReauthorize; `reauthPersistFail` fails each session's first save.
    func reauthorize(id: Int, request: AccountReauthorizeRequest, now: Date, arguments: [String]) throws -> UpstreamAccount {
        guard let account = account(id: id) else { throw APIError.server(status: 404, reason: AccountWriteReason.notFound) }
        guard account.isTokenAccount else { throw APIError.server(status: 400, reason: "NOT_OAUTH") }
        if arguments.contains(DemoData.AccountFixture.reauthUnsupported) {
            throw APIError.server(status: 400, envelope: ErrorEnvelope(reason: "REAUTH_UNSUPPORTED", metadata: ["detail": "shadow_account"]))
        }
        try checkSession(request.sessionID, platform: account.platform)
        if oauthSessions.saved.contains(request.sessionID) { return account }
        if arguments.contains(DemoData.AccountFixture.reauthPersistFail), oauthSessions.failedOnce.insert(request.sessionID).inserted {
            let metadata = ["retry_within_seconds": "300", "cause_reason": "FIXTURE"]
            throw APIError.server(status: 500, envelope: ErrorEnvelope(reason: "REAUTH_PERSIST_FAILED", metadata: metadata))
        }
        oauthSessions.saved.insert(request.sessionID)
        return savingToken(account, kind: request.authKind, now: now)
    }

    /// The fallback without accounts.reauthorize, and a new account's 完成授权 (S2-19): a made-up token for the session's platform
    /// and method, with the e-mail every platform but Gemini reports.
    func exchange(_ link: OAuthLink, code: OAuthCode) throws -> OAuthTokenInfo {
        try checkSession(link.sessionID, platform: link.platform.rawValue)
        var fields: [String: JSONValue] = ["access_token": .string("demo-access-token"), "refresh_token": .string("demo-refresh-token"),
                                           "token_type": .string("Bearer")]
        if link.platform != .gemini { fields[link.platform == .anthropic ? "email_address" : "email"] = .string(DemoData.AccountFixture.oauthEmail) }
        return try OAuthTokenInfo.fixture(platform: link.platform, kind: link.request.kind, fields: fields)
    }
    /// `POST :id/apply-oauth-credentials`: a missing account is a 404 without reason, as the server sends it.
    func applyOAuth(id: Int, type: OAuthAuthKind, now: Date) throws -> UpstreamAccount {
        guard let account = account(id: id) else { throw APIError.server(status: 404, reason: nil) }
        guard account.isTokenAccount else { throw APIError.server(status: 400, reason: "NOT_OAUTH") }
        return savingToken(account, kind: type, now: now)
    }

    /// persistOAuthCredentials: active again, every block cleared, the schedule switch untouched; an eight-hour token from `now`.
    private func savingToken(_ account: UpstreamAccount, kind: OAuthAuthKind?, now: Date) -> UpstreamAccount {
        var updated = account
        updated.status = "active"
        updated.errorMessage = nil; updated.errorSummary = nil; updated.errorKind = nil; updated.errorStatusCode = nil; updated.errorAt = nil
        updated.rateLimitResetAt = nil; updated.overloadUntil = nil; updated.tempUnschedulableUntil = nil; updated.tempUnschedulableReason = nil
        if let fields = updated.extra?.raw.objectValue {
            updated.extra = try? AccountExtra(raw: .object(fields.filter { $0.key != "model_rate_limits" }))
        }
        if account.platform == "anthropic", let kind { updated.type = kind.rawValue }
        updated.tokenStatus = AccountTokenStatus(expiresAt: ServerTime.utcTimestamp(now.addingTimeInterval(28_800)), lifetimeSeconds: 28_800,
                                                 refreshedAt: ServerTime.utcTimestamp(now), autoRefresh: account.tokenStatus?.autoRefresh ?? true)
        replace(updated)
        bump(account.id)
        return updated
    }
    private func checkSession(_ session: String, platform: String) throws {
        guard oauthSessions.sessions[session] == nil else { return }
        let prefix = platform == "anthropic" ? "CLAUDE" : platform.uppercased()
        throw APIError.server(status: 400, reason: "\(prefix)_OAUTH_SESSION_NOT_FOUND")
    }
    private static func demoRedirect(_ request: OAuthLinkRequest) -> String {
        switch request.platform {
        case .anthropic: "https://platform.example.invalid/oauth/code/callback"
        case .gemini where request.geminiOAuthType != .aiStudio: "https://codeassist.example.invalid/authcode"
        case .gemini, .openai: "http://localhost:1455/auth/callback"
        case .antigravity: "http://localhost:8085/callback"
        case .grok: "http://127.0.0.1:56121/callback"
        }
    }
}
