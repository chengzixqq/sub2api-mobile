import Foundation
import Observation
import Sub2Core

/// The session an authorization belongs to (S2D1-05): links, exchanges and saves carry its generation, read when the user taps.
struct AccountOAuthSession: Sendable, Equatable {
    let generation: UUID
    /// accounts.reauthorize: one step on the server; otherwise exchange-code then apply-oauth-credentials.
    let reauthorizeEndpoint: Bool
    /// accounts.oauth_error_reasons.
    let errorReasons: Bool
    let isReadOnlyToken: Bool
}

/// generate-auth-url (AppModel+Accounts; S2-19 reuses it).
@MainActor protocol OAuthLinkSource: AnyObject {
    var oauthSession: AccountOAuthSession? { get }
    func generateOAuthLink(_ request: OAuthLinkRequest, generation: UUID) async throws -> OAuthLink
}

/// A link and what was pasted for it, ready to exchange or to re-authorize with. Printing names the platform and method only.
struct OAuthSubmission: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let link: OAuthLink
    let code: OAuthCode
    /// The exchange's proxy: the account's own, or a new account's current pick (20 §7.4-6).
    let proxyID: Int?
    var description: String { "OAuthSubmission(\(link.platform.rawValue), \(link.request.kind.rawValue))" }
    var debugDescription: String { description }
}

enum OAuthSubmissionState: Sendable, Equatable {
    case notReady, expired, denied
    case ready(OAuthSubmission)
}

/// 20 §6.3 / §7.3-7.4 the three-step list's state, shared by 重新授权 and 新建账号 (S2-19): the method (Claude OAuth / Setup Token,
/// Gemini Google One / Code Assist), the link and its 30 minutes on the monotonic clock, the pasted or received code, and the error
/// under its step. Another method drops the link and the code; a link that answers after that is dropped too.
@MainActor @Observable
final class OAuthFlowModel {
    enum Phase: Sendable, Equatable { case idle, generating, ready, exchanging, done }

    let variant: OAuthFlowVariant
    /// Re-authorizing a Claude account: its method now; picking the other converts it.
    let originalKind: OAuthAuthKind?
    /// New accounts pick Google One / Code Assist; re-authorization keeps the account's.
    let choosesGeminiType: Bool
    private(set) var request: OAuthLinkRequest
    private(set) var phase: Phase = .idle
    private(set) var link: OAuthLink?
    private(set) var code = ""
    private(set) var error: AccountOAuthErrorCopy?
    private(set) var receivedAutomatically = false
    private(set) var listenFailed = false
    /// “已授权 · {邮箱}” (S2-19).
    private(set) var authorizedEmail: String?
    @ObservationIgnored private let source: any OAuthLinkSource
    @ObservationIgnored private let clock: @MainActor () -> ContinuousClock.Instant
    @ObservationIgnored private var ticket = UUID()

