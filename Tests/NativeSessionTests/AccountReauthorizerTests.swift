import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// The site clock of every case: 2026-10-24T08:00:00Z.
private let reauthNow = Date(timeIntervalSince1970: 1_792_828_800)
private let reauthTransport = APIError(kind: .transport, message: "连接超时，请检查网络后重试。")

private func tokenAccount(platform: String = "anthropic", type: String = "oauth", status: String = "active", schedulable: Bool = true,
                          refreshedAgo: TimeInterval? = 3_600, proxyID: Int? = 3, credentials: JSONValue? = nil) -> UpstreamAccount {
    let tokenStatus = AccountTokenStatus(expiresAt: ServerTime.utcTimestamp(reauthNow.addingTimeInterval(600)), lifetimeSeconds: 28_800,
                                         refreshedAt: refreshedAgo.map { ServerTime.utcTimestamp(reauthNow.addingTimeInterval(-$0)) }, autoRefresh: true)
    return UpstreamAccount(id: 2, name: "Claude-官方-02", platform: platform, type: type, status: status, schedulable: schedulable,
                           tokenStatus: tokenStatus, proxyID: proxyID, credentials: credentials)
}
/// The account as the server keeps it after a save `refreshedIn` seconds from the tap.
private func saved(_ account: UpstreamAccount, type: String? = nil, refreshedIn: TimeInterval = 1) -> UpstreamAccount {
    var updated = account
    updated.status = "active"
    if let type { updated.type = type }
    updated.tokenStatus = AccountTokenStatus(expiresAt: ServerTime.utcTimestamp(reauthNow.addingTimeInterval(28_800)), lifetimeSeconds: 28_800,
                                             refreshedAt: ServerTime.utcTimestamp(reauthNow.addingTimeInterval(refreshedIn)), autoRefresh: true)
    return updated
}
private func persistFailed(_ seconds: String? = "300") -> APIError {
    APIError.server(status: 500, envelope: ErrorEnvelope(reason: "REAUTH_PERSIST_FAILED", metadata: seconds.map { ["retry_within_seconds": $0] }))
}
private func submission(for account: UpstreamAccount, kind: OAuthAuthKind? = nil, code: String = "Kp7v#U5oT", state: String? = nil) -> OAuthSubmission {
    let request = OAuthLinkRequest.reauthorize(account, kind: kind)!
    let link = OAuthLink(request: request, authURL: URL(string: "https://auth.example.invalid/authorize")!, sessionID: "sess-1", state: state,
                         lifetime: OAuthLinkLifetime(generatedAt: .now))
    return OAuthSubmission(link: link, code: OAuthCode(value: code), proxyID: request.proxyID)
}
private func claudeToken(kind: OAuthAuthKind = .oauth) throws -> OAuthTokenInfo {
    try OAuthTokenInfo.fixture(platform: .anthropic, kind: kind, fields: ["access_token": .string("at-fixture"), "refresh_token": .string("rt-fixture"),
                                                                          "email_address": .string("ops@example.invalid")])
}

/// Answers from scripts and records what was sent; `onSend` runs before each write answers.
@MainActor private final class ScriptedReauthSource: AccountReauthorizeSource {
    struct Applied { let type: OAuthAuthKind; let credentials: [String: JSONValue]; let generation: UUID }
    var oauthSession: AccountOAuthSession?
    var reauthorizeReplies: [Result<UpstreamAccount, any Error>] = []
    var exchangeReplies: [Result<OAuthTokenInfo, any Error>] = []
    var applyReplies: [Result<UpstreamAccount, any Error>] = []
    var readReplies: [Result<VersionedAccount, any Error>] = []
    var onSend: (@MainActor () -> Void)?
    private(set) var reauthorized: [(request: AccountReauthorizeRequest, generation: UUID)] = []
    private(set) var exchanged: [(proxyID: Int?, generation: UUID)] = []
    private(set) var applied: [Applied] = []
    private(set) var reads = 0

    init(endpoint: Bool = true, readOnly: Bool = false) {
        oauthSession = AccountOAuthSession(generation: UUID(), reauthorizeEndpoint: endpoint, errorReasons: true, isReadOnlyToken: readOnly)
    }
    var generation: UUID? { oauthSession?.generation }
    var calls: Int { reauthorized.count + exchanged.count + applied.count + reads }
    func switchSession() {
        guard let old = oauthSession else { return }
        oauthSession = AccountOAuthSession(generation: UUID(), reauthorizeEndpoint: old.reauthorizeEndpoint, errorReasons: old.errorReasons,
                                           isReadOnlyToken: old.isReadOnlyToken)
    }

