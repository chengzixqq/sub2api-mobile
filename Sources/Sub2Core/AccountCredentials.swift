import Foundation

/// 20 §6.3: what the API Key sheet shows of a pasted key. Only the masked form is kept.
public struct APIKeyPreview: Sendable, Equatable {
    /// The first one that matches is shown.
    public static let recognizedPrefixes = ["sk-ant-api03-", "sk-proj-", "sk-", "AIza", "xai-", "AKIA"]
    public static let emptyText = "当前密钥已设置，不可查看"
    private static let dot: Character = "•"
    public let masked: String
    public let characterCount: Int

    public init?(_ input: String) {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        characterCount = key.count
        guard key.count > 8 else { masked = String(repeating: Self.dot, count: key.count); return }
        // A prefix is shown only when a part of the key stays hidden between it and the last four characters.
        let prefix = Self.recognizedPrefixes.first { key.hasPrefix($0) && key.count > $0.count + 4 } ?? ""
        masked = prefix + String(repeating: Self.dot, count: 4) + key.suffix(4)
    }
    /// “新密钥 sk-ant-api03-••••1234 · 25 个字符”.
    public var text: String { "新密钥 \(masked) · \(characterCount) 个字符" }
}

/// 20 §6.3 Base URL sheet.
public enum BaseURLRule {
    public static let invalidMessage = "地址要以 http:// 或 https:// 开头"
    public enum Verdict: Sendable, Equatable {
        case url(String)
        /// Left empty: the platform's official address.
        case officialDefault
        case invalid
        /// The `credentials_patch` value: an address, or null to go back to the official one (base_url is not a secret key).
        public var patchValue: JSONPatchValue? {
            switch self {
            case .url(let value): .set(.string(value))
            case .officialDefault: .delete
            case .invalid: nil
            }
        }
    }
    public static func validate(_ input: String) -> Verdict {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .officialDefault }
        return value.range(of: #"^https?://[^\s/]+"#, options: .regularExpression) == nil ? .invalid : .url(value)
    }
    /// 对接上游 (Antigravity API Key, and the older `upstream` type) has no official address: no 改回官方地址, and an empty field
    /// counts as not filled in.
    public static func requiresValue(platform: String, type: String) -> Bool {
        type == "upstream" || (platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "antigravity" && type == "apikey")
    }
    /// Greys out the save button.
    public static func isUnchanged(_ verdict: Verdict, current: String?) -> Bool {
        let saved = current?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch verdict {
        case .url(let value): return value == saved
        case .officialDefault: return saved.isEmpty
        case .invalid: return false
        }
    }
}

/// `POST :id/refresh`'s data: the account, or `{account, message, warning}` when Antigravity's project_id is still missing.
/// `message` is never read (00 §3.4).
public struct AccountRefreshResult: Decodable, Sendable {
    public static let missingProjectIDWarning = "missing_project_id_temporary"
    public let account: UpstreamAccount
    public let warning: String?
    public init(account: UpstreamAccount, warning: String? = nil) { self.account = account; self.warning = warning }
    private enum CodingKeys: String, CodingKey { case account, warning }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.account) else { self.init(account: try UpstreamAccount(from: decoder)); return }
        let warning = (try? c.decodeIfPresent(String.self, forKey: .warning)) ?? nil
        self.init(account: try c.decode(UpstreamAccount.self, forKey: .account), warning: warning?.isEmpty == false ? warning : nil)
    }
}

extension APIClient {
    /// 20 §6.4. With a key (admin.idempotent_writes, made at the tap, R05) the keyed executor retries within the single-account
    /// refresh limit (65 seconds) and an unanswered refresh ends as KeyedWriteFailure; without one it is sent once (00 §2.4).
    public func refreshAccount(id: Int, idempotencyKey: UUID?, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AccountRefreshResult> {
        let path = try accountPath(id, "/refresh"), body = Data("{}".utf8)
        guard let key = idempotencyKey else { return try await performUnkeyedWrite(path, method: "POST", body: body, requestID: UUID().uuidString.lowercased()) }
        return try await performKeyedWrite(KeyedWriteRequest(path: path, method: "POST", body: body, key: key, timeout: RequestTimeout.keyedBulk),
                                           onEvent: onEvent)
    }
}

/// The access token's times. `token_status` (accounts.token_status) is the only source when present; a server without it
/// leaves `credentials.expires_at` (Unix seconds or RFC 3339).
public enum AccountTokenTiming {
    private static let plausible = Date(timeIntervalSince1970: 946_684_800)...Date(timeIntervalSince1970: 7_258_118_400) // 2000–2200

    public static func expiresAt(_ account: UpstreamAccount) -> Date? {
        let date: Date?
        if let status = account.tokenStatus { date = ServerTime.parseTimestamp(status.expiresAt) }
        else { date = legacyExpiry(account.credentials?["expires_at"]) }
        return date.flatMap { plausible.contains($0) ? $0 : nil }
    }
    public static func refreshedAt(_ account: UpstreamAccount) -> Date? { ServerTime.parseTimestamp(account.tokenStatus?.refreshedAt) }

    private static func legacyExpiry(_ value: JSONValue?) -> Date? {
        switch value {
        case .number(let seconds)?: return Date(timeIntervalSince1970: NSDecimalNumber(decimal: seconds).doubleValue)
        case .string(let text)?:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let seconds = Int64(trimmed) { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
            return ServerTime.parseTimestamp(trimmed)
        default: return nil
        }
    }
}

/// 20 §6.4 / §6.5 read-back after a refresh or re-authorization whose result is unknown.
public enum AccountTokenReadback: Sendable, Equatable {
    case replaced, notReplaced
    /// No token_status on this server: the App cannot tell.
    case unknown
    /// The server stores whole seconds; this covers that and a small clock offset.
    public static let clockSlack: TimeInterval = 2

