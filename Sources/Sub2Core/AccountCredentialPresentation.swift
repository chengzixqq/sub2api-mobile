import Foundation

/// 20 §3.3 凭据: the rows an account's credentials take on the detail.
public enum AccountCredentialKind: Sendable, Equatable {
    /// How a key account's Base URL row edits.
    public enum BaseURLEdit: Sendable, Equatable {
        /// 修改 opens the sheet, which offers 改回官方地址.
        case optional
        /// 对接上游 has no official address (BaseURLRule.requiresValue).
        case required
        /// S2D1-22: a multi-protocol platform's endpoints are edited on the Web.
        case inWeb
    }
    /// API Key and Base URL.
    case key(BaseURLEdit)
    /// OAuth and Setup Token: the access token, 刷新令牌 and 重新授权….
    case token
    /// U17: AWS Bedrock and Vertex credentials are changed on the Web.
    case webOnly

    public static func of(_ account: UpstreamAccount, catalog: MetaCatalog) -> AccountCredentialKind {
        if account.isTokenAccount { return .token }
        if account.type == "bedrock" || account.type == "service_account" { return .webOnly }
        if catalog.platform(account.platform)?.multiProtocol != nil { return .key(.inWeb) }
        return .key(BaseURLRule.requiresValue(platform: account.platform, type: account.type) ? .required : .optional)
    }

    /// ⋯'s credential items, first in the menu (20 §3.4); S2-17 adds 重新授权….
    public var menuActions: [AccountCredentialMenuAction] {
        switch self {
        case .key: [.replaceKey]
        case .token: [.refresh]
        case .webOnly: []
        }
    }
    /// The section's footnote; Bedrock and Vertex have none in 20 §3.3, so theirs points to the Web.
    public var footer: String {
        switch self {
        case .key: "已保存的密钥不可查看，只能更换。更换立即生效、不能撤销；站点不再保存旧密钥，但它在上游仍然有效，泄露时请到上游控制台吊销。"
        case .token: "令牌到期前自动刷新。刷新令牌、重新授权都立即生效，不能撤销；重新授权会同时清除错误、限流状态（停用的账号会被重新启用），调度开关不变。"
        case .webOnly: "已保存的凭据不可查看；这类凭据请在 Web 中更换。"
        }
    }
}

/// ⋯'s credential items; the raw value names them (`account.detail.more.<raw>`).
public enum AccountCredentialMenuAction: String, Sendable, CaseIterable, Identifiable {
    case replaceKey, refresh
    public var id: String { rawValue }
    public var title: String { self == .replaceKey ? "更换 API Key…" : AccountRefreshCopy.title }
    public var systemImage: String { self == .replaceKey ? "key" : "arrow.clockwise" }
}

/// The API Key row: what is stored (never the key) and what it needs.
public struct AccountKeyRow: Sendable, Equatable {
    public enum Hint: Sendable, Equatable {
        /// A credential error and no new key this session.
        case rejected(statusCode: Int?)
        /// A new key this session while the error stays: only a passing test clears it.
        case awaitingTest(stillPaused: Bool)

        public var text: String {
            switch self {
            case .rejected(let code): "上游拒绝了这个密钥\(code.map { "（\($0)）" } ?? "")，需要更换"
            case .awaitingTest(let paused): "已更换：测试连接通过后自动清除错误" + (paused ? "（仍暂停调度）" : "")
            }
        }
        public var tone: Tone {
            if case .rejected = self { return .critical }
            return .neutral
        }
    }
    public let value: String
    public let isReplaced: Bool
    public let hint: Hint?
}

/// The Base URL row: `credentials.base_url` as stored, or the platform's official address.
public enum AccountBaseURLValue: Sendable, Equatable {
    /// The list's copy carries no credentials yet.
    case unknown
    case official
    case custom(String)
    public var text: String {
        switch self {
        case .unknown: DisplayFormat.missing
        case .official: AccountCredentialPresentation.official
        case .custom(let url): url
        }
    }
}

/// The access token row (no gauge: the design draws none, 20 §0.1).
public struct AccountTokenRow: Sendable, Equatable {
    public enum Badge: String, Sendable, CaseIterable {
        case valid, expiring, expired
        public var title: String {
            switch self {
            case .valid: "有效"
            case .expiring: "即将到期"
            case .expired: "已过期"
            }
        }
        public var tone: Tone {
            switch self {
            case .valid: .ok
            case .expiring: .caution
            case .expired: .critical
            }
        }
    }
    /// nil while the expiry is unknown.
    public let badge: Badge?
    public let text: String
    /// “不会自动刷新” for `token_status.auto_refresh == false`.
    public let note: String?
}