    func serverNow() -> Date { reauthNow }
    func generateOAuthLink(_ request: OAuthLinkRequest, generation: UUID) async throws -> OAuthLink { throw CancellationError() }
    func reauthorizeAccount(id: Int, request: AccountReauthorizeRequest, generation: UUID) async throws -> UpstreamAccount {
        reauthorized.append((request, generation))
        onSend?()
        return try reauthorizeReplies.removeFirst().get()
    }
    func exchangeOAuthCode(_ link: OAuthLink, code: OAuthCode, proxyID: Int?, generation: UUID) async throws -> OAuthTokenInfo {
        exchanged.append((proxyID, generation))
        return try exchangeReplies.removeFirst().get()
    }
    func applyOAuthCredentials(accountID: Int, type: OAuthAuthKind, credentials: [String: JSONValue], extra: [String: JSONValue]?,
                               generation: UUID) async throws -> UpstreamAccount {
        applied.append(Applied(type: type, credentials: credentials, generation: generation))
        onSend?()
        return try applyReplies.removeFirst().get()
    }
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        reads += 1
        return try readReplies.removeFirst().get()
    }
}

@MainActor private final class ReauthClock {
    var now: ContinuousClock.Instant = .now
}

@MainActor private func makeReauthorizer(_ account: UpstreamAccount, _ source: ScriptedReauthSource, faceID: Bool = false,
                                         authenticator: RecordingAuthenticator = RecordingAuthenticator(), clock: ReauthClock = ReauthClock(),
                                         scratch: ScratchDefaults) -> AccountReauthorizer {
    let preferences = AppPreferences(defaults: scratch.defaults)
    preferences.storeFaceIDRequirement(faceID)
    return AccountReauthorizer(account: account, source: source, gate: BiometricGate(preferences: preferences, authenticator: authenticator),
                               monotonicNow: { clock.now })
}
private func succeededResult(_ outcome: AccountReauthOutcome) -> AccountReauthResult? {
    if case .succeeded(let result) = outcome { return result }
    return nil
}

@MainActor @Test func oneStepReauthorizeSendsAccountProxyAndNoPreserveStatus() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource()
    source.reauthorizeReplies = [.success(saved(account))]
    let reauthorizer = makeReauthorizer(account, source, scratch: scratch)
    let result = try #require(succeededResult(await reauthorizer.submit(submission(for: account), switchedTo: nil)))
    let sent = try #require(source.reauthorized.first)
    #expect(source.reauthorized.count == 1 && sent.generation == source.generation)
    #expect(sent.request.sessionID == "sess-1" && sent.request.code == "Kp7v#U5oT" && sent.request.proxyID == 3 && sent.request.authKind == .oauth)
    #expect(sent.request.oauthType == nil && sent.request.tierID == nil)
    let body = String(decoding: try JSONEncoder().encode(sent.request), as: UTF8.self)
    #expect(!body.contains("preserve_status"), "\(body)")
    #expect(result.version == nil && result.account.id == 2 && result.receipt.text == "已重新授权 · 令牌已替换" && result.receipt.followUp == .test)
    #expect(reauthorizer.phase == .idle && !reauthorizer.hasHeldCredentials && reauthorizer.notice == nil)

    let gemini = tokenAccount(platform: "gemini", credentials: .object(["oauth_type": .string("google_one"), "tier_id": .string("google_one_free")]))
    source.reauthorizeReplies = [.success(saved(gemini))]
    let geminiReauthorizer = makeReauthorizer(gemini, source, scratch: scratch)
    _ = await geminiReauthorizer.submit(submission(for: gemini, state: "g7"), switchedTo: nil)
    let geminiSent = try #require(source.reauthorized.last?.request)
    #expect(geminiSent.oauthType == .googleOne && geminiSent.tierID == "google_one_free" && geminiSent.authKind == nil && geminiSent.state == "g7")
}

@MainActor @Test func faceIDDeniedSendsNothing() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource()
    let denied = makeReauthorizer(account, source, faceID: true, authenticator: RecordingAuthenticator(succeeds: false), scratch: scratch)
    #expect(await denied.submit(submission(for: account), switchedTo: nil) == .cancelled)
    #expect(source.calls == 0 && denied.phase == .idle && denied.notice == nil)
    source.reauthorizeReplies = [.success(saved(account))]
    let unavailable = makeReauthorizer(account, source, faceID: true, authenticator: RecordingAuthenticator(isAvailable: false), scratch: scratch)
    #expect(succeededResult(await unavailable.submit(submission(for: account), switchedTo: nil)) != nil)
}

