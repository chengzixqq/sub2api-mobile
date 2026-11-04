import Foundation
import Testing
@testable import Sub2Core

private func reauthAccount(platform: String = "anthropic", type: String = "oauth", status: String = "active", schedulable: Bool = true,
                           _ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":2,"name":"Claude-官方-02","platform":"\#(platform)","type":"\#(type)","status":"\#(status)","schedulable":\#(schedulable)"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private let callback1455 = OAuthCodeDelivery.callback(address: "localhost:1455")

@Test func targetLineFollowsProxy() {
    #expect(AccountReauthorizePresentation.targetLine(proxyID: 3, proxyName: "hk-02") == "授权走已保存的代理 hk-02；分组、并发和代理设置不变")
    #expect(AccountReauthorizePresentation.targetLine(proxyID: 3, proxyName: nil) == "授权走已保存的代理 #3；分组、并发和代理设置不变")
    #expect(AccountReauthorizePresentation.targetLine(proxyID: nil, proxyName: "hk-02") == "账号没有代理，授权页直连打开")
}

@Test func inactiveConfirmationOnlyForStoppedAccounts() throws {
    for status in ["inactive", "disabled", "unknown_x"] {
        #expect(AccountReauthorizePresentation.needsInactiveConfirmation(try reauthAccount(status: status)), "\(status)")
    }
    for status in ["active", "error"] {
        #expect(!AccountReauthorizePresentation.needsInactiveConfirmation(try reauthAccount(status: status)), "\(status)")
    }
    let enabled = AccountReauthorizePresentation.inactiveConfirmation(name: "Claude-官方-02", schedulable: true)
    let paused = AccountReauthorizePresentation.inactiveConfirmation(name: "Claude-官方-02", schedulable: false)
    #expect(enabled.title == "重新授权「Claude-官方-02」？" && paused.title == enabled.title)
    #expect(enabled.message == "这个账号现在是停用状态。授权后账号会被重新启用并参与调度。")
    #expect(paused.message == "这个账号现在是停用状态。授权后账号会被重新启用，调度仍暂停。")
    #expect(AccountReauthorizePresentation.continueTitle == "继续授权")
}

@Test func stepCopyForBothVariantsAndDeliveries() {
    func title(_ step: OAuthFlowStep, _ variant: OAuthFlowVariant, _ platform: OAuthPlatform, _ delivery: OAuthCodeDelivery) -> String {
        OAuthFlowCopy.title(step, variant: variant, platform: platform, platformName: "Anthropic", delivery: delivery)
    }
    #expect(title(.link, .reauthorize, .anthropic, .displayedCode) == "授权链接")
    #expect(title(.browser, .reauthorize, .anthropic, .displayedCode) == "登录 Anthropic 并授权")
    #expect(title(.code, .reauthorize, .anthropic, .displayedCode) == "粘贴授权码")
    #expect(title(.code, .reauthorize, .openai, callback1455) == "粘贴回调链接或 Code")
    #expect(title(.link, .create, .openai, callback1455) == "生成授权链接")
    #expect(title(.browser, .create, .openai, callback1455) == "在浏览器里登录 ChatGPT 并授权")
    #expect(title(.code, .create, .openai, callback1455) == "完成授权")
    #expect(title(.code, .create, .gemini, .displayedCode) == "粘贴授权码")
    #expect(OAuthFlowCopy.browserNote(delivery: .displayedCode, listening: false) == "登录要授权的那个账号。授权后页面会显示授权码，复制它。")
    #expect(OAuthFlowCopy.browserNote(delivery: .callback(address: "127.0.0.1:56121"), listening: false)
        == "登录要授权的那个账号。授权后浏览器跳到 127.0.0.1:56121 的页面（打不开是正常的），拷贝地址栏里的链接。")
    #expect(OAuthFlowCopy.browserNote(delivery: callback1455, listening: true) == "授权后自动回到这里（App 临时监听 localhost:1455）")
    #expect(OAuthFlowCopy.browserNote(delivery: .displayedCode, listening: true) == "登录要授权的那个账号。授权后页面会显示授权码，复制它。")
    #expect(OAuthFlowCopy.codeLabel(.displayedCode) == "授权码" && OAuthFlowCopy.codeLabel(callback1455) == "回调链接或 Code")
    #expect(OAuthFlowCopy.codePlaceholder(.displayedCode) == "授权页显示的授权码")
    #expect(OAuthFlowCopy.codePlaceholder(callback1455) == "地址栏里的回调链接，或其中的 code")
    #expect(OAuthFlowCopy.autoReceived(address: "localhost:1455") == "已自动接收回调（localhost:1455），code 和 state 已填好")
}

