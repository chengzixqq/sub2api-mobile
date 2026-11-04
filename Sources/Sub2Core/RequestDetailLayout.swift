import Foundation

/// The request detail's numbered sections (40 §7.1). The head card and the button row carry no number, as in the decided design
/// (S4D2a-14); the rest are numbered in the order they appear, from 壹.
public enum RequestDetailSection: String, CaseIterable, Sendable { case timing, attempts, tokens, links, identifiers }

/// One row of 关联 (40 §7.3). A missing name reads “—” and opens nothing, even with an id; the key never opens anything.
public struct RequestLinkRow: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable { case user, key, group, account }
    public let kind: Kind
    public let title: String
    /// 用户 / 分组 / 账号; the key's `key_masked`, or “prefix…” once the error detail has it; nil without one.
    public let trailing: String?
    /// Only the key's trailing text.
    public let isMonospacedTrailing: Bool
    /// The page a tap opens.
    public let targetID: Int?
    public var id: Kind { kind }
}

/// One row of 标识 (40 §7.3). 请求 ID always shows; the others only with a value.
public struct RequestIdentifierRow: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable { case request, client, upstream }
    public let kind: Kind
    /// 请求 ID / 服务端请求 ID / 上游请求 ID.
    public let label: String
    public let value: String
    public var id: Kind { kind }
}

/// The request detail's own wording (40 §7.5); S4-08b adds its buttons and receipts in an extension (S4D2a-08).
public enum RequestDetailCopy {
    public static let gone = "记录不存在或已清理"
    public static let opsDisabledDetail = "运维监控未开启，看不到更多信息"
    public static let detailFailed = "详情加载失败"
    public static let chainUnavailable = "没能取到重试链"
    public static let viewAccount = "查看账号"
    public static let loading = "正在读取记录…"
    /// The last fallback row of a recovered request whose success was not found: the client did get its answer.
    public static let laterTriesUnrecorded = "失败，后续尝试未记录"
    public static let expandHint = "点按展开全文"
}

/// Which sections the detail shows and what its 关联, 标识 and Token rows say (40 §7.3); S4-08 and S4-08b draw with it.
public enum RequestDetailLayout {
    /// 耗时 → 上游尝试 (when shown) → Token (the success look) → 关联 → 标识.
    public static func sections(style: RequestDetailStyle, showsAttempts: Bool) -> [RequestDetailSection] {
        [.timing] + (showsAttempts ? [.attempts] : []) + (style == .success ? [.tokens] : []) + [.links, .identifiers]
    }
    public static func ordinal(_ section: RequestDetailSection, in sections: [RequestDetailSection]) -> String? {
        sections.firstIndex(of: section).map { ChineseOrdinal.text($0 + 1) }
    }
    public static func title(_ section: RequestDetailSection) -> String {
        switch section {
        case .timing: "耗时"
        case .attempts: "上游尝试"
        case .tokens: "Token"
        case .links: "关联"
        case .identifiers: "标识"
        }
    }

    // MARK: 关联

    /// `user.username` ?? `user.email`, `api_key.name` with `key_masked`, `group.name`, `account.name`.
    public static func links(_ usage: UsageRequestRecord) -> [RequestLinkRow] {
        [link(.user, name: firstText(usage.userName, usage.userEmail), id: usage.userID),
         keyLink(name: usage.apiKeyName, trailing: usage.apiKeyMasked),
         link(.group, name: usage.groupName, id: usage.groupID),
         link(.account, name: usage.accountName, id: usage.accountID)]
    }
    /// `user_email`, `api_key_name` with the detail's `api_key_prefix…`, `group_name`, `account_name`.
    public static func links(_ record: RequestErrorRecord, detail: RequestErrorDetail?) -> [RequestLinkRow] {
        [link(.user, name: record.userEmail, id: record.userID),
         keyLink(name: record.apiKeyName, trailing: detail?.apiKeyPrefix.map { $0 + "…" }),
         link(.group, name: record.groupName, id: record.groupID),
         link(.account, name: record.accountName, id: record.accountID)]
    }

    // MARK: 标识

    /// `request_id`, then `upstream_request_id`.
    public static func identifiers(_ usage: UsageRequestRecord) -> [RequestIdentifierRow] {
        [identifier(.request, usage.requestID, always: true), identifier(.upstream, usage.upstreamRequestID)].compactMap { $0 }
    }
    /// `request_id`, `client_request_id`, then the chain's last `upstream_request_id`.
    public static func identifiers(_ record: RequestErrorRecord, chain: RequestAttempts?) -> [RequestIdentifierRow] {
        [identifier(.request, record.requestID, always: true), identifier(.client, record.clientRequestID),
         identifier(.upstream, chain.flatMap(RequestDetailPresentation.lastUpstreamRequestID))].compactMap { $0 }
    }

    // MARK: Token

    /// 输入 / 输出 / 缓存读 / 缓存写, grouped by thousands.
    public static func tokenCells(_ usage: UsageRequestRecord) -> [RequestCostCell] {
        [("输入", usage.inputTokens), ("输出", usage.outputTokens), ("缓存读", usage.cacheReadTokens), ("缓存写", usage.cacheCreationTokens)]
            .map { RequestCostCell(label: $0.0, value: DisplayFormat.grouped($0.1)) }
    }

    private static func link(_ kind: RequestLinkRow.Kind, name: String?, id: Int?) -> RequestLinkRow {
        let title = RequestDetailPresentation.trimmed(name)
        let trailing: String? = switch kind {
        case .user: "用户"
        case .group: "分组"
        case .account: "账号"
        case .key: nil
        }
        return RequestLinkRow(kind: kind, title: title ?? DisplayFormat.missing, trailing: trailing, isMonospacedTrailing: false,
                              targetID: title == nil ? nil : id.flatMap { $0 > 0 ? $0 : nil })
    }
    private static func keyLink(name: String?, trailing: String?) -> RequestLinkRow {
        RequestLinkRow(kind: .key, title: RequestDetailPresentation.trimmed(name) ?? DisplayFormat.missing,
                       trailing: RequestDetailPresentation.trimmed(trailing), isMonospacedTrailing: true, targetID: nil)
    }
    private static func identifier(_ kind: RequestIdentifierRow.Kind, _ value: String?, always: Bool = false) -> RequestIdentifierRow? {
        let text = RequestDetailPresentation.trimmed(value)
        guard text != nil || always else { return nil }
        let label = switch kind {
        case .request: "请求 ID"
        case .client: "服务端请求 ID"
        case .upstream: "上游请求 ID"
        }
        return RequestIdentifierRow(kind: kind, label: label, value: text ?? DisplayFormat.missing)
    }
    private static func firstText(_ values: String?...) -> String? { values.lazy.compactMap(RequestDetailPresentation.trimmed).first }
}

extension RequestDetailPresentation {
    /// A recovered request (`clientSucceeded`) whose success the fallback could not find: the last failure did not reach the
    /// client, so its line reads “失败，后续尝试未记录” instead of “失败，错误返回客户端”. Otherwise `fallbackRows(events:success:)`.
    public static func fallbackRows(events: [UpstreamErrorEvent], success: UsageRequestRecord?, clientSucceeded: Bool) -> [AttemptRow] {
        let rows = fallbackRows(events: events, success: success)
        guard clientSucceeded, success == nil, let last = rows.last else { return rows }
        return rows.dropLast() + [AttemptRow(id: last.id, title: last.title, accountID: last.accountID, trailing: last.trailing,
                                             subtitle: RequestDetailCopy.laterTriesUnrecorded, tone: last.tone)]
    }
}