@MainActor @Test func faceIDVerifiedOnceAndNotForRetry() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource(), authenticator = RecordingAuthenticator()
    source.reauthorizeReplies = [.failure(persistFailed()), .success(saved(account)), .failure(APIError.server(status: 400, reason: "CLAUDE_OAUTH_CODE_REJECTED")),
                                 .success(saved(account))]
    source.readReplies = [.success(VersionedAccount(account: account, etag: "\"cv-1\""))]
    let reauthorizer = makeReauthorizer(account, source, faceID: true, authenticator: authenticator, scratch: scratch)
    #expect(await reauthorizer.submit(submission(for: account), switchedTo: nil) == .notice)
    #expect(authenticator.calls == 1 && reauthorizer.notice == .persistFailed)
    #expect(succeededResult(await reauthorizer.retry()) != nil)
    #expect(authenticator.calls == 1 && source.reauthorized[0].request == source.reauthorized[1].request)
    guard case .stepError = await reauthorizer.submit(submission(for: account), switchedTo: nil) else { Issue.record("no step error"); return }
    _ = await reauthorizer.submit(submission(for: account), switchedTo: nil)
    #expect(authenticator.calls == 3)
}

@MainActor @Test func persistFailedConfirmedByReadBackCountsAsSuccess() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource()
    source.reauthorizeReplies = [.failure(persistFailed())]
    source.readReplies = [.success(VersionedAccount(account: saved(account), etag: "\"cv-5\""))]
    let reauthorizer = makeReauthorizer(account, source, scratch: scratch)
    let result = try #require(succeededResult(await reauthorizer.submit(submission(for: account), switchedTo: nil)))
    #expect(result.version?.etag == "\"cv-5\"" && source.reauthorized.count == 1 && source.reads == 1)
}

@MainActor @Test func persistFailedNotSavedOffersRetryWithinWindow() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource(), clock = ReauthClock()
    source.reauthorizeReplies = [.failure(persistFailed("120")), .success(saved(account))]
    source.readReplies = [.success(VersionedAccount(account: account, etag: "\"cv-1\""))]
    let reauthorizer = makeReauthorizer(account, source, clock: clock, scratch: scratch)
    let start = clock.now
    #expect(await reauthorizer.submit(submission(for: account), switchedTo: nil) == .notice)
    #expect(reauthorizer.notice == .persistFailed && reauthorizer.hasHeldCredentials && source.reauthorized.count == 1)
    #expect(reauthorizer.canRetry(at: start + .seconds(119)) && !reauthorizer.canRetry(at: start + .seconds(120)))
    #expect(succeededResult(await reauthorizer.retry()) != nil)
    #expect(source.reauthorized.count == 2 && source.reauthorized[0].request == source.reauthorized[1].request)

    source.reauthorizeReplies = [.failure(persistFailed(nil))]
    source.readReplies = [.success(VersionedAccount(account: account, etag: "\"cv-1\""))]
    let closed = makeReauthorizer(account, source, clock: clock, scratch: scratch)
    _ = await closed.submit(submission(for: account), switchedTo: nil)
    #expect(closed.notice == .persistFailed && !closed.canRetry(at: clock.now))
    clock.now = start + .seconds(10)
    #expect(await closed.retry() == .cancelled && source.reauthorized.count == 3)
    closed.restart()
    #expect(closed.notice == nil && !closed.hasHeldCredentials)
}

@MainActor @Test func transportFailureReadsBackThenOffersManualRetry() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource()
    source.reauthorizeReplies = [.failure(reauthTransport)]
    source.readReplies = [.success(VersionedAccount(account: saved(account), etag: "\"cv-2\""))]
    #expect(succeededResult(await makeReauthorizer(account, source, scratch: scratch).submit(submission(for: account), switchedTo: nil)) != nil)

    source.reauthorizeReplies = [.failure(reauthTransport), .success(saved(account))]
    source.readReplies = [.success(VersionedAccount(account: account, etag: "\"cv-1\""))]
    let reauthorizer = makeReauthorizer(account, source, scratch: scratch)
    #expect(await reauthorizer.submit(submission(for: account), switchedTo: nil) == .notice)
    #expect(reauthorizer.notice == .unconfirmed && source.reauthorized.count == 2 && reauthorizer.canRetry(at: .now))
    #expect(succeededResult(await reauthorizer.retry()) != nil && source.reauthorized.count == 3)

    source.reauthorizeReplies = [.failure(APIError.server(status: 503, reason: nil))]
    source.readReplies = [.success(VersionedAccount(account: account, etag: nil))]
    let busy = makeReauthorizer(account, source, scratch: scratch)
    _ = await busy.submit(submission(for: account), switchedTo: nil)
    #expect(busy.notice == .unconfirmed)
}

