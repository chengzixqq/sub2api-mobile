import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 40 §5 模型页 over the shared analytics session (S4-19): only the group filter counts, every read carries the model, its source,
// the range and that group; the page's cards are its own and leave the subtitle's “N 分钟前更新” alone.

private let site = UUID(uuidString: "3B241101-E2BB-4255-8CAF-4136C566A962")!
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-16 09:41 in Shanghai.
private let morning = Date(timeIntervalSince1970: 1_792_114_860)
private let opus = AnalyticsModelName("claude-opus-4", source: .requested)
private let mapping = AnalyticsModelName("claude-opus-4 -> claude-opus-4-20250514", source: .mapping)

@MainActor private func makeSession(_ scratch: ScratchDefaults, modelSource: Bool = true, opsModelFilter: Bool = true,
                                    groups: GroupDirectory? = nil) -> AnalyticsSessionState {
    AnalyticsSessionState(serverID: site, generation: UUID(), client: sessionClient(SessionTransport { _ in sessionOK("{}") }), timeZone: shanghai,
                          supportsModelSource: modelSource, supportsOpsModelFilter: opsModelFilter,
                          memory: AnalyticsMemory(defaults: scratch.defaults), entry: .last7, groups: groups, clock: { morning },
                          isSessionCurrent: { true })
}

@MainActor @Test func modelPageKeepsOnlyTheGroupFilter() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    #expect(session.modelPageGroupID == nil && session.modelPageScope().groupID == nil && session.modelPageSharesBillingTotal)

    session.setFilter(.group(id: 1))
    #expect(session.modelPageScope().groupID == 1 && session.modelPageScope().model == nil)
    let grouped = session.modelPageQuery(opus)
    #expect(grouped.model == "claude-opus-4" && grouped.modelSource == .requested && grouped.groupID == 1)
    #expect(session.modelPageSharesBillingTotal)

    session.setFilter(.model(name: "gpt-5"))
    let ignored = session.modelPageQuery(mapping)
    #expect(ignored.model == mapping.raw && ignored.modelSource == .mapping && ignored.groupID == nil)
    #expect(session.modelPageScope().model == nil && session.modelPageGroupID == nil && session.modelPageGroupLabel == nil)
    #expect(!session.modelPageSharesBillingTotal)
}

@MainActor @Test func modelPageQueriesFollowTheRangeAndComparison() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    let query = session.modelPageQuery(opus)
    #expect(query.start == session.range.start && query.end == session.range.end)
    #expect(query.granularity == session.range.granularity && query.timeZone == shanghai)
    let comparison = session.modelPageComparisonQuery(opus)
    #expect(comparison.start == session.range.comparison.start && comparison.end == session.range.comparison.end)
    #expect(comparison.model == query.model && comparison.modelSource == query.modelSource && comparison.groupID == query.groupID)

    let old = makeSession(scratch, modelSource: false)
    #expect(old.modelPageQuery(mapping).modelSource == nil && old.modelPageQuery(mapping).model == "claude-opus-4")
}

@MainActor @Test func modelPageSpeedPlanAndOpsQuery() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    session.setFilter(.group(id: 1))
    let plan = session.modelPageSpeedPlan(mapping)
    #expect(plan == mapping.speedPlan(supportsOpsModelFilter: true))
    let ops = session.modelPageOpsQuery(plan)
    #expect(ops?.groupID == 1 && ops?.start == session.range.start && ops?.end == session.range.end)
    #expect(ops?.model == "claude-opus-4-20250514" && ops?.modelSource == .upstream)

    let old = makeSession(scratch, opsModelFilter: false)
    #expect(old.modelPageSpeedPlan(opus) == .matching("claude-opus-4"))
    #expect(old.modelPageSpeedPlan(mapping) == .unavailable)
    #expect(old.modelPageOpsQuery(.unavailable) == nil)
}

@MainActor @Test func modelPageLogsRouteCarriesModelSourceAndGroup() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let groups = GroupDirectory(load: { [AdminGroup(id: 1, name: "高级组")] })
    await groups.ensureLoaded()
    let session = makeSession(scratch, groups: groups)
    #expect(session.modelPageLogsRoute(mapping) == LogsRoute(scope: .usage, model: mapping.raw, modelSource: .mapping))

    session.setFilter(.group(id: 1))
    #expect(session.modelPageGroupLabel == "高级组")
    #expect(session.modelPageLogsRoute(mapping)
        == LogsRoute(scope: .usage, group: RouteObject(id: 1, name: "高级组"), model: mapping.raw, modelSource: .mapping))
    session.setFilter(.group(id: 9))
    #expect(session.modelPageLogsRoute(opus).group == RouteObject(id: 9, name: nil))
    #expect(session.modelPageGroupLabel == "#9")

    let old = makeSession(scratch, modelSource: false)
    old.setFilter(nil)
    #expect(old.modelPageLogsRoute(mapping) == LogsRoute(scope: .usage, model: "claude-opus-4", modelSource: .requested))
}

@MainActor @Test func modelPageCardsArePerModelAndLeaveTheUpdateLineAlone() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    let keys = [AnalyticsCardKey.modelPage(.summary, opus), .modelPage(.summary, AnalyticsModelName("claude-opus-4", source: .upstream)),
                .modelPage(.summary, AnalyticsModelName("gpt-5", source: .requested)), .modelPage(.trend, opus)]
    #expect(Set(keys).count == keys.count)
    for key in keys + AnalyticsModelPart.allCases.map({ AnalyticsCardKey.modelPage($0, mapping) }) + [.modelPageDenominator] {
        #expect(!key.showsInUpdateLine && key.scope == .rangeAndFilter, "\(key.name)")
    }

    let key = AnalyticsCardKey.modelPage(.summary, opus)
    await session.load(key, fixture: { _ in 1 }) { _, _ in 1 }
    #expect(session.state(key, as: Int.self)?.value == 1)
    #expect(session.earliestUpdate == nil)
    session.select(.preset(.last30))
    #expect(session.state(key, as: Int.self)?.value == nil)
    await session.load(key, fixture: { _ in 2 }) { _, _ in 2 }
    session.setFilter(.group(id: 2))
    #expect(session.state(key, as: Int.self)?.value == nil)
}
