import Foundation
import Observation
import Sub2Core

/// Which choices a card's data follows (40 §1.2): a range change clears every card but RPM / TPM, which keeps its own rolling
/// window; a filter change clears every card but the filter sheet's own lists.
enum AnalyticsCardScope: Hashable, Sendable {
    case rangeAndFilter, rangeOnly, filterOnly

    func isInvalidated(rangeChanged: Bool, filterChanged: Bool) -> Bool {
        switch self {
        case .rangeAndFilter: rangeChanged || filterChanged
        case .rangeOnly: rangeChanged
        case .filterOnly: filterChanged
        }
    }
}

/// The choices the session's cards follow; never `now`, which moves on with every refresh (40 §1.7).
struct AnalyticsScope: Hashable, Sendable {
    let selection: AnalyticsRangeSelection
    let filter: AnalyticsFilter?
}

/// A card's place in the session; each card adds its key in its own file (X44).
struct AnalyticsCardKey: Hashable, Sendable {
    let name: String
    let scope: AnalyticsCardScope
    /// Whether its last success counts toward the subtitle “N 分钟前更新”; the filter sheet's lists do not.
    let showsInUpdateLine: Bool

    init(_ name: String, scope: AnalyticsCardScope = .rangeAndFilter, showsInUpdateLine: Bool = true) {
        self.name = name; self.scope = scope; self.showsInUpdateLine = showsInUpdateLine
    }
}

/// 40 §1.1 subtitle after the site name: 刚刚更新, N 分钟前更新, then the time of day (今天 09:41 更新).
enum AnalyticsUpdateLine {
    static func text(earliest: Date?, now: Date, timeZone: TimeZone) -> String? {
        guard let earliest else { return nil }
        let elapsed = now.timeIntervalSince(earliest)
        let isRecent = abs(elapsed) < 60 || (elapsed > 0 && elapsed < 3_600)
        return DisplayFormat.relativeTime(earliest, now: now, timeZone: timeZone) + (isRecent ? "更新" : " 更新")
    }
}

@MainActor private protocol AnalyticsCardSlot: AnyObject {
    var hasCardValue: Bool { get }
    var updatedAt: Date? { get }
    func reset()
    func cancel()
}

extension LoadState: AnalyticsCardSlot {
    fileprivate var hasCardValue: Bool { value != nil }
}

/// 40 §0.1: the range, the filter and the cards' data that `analytics` and the More / Chart / Rank / Model pages it pushes share,
/// registered in PageStateRegistry under `PageStateKey.analyticsSession`, so it goes when the stack leaves analytics. The choices
/// come from AnalyticsMemory and are written back only when the user changes them; the cards' data never outlives the stack.
@MainActor @Observable
final class AnalyticsSessionState {
    let serverID: UUID
    let generation: UUID
    let client: APIClient
    let timeZone: ServerTimeZone
    /// `usage.model_source` and `ops.dashboard_model_filter` (40 §1.2 参数映射).
    let supportsModelSource: Bool
    let supportsOpsModelFilter: Bool
    let isUITesting: Bool
    /// The session's group names; the filter sheet lists them and a remembered group must still be among them.
    let groups: GroupDirectory?
    /// The selection resolved at `now`, kept so views do not rebuild the buckets on every read.
    private(set) var range: AnalyticsRange
    private(set) var filter: AnalyticsFilter?
    /// Moves when a card's state is made, so a view that found none reads again; reading a card never writes.
    private var slotsVersion = 0
    @ObservationIgnored private var slots: [AnalyticsCardKey: any AnalyticsCardSlot] = [:]
    /// The reads out, one per card; a choice change, `reset` and `cancelAll` drop them, so the next page asking reads anew.
    @ObservationIgnored private var reads: [AnalyticsCardKey: Read] = [:]
    @ObservationIgnored private var checkedFilter = false
    @ObservationIgnored private let memory: AnalyticsMemory
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let isSessionCurrent: @MainActor () -> Bool

    /// `entry` counts only while the site remembers no range; `clock` is the server clock; `isSessionCurrent` turns false once the
    /// site session that made this one ends.
    init(serverID: UUID, generation: UUID, client: APIClient, timeZone: ServerTimeZone, supportsModelSource: Bool,
         supportsOpsModelFilter: Bool, memory: AnalyticsMemory, entry: AnalyticsEntryRange, groups: GroupDirectory?,
         isUITesting: Bool = false, clock: @escaping @MainActor () -> Date, isSessionCurrent: @escaping @MainActor () -> Bool) {
        self.serverID = serverID; self.generation = generation; self.client = client; self.timeZone = timeZone
        self.supportsModelSource = supportsModelSource; self.supportsOpsModelFilter = supportsOpsModelFilter
        self.memory = memory; self.groups = groups; self.isUITesting = isUITesting
        self.clock = clock; self.isSessionCurrent = isSessionCurrent
        let now = clock()
        let selection = memory.range(serverID: serverID, entry: entry, bounds: AnalyticsDayBounds(now: now, zone: timeZone))
        range = AnalyticsRange.resolve(selection, now: now, zone: timeZone)
        filter = memory.filter(serverID: serverID)
    }

