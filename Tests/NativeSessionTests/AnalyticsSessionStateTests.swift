import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 40 §0.1 / §1.2 / §1.7: the analytics session shared along one stack (S4-12, S4D1-02).

private let site = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-16 09:41 in Shanghai.
private let morning = Date(timeIntervalSince1970: 1_792_114_860)
private let billing = AnalyticsCardKey("billing")
private let shares = AnalyticsCardKey("shares", scope: .rangeOnly, showsInUpdateLine: false)
private let perf = AnalyticsCardKey("perf", scope: .filterOnly)

@MainActor private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor private final class CallCounter {
    var count = 0
}

@MainActor private final class SiteSessionFlag {
    var isCurrent = true
}

@MainActor private func makeSession(_ scratch: ScratchDefaults, clock: TestClock = TestClock(morning), entry: AnalyticsEntryRange = .today,
                                    groups: GroupDirectory? = nil, opsModelFilter: Bool = true,
                                    isCurrent: @escaping @MainActor () -> Bool = { true }) -> AnalyticsSessionState {
    AnalyticsSessionState(serverID: site, generation: UUID(), client: sessionClient(SessionTransport { _ in sessionOK("{}") }), timeZone: shanghai,
                          supportsModelSource: true, supportsOpsModelFilter: opsModelFilter, memory: AnalyticsMemory(defaults: scratch.defaults),
                          entry: entry, groups: groups, clock: { clock.now }, isSessionCurrent: isCurrent)
}

@MainActor private func load(_ session: AnalyticsSessionState, _ key: AnalyticsCardKey, value: Int, refresh: Bool = false,
                             counter: CallCounter? = nil) async {
    await session.load(key, refresh: refresh, fixture: { _ in value }) { _, _ in
        counter?.count += 1
        return value
    }
}

@MainActor @Test func sessionStartsFromMemoryAndRemembersOnlyChanges() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch, entry: .today)
    #expect(session.selection == .preset(.today))
    #expect(session.filter == nil)
    session.select(.preset(.today))
    #expect(scratch.defaults.object(forKey: AnalyticsMemory.key("range", serverID: site)) == nil)
    session.select(.preset(.last30))
    session.setFilter(.model(name: "gpt-5"))
    #expect(session.selection == .preset(.last30))
    let next = makeSession(scratch, entry: .last7)
    #expect(next.selection == .preset(.last30))
    #expect(next.filter == .model(name: "gpt-5"))
    #expect(next.range.granularity == .day)
}

@MainActor @Test func lateResultForOldScopeIsDropped() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    let gate = SessionGate()
    let loading = Task { @MainActor in
        await session.load(billing, fixture: { _ in 0 }) { _, _ in
            await gate.wait()
            return 1
        }
    }
    while !(await gate.arrived) { await Task.yield() }
    session.select(.preset(.last7))
    await gate.open()
    await loading.value
    #expect(session.state(billing, as: Int.self)?.value == nil)
    #expect(session.state(billing, as: Int.self)?.isLoading == false)
}

@MainActor @Test func rangeAndFilterInvalidationMatrix() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    func values() -> [Int?] { [billing, shares, perf].map { session.state($0, as: Int.self)?.value } }
    for key in [billing, shares, perf] { await load(session, key, value: 1) }
    session.select(.preset(.last7))
    #expect(values() == [nil, nil, 1])
    for key in [billing, shares, perf] { await load(session, key, value: 2) }
    session.setFilter(.group(id: 3))
    #expect(values() == [nil, 2, nil])
    // Cards that kept their data are not read again; choosing what is already chosen clears nothing.
    for key in [billing, shares, perf] { await load(session, key, value: 3) }
    session.setFilter(.group(id: 3))
    session.select(.preset(.last7))
    #expect(values() == [3, 2, 3])

    #expect(AnalyticsCardScope.rangeAndFilter.isInvalidated(rangeChanged: true, filterChanged: false))
    #expect(AnalyticsCardScope.rangeAndFilter.isInvalidated(rangeChanged: false, filterChanged: true))
    #expect(AnalyticsCardScope.rangeOnly.isInvalidated(rangeChanged: true, filterChanged: false))
    #expect(!AnalyticsCardScope.rangeOnly.isInvalidated(rangeChanged: false, filterChanged: true))
    #expect(!AnalyticsCardScope.filterOnly.isInvalidated(rangeChanged: true, filterChanged: false))
    #expect(AnalyticsCardScope.filterOnly.isInvalidated(rangeChanged: false, filterChanged: true))
}

@MainActor @Test func secondaryPagesShareTheSameCache() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    let counter = CallCounter()
    #expect(session.state(billing, as: Int.self) == nil)
    #expect(!session.hasValue(billing))
    await load(session, billing, value: 5, counter: counter)
    await load(session, billing, value: 6, counter: counter)
    #expect(counter.count == 1)
    #expect(session.state(billing, as: Int.self)?.value == 5)
    #expect(session.hasValue(billing))
    await load(session, billing, value: 7, refresh: true, counter: counter)
    #expect(counter.count == 2)
    #expect(session.state(billing, as: Int.self)?.value == 7)
    session.reset(billing)
    #expect(!session.hasValue(billing))
}

