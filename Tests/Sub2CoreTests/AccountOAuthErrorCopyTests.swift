import Foundation
import Testing
@testable import Sub2Core

private func serverError(_ status: Int, _ reason: String?, metadata: [String: String]? = nil) -> APIError {
    APIError.server(status: status, envelope: ErrorEnvelope(code: .int(status), reason: reason, metadata: metadata))
}
private func copy(_ error: APIError, flow: AccountOAuthErrorCopy.Flow = .exchange, platform: OAuthPlatform = .openai,
                  reasonsSupported: Bool = true) -> AccountOAuthErrorCopy? {
    AccountOAuthErrorCopy.resolve(error, flow: flow, platform: platform, reasonsSupported: reasonsSupported)
}

@Test func oauthReasonsMapToStepCopyAndRemedies() throws {
    for reason in ["CLAUDE_OAUTH_SESSION_NOT_FOUND", "GEMINI_OAUTH_SESSION_NOT_FOUND", "OPENAI_OAUTH_SESSION_NOT_FOUND", "GROK_OAUTH_SESSION_ALREADY_USED"] {
        let result = try #require(copy(serverError(400, reason)), "\(reason)")
        #expect(result.message == "授权链接已过期" && result.remedies == [.regenerateLink] && result.step == .code)
    }
    for reason in ["ANTIGRAVITY_OAUTH_INVALID_STATE", "OPENAI_OAUTH_STATE_REQUIRED"] {
        let result = try #require(copy(serverError(400, reason), platform: .antigravity), "\(reason)")
        #expect(result.message == "授权码不是这次链接换来的" && result.remedies == [.reopenLink, .regenerateLink])
    }
    let rejected = try #require(copy(serverError(400, "OPENAI_OAUTH_CODE_REJECTED", metadata: ["upstream_status": "400"])))
    #expect(rejected.message == "授权码无效或已被使用" && rejected.detail == "回到浏览器重新授权，或者重新生成链接。")
    #expect(rejected.remedies == [.reopenLink, .regenerateLink])
    let entitlement = try #require(copy(serverError(403, "GROK_OAUTH_ENTITLEMENT_DENIED"), platform: .grok))
    #expect(entitlement.message == "这个 xAI 账号没有授权" && entitlement.step == .browser && entitlement.remedies == [.regenerateLink])
    let unreachable = try #require(copy(serverError(502, "OAUTH_EXCHANGE_FAILED", metadata: ["platform": "antigravity"]), flow: .reauthorize))
    #expect(unreachable.message == "服务器连不上 Google" && unreachable.remedies == [.retry, .regenerateLink])
    #expect(copy(serverError(502, "OAUTH_EXCHANGE_FAILED"), flow: .reauthorize, platform: .anthropic)?.message == "服务器连不上 Claude")
    for reason in ["OPENAI_OAUTH_PROXY_REQUIRED", "OPENAI_OAUTH_TOKEN_EXCHANGE_FAILED", "OPENAI_OAUTH_REQUEST_FAILED", "OPENAI_OAUTH_CLIENT_INIT_FAILED"] {
        let proxy = try #require(copy(serverError(502, reason)), "\(reason)")
        #expect(proxy.message == "服务器连不上 OpenAI，授权码还没用掉" && proxy.detail == "换一个能访问 OpenAI 的代理，直接重新兑换。")
        #expect(proxy.remedies == [.changeProxy])
    }
    for error in [serverError(404, "PROXY_NOT_FOUND"), serverError(400, "OPENAI_OAUTH_PROXY_NOT_FOUND"), serverError(400, "GROK_OAUTH_PROXY_NOT_FOUND")] {
        let proxy = try #require(copy(error, flow: .authURL))
        #expect(proxy.message == "代理不属于本工作区" && proxy.remedies == [.pickProxy] && proxy.step == .link)
    }
    let notOAuth = try #require(copy(serverError(400, "NOT_OAUTH"), flow: .apply))
    #expect(notOAuth.message == "这个账号不能在手机上重新授权" && notOAuth.remedies == [.editInWeb] && notOAuth.step == .code)
    #expect(copy(serverError(400, "CLAUDE_OAUTH_SESSION_NOT_FOUND"), flow: .authURL)?.step == .link)
    #expect(AccountOAuthErrorCopy.Remedy.allCases.map(\.title)
            == ["重新生成链接", "重新打开本次链接", "重试", "换个代理再试", "重试保存", "重新授权", "在 Web 中编辑", "改选代理"])
    #expect(OAuthFlowStep.allCases == [.link, .browser, .code] && OAuthFlowStep.link < .browser && OAuthFlowStep.browser < .code)
}