/// 20 §3.3 凭据 rows. `now` is always the site's ServerClock time and absolute times use the server's zone (20 §0.6).
public enum AccountCredentialPresentation {
    public static let title = "凭据"
    public static let immediate = "立即生效"
    public static let official = "官方地址"
    public static let stored = "已设置 · 不可查看"
    public static let unset = "未设置"
    public static let noAutoRefresh = "不会自动刷新"
    private static let hour: TimeInterval = 3_600, day: TimeInterval = 86_400

    /// “已更换 · HH:MM” for a key replaced this session (`replacedAt`, ServerClock time). R12: the code is error_status_code only.
    public static func keyRow(_ account: UpstreamAccount, replacedAt: Date?, now: Date, timeZone: TimeZone) -> AccountKeyRow {
        let value = replacedAt.map { "已更换 · " + DisplayFormat.clock($0, timeZone: timeZone) } ?? secretValue(account, flag: "has_api_key")
        let credentialError = AccountDisplayState(account, now: now).isCredentialError
        let hint: AccountKeyRow.Hint? = !credentialError ? nil
            : replacedAt == nil ? .rejected(statusCode: account.errorStatusCode) : .awaitingTest(stillPaused: !account.schedulable)
        return AccountKeyRow(value: value, isReplaced: replacedAt != nil, hint: hint)
    }
    /// Bedrock and Vertex: any stored secret counts.
    public static func storedSecret(_ account: UpstreamAccount) -> String { secretValue(account, flag: nil) }

    public static func baseURL(_ account: UpstreamAccount) -> AccountBaseURLValue {
        guard let credentials = account.credentials else { return .unknown }
        let url = credentials["base_url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return url.isEmpty ? .official : .custom(url)
    }

    /// 有效 from an hour left, 即将到期 below, 已过期 at 0; “N 分钟后” rounds up, “N 小时后” to the nearest hour, “N 天后” down.
    /// The expiry reads HH:MM within a day of now, yyyy-MM-dd HH:mm otherwise (a Setup Token lives about a year).
    public static func tokenRow(_ account: UpstreamAccount, now: Date, timeZone: TimeZone) -> AccountTokenRow {
        let note = account.tokenStatus?.autoRefresh == false ? noAutoRefresh : nil
        guard let expiry = AccountTokenTiming.expiresAt(account) else { return AccountTokenRow(badge: nil, text: DisplayFormat.missing, note: note) }
        let left = expiry.timeIntervalSince(now)
        let badge: AccountTokenRow.Badge = left >= hour ? .valid : left > 0 ? .expiring : .expired
        let at = abs(left) < day ? DisplayFormat.clock(expiry, timeZone: timeZone)
            : AccountExpiry.text(AccountExpiry.seconds(of: expiry), timeZone: timeZone)
        return AccountTokenRow(badge: badge, text: "\(remaining(left))（到期 \(at)）", note: note)
    }

    private static func remaining(_ left: TimeInterval) -> String {
        if left <= 0 { return AccountTokenRow.Badge.expired.title }
        if left < hour { return "\(max(1, Int((left / 60).rounded(.up)))) 分钟后" }
        if left < day { return "\(Int((left / hour).rounded())) 小时后" }
        return "\(Int((left / day).rounded(.down))) 天后"
    }
    /// The backend sends has_<key> only for a stored secret (credentials_status is omitempty); the list's copy has neither.
    private static func secretValue(_ account: UpstreamAccount, flag: String?) -> String {
        let flags = account.credentialsStatus ?? [:]
        let isStored = flag.map { flags[$0] == true } ?? flags.values.contains(true)
        if isStored { return stored }
        return account.credentials == nil && account.credentialsStatus == nil ? DisplayFormat.missing : unset
    }
}

/// 20 §6.3 更换 API Key sheet. The key lives only in the sheet and in the request; neither prints it.
public enum AccountKeySheetCopy {
    public static let title = "更换 API Key"
    public static let fieldName = "API Key"
    public static let fieldLabel = "新 API Key"
    public static let placeholder = "粘贴新的 API Key"
    public static let submit = "更换 API Key"
    public static let receipt = "已更换 API Key"
    /// The receipt's button: the connection test (20 §0.4-2).
    public static let test = "测试"