@MainActor @Test func advanceNowKeepsCache() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let clock = TestClock(morning)
    let session = makeSession(scratch, clock: clock)
    await load(session, billing, value: 1)
    let scope = session.scope
    clock.now = morning.addingTimeInterval(120)
    session.advanceNow()
    #expect(session.now == clock.now)
    #expect(session.range.end == clock.now)
    #expect(session.range.start == AnalyticsRange.resolve(.preset(.today), now: morning, zone: shanghai).start)
    #expect(session.scope == scope)
    #expect(session.state(billing, as: Int.self)?.value == 1)
    #expect(session.currentRange().now == clock.now)
}

@MainActor @Test func updateLineUsesTheEarliestSuccess() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    #expect(session.earliestUpdate == nil)
    #expect(session.updateLine(now: morning) == nil)
    await load(session, shares, value: 1)
    try await Task.sleep(for: .milliseconds(5))
    await load(session, billing, value: 1)
    try await Task.sleep(for: .milliseconds(5))
    await load(session, perf, value: 1)
    let first = try #require(session.state(billing, as: Int.self)?.updatedAt)
    #expect(session.earliestUpdate == first)
    #expect(session.updateLine(now: first.addingTimeInterval(300)) == "5 分钟前更新")
}

@Test func updateLineWording() {
    let zone = shanghai.timeZone
    #expect(AnalyticsUpdateLine.text(earliest: nil, now: morning, timeZone: zone) == nil)
    #expect(AnalyticsUpdateLine.text(earliest: morning.addingTimeInterval(-30), now: morning, timeZone: zone) == "刚刚更新")
    #expect(AnalyticsUpdateLine.text(earliest: morning.addingTimeInterval(-300), now: morning, timeZone: zone) == "5 分钟前更新")
    #expect(AnalyticsUpdateLine.text(earliest: morning.addingTimeInterval(-7_200), now: morning, timeZone: zone) == "今天 07:41 更新")
}

@MainActor @Test func staleGenerationIsReported() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let connection = SiteSessionFlag()
    let session = makeSession(scratch, isCurrent: { connection.isCurrent })
    #expect(!session.isStale(currentGeneration: session.generation))
    #expect(session.isStale(currentGeneration: UUID()))
    connection.isCurrent = false
    await load(session, billing, value: 1)
    #expect(session.state(billing, as: Int.self)?.value == nil)
}

@MainActor @Test func queriesCarryTheRangeAndFilter() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    session.setFilter(.group(id: 3))
    let query = session.query()
    #expect(query.start == session.range.start && query.end == session.range.end)
    #expect(query.granularity == .hour && query.timeZone == shanghai && query.groupID == 3)
    #expect(session.query(filtered: false).groupID == nil)
    let comparison = session.comparisonQuery()
    #expect(comparison.start == session.range.comparison.start && comparison.end == session.range.comparison.end)
    #expect(comparison.groupID == 3)
    session.setFilter(.model(name: "claude-opus-4"))
    #expect(session.query().model == "claude-opus-4" && session.query().modelSource == .requested)
    let ops = session.opsQuery(start: session.range.start, end: session.range.end)
    #expect(ops.model == "claude-opus-4" && ops.groupID == nil)
    #expect(!session.opsIsSiteWide)
    #expect(makeSession(scratch, opsModelFilter: false).opsIsSiteWide)
}

@MainActor @Test func filterNameFollowsTheDirectory() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let groups = GroupDirectory(load: { [AdminGroup(id: 1, name: "高级组")] })
    await groups.ensureLoaded()
    let session = makeSession(scratch, groups: groups)
    #expect(session.filterName == nil)
    session.setFilter(.group(id: 1))
    #expect(session.filterName == "高级组")
    session.setFilter(.group(id: 9))
    #expect(session.filterName == "#9")
    session.setFilter(.model(name: "gpt-5"))
    #expect(session.filterName == "gpt-5")
    #expect(AnalyticsFilter.Kind.allCases.map(\.title) == ["分组", "模型"])
}

@MainActor @Test func prepareDropsARememberedGroupTheDirectoryNoLongerHas() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    AnalyticsMemory(defaults: scratch.defaults).setFilter(.group(id: 9), serverID: site)
    let session = makeSession(scratch, groups: GroupDirectory(load: { [AdminGroup(id: 1, name: "高级组")] }))
    #expect(session.filter == .group(id: 9))
    await load(session, billing, value: 1)
    await session.prepare()
    #expect(session.filter == nil)
    #expect(session.state(billing, as: Int.self)?.value == nil)
    #expect(AnalyticsMemory(defaults: scratch.defaults).filter(serverID: site) == nil)
}

