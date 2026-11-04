import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 40 §0.1 本机记忆: per site under analytics.<站点 id>.<项>, written only when the user changes a choice (S4D1-03).

private let siteA = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
private let siteB = UUID(uuidString: "7A9619FF-8B86-D011-B42D-00C04FC964FF")!
private let today = AnalyticsDay("2026-10-16")!
private let bounds = AnalyticsDayBounds(today: today)

private func storedKey(_ item: String, _ serverID: UUID = siteA) -> String { "analytics.\(serverID.uuidString).\(item)" }
private func day(_ text: String) -> AnalyticsDay { AnalyticsDay(text)! }

@MainActor @Test func keysArePerSiteUnderTheAnalyticsPrefix() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    memory.setRange(.preset(.last30), serverID: siteA)
    memory.setFilter(.group(id: 3), serverID: siteA)
    memory.setRankCardDimension(.user, serverID: siteA)
    memory.setRankSort(.requests, for: .user, serverID: siteA)
    memory.setRankModelSource(.upstream, serverID: siteA)
    memory.setPerfWindow(.h6, serverID: siteA)
    memory.setPerfMetric(.tpm, serverID: siteA)
    let prefix = "analytics.\(siteA.uuidString)."
    let stored = Set(scratch.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) })
    #expect(stored == Set(["range", "filter", "rankCard", "rankSort.user", "rankModelSource", "perfWindow", "perfMetric"].map { prefix + $0 }))
    #expect(scratch.defaults.string(forKey: storedKey("range")) == "last30")
    #expect(scratch.defaults.string(forKey: storedKey("filter")) == "group:3")
    #expect(scratch.defaults.string(forKey: storedKey("rankSort.user")) == "requests")
    #expect(scratch.defaults.integer(forKey: storedKey("perfWindow")) == 6)
    #expect(AnalyticsMemory.key("range", serverID: siteA) == storedKey("range"))
}

@MainActor @Test func entryDefaultIsNotWrittenUntilTheUserChangesTheRange() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    #expect(memory.range(serverID: siteA, entry: .today, bounds: bounds) == .preset(.today))
    #expect(scratch.defaults.object(forKey: storedKey("range")) == nil)
    // Only entered from the overview, never changed: the search directory still opens on 近 7 天.
    #expect(memory.range(serverID: siteA, entry: .last7, bounds: bounds) == .preset(.last7))
    memory.setRange(.preset(.last30), serverID: siteA)
    #expect(memory.range(serverID: siteA, entry: .today, bounds: bounds) == .preset(.last30))
    #expect(memory.range(serverID: siteA, entry: .last7, bounds: bounds) == .preset(.last30))
}

@MainActor @Test func rememberedRangeIgnoresTheEntry() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    memory.setRange(.preset(.lastMonth), serverID: siteA)
    for entry in AnalyticsEntryRange.allCases {
        #expect(memory.range(serverID: siteA, entry: entry, bounds: bounds) == .preset(.lastMonth))
    }
}

@MainActor @Test func presetsAreStoredByKeyAndRecomputedForToday() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    let later = AnalyticsDayBounds(today: today.adding(days: 40))
    for preset in AnalyticsPreset.allCases {
        memory.setRange(.preset(preset), serverID: siteA)
        #expect(scratch.defaults.string(forKey: storedKey("range")) == preset.rawValue)
        #expect(scratch.defaults.object(forKey: storedKey("range.start")) == nil)
        #expect(scratch.defaults.object(forKey: storedKey("range.end")) == nil)
        #expect(memory.range(serverID: siteA, entry: .today, bounds: later) == .preset(preset))
    }
}

@MainActor @Test func customRangeStoresItsDays() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    let several = AnalyticsRangeSelection.custom(from: day("2026-10-01"), to: day("2026-10-05"))
    memory.setRange(several, serverID: siteA)
    #expect(scratch.defaults.string(forKey: storedKey("range")) == "custom")
    #expect(scratch.defaults.string(forKey: storedKey("range.start")) == "2026-10-01")
    #expect(scratch.defaults.string(forKey: storedKey("range.end")) == "2026-10-05")
    #expect(memory.range(serverID: siteA, entry: .today, bounds: bounds) == several)
    let single = AnalyticsRangeSelection.custom(from: day("2026-10-14"), to: day("2026-10-14"))
    memory.setRange(single, serverID: siteA)
    #expect(memory.range(serverID: siteA, entry: .last7, bounds: bounds) == single)
    memory.setRange(.preset(.today), serverID: siteA)
    #expect(scratch.defaults.object(forKey: storedKey("range.start")) == nil)
    #expect(scratch.defaults.object(forKey: storedKey("range.end")) == nil)
}

@MainActor @Test func customRangeOlderThan366DaysFallsBackToTheEntry() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    let oldest = AnalyticsRangeSelection.custom(from: bounds.earliest, to: today)
    memory.setRange(oldest, serverID: siteA)
    #expect(memory.range(serverID: siteA, entry: .today, bounds: bounds) == oldest)
    memory.setRange(.custom(from: bounds.earliest.adding(days: -1), to: day("2026-10-01")), serverID: siteA)
    #expect(memory.range(serverID: siteA, entry: .last7, bounds: bounds) == .preset(.last7))
    for item in ["range", "range.start", "range.end"] { #expect(scratch.defaults.object(forKey: storedKey(item)) == nil) }
}

