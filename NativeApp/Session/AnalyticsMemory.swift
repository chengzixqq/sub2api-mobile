import Foundation
import Sub2Core

/// 40 §1.2: one condition at a time, a group or a model (the filter sheet picks requested model names).
enum AnalyticsFilter: Hashable, Sendable {
    case group(id: Int)
    case model(name: String)

    enum Kind: String, CaseIterable, Hashable, Sendable {
        case group, model
        var title: String { self == .group ? "分组" : "模型" }
    }

    var kind: Kind {
        switch self {
        case .group: .group
        case .model: .model
        }
    }
    /// “group:3”, “model:<name>”; a model name may hold colons, so only the first one splits.
    var storedValue: String {
        switch self {
        case .group(let id): "group:\(id)"
        case .model(let name): "model:" + name
        }
    }
    init?(storedValue: String) {
        guard let colon = storedValue.firstIndex(of: ":") else { return nil }
        let value = String(storedValue[storedValue.index(after: colon)...])
        switch storedValue[..<colon] {
        case "group":
            guard let id = Int(value), id > 0 else { return nil }
            self = .group(id: id)
        case "model":
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            self = .model(name: value)
        default:
            return nil
        }
    }

    /// `usage/stats` and `dashboard/*` (40 §1.2 参数映射): `model_source=requested` only where the site reads it; an older server
    /// reads a model alone as requested anyway.
    func applied(to query: AnalyticsQuery, supportsModelSource: Bool) -> AnalyticsQuery {
        var scoped = query
        switch self {
        case .group(let id):
            scoped.groupID = id; scoped.model = nil; scoped.modelSource = nil
        case .model(let name):
            scoped.groupID = nil; scoped.model = name; scoped.modelSource = supportsModelSource ? .requested : nil
        }
        return scoped
    }
    /// `ops/dashboard/*`: OpsQuery itself leaves the model out where the site cannot filter by it.
    func opsQuery(start: Date, end: Date) -> OpsQuery {
        switch self {
        case .group(let id): OpsQuery(start: start, end: end, groupID: id)
        case .model(let name): OpsQuery(start: start, end: end, model: name, modelSource: .requested)
        }
    }
}

/// 40 §1.4 RPM / TPM 卡的窗口.
enum PerfWindow: Int, CaseIterable, Hashable, Sendable {
    case h1 = 1, h6 = 6, h24 = 24
    var hours: Int { rawValue }
    var title: String { "近 \(rawValue) 小时" }
}

extension AnalyticsEntryRange {
    var selection: AnalyticsRangeSelection { .preset(self == .today ? .today : .last7) }
}

/// 40 §0.1 本机记忆: the analytics choices per site in UserDefaults (`analytics.<站点 id>.<项>`), only interface preferences. App state
/// (X03): signing out and switching sites keep it, deleting a site removes it. Written only when the user changes a choice
/// (S4D1-03), except `route.metric`, which the spec writes back.
@MainActor
struct AnalyticsMemory {
    let defaults: UserDefaults

    enum Item {
        static let range = "range", rangeStart = "range.start", rangeEnd = "range.end", filter = "filter"
        static let rankCard = "rankCard", rankModelSource = "rankModelSource", perfWindow = "perfWindow", perfMetric = "perfMetric"
        static func rankSort(_ dimension: AnalyticsRankDimension) -> String { "rankSort." + dimension.rawValue }
    }
    static func key(_ item: String, serverID: UUID) -> String { prefix(serverID) + item }
    private static func prefix(_ serverID: UUID) -> String { "analytics." + serverID.uuidString + "." }
    private static let customRange = "custom"

    // MARK: Range and filter