    public static func target(name: String) -> String { "\(name) · 点按底部按钮后立即生效" }
    public static func footer(verifiesFaceID: Bool) -> String {
        "站点立即改用新密钥，旧密钥不再保存、不能找回；如果旧密钥泄露，请到上游控制台吊销" + (verifiesFaceID ? "。点按后验证 Face ID" : "")
    }
    /// Only `credentials_patch.api_key`, trimmed; nil while nothing is pasted. Never undone (20 §0.4-2).
    public static func change(forKey raw: String) -> AccountEditChange? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return AccountEditChange(fieldNames: [fieldName], request: AccountPatchRequest(credentialsPatch: ["api_key": .set(.string(key))]), undo: nil)
    }
}

/// 20 §6.3 Base URL sheet: the field over the saved `base_url`. Leaving it empty goes back to the official address (null), except
/// for 对接上游, which needs one.
public struct AccountBaseURLDraft: Sendable, Equatable {
    public static let title = "Base URL"
    public static let placeholder = "留空使用官方地址"
    public static let clear = "清空"
    public static let requiredMessage = "对接上游需要填写 Base URL"
    public static let customNote = "请求改发到这个地址"
    public static let officialNote = "留空：使用官方地址"

    public let original: String
    public let isRequired: Bool
    public var text: String

    public init(account: UpstreamAccount) {
        if case .custom(let url) = AccountCredentialPresentation.baseURL(account) { original = url } else { original = "" }
        isRequired = BaseURLRule.requiresValue(platform: account.platform, type: account.type)
        text = original
    }

    public var verdict: BaseURLRule.Verdict { BaseURLRule.validate(text) }
    public var isChanged: Bool { !BaseURLRule.isUnchanged(verdict, current: original) }
    public var error: String? {
        switch verdict {
        case .invalid: BaseURLRule.invalidMessage
        case .officialDefault where isRequired: Self.requiredMessage
        default: nil
        }
    }
    /// The line under the field (design AeUrlSheet).
    public var note: String { error ?? (verdict == .officialDefault ? Self.officialNote : Self.customNote) }
    public var isRestore: Bool { isChanged && verdict == .officialDefault && !isRequired }
    public var submitTitle: String { isRestore ? "改回官方地址" : "保存 Base URL" }
    public var canSubmit: Bool { isChanged && error == nil }
    public var receipt: String { isRestore ? "已改回官方地址" : "已保存 Base URL" }
    /// No undo: the receipt offers 测试 instead (design aeToastTest).
    public var change: AccountEditChange? {
        guard canSubmit, let value = verdict.patchValue else { return nil }
        return AccountEditChange(fieldNames: [Self.title], request: AccountPatchRequest(credentialsPatch: ["base_url": value]), undo: nil)
    }
}

/// 20 §6.4 刷新令牌's receipts beyond the success one (AccountCredentialCopy.refreshReceipt).
public enum AccountRefreshCopy {
    public static let title = "刷新令牌"
    public static let notApplied = "刷新令牌没有生效，可以重试"
    public static let unconfirmedRetry = "刷新令牌结果未确认，可用同一编号重试"
    public static let storeUnavailable = "刷新令牌没有生效：服务器暂时无法受理，稍后用同一编号重试"
    public static let shadowAccount = "影子账号的凭据跟随母账号，请刷新母账号的令牌"
    static let shadowReason = "SPARK_SHADOW_NO_REFRESH"

    public static func failed(reason: String) -> String { "刷新令牌没有成功：\(reason)" }
    /// The refresh endpoint answers a missing account with a 404 without reason; a non-JSON 404 is an unsupported site.
    public static func isMissing(_ error: any Error) -> Bool {
        guard let api = error as? APIError, api.statusCode == 404, api.kind != .unsupported else { return false }
        return api.reason == nil || api.reason == AccountWriteReason.notFound
    }
    public static func reason(for error: any Error) -> String {
        if let api = error as? APIError, api.statusCode == 400, api.reason == shadowReason { return shadowAccount }
        return isMissing(error) ? AccountActionCopy.missingReason : AccountActionCopy.reason(for: error)
    }
}