@MainActor @Test func brokenRangeValuesReadAsMissing() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    let broken: [[String: String]] = [
        ["range": "fortnight"],
        ["range": "custom", "range.start": "2026-10-01"],
        ["range": "custom", "range.start": "2026-10-09", "range.end": "2026-10-02"],
        ["range": "custom", "range.start": "2026-10-10", "range.end": "2026-10-17"],
        ["range": "custom", "range.start": "2026-13-01", "range.end": "2026-10-02"],
        ["range": "custom", "range.start": "2026/10/01", "range.end": "2026-10-02"]
    ]
    for values in broken {
        values.forEach { scratch.defaults.set($0.value, forKey: storedKey($0.key)) }
        #expect(memory.range(serverID: siteA, entry: .today, bounds: bounds) == .preset(.today))
        for item in ["range", "range.start", "range.end"] { #expect(scratch.defaults.object(forKey: storedKey(item)) == nil) }
    }
}

@MainActor @Test func filterRoundTripsAndModelNamesMayContainColons() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    memory.setFilter(.group(id: 3), serverID: siteA)
    #expect(memory.filter(serverID: siteA) == .group(id: 3))
    memory.setFilter(.model(name: "vendor:claude:opus-4"), serverID: siteA)
    #expect(scratch.defaults.string(forKey: storedKey("filter")) == "model:vendor:claude:opus-4")
    #expect(memory.filter(serverID: siteA) == .model(name: "vendor:claude:opus-4"))
    memory.setFilter(nil, serverID: siteA)
    #expect(scratch.defaults.object(forKey: storedKey("filter")) == nil)
    for raw in ["group:abc", "group:0", "group:-2", "model:", "model:  ", "account:3", "group"] {
        scratch.defaults.set(raw, forKey: storedKey("filter"))
        #expect(memory.filter(serverID: siteA) == nil)
        #expect(scratch.defaults.object(forKey: storedKey("filter")) == nil)
    }
    #expect(AnalyticsFilter(storedValue: "group:12") == .group(id: 12))
    #expect(AnalyticsFilter.group(id: 4).kind == .group && AnalyticsFilter.model(name: "m").kind == .model)
}

@MainActor @Test func rememberedGroupMissingFromTheDirectoryIsDropped() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    let directory = [AdminGroup(id: 1, name: "高级组"), AdminGroup(id: 6, name: "测试组", status: "inactive")]
    memory.setFilter(.group(id: 9), serverID: siteA)
    #expect(memory.validatedFilter(serverID: siteA, groups: directory) == nil)
    #expect(scratch.defaults.object(forKey: storedKey("filter")) == nil)
    memory.setFilter(.group(id: 6), serverID: siteA)
    #expect(memory.validatedFilter(serverID: siteA, groups: directory) == .group(id: 6))
    memory.setFilter(.model(name: "gpt-5"), serverID: siteA)
    #expect(memory.validatedFilter(serverID: siteA, groups: []) == .model(name: "gpt-5"))
}

@MainActor @Test func anotherSiteReadsItsOwnMemory() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    memory.setRange(.preset(.last30), serverID: siteA)
    memory.setFilter(.group(id: 3), serverID: siteA)
    #expect(memory.range(serverID: siteB, entry: .today, bounds: bounds) == .preset(.today))
    #expect(memory.filter(serverID: siteB) == nil)
    #expect(memory.range(serverID: siteA, entry: .today, bounds: bounds) == .preset(.last30))
    #expect(memory.filter(serverID: siteA) == .group(id: 3))
}

@MainActor @Test func removeAllDeletesOnlyThatSite() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    for site in [siteA, siteB] {
        memory.setRange(.custom(from: day("2026-10-01"), to: day("2026-10-02")), serverID: site)
        memory.setFilter(.model(name: "gpt-5"), serverID: site)
        memory.setRankSort(.tokens, for: .group, serverID: site)
        memory.setPerfWindow(.h24, serverID: site)
    }
    scratch.defaults.set(5, forKey: "push.device." + siteA.uuidString)
    scratch.defaults.set("dark", forKey: "ui.appearance")
    memory.removeAll(serverID: siteA)
    let prefixA = "analytics.\(siteA.uuidString)."
    #expect(!scratch.defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix(prefixA) })
    #expect(memory.range(serverID: siteB, entry: .today, bounds: bounds) == .custom(from: day("2026-10-01"), to: day("2026-10-02")))
    #expect(memory.filter(serverID: siteB) == .model(name: "gpt-5"))
    #expect(memory.rankSort(for: .group, serverID: siteB) == .tokens)
    #expect(scratch.defaults.integer(forKey: "push.device." + siteA.uuidString) == 5)
    #expect(scratch.defaults.string(forKey: "ui.appearance") == "dark")
}