    /// The remembered range, else the entry's. A custom range must lie within `bounds` (U36); one that does not, and any value this
    /// App cannot read, is removed.
    func range(serverID: UUID, entry: AnalyticsEntryRange, bounds: AnalyticsDayBounds) -> AnalyticsRangeSelection {
        guard let stored = string(Item.range, serverID) else { return entry.selection }
        if let preset = AnalyticsPreset(rawValue: stored) { return .preset(preset) }
        if stored == Self.customRange, let from = day(Item.rangeStart, serverID), let to = day(Item.rangeEnd, serverID),
           from <= to, bounds.contains(from), bounds.contains(to) {
            return .custom(from: from, to: to)
        }
        remove([Item.range, Item.rangeStart, Item.rangeEnd], serverID)
        return entry.selection
    }
    /// A preset by its key, recomputed from today on the next entry; a custom range by its days.
    func setRange(_ selection: AnalyticsRangeSelection, serverID: UUID) {
        switch selection {
        case .preset(let preset):
            set(preset.rawValue, Item.range, serverID)
            remove([Item.rangeStart, Item.rangeEnd], serverID)
        case .custom(let from, let to):
            set(Self.customRange, Item.range, serverID)
            set(from.description, Item.rangeStart, serverID)
            set(to.description, Item.rangeEnd, serverID)
        }
    }
    func filter(serverID: UUID) -> AnalyticsFilter? {
        guard let stored = string(Item.filter, serverID) else { return nil }
        guard let filter = AnalyticsFilter(storedValue: stored) else {
            remove([Item.filter], serverID)
            return nil
        }
        return filter
    }
    func setFilter(_ filter: AnalyticsFilter?, serverID: UUID) {
        guard let filter else { return remove([Item.filter], serverID) }
        set(filter.storedValue, Item.filter, serverID)
    }
    /// Only once `groups/all` has loaded: a remembered group no longer in it is dropped; an inactive one stays.
    func validatedFilter(serverID: UUID, groups: [AdminGroup]) -> AnalyticsFilter? {
        let filter = filter(serverID: serverID)
        guard case .group(let id)? = filter, !groups.contains(where: { $0.id == id }) else { return filter }
        setFilter(nil, serverID: serverID)
        return nil
    }

    // MARK: Rankings (40 §4.4) and RPM / TPM (40 §1.4)

    func rankCardDimension(serverID: UUID) -> AnalyticsRankDimension { value(Item.rankCard, serverID) ?? .model }
    func setRankCardDimension(_ dimension: AnalyticsRankDimension, serverID: UUID) { set(dimension.rawValue, Item.rankCard, serverID) }
    func rankSort(for dimension: AnalyticsRankDimension, serverID: UUID) -> AnalyticsRankMetric {
        value(Item.rankSort(dimension), serverID) ?? .actualCost
    }
    func setRankSort(_ metric: AnalyticsRankMetric, for dimension: AnalyticsRankDimension, serverID: UUID) {
        set(metric.rawValue, Item.rankSort(dimension), serverID)
    }
    func rankModelSource(serverID: UUID) -> ModelSource { value(Item.rankModelSource, serverID) ?? .requested }
    func setRankModelSource(_ source: ModelSource, serverID: UUID) { set(source.rawValue, Item.rankModelSource, serverID) }
    func perfWindow(serverID: UUID) -> PerfWindow {
        (defaults.object(forKey: Self.key(Item.perfWindow, serverID: serverID)) as? Int).flatMap { PerfWindow(rawValue: $0) } ?? .h1
    }
    func setPerfWindow(_ window: PerfWindow, serverID: UUID) { defaults.set(window.rawValue, forKey: Self.key(Item.perfWindow, serverID: serverID)) }
    /// The overview's RPM or TPM cell (`route.metric`) wins over the memory and is remembered.
    func perfMetric(serverID: UUID, route: PerfMetric?) -> PerfMetric {
        guard let route else { return value(Item.perfMetric, serverID) ?? .rpm }
        setPerfMetric(route, serverID: serverID)
        return route
    }
    func setPerfMetric(_ metric: PerfMetric, serverID: UUID) { set(metric.rawValue, Item.perfMetric, serverID) }

    /// A deleted site takes its memory with it.
    func removeAll(serverID: UUID) {
        let prefix = Self.prefix(serverID)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) { defaults.removeObject(forKey: key) }
    }

    private func string(_ item: String, _ serverID: UUID) -> String? { defaults.string(forKey: Self.key(item, serverID: serverID)) }
    private func day(_ item: String, _ serverID: UUID) -> AnalyticsDay? { string(item, serverID).flatMap { AnalyticsDay($0) } }
    private func value<Value: RawRepresentable>(_ item: String, _ serverID: UUID) -> Value? where Value.RawValue == String {
        string(item, serverID).flatMap { Value(rawValue: $0) }
    }
    private func set(_ value: String, _ item: String, _ serverID: UUID) { defaults.set(value, forKey: Self.key(item, serverID: serverID)) }
    private func remove(_ items: [String], _ serverID: UUID) {
        items.forEach { defaults.removeObject(forKey: Self.key($0, serverID: serverID)) }
    }
}