    var selection: AnalyticsRangeSelection { range.selection }
    var now: Date { range.now }
    var scope: AnalyticsScope { AnalyticsScope(selection: selection, filter: filter) }
    var isLive: Bool { range.includesNow }
    /// The selection resolved at this moment, for the custom range sheet's dates.
    func currentRange() -> AnalyticsRange { AnalyticsRange.resolve(selection, now: clock(), zone: timeZone) }
    /// The chip's name: the group's (“#id” while unknown) or the model.
    var filterName: String? {
        switch filter {
        case .group(let id)?: groups?.name(for: id) ?? "#\(id)"
        case .model(let name)?: name
        case nil: nil
        }
    }

    // MARK: Choices

    /// 40 §0.1: once `groups/all` has loaded, a remembered group it no longer has is dropped; until then, or when it fails, the
    /// filter stays (the backend reads an unknown group_id as no usage).
    func prepare() async {
        guard !checkedFilter, let groups, case .group? = filter else { return }
        await groups.ensureLoaded()
        guard groups.state.value != nil else { return }
        checkedFilter = true
        let kept = memory.validatedFilter(serverID: serverID, groups: groups.groups)
        guard kept != filter else { return }
        filter = kept
        invalidate(rangeChanged: false, filterChanged: true)
    }
    /// 40 §1.2: the range already shown does nothing; another is remembered and clears every card that follows the range.
    func select(_ selection: AnalyticsRangeSelection) {
        let next = AnalyticsRange.resolve(selection, now: clock(), zone: timeZone)
        guard next.selection != range.selection else { return }
        range = next
        memory.setRange(next.selection, serverID: serverID)
        invalidate(rangeChanged: true, filterChanged: false)
    }
    func setFilter(_ filter: AnalyticsFilter?) {
        guard filter != self.filter else { return }
        self.filter = filter
        memory.setFilter(filter, serverID: serverID)
        invalidate(rangeChanged: false, filterChanged: true)
    }
    /// 40 §1.7: a refresh moves “now” on; the start, the choices and the cards stay.
    func advanceNow() { range = AnalyticsRange.resolve(selection, now: clock(), zone: timeZone) }

    // MARK: Queries

    /// `filtered: false` for the filter sheet's shares, which cover the whole range.
    func query(filtered: Bool = true) -> AnalyticsQuery {
        let base = AnalyticsQuery(start: range.start, end: range.end, granularity: range.granularity, timeZone: timeZone)
        guard filtered, let filter else { return base }
        return filter.applied(to: base, supportsModelSource: supportsModelSource)
    }
    /// The window an increase or decrease is measured against (40 §1.2 对比窗口), with the same filter.
    func comparisonQuery() -> AnalyticsQuery {
        var query = query()
        query.start = range.comparison.start; query.end = range.comparison.end
        return query
    }
    func opsQuery(start: Date, end: Date) -> OpsQuery { filter?.opsQuery(start: start, end: end) ?? OpsQuery(start: start, end: end) }
    /// A model filter the ops charts cannot send: their header says they show the whole site.
    var opsIsSiteWide: Bool { opsQuery(start: range.start, end: range.end).isSiteWide(supportsModelFilter: supportsOpsModelFilter) }

    // MARK: Cards

    /// nil until the card first loads; the card shows its loading state meanwhile.
    func state<Value: Sendable>(_ key: AnalyticsCardKey, as type: Value.Type = Value.self) -> LoadState<Value>? {
        _ = slotsVersion
        return slots[key] as? LoadState<Value>
    }
    func hasValue(_ key: AnalyticsCardKey) -> Bool {
        _ = slotsVersion
        return slots[key]?.hasCardValue ?? false
    }
    /// A page asking for a card that already has its data, or is reading it, shares it; `refresh` reads again (the 60-second
    /// refresh, pull to refresh, 重试本项). A read already out is waited for, and the page that started it going away (its `.task`
    /// cancelled when it pushes a chart) does not cancel it, as GroupDirectory does. A result that lands after the site session
    /// ended, or after a change of the choices the card follows, is dropped.
    func load<Value: Sendable>(_ key: AnalyticsCardKey, refresh: Bool = false,
                               fixture: @escaping @MainActor @Sendable (AnalyticsSessionState) throws -> Value,
                               operation: @escaping @MainActor @Sendable (APIClient, AnalyticsSessionState) async throws -> Value) async {
        if let read = reads[key] { await read.task.value; return }
        let state = slot(key, as: Value.self)
        guard refresh || state.value == nil else { return }
        let started = scope, client = client, usesFixture = isUITesting, id = UUID()
        let isCurrent: @MainActor @Sendable () -> Bool = { [weak self] in self?.isCurrent(key, since: started) ?? false }
        let read: @MainActor @Sendable () async throws -> Value = { [weak self] in
            guard let self else { throw CancellationError() }
            if usesFixture { return try fixture(self) }
            return try await operation(client, self)
        }
        let task = Task { [weak self] in
            await state.load(isCurrent: isCurrent, operation: read)
            if self?.reads[key]?.id == id { self?.reads[key] = nil }
        }
        reads[key] = Read(id: id, task: task)
        await task.value
    }
    func reset(_ key: AnalyticsCardKey) {
        reads[key] = nil
        slots[key]?.reset()
    }
    func cancelAll() {
        reads = [:]
        slots.values.forEach { $0.cancel() }
    }

