import Foundation

/// Who the three-step list serves: an account authorized again (20 §6.3) or a new account (20 §7.3).
public enum OAuthFlowVariant: Sendable, Equatable { case reauthorize, create }

/// How the code comes back: shown on the provider's page, or in the address of a local callback page.
public enum OAuthCodeDelivery: Sendable, Equatable {
    case displayedCode
    case callback(address: String)

    /// Before a link exists: the platform's usual way (Gemini AI Studio lands on localhost:1455 too).
    public static func expected(platform: OAuthPlatform, geminiType: GeminiOAuthType) -> OAuthCodeDelivery {
        if platform == .gemini, geminiType == .aiStudio { return .callback(address: "localhost:1455") }
        return platform.callbackAddress.map { .callback(address: $0) } ?? .displayedCode
    }
    /// A link's own `redirect_uri` wins over the table; a link without one falls back to it.
    public static func of(authURL: URL, platform: OAuthPlatform, geminiType: GeminiOAuthType = .codeAssist) -> OAuthCodeDelivery {
        if let endpoint = OAuthLoopback.endpoint(authURL: authURL) { return .callback(address: endpoint.address) }
        let redirects = URLComponents(url: authURL, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "redirect_uri" } == true
        return redirects ? .displayedCode : expected(platform: platform, geminiType: geminiType)
    }
}

/// 20 §6.3 / §7.3 the three steps' words (design AeReauthSheet and AnOAuthList).
public enum OAuthFlowCopy {
    public static let lifetimeNote = "链接 30 分钟内有效"
    public static let generate = "生成授权链接"
    public static let generating = "生成中…"
    public static let copyLink = "复制链接"
    public static let copied = "已复制"
    public static let open = "打开"
    public static let clear = "清空"
    public static let recognized = "已从链接里识别出 code 和 state"
    public static let listenFailedHint = "没能自动接收回调。重新打开浏览器，在 Safari 的错误页点底部“分享 → 拷贝”，再回来点“粘贴”。"

    /// The link's time left on the monotonic clock (OAuthLinkLifetime).
    public static func remaining(_ seconds: TimeInterval) -> String { "已生成 · \(DisplayFormat.countdown(seconds)) 内有效" }

    /// `platformName` is the account's platform as the App names it; a new account names who signs in instead.
    public static func title(_ step: OAuthFlowStep, variant: OAuthFlowVariant, platform: OAuthPlatform, platformName: String,
                             delivery: OAuthCodeDelivery) -> String {
        switch (step, variant) {
        case (.link, .reauthorize): "授权链接"
        case (.link, .create): generate
        case (.browser, .reauthorize): "登录 \(platformName) 并授权"
        case (.browser, .create): "在浏览器里登录 \(platform.signInName) 并授权"
        case (.code, _): delivery == .displayedCode ? "粘贴授权码" : variant == .create ? "完成授权" : "粘贴回调链接或 Code"
        }
    }
    /// `listening`: the App takes the callback itself (new accounts, S2-19).
    public static func browserNote(delivery: OAuthCodeDelivery, listening: Bool) -> String {
        switch delivery {
        case .displayedCode: "登录要授权的那个账号。授权后页面会显示授权码，复制它。"
        case .callback(let address) where listening: "授权后自动回到这里（App 临时监听 \(address)）"
        case .callback(let address): "登录要授权的那个账号。授权后浏览器跳到 \(address) 的页面（打不开是正常的），拷贝地址栏里的链接。"
        }
    }
    public static func codeLabel(_ delivery: OAuthCodeDelivery) -> String { delivery == .displayedCode ? "授权码" : "回调链接或 Code" }
    public static func codePlaceholder(_ delivery: OAuthCodeDelivery) -> String {
        delivery == .displayedCode ? "授权页显示的授权码" : "地址栏里的回调链接，或其中的 code"
    }
    public static func autoReceived(address: String) -> String { "已自动接收回调（\(address)），code 和 state 已填好" }
    /// Claude's method and its scope; picking the other one converts the account (design AE_REAUTH_SCOPE).
    public static func claudeScope(_ kind: OAuthAuthKind, original: OAuthAuthKind?) -> String {
        kind.scopeNote + (original.map { $0 == kind ? "" : " · 授权后账号类型改为 \(kind.title)" } ?? "")
    }
    public static func proxyHint(proxyName: String) -> String {
        "授权页要从代理 \(proxyName) 的出口打开；手机做不到时，复制链接到走同一代理的电脑上打开"
    }
}

/// “重新授权「X」？” before a stopped account's sheet opens (20 §6.4-1).
public struct AccountReauthorizeConfirmation: Sendable, Equatable {
    public let title: String
    public let message: String
}

/// 20 §6.3 / §6.4 the 重新授权 sheet's own words.
public enum AccountReauthorizePresentation {
    public static let title = "重新授权"
    public static let submit = "替换令牌"
    public static let continueTitle = "继续授权"
    public static let persistFailedTitle = "令牌已换到，但没保存成功"
    public static let unconfirmedTitle = "不能确认是否已替换"

    public static func targetLine(proxyID: Int?, proxyName: String?) -> String {
        guard let proxyID else { return "账号没有代理，授权页直连打开" }
        let name = OAuthLinkRequest.nonEmpty(proxyName) ?? "#\(proxyID)"
        return "授权走已保存的代理 \(name)；分组、并发和代理设置不变"
    }
    /// The server enables any account it authorizes (ClearAccountError), so every status shown as 停用 asks first: inactive, the
    /// historical disabled, anything unknown.
    public static func needsInactiveConfirmation(_ account: UpstreamAccount) -> Bool { account.status != "active" && account.status != "error" }
    public static func inactiveConfirmation(name: String, schedulable: Bool) -> AccountReauthorizeConfirmation {
        AccountReauthorizeConfirmation(title: "重新授权「\(name)」？",
                                       message: "这个账号现在是停用状态。授权后账号会被重新启用\(schedulable ? "并参与调度" : "，调度仍暂停")。")
    }
    public static func failure(reason: String) -> String { "重新授权没有成功：\(reason)" }

    /// What the server would refuse only after the code is spent (prepareReauthorize): such an account goes to the Web without a link.
    public static func precheck(_ account: UpstreamAccount) -> String? {
        guard let platform = OAuthPlatform(accountPlatform: account.platform), account.isTokenAccount else {
            return AccountOAuthErrorCopy.unsupportedText(nil)
        }
        if account.parentAccountID != nil { return AccountOAuthErrorCopy.unsupportedText("shadow_account") }
        if platform == .openai, isPersonalAccessToken(account) { return AccountOAuthErrorCopy.unsupportedText("codex_personal_access_token") }
        return nil
    }
    private static func isPersonalAccessToken(_ account: UpstreamAccount) -> Bool {
        ["auth_mode", "openai_auth_mode"].contains { key in
            let mode = account.credentials?[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return mode == "personal_access_token" || mode == "personalaccesstoken"
        }
    }
}