    init(request: OAuthLinkRequest, variant: OAuthFlowVariant, originalKind: OAuthAuthKind? = nil, choosesGeminiType: Bool = false,
         source: any OAuthLinkSource, now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.request = request; self.variant = variant; self.originalKind = originalKind; self.choosesGeminiType = choosesGeminiType
        self.source = source; self.clock = now
    }
    /// The account's own proxy, method and Gemini type; nil for a platform the App cannot authorize.
    static func reauthorize(_ account: UpstreamAccount, source: any OAuthLinkSource,
                            now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }) -> OAuthFlowModel? {
        guard let request = OAuthLinkRequest.reauthorize(account) else { return nil }
        let original = request.platform == .anthropic ? request.kind : nil
        return OAuthFlowModel(request: request, variant: .reauthorize, originalKind: original, source: source, now: now)
    }

    var platform: OAuthPlatform { request.platform }
    var kind: OAuthAuthKind { request.kind }
    var isBusy: Bool { phase == .generating || phase == .exchanging }
    var canGenerate: Bool { !isBusy && !needsProjectID }
    var needsProjectID: Bool { choosesGeminiType && platform == .gemini && request.geminiOAuthType == .codeAssist && request.projectID == nil }
    var typeSwitchTarget: OAuthAuthKind? { originalKind.flatMap { $0 == kind ? nil : kind } }
    var codeDelivery: OAuthCodeDelivery {
        guard let link else { return .expected(platform: platform, geminiType: request.geminiOAuthType) }
        return .of(authURL: link.authURL, platform: link.platform, geminiType: link.request.geminiOAuthType)
    }
    var loopback: OAuthLoopbackEndpoint? { link.flatMap { OAuthLoopback.endpoint(authURL: $0.authURL) } }
    var stage: OAuthFlowStep {
        guard link != nil else { return .link }
        return code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .browser : .code
    }
    /// A pasted callback link that carried its own state.
    var recognizesLink: Bool {
        guard let link, link.platform != .anthropic, case .code(let parsed) = OAuthCallback.parse(code, platform: link.platform) else { return false }
        return parsed.state != nil
    }

    var now: ContinuousClock.Instant { clock() }
    func remainingSeconds(at instant: ContinuousClock.Instant) -> TimeInterval? { link?.lifetime.remainingSeconds(at: instant) }
    func isExpired(at instant: ContinuousClock.Instant) -> Bool { link?.lifetime.isExpired(at: instant) ?? false }

    func submission(at instant: ContinuousClock.Instant) -> OAuthSubmissionState {
        guard let link else { return .notReady }
        if link.lifetime.isExpired(at: instant) { return .expired }
        switch OAuthCallback.parse(code, platform: link.platform) {
        case .empty, .invalid: return .notReady
        case .denied: return .denied
        case .code(let parsed): return .ready(OAuthSubmission(link: link, code: parsed, proxyID: request.proxyID))
        }
    }
    /// The 30 minutes run out here, before the server says anything (20 §6.5); a refusal in the browser shows under step 2.
    func shownError(at instant: ContinuousClock.Instant) -> AccountOAuthErrorCopy? {
        switch submission(at: instant) {
        case .expired: AccountOAuthErrorCopy.linkExpired
        case .denied: AccountOAuthErrorCopy.denied
        case .notReady, .ready: error
        }
    }

    // MARK: Choices

    func selectKind(_ kind: OAuthAuthKind) {
        guard platform == .anthropic, kind != request.kind else { return }
        request = rebuilt(kind: kind)
        dropLink()
    }
    /// A new account's tier follows the type (S2-19).
    func selectGeminiType(_ type: GeminiOAuthType) {
        guard choosesGeminiType, platform == .gemini, type != request.geminiOAuthType else { return }
        request = rebuilt(geminiType: type)
        dropLink()
    }
    func setProjectID(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = trimmed.isEmpty ? nil : trimmed
        guard projectID != request.projectID else { return }
        request = rebuilt(projectID: .some(projectID))
        if link != nil { dropLink() }
    }
    /// Only the exchange that follows uses it: the link and the progress stay (20 §7.4-6).
    func updateProxy(_ id: Int?) { request = rebuilt(proxyID: .some(id)) }

    // MARK: Link and code

    func generate() async {
        guard canGenerate, let session = source.oauthSession else { return }
        let mine = UUID()
        ticket = mine
        phase = .generating
        error = nil
        do {
            let made = try await source.generateOAuthLink(request, generation: session.generation)
            guard ticket == mine else { return }
            link = made
            code = ""
            receivedAutomatically = false
            listenFailed = false
            phase = .ready
        } catch {
            guard ticket == mine else { return }
            phase = .idle
            guard !(error is CancellationError) else { return }
            self.error = Self.linkError(error, platform: platform, reasonsSupported: session.errorReasons)
        }
    }
    func setCode(_ text: String) {
        code = text
        receivedAutomatically = false
        if let error, error.step != .link { self.error = nil }
    }
    /// The App's own listener caught the callback (new accounts).
    func receiveCallback(_ url: URL) {
        guard code != url.absoluteString else { return }
        setCode(url.absoluteString)
        receivedAutomatically = true
    }
    func noteListenFailed() { listenFailed = true }
    func show(_ error: AccountOAuthErrorCopy) { self.error = error }
    func clearError() { error = nil }
    /// Back to step 1: the link, the code and any error go.
    func restart() { dropLink() }

    // MARK: A new account's 完成授权 (S2-19)

    func beginExchange() {
        phase = .exchanging
        error = nil
    }
    func finishExchange(email: String?) {
        phase = .done
        authorizedEmail = email
    }
    func failExchange(_ error: AccountOAuthErrorCopy) {
        phase = link == nil ? .idle : .ready
        self.error = error
    }

    private func dropLink() {
        ticket = UUID()
        link = nil
        code = ""
        error = nil
        receivedAutomatically = false
        listenFailed = false
        authorizedEmail = nil
        phase = .idle
    }
    private func rebuilt(kind: OAuthAuthKind? = nil, geminiType: GeminiOAuthType? = nil, projectID: String?? = nil, proxyID: Int?? = nil) -> OAuthLinkRequest {
        OAuthLinkRequest(platform: request.platform, kind: kind ?? request.kind, proxyID: proxyID ?? request.proxyID, accountID: request.accountID,
                         geminiOAuthType: geminiType ?? request.geminiOAuthType, projectID: projectID ?? request.projectID,
                         tierID: geminiType?.defaultTierID ?? request.tierID)
    }
    private static func linkError(_ error: any Error, platform: OAuthPlatform, reasonsSupported: Bool) -> AccountOAuthErrorCopy {
        let copy = (error as? APIError).flatMap { AccountOAuthErrorCopy.resolve($0, flow: .authURL, platform: platform, reasonsSupported: reasonsSupported) }
        return copy ?? AccountOAuthErrorCopy(message: error.localizedDescription, step: .link, remedies: [])
    }
}