@Test func deliveryFollowsTheLinkThenThePlatform() {
    #expect(OAuthCodeDelivery.expected(platform: .anthropic, geminiType: .codeAssist) == .displayedCode)
    #expect(OAuthCodeDelivery.expected(platform: .gemini, geminiType: .googleOne) == .displayedCode)
    #expect(OAuthCodeDelivery.expected(platform: .gemini, geminiType: .aiStudio) == callback1455)
    #expect(OAuthCodeDelivery.expected(platform: .grok, geminiType: .codeAssist) == .callback(address: "127.0.0.1:56121"))
    let custom = URL(string: "https://auth.example.invalid/a?redirect_uri=http%3A%2F%2F127.0.0.1%3A50000%2Fcallback")!
    #expect(OAuthCodeDelivery.of(authURL: custom, platform: .grok) == .callback(address: "127.0.0.1:50000"))
    let shown = URL(string: "https://auth.example.invalid/a?redirect_uri=https%3A%2F%2Fcodeassist.example.invalid%2Fauthcode")!
    #expect(OAuthCodeDelivery.of(authURL: shown, platform: .gemini) == .displayedCode)
    #expect(OAuthCodeDelivery.of(authURL: URL(string: "https://auth.example.invalid/a")!, platform: .openai) == callback1455)
}

@Test func claudeScopeProxyHintAndTiming() {
    #expect(OAuthFlowCopy.claudeScope(.oauth, original: .oauth) == "完整权限")
    #expect(OAuthFlowCopy.claudeScope(.setupToken, original: nil) == "只授予推理权限")
    #expect(OAuthFlowCopy.claudeScope(.setupToken, original: .oauth) == "只授予推理权限 · 授权后账号类型改为 Setup Token")
    #expect(OAuthFlowCopy.claudeScope(.oauth, original: .setupToken) == "完整权限 · 授权后账号类型改为 OAuth")
    #expect(OAuthFlowCopy.proxyHint(proxyName: "hk-02") == "授权页要从代理 hk-02 的出口打开；手机做不到时，复制链接到走同一代理的电脑上打开")
    #expect(OAuthFlowCopy.lifetimeNote == "链接 30 分钟内有效")
    #expect(OAuthFlowCopy.remaining(1_799.2) == "已生成 · 30:00 内有效")
    #expect(OAuthFlowCopy.remaining(59) == "已生成 · 0:59 内有效")
}

@Test func precheckFailureAndUnconfirmedCopy() throws {
    #expect(AccountReauthorizePresentation.precheck(try reauthAccount(platform: "kiro")) == "这个账号不能在手机上重新授权")
    #expect(AccountReauthorizePresentation.precheck(try reauthAccount(type: "apikey")) == "这个账号不能在手机上重新授权")
    #expect(AccountReauthorizePresentation.precheck(try reauthAccount(platform: "openai", #""credentials":{"auth_mode":"personal_access_token"}"#))
        == "PAT 账号请在 Web 重新导入")
    #expect(AccountReauthorizePresentation.precheck(try reauthAccount(platform: "openai", #""credentials":{"openai_auth_mode":"PersonalAccessToken"}"#))
        == "PAT 账号请在 Web 重新导入")
    #expect(AccountReauthorizePresentation.precheck(try reauthAccount(#""parent_account_id":9"#)) == "影子账号的凭据跟随母账号，请重新授权母账号")
    #expect(AccountReauthorizePresentation.precheck(try reauthAccount()) == nil)
    #expect(AccountReauthorizePresentation.precheck(try reauthAccount(platform: "openai", #""credentials":{"auth_mode":"oauth"}"#)) == nil)
    #expect(AccountReauthorizePresentation.failure(reason: "站点暂时不可用") == "重新授权没有成功：站点暂时不可用")
    #expect(AccountReauthorizePresentation.unconfirmedTitle == "不能确认是否已替换")
}