@Test func grokExchangeFailuresAlwaysNeedNewLink() throws {
    let rejected = try #require(copy(serverError(400, "GROK_OAUTH_CODE_REJECTED"), platform: .grok))
    #expect(rejected.message == "授权码无效或已被使用" && rejected.remedies == [.regenerateLink] && rejected.detail == nil)
    for reason in ["GROK_OAUTH_TOKEN_EXCHANGE_FAILED", "GROK_OAUTH_REQUEST_FAILED", "GROK_OAUTH_CLIENT_INIT_FAILED", "GROK_OAUTH_INVALID_TOKEN_RESPONSE"] {
        let failed = try #require(copy(serverError(502, reason), platform: .grok), "\(reason)")
        #expect(failed.message == "服务器连不上 xAI" && failed.remedies == [.regenerateLink] && failed.detail == nil)
    }
    let reauth = try #require(copy(serverError(502, "OAUTH_EXCHANGE_FAILED", metadata: ["platform": "grok"]), flow: .reauthorize, platform: .grok))
    #expect(reauth.message == "服务器连不上 xAI" && reauth.remedies == [.regenerateLink])
    #expect(copy(serverError(400, "GROK_OAUTH_INVALID_STATE"), platform: .grok)?.remedies == [.regenerateLink])
}

@Test func reauthUnsupportedUsesMetadataDetail() throws {
    let texts: [(String?, String)] = [
        ("shadow_account", "影子账号的凭据跟随母账号，请重新授权母账号"), ("codex_personal_access_token", "PAT 账号请在 Web 重新导入"),
        ("unsupported_platform", "这个账号不能在手机上重新授权"), ("auth_kind_not_supported", "这个账号不能在手机上重新授权"), (nil, "这个账号不能在手机上重新授权")
    ]
    for (detail, message) in texts {
        let result = try #require(copy(serverError(400, "REAUTH_UNSUPPORTED", metadata: detail.map { ["detail": $0] }), flow: .reauthorize))
        #expect(result.message == message && result.remedies == [.editInWeb])
    }
}

@Test func persistFailureCarriesRetryWindow() throws {
    let saved = try #require(copy(serverError(500, "REAUTH_PERSIST_FAILED", metadata: ["retry_within_seconds": "300", "cause_reason": "X"]), flow: .reauthorize))
    #expect(saved.message == "令牌已换到，但没保存成功" && saved.remedies == [.retrySave] && saved.retryWindow == .seconds(300))
    for metadata in [nil, ["retry_within_seconds": "soon"], ["retry_within_seconds": "0"]] {
        let expired = try #require(copy(serverError(500, "REAUTH_PERSIST_FAILED", metadata: metadata), flow: .reauthorize))
        #expect(expired.remedies == [.reauthorize] && expired.retryWindow == nil)
    }
}

@Test func oldServerFiveHundredReadsAsLikelyExpired() throws {
    for flow in [AccountOAuthErrorCopy.Flow.exchange, .reauthorize] {
        let result = try #require(copy(serverError(500, nil), flow: flow, reasonsSupported: false))
        #expect(result.message == "授权链接可能已过期" && result.remedies == [.regenerateLink] && result.step == .code)
    }
    #expect(copy(serverError(500, nil), flow: .exchange, reasonsSupported: true) == nil)
    #expect(copy(serverError(500, nil), flow: .apply, reasonsSupported: false) == nil)
    #expect(copy(serverError(500, "SOMETHING_ELSE"), flow: .exchange, reasonsSupported: false) == nil)
}

@Test func unrelatedErrorsFallBackAndCatalogStaysUnchanged() {
    for error in [serverError(429, "RATE_LIMITED"), serverError(401, nil), serverError(409, "MIXED_CHANNEL_WARNING"), serverError(400, nil), .invalidResponse] {
        #expect(copy(error) == nil)
    }
    #expect(ReasonCatalog.entry(status: 502, reason: "OAUTH_EXCHANGE_FAILED").message == "站点暂时不可用")
    #expect(ReasonCatalog.entry(status: 404, reason: "PROXY_NOT_FOUND").message == ReasonCatalog.entry(status: 404, reason: "USER_NOT_FOUND").message)
    let expired = AccountOAuthErrorCopy.linkExpired
    #expect(expired.message == "授权链接已过期" && expired.detail == "链接生成超过 30 分钟，授权会话已失效，需要重新生成。")
    #expect(expired.step == .link && expired.remedies == [.regenerateLink])
    let denied = AccountOAuthErrorCopy.denied
    #expect(denied.message == "你在浏览器里拒绝了授权" && denied.detail == "重新打开链接，登录后点“授权”。")
    #expect(denied.step == .browser && denied.remedies == [.reopenLink])
}