    /// The subtitle's time: the oldest last success among the cards that count.
    var earliestUpdate: Date? {
        _ = slotsVersion
        return slots.filter { $0.key.showsInUpdateLine }.compactMap { $0.value.updatedAt }.min()
    }
    /// `now` is the phone's clock, like the cards' success times.
    func updateLine(now: Date) -> String? { AnalyticsUpdateLine.text(earliest: earliestUpdate, now: now, timeZone: timeZone.timeZone) }
    func isStale(currentGeneration: UUID) -> Bool { generation != currentGeneration }

    private func isCurrent(_ key: AnalyticsCardKey, since started: AnalyticsScope) -> Bool {
        isSessionCurrent()
            && !key.scope.isInvalidated(rangeChanged: started.selection != selection, filterChanged: started.filter != filter)
    }
    private func slot<Value: Sendable>(_ key: AnalyticsCardKey, as type: Value.Type) -> LoadState<Value> {
        if let existing = slots[key] as? LoadState<Value> { return existing }
        if let other = slots[key] {
            assertionFailure("Analytics card \(key.name) loaded with another value type")
            other.cancel()
        }
        let made = LoadState<Value>()
        slots[key] = made
        slotsVersion += 1
        return made
    }
    private func invalidate(rangeChanged: Bool, filterChanged: Bool) {
        for (key, slot) in slots where key.scope.isInvalidated(rangeChanged: rangeChanged, filterChanged: filterChanged) {
            reads[key] = nil
            slot.reset()
        }
    }
    private struct Read {
        let id: UUID
        let task: Task<Void, Never>
    }
}

/// 40 §1.2 筛选 sheet rows: groups in directory order (inactive ones marked and still selectable), models by actual cost. A share
/// is of the current range's whole actual cost, unassigned usage included; 0.0% without usage, nil while the usage is unknown.
enum AnalyticsFilterOptions {
    struct Row: Identifiable, Equatable, Sendable {
        let filter: AnalyticsFilter
        let title: String
        let isInactive: Bool
        let share: String?
        var id: String { filter.storedValue }
    }

    static func groupRows(directory: [AdminGroup], usage: [AnalyticsBreakdown]?) -> [Row] {
        let total = usage.map(totalActualCost)
        let spent = Dictionary((usage ?? []).compactMap { row in row.groupID.map { ($0, row.actualCost ?? 0) } }, uniquingKeysWith: +)
        return directory.map { group in
            Row(filter: .group(id: group.id), title: group.name, isInactive: group.status != "active",
                share: total.map { share(spent[group.id] ?? 0, of: $0) })
        }
    }
    /// The model filtered by stays listed (at 0.0%) when the range has no usage of it, so its row shows as chosen.
    static func modelRows(_ models: [AnalyticsBreakdown], current: AnalyticsFilter? = nil) -> [Row] {
        let total = totalActualCost(models)
        let named = models.compactMap { row -> (String, Decimal)? in
            guard let name = row.model, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (name, row.actualCost ?? 0)
        }
        let rows = Dictionary(named, uniquingKeysWith: +)
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { Row(filter: .model(name: $0.key), title: $0.key, isInactive: false, share: share($0.value, of: total)) }
        guard case .model(let name)? = current, !rows.contains(where: { $0.filter == current }) else { return rows }
        return rows + [Row(filter: .model(name: name), title: name, isInactive: false, share: share(0, of: total))]
    }
    static func note(kind: AnalyticsFilter.Kind, supportsOpsModelFilter: Bool) -> String {
        switch kind {
        case .group:
            "筛选后趋势、合计、排行和运行类图表都只算这个分组。分组按请求时 Key 所属的分组算：用户排行只算各用户在这个分组 Key 上的用量，一个用户的 Key 分属几个分组时，会出现在几个分组里。"
        case .model:
            supportsOpsModelFilter ? "运行类图表也只算这个模型。" : "运行类图表（RPM / TPM、时长、错误）后端不支持按模型，仍显示全站。"
        }
    }

    private static func totalActualCost(_ rows: [AnalyticsBreakdown]) -> Decimal { rows.reduce(0) { $0 + ($1.actualCost ?? 0) } }
    private static func share(_ value: Decimal, of total: Decimal) -> String {
        guard total > 0 else { return DisplayFormat.ratioPercent(0) }
        return DisplayFormat.ratioPercent(NSDecimalNumber(decimal: value / total).doubleValue)
    }
}