@MainActor @Test func readBackFailureStillOffersRetry() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource()
    source.reauthorizeReplies = [.failure(persistFailed()), .failure(reauthTransport), .failure(reauthTransport)]
    source.readReplies = [.failure(reauthTransport), .failure(reauthTransport), .failure(APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND"))]
    let first = makeReauthorizer(account, source, scratch: scratch)
    _ = await first.submit(submission(for: account), switchedTo: nil)
    #expect(first.notice == .persistFailed)
    let second = makeReauthorizer(account, source, scratch: scratch)
    _ = await second.submit(submission(for: account), switchedTo: nil)
    #expect(second.notice == .unconfirmed)
    let third = makeReauthorizer(account, source, scratch: scratch)
    #expect(await third.submit(submission(for: account), switchedTo: nil) == .missing)
    #expect(!third.hasHeldCredentials)
}

@MainActor @Test func fallbackExchangesOnceAndRetriesApplyWithSameTokens() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource(endpoint: false)
    source.exchangeReplies = [.success(try claudeToken(kind: .setupToken))]
    source.applyReplies = [.failure(APIError.server(status: 500, reason: nil)), .success(saved(account, type: "setup-token"))]
    source.readReplies = [.success(VersionedAccount(account: account, etag: "\"cv-1\""))]
    let reauthorizer = makeReauthorizer(account, source, scratch: scratch)
    #expect(await reauthorizer.submit(submission(for: account, kind: .setupToken), switchedTo: .setupToken) == .notice)
    #expect(source.exchanged.count == 1 && source.exchanged[0].proxyID == 3 && source.reauthorized.isEmpty)
    #expect(reauthorizer.notice == .persistFailed && reauthorizer.hasHeldCredentials && reauthorizer.canRetry(at: .now + .seconds(3_600)))
    let result = try #require(succeededResult(await reauthorizer.retry()))
    #expect(source.exchanged.count == 1 && source.applied.count == 2 && source.applied.allSatisfy { $0.type == .setupToken })
    #expect(source.applied[0].credentials == source.applied[1].credentials && source.applied[1].credentials["access_token"] == .string("at-fixture"))
    #expect(result.receipt.text.hasPrefix("已重新授权 · 账号类型改为 Setup") && !reauthorizer.hasHeldCredentials)

    source.exchangeReplies = [.success(try claudeToken())]
    source.applyReplies = [.failure(reauthTransport)]
    source.readReplies = [.success(VersionedAccount(account: account, etag: nil))]
    let unsure = makeReauthorizer(account, source, scratch: scratch)
    _ = await unsure.submit(submission(for: account), switchedTo: nil)
    #expect(unsure.notice == .unconfirmed && unsure.hasHeldCredentials)
}

@MainActor @Test func discardDropsHeldTokensAndPendingRequest() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource(endpoint: false)
    source.exchangeReplies = [.success(try claudeToken())]
    source.applyReplies = [.failure(APIError.server(status: 400, reason: nil))]
    source.readReplies = [.success(VersionedAccount(account: account, etag: nil))]
    let reauthorizer = makeReauthorizer(account, source, scratch: scratch)
    _ = await reauthorizer.submit(submission(for: account), switchedTo: nil)
    #expect(reauthorizer.hasHeldCredentials)
    let calls = source.calls
    reauthorizer.discard()
    #expect(!reauthorizer.hasHeldCredentials)
    #expect(await reauthorizer.retry() == .cancelled && source.calls == calls)
}

@MainActor @Test func unsupportedAndNotOAuthOfferEditInWeb() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource()
    let rows: [(String?, String)] = [("shadow_account", "影子账号的凭据跟随母账号，请重新授权母账号"), ("codex_personal_access_token", "PAT 账号请在 Web 重新导入"),
                                     ("unsupported_platform", "这个账号不能在手机上重新授权")]
    for (detail, text) in rows {
        source.reauthorizeReplies = [.failure(APIError.server(status: 400, envelope: ErrorEnvelope(reason: "REAUTH_UNSUPPORTED", metadata: detail.map { ["detail": $0] })))]
        let reauthorizer = makeReauthorizer(account, source, scratch: scratch)
        #expect(await reauthorizer.submit(submission(for: account), switchedTo: nil) == .notice)
        #expect(reauthorizer.notice == .unsupported(text), "\(text)")
    }
    source.reauthorizeReplies = [.failure(APIError.server(status: 400, reason: "NOT_OAUTH"))]
    let notOAuth = makeReauthorizer(account, source, scratch: scratch)
    _ = await notOAuth.submit(submission(for: account), switchedTo: nil)
    #expect(notOAuth.notice == .unsupported("这个账号不能在手机上重新授权") && source.reads == 0)
}

