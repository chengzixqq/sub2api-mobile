import Foundation

public protocol ListField: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    var title: String { get }
    static var defaultFields: [Self] { get }
    static var storageNamespace: String { get }
}

/// Stores presentation preferences only. Profile IDs isolate saved logins, including
/// two administrators using the same server. Unknown fields never become visible.
public struct ListFieldSelection<Field: ListField>: Equatable, Sendable {
    public private(set) var orderedFields: [Field]
    private var enabled: Set<Field>

    public init(rawValue: String? = nil) {
        let available = Array(Field.allCases)
        guard let rawValue, let data = rawValue.data(using: .utf8),
              let saved = try? JSONDecoder().decode(StoredSelection.self, from: data), saved.version == 1 else {
            orderedFields = available
            enabled = Set(Field.defaultFields)
            return
        }
        var seen = Set<Field>()
        let recovered = saved.order.compactMap(Field.init(rawValue:)).filter { seen.insert($0).inserted }
        let added = available.filter { !seen.contains($0) }
        orderedFields = recovered + added
        enabled = Set(saved.enabled.compactMap(Field.init(rawValue:)))
        // Newly introduced default fields are enabled once. Existing hidden fields
        // remain hidden because they are still present in the stored order.
        enabled.formUnion(added.filter { Field.defaultFields.contains($0) })
    }

    public var visibleFields: [Field] { orderedFields.filter { enabled.contains($0) } }
    public func isEnabled(_ field: Field) -> Bool { enabled.contains(field) }
    public mutating func setEnabled(_ value: Bool, for field: Field) {
        if value { enabled.insert(field) } else { enabled.remove(field) }
    }
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let valid = offsets.filter { orderedFields.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moved = valid.map { orderedFields[$0] }
        let remaining = orderedFields.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let insertion = max(0, min(remaining.count, destination - valid.filter { $0 < destination }.count))
        orderedFields = Array(remaining.prefix(insertion)) + moved + Array(remaining.dropFirst(insertion))
    }
    public var rawValue: String {
        let record = StoredSelection(version: 1, order: orderedFields.map(\.rawValue), enabled: visibleFields.map(\.rawValue))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(record)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    public static func storageKey(profileID: UUID?) -> String {
        "sub2mobile.list-fields.v1.\(Field.storageNamespace).\(profileID?.uuidString ?? "unconnected")"
    }
}

private struct StoredSelection: Codable { let version: Int; let order: [String]; let enabled: [String] }

public enum AccountListField: String, ListField, Codable {
    case platform, authenticationType, groups, concurrency, priority, rateMultiplier, status, schedulable
    case expiresAt, lastUsedAt, createdAt, notes, rpm, usage
    case accountID, capacity, todayStats, window, proxy, loadFactor, schedulerScore, upstreamBilling, baseRPM
    public static let storageNamespace = "accounts"
    public static let defaultFields: [Self] = [.platform, .authenticationType, .groups, .concurrency, .capacity, .rpm, .status, .schedulable]
    public var title: String {
        switch self {
        case .platform: "平台"
        case .authenticationType: "认证类型"
        case .groups: "分组"
        case .concurrency: "在用并发"
        case .priority: "优先级"
        case .rateMultiplier: "账号倍率"
        case .status: "状态"
        case .schedulable: "调度"
        case .expiresAt: "过期时间"
        case .lastUsedAt: "最后使用"
        case .createdAt: "创建时间"
        case .notes: "备注"
        case .rpm: "在用 RPM"
        case .usage: "配额已用"
        case .accountID: "账号 ID"
        case .capacity: "容量"
        case .todayStats: "今日统计"
        case .window: "用量窗口"
        case .proxy: "代理"
        case .loadFactor: "负载系数"
        case .schedulerScore: "调度权值"
        case .upstreamBilling: "上游声明倍率"
        case .baseRPM: "基础 RPM 限额"
        }
    }
}

public enum UserListField: String, ListField, Codable {
    case username, role, status, balance, concurrency, createdAt, lastUsedAt, lastActiveAt, notes, rpm
    public static let storageNamespace = "users"
    public static let defaultFields: [Self] = [.username, .role, .status, .balance, .concurrency]
    public var title: String {
        switch self {
        case .username: "用户名"
        case .role: "角色"
        case .status: "状态"
        case .balance: "余额"
        case .concurrency: "并发"
        case .createdAt: "创建时间"
        case .lastUsedAt: "最后使用"
        case .lastActiveAt: "最后活跃"
        case .notes: "备注"
        case .rpm: "RPM 限额"
        }
    }
}

public enum ListFieldPresentation {
    public static func timestamp(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "暂无记录" }
        let parser = ISO8601DateFormatter()
        var date = parser.date(from: value)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = parser.date(from: value)
        }
        guard let date else { return "时间格式不受支持" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    public static func timestamp(seconds: Int64?) -> String {
        guard let seconds else { return "未设置" }
        return Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(date: .abbreviated, time: .shortened)
    }
}