@MainActor @Test func aDirectoryThatFailsKeepsTheRememberedGroup() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    AnalyticsMemory(defaults: scratch.defaults).setFilter(.group(id: 9), serverID: site)
    let session = makeSession(scratch, groups: GroupDirectory(load: { throw URLError(.timedOut) }))
    await session.prepare()
    #expect(session.filter == .group(id: 9))
    #expect(AnalyticsMemory(defaults: scratch.defaults).filter(serverID: site) == .group(id: 9))
}

@MainActor @Test func leavingTheAnalyticsStackDropsTheSession() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let registry = PageStateRegistry(), router = AppRouter(selectedTab: .today)
    router.setPath([.analytics(), .analyticsChart(.tokens)], for: .today)
    let first = registry.state(PageStateKey.analyticsSession, tab: .today, prunedBy: router) { makeSession(scratch) }
    #expect(registry.existing(PageStateKey.analyticsSession, tab: .today, in: router, as: AnalyticsSessionState.self) === first)
    router.setPath([.analytics()], for: .today)
    #expect(registry.existing(PageStateKey.analyticsSession, tab: .today, in: router, as: AnalyticsSessionState.self) === first)
    router.setPath([], for: .today)
    #expect(registry.existing(PageStateKey.analyticsSession, tab: .today, in: router, as: AnalyticsSessionState.self) == nil)
    let again = registry.state(PageStateKey.analyticsSession, tab: .today, prunedBy: router) { makeSession(scratch) }
    #expect(again !== first)
}

private func breakdowns(_ json: String) throws -> [AnalyticsBreakdown] {
    try JSONDecoder().decode([AnalyticsBreakdown].self, from: Data(json.utf8))
}

@Test func groupRowsShareTheRangeUsageIncludingUnassigned() throws {
    let directory = [AdminGroup(id: 2, name: "标准组", sortOrder: 1), AdminGroup(id: 1, name: "高级组", sortOrder: 2),
                     AdminGroup(id: 6, name: "测试组", status: "inactive", sortOrder: 3)]
    let usage = try breakdowns("""
    [{"group_id":1,"group_name":"高级组","requests":3,"total_tokens":9,"actual_cost":"60"},
     {"group_id":0,"group_name":"","requests":1,"total_tokens":2,"actual_cost":"20"},
     {"group_id":2,"group_name":"标准组","requests":1,"total_tokens":2,"actual_cost":"20"}]
    """)
    let rows = AnalyticsFilterOptions.groupRows(directory: directory, usage: usage)
    #expect(rows.map(\.title) == ["标准组", "高级组", "测试组"])
    #expect(rows.map(\.share) == ["20.0%", "60.0%", "0.0%"])
    #expect(rows.map(\.isInactive) == [false, false, true])
    #expect(rows.map(\.filter) == [.group(id: 2), .group(id: 1), .group(id: 6)])
    #expect(AnalyticsFilterOptions.groupRows(directory: directory, usage: nil).map(\.share) == [nil, nil, nil])
    #expect(AnalyticsFilterOptions.groupRows(directory: directory, usage: []).map(\.share) == ["0.0%", "0.0%", "0.0%"])
}

@Test func modelRowsGoByActualCost() throws {
    let models = try breakdowns("""
    [{"model":"gpt-5","requests":3,"total_tokens":9,"actual_cost":"10"},
     {"model":"claude-opus-4","requests":1,"total_tokens":2,"actual_cost":"30"},
     {"model":" ","requests":1,"total_tokens":2,"actual_cost":"5"},
     {"model":"glm-4.6","requests":1,"total_tokens":2}]
    """)
    let rows = AnalyticsFilterOptions.modelRows(models)
    #expect(rows.map(\.title) == ["claude-opus-4", "gpt-5", "glm-4.6"])
    #expect(rows.map(\.share) == ["66.7%", "22.2%", "0.0%"])
    #expect(rows.first?.filter == .model(name: "claude-opus-4"))
    let kept = AnalyticsFilterOptions.modelRows(models, current: .model(name: "kimi-k2"))
    #expect(kept.map(\.title) == ["claude-opus-4", "gpt-5", "glm-4.6", "kimi-k2"])
    #expect(kept.last?.share == "0.0%")
    #expect(AnalyticsFilterOptions.modelRows(models, current: .model(name: "gpt-5")).count == 3)
    #expect(AnalyticsFilterOptions.modelRows(models, current: .group(id: 1)).count == 3)
}

@Test func filterNotesFollowTheKindAndOpsCapability() {
    #expect(AnalyticsFilterOptions.note(kind: .group, supportsOpsModelFilter: false)
        == "筛选后趋势、合计、排行和运行类图表都只算这个分组。分组按请求时 Key 所属的分组算：用户排行只算各用户在这个分组 Key 上的用量，一个用户的 Key 分属几个分组时，会出现在几个分组里。")
    #expect(AnalyticsFilterOptions.note(kind: .model, supportsOpsModelFilter: true) == "运行类图表也只算这个模型。")
    #expect(AnalyticsFilterOptions.note(kind: .model, supportsOpsModelFilter: false) == "运行类图表（RPM / TPM、时长、错误）后端不支持按模型，仍显示全站。")
}