@MainActor @Test func oauthReasonsLandOnTheirSteps() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let claude = tokenAccount(), source = ScriptedReauthSource()
    func step(_ account: UpstreamAccount, _ error: APIError, state: String? = nil) async -> AccountOAuthErrorCopy? {
        source.reauthorizeReplies = [.failure(error)]
        let outcome = await makeReauthorizer(account, source, scratch: scratch).submit(submission(for: account, state: state), switchedTo: nil)
        if case .stepError(let copy) = outcome { return copy }
        return nil
    }
    let expired = await step(claude, APIError.server(status: 400, reason: "CLAUDE_OAUTH_SESSION_NOT_FOUND"))
    #expect(expired?.step == .code && expired?.message == "授权链接已过期" && expired?.remedies == [.regenerateLink])
    #expect(await step(claude, APIError.server(status: 400, reason: "CLAUDE_OAUTH_INVALID_STATE"))?.step == .code)
    #expect(await step(claude, APIError.server(status: 400, reason: "CLAUDE_OAUTH_CODE_REJECTED"))?.message == "授权码无效或已被使用")
    let grok = tokenAccount(platform: "grok")
    #expect(await step(grok, APIError.server(status: 400, reason: "GROK_OAUTH_CODE_REJECTED"), state: "k4")?.remedies == [.regenerateLink])
    #expect(await step(grok, APIError.server(status: 403, reason: "GROK_OAUTH_ENTITLEMENT_DENIED"), state: "k4")?.step == .browser)
    let unreachable = await step(grok, APIError.server(status: 502, envelope: ErrorEnvelope(reason: "OAUTH_EXCHANGE_FAILED", metadata: ["platform": "grok"])),
                                 state: "k4")
    #expect(unreachable?.step == .code && unreachable?.message == "服务器连不上 xAI" && unreachable?.remedies == [.regenerateLink])
    #expect(source.reads == 0)
    // No state for a platform that checks it: nothing is sent and the paste step says so.
    let openAI = tokenAccount(platform: "openai")
    let sent = source.reauthorized.count
    #expect(await step(openAI, APIError.server(status: 500, reason: nil))?.step == .code && source.reauthorized.count == sent)
}

@MainActor @Test func missingSessionChangeReadOnlyAndReconfirm() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource()
    source.reauthorizeReplies = [.failure(APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND"))]
    #expect(await makeReauthorizer(account, source, scratch: scratch).submit(submission(for: account), switchedTo: nil) == .missing)

    let fallback = ScriptedReauthSource(endpoint: false)
    fallback.exchangeReplies = [.success(try claudeToken())]
    fallback.applyReplies = [.failure(APIError.server(status: 404, reason: nil))]
    #expect(await makeReauthorizer(account, fallback, scratch: scratch).submit(submission(for: account), switchedTo: nil) == .missing)

    source.reauthorizeReplies = [.failure(reauthTransport)]
    source.onSend = { source.switchSession() }
    let switched = makeReauthorizer(account, source, scratch: scratch)
    #expect(await switched.submit(submission(for: account), switchedTo: nil) == .cancelled)
    #expect(source.reads == 0 && switched.notice == nil && !switched.hasHeldCredentials)
    source.onSend = nil

    let readOnly = ScriptedReauthSource(readOnly: true)
    #expect(await makeReauthorizer(account, readOnly, scratch: scratch).submit(submission(for: account), switchedTo: nil) == .cancelled)
    #expect(readOnly.calls == 0)

    source.reauthorizeReplies = [.failure(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed))]
    let reconfirm = makeReauthorizer(account, source, scratch: scratch)
    #expect(await reconfirm.submit(submission(for: account), switchedTo: nil) == .notice)
    guard case .reconfirm = reconfirm.notice else { Issue.record("no reconfirm"); return }
    #expect(reconfirm.phase == .idle)
}

@MainActor @Test func typeSwitchPassedToReceipt() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let account = tokenAccount(), source = ScriptedReauthSource()
    source.reauthorizeReplies = [.success(saved(account, type: "setup-token"))]
    let reauthorizer = makeReauthorizer(account, source, scratch: scratch)
    let result = try #require(succeededResult(await reauthorizer.submit(submission(for: account, kind: .setupToken), switchedTo: .setupToken)))
    #expect(result.receipt.text == "已重新授权 · 账号类型改为 Setup\u{00A0}Token · 令牌已替换")
    #expect(source.reauthorized.last?.request.authKind == .setupToken)
}
