import Foundation

/// 20 §3.3 模型: `credentials.model_mapping`, request model → actual model. Read like the backend's resolveModelMapping (string
/// values only) and the Web's splitModelMappingObject (a blank key or value is dropped, the rest kept as written). Rows show by
/// request model; ones added while editing go last. The table compares and saves as a whole, so its order never counts.
public struct AccountModelMapping: Equatable, Sendable {
    public struct Entry: Equatable, Hashable, Sendable, Identifiable {
        public let from: String
        public let to: String
        public var id: String { from }
        /// The row says 原样转发.
        public var isPassthrough: Bool { from == to }
        public init(from: String, to: String) { self.from = from; self.to = to }
    }
    public static let credentialKey = "model_mapping"
    public static let emptyText = "支持所有模型"
    public static let unlimitedText = "未限制"
    public static let passthroughText = "原样转发"
    public static let passthroughNote = "已开启自动透传，模型限制不生效"
    public static let footnote = "列表为空时支持所有模型；列出后，没列出的模型不会调度到这个账号。映射把请求模型换成实际模型，* 只能放在末尾。"

    public let entries: [Entry]
    public init(entries: [Entry] = []) { self.entries = entries }
    public init(credentials: JSONValue?) {
        let fields = credentials?[Self.credentialKey]?.objectValue ?? [:]
        entries = fields.compactMap { key, value -> Entry? in
            guard let to = value.stringValue, !Self.trimmed(key).isEmpty, !Self.trimmed(to).isEmpty else { return nil }
            return Entry(from: key, to: to)
        }.sorted { $0.from < $1.from }
    }

    public var isEmpty: Bool { entries.isEmpty }
    /// The section's top right: “只调度这 N 个” / “未限制”.
    public var summary: String { isEmpty ? Self.unlimitedText : "只调度这 \(DisplayFormat.grouped(entries.count)) 个" }
    public func entry(from model: String) -> Entry? { entries.first { $0.from == model } }

    /// 添加模型: each as {m: m}, like the Web whitelist (wildcards and models already listed are skipped).
    public func adding(models: [String]) -> AccountModelMapping {
        var rows = entries
        for model in models.map(Self.trimmed) where !model.isEmpty && !model.contains("*") && !rows.contains(where: { $0.from == model }) {
            rows.append(Entry(from: model, to: model))
        }
        return AccountModelMapping(entries: rows)
    }
    /// A tap in the 添加模型 list (design AeModelAddBody): a listed model leaves, mapping included; another one joins.
    public func toggling(model: String) -> AccountModelMapping {
        entry(from: model) == nil ? adding(models: [model]) : removing(from: model)
    }
    public func removing(from model: String) -> AccountModelMapping { AccountModelMapping(entries: entries.filter { $0.from != model }) }
    /// 添加映射, trimmed; the mapping is unchanged when the pair is refused.
    public func adding(from: String, to: String) throws -> AccountModelMapping {
        if let error = Self.validate(from: from, to: to, existing: self) { throw error }
        return AccountModelMapping(entries: entries + [Entry(from: Self.trimmed(from), to: Self.trimmed(to))])
    }
    /// The Web's isValidWildcardPattern: one `*`, at the end of the request model; none in the actual model.
    public static func validate(from: String, to: String, existing: AccountModelMapping) -> AccountModelMappingError? {
        let from = trimmed(from), to = trimmed(to)
        if from.isEmpty { return .emptyFrom }
        if let star = from.firstIndex(of: "*"), from.index(after: star) != from.endIndex { return .wildcardNotAtEnd }
        if existing.entry(from: from) != nil { return .duplicate }
        if to.contains("*") { return .wildcardInTarget }
        if to.isEmpty { return .emptyTo }
        return nil
    }

    public func sameTable(as other: AccountModelMapping) -> Bool { table == other.table }
    private var table: [String: String] { Dictionary(entries.map { ($0.from, $0.to) }) { first, _ in first } }
    /// nil for an empty table.
    public var jsonValue: JSONValue? { isEmpty ? nil : .object(table.mapValues(JSONValue.string)) }
    /// The whole table, or null when emptied (20 §3.3 保存).
    public var patchValue: JSONPatchValue { jsonValue.map(JSONPatchValue.set) ?? .delete }

    /// “限流 N 分钟” while the row's actual model is rate limited: the backend keys model limits by the mapped model
    /// (model_rate_limit.go modelRateLimitKeysForRequest → GetMappedModel). `now` is the site's ServerClock time.
    public static func limitBadge(for entry: Entry, limits: [AccountModelRateLimit], now: Date) -> String? {
        guard let limit = limits.first(where: { $0.model == entry.to && $0.resetAt > now }) else { return nil }
        return "限流 " + DisplayFormat.minutesLeft(limit.resetAt.timeIntervalSince(now))
    }
    /// Backend IsOpenAIPassthroughEnabled: OpenAI only; `openai_passthrough` decides when it is a boolean, else the old
    /// `openai_oauth_passthrough`.
    public static func passthroughEnabled(_ account: UpstreamAccount) -> Bool {
        guard account.platform == "openai" else { return false }
        if let flag = account.extra?["openai_passthrough"]?.boolValue { return flag }
        return account.extra?["openai_oauth_passthrough"]?.boolValue == true
    }
    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Why 添加映射 is refused; a blank side only greys the button.
public enum AccountModelMappingError: Error, Equatable, Sendable {
    case emptyFrom, emptyTo, wildcardNotAtEnd, wildcardInTarget, duplicate
    public var message: String? {
        switch self {
        case .emptyFrom, .emptyTo: nil
        case .wildcardNotAtEnd: "通配符 * 只能放在末尾"
        case .wildcardInTarget: "实际模型不能用通配符"
        case .duplicate: "这个请求模型已在列表里"
        }
    }
}

/// The 模型 sheet's copy of the table: one field, “模型”; the undo writes back the stored value as it was.
public struct AccountModelsDraft: Equatable, Sendable {
    public static let fieldName = "模型"
    public let base: AccountModelMapping
    public var mapping: AccountModelMapping
    private let stored: JSONValue?

    public init(account: UpstreamAccount) {
        base = AccountModelMapping(credentials: account.credentials)
        mapping = base
        stored = account.credentials?[AccountModelMapping.credentialKey]
    }
    public var hasChanges: Bool { !mapping.sameTable(as: base) }
    public var changedFieldNames: [String] { hasChanges ? [Self.fieldName] : [] }
    public func patch() -> AccountPatchRequest {
        hasChanges ? AccountPatchRequest(credentialsPatch: [AccountModelMapping.credentialKey: mapping.patchValue]) : AccountPatchRequest()
    }
    public func undoPatch() -> AccountPatchRequest {
        AccountPatchRequest(credentialsPatch: [AccountModelMapping.credentialKey: stored.map(JSONPatchValue.set) ?? .delete])
    }
    /// What 保存 hands to AccountPatchFlow; nil without a change (S2D1-08).
    public func change() -> AccountEditChange? {
        hasChanges ? AccountEditChange(fieldNames: changedFieldNames, request: patch(), undo: undoPatch()) : nil
    }
}
