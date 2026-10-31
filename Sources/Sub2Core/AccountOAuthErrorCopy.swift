import Foundation

/// The three steps of an authorization (link, sign-in in the browser, code); an error is shown under its step.
public enum OAuthFlowStep: Int, Sendable, CaseIterable, Comparable {
    case link = 0, browser, code
    public static func < (lhs: OAuthFlowStep, rhs: OAuthFlowStep) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 20 §0.5's OAuth reasons as the authorization sheets show them: the text, the step it sits under and what can be done next.
/// ReasonCatalog keeps its general wording for every other page.
public struct AccountOAuthErrorCopy: Sendable, Equatable {
    public enum Flow: Sendable, Equatable {
        case authURL
        /// exchange-code: a new account, or re-authorizing without accounts.reauthorize.
        case exchange
        case reauthorize
        case apply
    }
    public enum Remedy: String, Sendable, Equatable, CaseIterable {
        case regenerateLink, reopenLink, retry, changeProxy, retrySave, reauthorize, editInWeb, pickProxy
        public var title: String {
            switch self {
            case .regenerateLink: "重新生成链接"
            case .reopenLink: "重新打开本次链接"
            case .retry: "重试"
            case .changeProxy: "换个代理再试"
            case .retrySave: "重试保存"
            case .reauthorize: "重新授权"
            case .editInWeb: "在 Web 中编辑"
            case .pickProxy: "改选代理"
            }
        }
    }
    public let message: String
    public let detail: String?
    public let step: OAuthFlowStep
    public let remedies: [Remedy]
    /// REAUTH_PERSIST_FAILED's `retry_within_seconds`. The caller times it on the monotonic clock from the error and then
    /// offers 重新授权 instead of 重试保存.
    public let retryWindow: Duration?

    public init(message: String, detail: String? = nil, step: OAuthFlowStep, remedies: [Remedy], retryWindow: Duration? = nil) {
        self.message = message; self.detail = detail; self.step = step; self.remedies = remedies; self.retryWindow = retryWindow
    }

    /// The local 30-minute limit, reached before the server says anything (20 §6.5).
    public static let linkExpired = AccountOAuthErrorCopy(message: "授权链接已过期", detail: "链接生成超过 30 分钟，授权会话已失效，需要重新生成。",
                                                          step: .link, remedies: [.regenerateLink])
    /// The callback came back with `error=access_denied`.
    public static let denied = AccountOAuthErrorCopy(message: "你在浏览器里拒绝了授权", detail: "重新打开链接，登录后点“授权”。",
                                                     step: .browser, remedies: [.reopenLink])

    /// nil for an error this table does not cover: the caller shows `error.localizedDescription`. `reasonsSupported` is
    /// accounts.oauth_error_reasons; without it an exchange that failed with a bare 500 most likely met an expired session.
    public static func resolve(_ error: APIError, flow: Flow, platform: OAuthPlatform, reasonsSupported: Bool) -> AccountOAuthErrorCopy? {
        guard let status = error.statusCode else { return nil }
        guard let reason = error.reason, !reason.isEmpty else {
            let expired = !reasonsSupported && status == 500 && (flow == .exchange || flow == .reauthorize)
            return expired ? AccountOAuthErrorCopy(message: "授权链接可能已过期", step: step(flow), remedies: [.regenerateLink]) : nil
        }
        guard let entry = entry(status: status, reason: reason, error: error, platform: platform) else { return nil }
        return adjusted(entry, flow: flow, platform: platform)
    }

    private static func step(_ flow: Flow) -> OAuthFlowStep { flow == .authURL ? .link : .code }
    /// Grok's exchange spends the session first, so after any failed exchange only a new link helps.
    private static func adjusted(_ copy: AccountOAuthErrorCopy, flow: Flow, platform: OAuthPlatform) -> AccountOAuthErrorCopy {
        let shown = copy.step == .browser ? OAuthFlowStep.browser : step(flow)
        let spent = platform.consumesSessionOnExchange && (flow == .exchange || flow == .reauthorize)
        let linkOnly: Set<Remedy> = [.regenerateLink, .reopenLink, .retry, .changeProxy]
        guard spent, !copy.remedies.isEmpty, copy.remedies.allSatisfy(linkOnly.contains) else {
            return AccountOAuthErrorCopy(message: copy.message, detail: copy.detail, step: shown, remedies: copy.remedies, retryWindow: copy.retryWindow)
        }
        return AccountOAuthErrorCopy(message: copy.message, step: shown, remedies: [.regenerateLink])
    }