@MainActor @Test func signingOutKeepsTheMemory() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    AnalyticsMemory(defaults: scratch.defaults).setRange(.preset(.thisMonth), serverID: siteA)
    AnalyticsMemory(defaults: scratch.defaults).setFilter(.group(id: 2), serverID: siteA)
    let again = AnalyticsMemory(defaults: scratch.defaults)
    #expect(again.range(serverID: siteA, entry: .last7, bounds: bounds) == .preset(.thisMonth))
    #expect(again.filter(serverID: siteA) == .group(id: 2))
}

@MainActor @Test func rankingChoicesHaveDefaultsAndArePerDimension() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    #expect(memory.rankCardDimension(serverID: siteA) == .model)
    #expect(memory.rankModelSource(serverID: siteA) == .requested)
    for dimension in AnalyticsRankDimension.allCases { #expect(memory.rankSort(for: dimension, serverID: siteA) == .actualCost) }
    memory.setRankSort(.requests, for: .model, serverID: siteA)
    memory.setRankCardDimension(.group, serverID: siteA)
    memory.setRankModelSource(.mapping, serverID: siteA)
    #expect(memory.rankSort(for: .model, serverID: siteA) == .requests)
    #expect(memory.rankSort(for: .user, serverID: siteA) == .actualCost)
    #expect(memory.rankSort(for: .group, serverID: siteA) == .actualCost)
    #expect(memory.rankCardDimension(serverID: siteA) == .group)
    #expect(memory.rankModelSource(serverID: siteA) == .mapping)
    scratch.defaults.set("cost", forKey: storedKey("rankSort.user"))
    scratch.defaults.set("vendor", forKey: storedKey("rankCard"))
    scratch.defaults.set("both", forKey: storedKey("rankModelSource"))
    #expect(memory.rankSort(for: .user, serverID: siteA) == .actualCost)
    #expect(memory.rankCardDimension(serverID: siteA) == .model)
    #expect(memory.rankModelSource(serverID: siteA) == .requested)
}

@MainActor @Test func perfWindowAndMetricDefaultAndPersist() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    #expect(memory.perfWindow(serverID: siteA) == .h1)
    #expect(memory.perfMetric(serverID: siteA, route: nil) == .rpm)
    memory.setPerfWindow(.h24, serverID: siteA)
    memory.setPerfMetric(.tpm, serverID: siteA)
    #expect(memory.perfWindow(serverID: siteA) == .h24)
    #expect(memory.perfMetric(serverID: siteA, route: nil) == .tpm)
    scratch.defaults.set(7, forKey: storedKey("perfWindow"))
    #expect(memory.perfWindow(serverID: siteA) == .h1)
    #expect(PerfWindow.allCases.map(\.title) == ["近 1 小时", "近 6 小时", "近 24 小时"])
    #expect(PerfWindow.allCases.map(\.hours) == [1, 6, 24])
}

@MainActor @Test func routeMetricWinsAndIsWrittenBack() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    memory.setPerfMetric(.rpm, serverID: siteA)
    #expect(memory.perfMetric(serverID: siteA, route: .tpm) == .tpm)
    #expect(scratch.defaults.string(forKey: storedKey("perfMetric")) == "tpm")
    #expect(memory.perfMetric(serverID: siteA, route: nil) == .tpm)
}

@Test func filterMapsToAnalyticsQueryParameters() throws {
    let zone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
    let start = Date(timeIntervalSince1970: 1_760_544_000), end = start.addingTimeInterval(3_600)
    let base = AnalyticsQuery(start: start, end: end, granularity: .hour, timeZone: zone)
    func items(_ query: AnalyticsQuery) throws -> [String: String] {
        Dictionary(try query.queryItems().map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, later in later })
    }
    let group = try items(AnalyticsFilter.group(id: 3).applied(to: base, supportsModelSource: true))
    #expect(group["group_id"] == "3" && group["model"] == nil && group["model_source"] == nil)
    let model = try items(AnalyticsFilter.model(name: "claude-opus-4").applied(to: base, supportsModelSource: true))
    #expect(model["model"] == "claude-opus-4" && model["model_source"] == "requested" && model["group_id"] == nil)
    let oldServer = try items(AnalyticsFilter.model(name: "claude-opus-4").applied(to: base, supportsModelSource: false))
    #expect(oldServer["model"] == "claude-opus-4" && oldServer["model_source"] == nil)
}

@Test func filterMapsToOpsQuery() {
    let start = Date(timeIntervalSince1970: 1_760_544_000), end = start.addingTimeInterval(3_600)
    let group = AnalyticsFilter.group(id: 3).opsQuery(start: start, end: end)
    #expect(group == OpsQuery(start: start, end: end, groupID: 3))
    let model = AnalyticsFilter.model(name: "gpt-5").opsQuery(start: start, end: end)
    #expect(model == OpsQuery(start: start, end: end, model: "gpt-5", modelSource: .requested))
    #expect(!model.isSiteWide(supportsModelFilter: true))
    #expect(model.isSiteWide(supportsModelFilter: false))
    #expect(!group.isSiteWide(supportsModelFilter: false))
}