    /// `startedAt` is the ServerClock time taken before sending; `previousRefreshedAt` the value read before the write.
    public static func check(_ account: UpstreamAccount, since startedAt: Date, previousRefreshedAt: Date? = nil) -> AccountTokenReadback {
        guard account.tokenStatus != nil else { return .unknown }
        guard let refreshed = AccountTokenTiming.refreshedAt(account) else { return .notReplaced }
        let earliest = startedAt.timeIntervalSince1970.rounded(.down) - clockSlack
        if refreshed.timeIntervalSince1970 >= earliest { return .replaced }
        if let previousRefreshedAt, refreshed > previousRefreshedAt { return .replaced }
        return .notReplaced
    }
}

extension AccountWriteCheck {
    public static func tokenReplaced(_ account: UpstreamAccount, since startedAt: Date, previousRefreshedAt: Date? = nil) -> AccountTokenReadback {
        AccountTokenReadback.check(account, since: startedAt, previousRefreshedAt: previousRefreshedAt)
    }
}

/// A re-authorization receipt and its button.
public struct AccountCredentialReceipt: Sendable, Equatable {
    public enum FollowUp: Sendable, Equatable {
        case test, enableScheduling
        public var title: String { self == .test ? "测试" : "启用调度" }
    }
    public let text: String
    public let followUp: FollowUp
    public init(text: String, followUp: FollowUp) { self.text = text; self.followUp = followUp }
}

/// 20 §6.3 receipts and the note under 替换令牌 (design aeReauthResult / aeReauthNote). `now` is always the caller's ServerClock time.
public enum AccountCredentialCopy {
    public static let refreshedWithoutProjectID = "已刷新令牌，project_id 暂未取到（会自动重试）"

    public static func refreshReceipt(_ result: AccountRefreshResult, timeZone: TimeZone) -> String {
        if result.warning == AccountRefreshResult.missingProjectIDWarning { return refreshedWithoutProjectID }
        guard let expiry = AccountTokenTiming.expiresAt(result.account) else { return "已刷新令牌" }
        return "已刷新令牌 · 新令牌 \(DisplayFormat.clock(expiry, timeZone: timeZone)) 到期"
    }

    /// Compares the account before and after: what was cleared (the state, and model limits gone since), whether it came back
    /// enabled, and the schedule switch, which re-authorization never changes.
    public static func reauthorizeReceipt(before: UpstreamAccount, after: UpstreamAccount, switchedTo: OAuthAuthKind?, now: Date) -> AccountCredentialReceipt {
        let old = AccountDisplayState(before, now: now), new = AccountDisplayState(after, now: now)
        let stateWord = clearedWord(old.state).flatMap { new.state == old.state ? nil : $0 }
        let remaining = Set(new.modelRateLimits.map(\.model))
        let cleared = clearedPhrase(stateWord, models: old.modelRateLimits.filter { !remaining.contains($0.model) }.count)
        let touched = stateWord != nil || old.state == .inactive
        let tail = old.state == .inactive && after.status == "active" ? "已启用账号" : cleared.map { "已清除\($0)" } ?? "令牌已替换"
        let schedule = touched ? (new.state == .available ? " · 参与调度" : " · 仍暂停调度") : ""
        let head = switchedTo.map { "已重新授权 · 账号类型改为 \(typeWord($0))" } ?? "已重新授权"
        let followUp: AccountCredentialReceipt.FollowUp = new.state == .available || old.state == .available ? .test : .enableScheduling
        return AccountCredentialReceipt(text: "\(head) · \(tail)\(schedule)", followUp: followUp)
    }

    /// “点按后立即保存新令牌[，账号类型改为 X][，并重新启用账号 / ，并清除{…}]；调度开关不变。[…之后仍暂停。]站点不再使用旧令牌，不能撤回[；之后验证 Face ID]”.
    public static func replaceTokenNote(_ account: UpstreamAccount, switchedTo: OAuthAuthKind?, verifiesWithFaceID: Bool, now: Date) -> String {
        let display = AccountDisplayState(account, now: now)
        let cleared = clearedPhrase(clearedWord(display.state), models: display.modelRateLimits.count)
        let kind = switchedTo.map { "，账号类型改为 \(typeWord($0))" } ?? ""
        let effect = display.state == .inactive ? "，并重新启用账号" : cleared.map { "，并清除\($0)" } ?? ""
        let stays = display.state == .error ? "出错时已停止调度，之后仍暂停。"
            : cleared != nil && !account.schedulable ? "账号已停止调度，之后仍暂停。" : ""
        return "点按后立即保存新令牌\(kind)\(effect)；调度开关不变。\(stays)站点不再使用旧令牌，不能撤回" + (verifiesWithFaceID ? "；之后验证 Face ID" : "")
    }

    private static func clearedWord(_ state: AccountScheduleState) -> String? {
        switch state {
        case .error: "错误"
        case .rateLimited: "限流"
        case .overloaded: "过载"
        case .tempUnschedulable: "临时不可调度"
        case .paused, .inactive, .available: nil
        }
    }
    /// “限流和 2 项模型限流”, “错误”, or “ 1 项模型限流” on its own.
    private static func clearedPhrase(_ word: String?, models: Int) -> String? {
        let parts = [word, models > 0 ? " \(models) 项模型限流" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "和")
    }
    /// “Setup Token” never breaks across lines inside a sentence.
    private static func typeWord(_ kind: OAuthAuthKind) -> String { kind.title.replacingOccurrences(of: " ", with: "\u{00A0}") }
}