    // The step here is a placeholder except for .browser; `adjusted` sets it from the flow.
    private static func entry(status: Int, reason: String, error: APIError, platform: OAuthPlatform) -> AccountOAuthErrorCopy? {
        switch (status, reason) {
        case (400, _) where reason.hasSuffix("_OAUTH_SESSION_NOT_FOUND") || reason == "GROK_OAUTH_SESSION_ALREADY_USED":
            return copy("授权链接已过期", [.regenerateLink])
        case (400, _) where reason.hasSuffix("_OAUTH_INVALID_STATE") || reason.hasSuffix("_OAUTH_STATE_REQUIRED"):
            return copy("授权码不是这次链接换来的", [.reopenLink, .regenerateLink])
        case (400, _) where reason.hasSuffix("_OAUTH_CODE_REJECTED"):
            return copy("授权码无效或已被使用", [.reopenLink, .regenerateLink], detail: "回到浏览器重新授权，或者重新生成链接。")
        case (403, "GROK_OAUTH_ENTITLEMENT_DENIED"):
            return AccountOAuthErrorCopy(message: "这个 xAI 账号没有授权", step: .browser, remedies: [.regenerateLink])
        case (502, "OAUTH_EXCHANGE_FAILED"):
            let name = error.metadata["platform"].flatMap(OAuthPlatform.init(accountPlatform:))?.upstreamName ?? platform.upstreamName
            return copy("服务器连不上 \(name)", [.retry, .regenerateLink])
        case (502, _) where openAIUnreachable.contains(reason):
            return copy("服务器连不上 OpenAI，授权码还没用掉", [.changeProxy], detail: "换一个能访问 OpenAI 的代理，直接重新兑换。")
        case (502, _) where grokUnreachable.contains(reason):
            return copy("服务器连不上 xAI", [.regenerateLink])
        case (500, "REAUTH_PERSIST_FAILED"):
            let seconds = error.metadata["retry_within_seconds"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0 > 0 ? $0 : nil }
            return AccountOAuthErrorCopy(message: "令牌已换到，但没保存成功", step: .code, remedies: seconds == nil ? [.reauthorize] : [.retrySave],
                                         retryWindow: seconds.map { .seconds($0) })
        case (400, "NOT_OAUTH"):
            return copy(unsupported, [.editInWeb])
        case (400, "REAUTH_UNSUPPORTED"):
            return copy(unsupportedText(error.metadata["detail"]), [.editInWeb])
        case (404, "PROXY_NOT_FOUND"), (400, "OPENAI_OAUTH_PROXY_NOT_FOUND"), (400, "GROK_OAUTH_PROXY_NOT_FOUND"):
            return copy("代理不属于本工作区", [.pickProxy])
        default:
            return nil
        }
    }
    private static func copy(_ message: String, _ remedies: [Remedy], detail: String? = nil) -> AccountOAuthErrorCopy {
        AccountOAuthErrorCopy(message: message, detail: detail, step: .code, remedies: remedies)
    }

    private static let openAIUnreachable: Set<String> = [
        "OPENAI_OAUTH_PROXY_REQUIRED", "OPENAI_OAUTH_TOKEN_EXCHANGE_FAILED", "OPENAI_OAUTH_REQUEST_FAILED", "OPENAI_OAUTH_CLIENT_INIT_FAILED"
    ]
    private static let grokUnreachable: Set<String> = [
        "GROK_OAUTH_TOKEN_EXCHANGE_FAILED", "GROK_OAUTH_REQUEST_FAILED", "GROK_OAUTH_CLIENT_INIT_FAILED", "GROK_OAUTH_INVALID_TOKEN_RESPONSE"
    ]
    private static let unsupported = "这个账号不能在手机上重新授权"
    /// REAUTH_UNSUPPORTED by `metadata.detail`; S2-17 checks the same cases before a link is made.
    public static func unsupportedText(_ detail: String?) -> String {
        switch detail {
        case "shadow_account": "影子账号的凭据跟随母账号，请重新授权母账号"
        case "codex_personal_access_token": "PAT 账号请在 Web 重新导入"
        default: unsupported
        }
    }
}
