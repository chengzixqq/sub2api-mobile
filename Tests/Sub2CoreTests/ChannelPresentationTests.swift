import Foundation
import Testing
@testable import Sub2Core

private func item(_ state: String?, name: String? = "标准组", id: Int = 1, platform: String = "openai", reason: String? = nil,
                  reliability: Double? = nil, success: Int? = nil, errors: Int? = nil, sample: String? = nil, p50: Double? = nil) -> ChannelItem {
    ChannelItem(platform: platform, groupID: id, groupName: name, currentStatus: ChannelCurrentStatus(state: state, reason: reason),
                metrics: ChannelMetrics(reliabilityRate: reliability, channelErrors: errors, successRequests: success, sampleState: sample,
                                        ttft: ChannelLatency(p50Ms: p50)))
}
private func bucket(_ minute: Int, _ reliability: String?) -> ChannelBucket {
    ChannelBucket(bucketStart: Date(timeIntervalSince1970: 1_800_000_000 + Double(minute) * 60), reliability: reliability)
}

struct ChannelStatusCase: Sendable, CustomTestStringConvertible {
    let state: String?
    let status: ChannelStatus
    let label: String
    let tone: Tone
    var testDescription: String { state ?? "nil" }
}
private let channelStatusCases = [
    ChannelStatusCase(state: "healthy", status: .available, label: "可用", tone: .ok),
    ChannelStatusCase(state: "warning", status: .degraded, label: "性能下降", tone: .caution),
    ChannelStatusCase(state: "critical", status: .unavailable, label: "不可用", tone: .critical),
    ChannelStatusCase(state: "unknown", status: .unknown, label: "未知", tone: .neutral),
    ChannelStatusCase(state: "stale", status: .unknown, label: "未知", tone: .neutral),
    ChannelStatusCase(state: "maintenance", status: .unknown, label: "未知", tone: .neutral),
    ChannelStatusCase(state: nil, status: .unknown, label: "未知", tone: .neutral),
    ChannelStatusCase(state: " Healthy ", status: .available, label: "可用", tone: .ok)
]

@Test(arguments: channelStatusCases)
func channelStatusMapsStateWordsToneAndRank(row: ChannelStatusCase) {
    let status = ChannelStatus(state: row.state)
    #expect(status == row.status && status.label == row.label && status.tone == row.tone)
    #expect(ChannelPresentation.status(item(row.state)) == row.status)
    #expect(ChannelStatus.allCases == [.unavailable, .degraded, .unknown, .available])
    #expect(ChannelStatus.allCases.sorted() == ChannelStatus.allCases)
}

@Test func channelCountsTreatStaleAndUnknownValuesAsUnknown() {
    let items = ["healthy", "healthy", "warning", "critical", "unknown", "stale", "maintenance", nil].map { item($0) }
    let counts = ChannelPresentation.counts(items)
    #expect(counts == ChannelCounts(available: 2, degraded: 1, unavailable: 1, unknown: 4) && counts.total == 8)
    #expect(ChannelPresentation.counts([]) == ChannelCounts() && ChannelCounts().total == 0)
    #expect(ChannelPresentation.counts([ChannelItem()]) == ChannelCounts(unknown: 1))
}

@Test func channelSortedOrdersUnavailableDegradedUnknownAvailable() {
    let items = [item("healthy", name: "组10", id: 1), item("healthy", name: "组2", id: 2), item("stale", name: nil, id: 30),
                 item("critical", name: "b组", id: 4), item("warning", name: "A组", id: 6), item("warning", name: "a组", id: 5),
                 item(nil, name: "分组 #4", id: 7), item("critical", name: "a组", id: 8)]
    #expect(ChannelPresentation.sorted(items).map(\.groupID) == [8, 4, 5, 6, 7, 30, 2, 1])
    #expect(items.map(\.groupID) == [1, 2, 30, 4, 6, 5, 7, 8])
    #expect(ChannelPresentation.sorted([]).isEmpty)
}

@Test func channelTitleFallsBackToGroupNumber() {
    #expect(ChannelPresentation.title(item("healthy", name: "标准组", id: 12)) == "标准组")
    #expect(ChannelPresentation.title(item("healthy", name: " 标准组 ", id: 12)) == "标准组")
    for name in [nil, "", "  "] as [String?] {
        #expect(ChannelPresentation.title(item("healthy", name: name, id: 12)) == "分组 #12")
    }
}

@Test func channelStripKeepsLatest18AndPadsLeft() {
    let nineteen = (0..<19).map { bucket($0 * 5, $0 == 0 ? "critical" : "healthy") }
    let latest = ChannelPresentation.strip(nineteen)
    #expect(latest.count == 18 && latest.allSatisfy { $0 == .ok })
    let shuffled = [bucket(20, "unknown"), bucket(0, "healthy"), bucket(10, "critical"), bucket(5, "warning"), bucket(15, "maintenance")]
    let padded: [Tone?] = Array(repeating: nil, count: 13) + [.ok, .caution, .critical, nil, nil]
    #expect(ChannelPresentation.strip(shuffled) == padded)
    #expect(ChannelPresentation.strip([]) == Array(repeating: nil, count: 18))
    let undated: [Tone?] = Array(repeating: nil, count: 16) + [.ok, .critical]
    #expect(ChannelPresentation.strip([bucket(0, "critical"), ChannelBucket(reliability: "healthy")]) == undated)
    #expect(ChannelPresentation.stripLength == 18)
}

struct ChannelNoteCase: Sendable, CustomTestStringConvertible {
    let item: ChannelItem
    let note: String
    var testDescription: String { note }
}
private let channelNoteCases = [
    ChannelNoteCase(item: item("healthy", reliability: 0.996, p50: 1400), note: "可用率 99.6% · 首字 1.4s"),
    ChannelNoteCase(item: item("warning", reliability: 0.971, p50: 850), note: "可用率 97.1% · 首字 850ms"),
    ChannelNoteCase(item: item("warning", reliability: 0.95, sample: "insufficient", p50: 2100), note: "可用率 95.0% · 首字 2.1s"),
    ChannelNoteCase(item: item("healthy", reliability: 0.996), note: "可用率 99.6% · 首字 —"),
    ChannelNoteCase(item: item("healthy", p50: 1400), note: "可用率 — · 首字 1.4s"),
    ChannelNoteCase(item: ChannelItem(currentStatus: ChannelCurrentStatus(state: "healthy")), note: "可用率 — · 首字 —"),
    ChannelNoteCase(item: item("critical", success: 68, errors: 32), note: "错误率 32.0% · 首字 —"),
    ChannelNoteCase(item: item("critical", reliability: 0.7, p50: 12_400), note: "错误率 30.0% · 首字 12s"),
    ChannelNoteCase(item: item("unknown", sample: "no_samples"), note: "无样本"),
    ChannelNoteCase(item: item("unknown", sample: "insufficient"), note: "样本不足"),
    ChannelNoteCase(item: item("unknown", reason: "insufficient_samples", sample: "sufficient"), note: "样本不足"),
    ChannelNoteCase(item: item("unknown", reason: "no_samples"), note: "无样本"),
    ChannelNoteCase(item: item("unknown", reason: "collection_unavailable", reliability: 0.99, sample: "no_samples"), note: "采集不可用"),
    ChannelNoteCase(item: item("stale", reason: "traffic_expired", reliability: 0.99, p50: 900), note: "数据已过期"),
    ChannelNoteCase(item: item("unknown", reliability: 0.99), note: "可用率 99.0% · 首字 —")
]

@Test(arguments: channelNoteCases)
func channelNoteCoversEveryBranch(row: ChannelNoteCase) {
    #expect(ChannelPresentation.note(row.item) == row.note)
}

@Test func channelReliabilityTextAndErrorRate() throws {
    #expect(ChannelPresentation.reliabilityText(item("healthy", reliability: 0.996)) == "99.6%")
    #expect(ChannelPresentation.reliabilityText(item("healthy")) == "—")
    #expect(ChannelPresentation.reliabilityText(ChannelItem()) == "—")
    #expect(ChannelPresentation.errorRate(ChannelMetrics(channelErrors: 32, successRequests: 68)) == 0.32)
    #expect(ChannelPresentation.errorRate(ChannelMetrics(channelErrors: 0, successRequests: 0)) == nil)
    let fallback = try #require(ChannelPresentation.errorRate(ChannelMetrics(reliabilityRate: 0.7, channelErrors: 0, successRequests: 0)))
    #expect(abs(fallback - 0.3) < 1e-9)
    let countsMissing = try #require(ChannelPresentation.errorRate(ChannelMetrics(reliabilityRate: 0.7)))
    #expect(abs(countsMissing - 0.3) < 1e-9)
    #expect(ChannelPresentation.errorRate(nil) == nil)
}

private let channelCoverageCases: [(ChannelCoverage?, Bool)] = [
    (ChannelCoverage(state: "complete", collectorState: "healthy"), false), (ChannelCoverage(state: "partial", collectorState: "healthy"), false),
    (ChannelCoverage(state: "complete", collectorState: "stale"), true), (ChannelCoverage(state: "stale", collectorState: "healthy"), true),
    (ChannelCoverage(state: "unavailable", collectorState: "disabled"), true), (nil, false),
    (ChannelCoverage(state: "partial", collectorState: nil), false), (ChannelCoverage(state: " Stale ", collectorState: " Healthy "), true)
]

@Test(arguments: channelCoverageCases)
func channelCoverageHintRules(coverage: ChannelCoverage?, shows: Bool) {
    #expect(ChannelPresentation.showsCoverageHint(coverage) == shows)
    #expect(ChannelPresentation.coverageHint == "渠道数据采集延迟，显示的可能不是最新状态")
}

@Test func channelPlatformSummaryIgnoresCaseAndPicksWorst() throws {
    let items = [item("healthy", id: 1, platform: "openai", reliability: 0.99), item("warning", id: 2, platform: "OpenAI", reliability: 0.95),
                 item("critical", id: 3, platform: "anthropic", reliability: 0.5)]
    let summary = try #require(ChannelPresentation.platformSummary(items, platform: " OpenAI "))
    #expect(summary == ChannelPlatformSummary(worst: .degraded, channelCount: 2, lowestReliability: 0.95))
    #expect(summary.worst.label == "性能下降" && summary.worst.tone == .caution)
    #expect(ChannelPresentation.platformNote(summary) == "2 个分组渠道 · 最低可用率 95.0%")
    #expect(ChannelPresentation.platformSummary(items, platform: "gemini") == nil)
    #expect(ChannelPresentation.platformSummary(items, platform: "  ") == nil)
    #expect(ChannelPresentation.platformNote(nil) == "没有这个平台的渠道探测")
    let unmeasured = try #require(ChannelPresentation.platformSummary([item("unknown", platform: "gemini")], platform: "Gemini"))
    #expect(unmeasured == ChannelPlatformSummary(worst: .unknown, channelCount: 1, lowestReliability: nil))
    #expect(ChannelPresentation.platformNote(unmeasured) == "1 个分组渠道 · 最低可用率 —")
}

private let channelRefreshCases: [(Int?, TimeInterval)] = [(nil, 60), (0, 60), (-1, 60), (10, 30), (30, 30), (45, 45), (300, 300), (600, 300)]

@Test(arguments: channelRefreshCases)
func channelRefreshIntervalClampsToBackendBounds(seconds: Int?, expected: TimeInterval) {
    #expect(ChannelPresentation.refreshInterval(seconds) == expected)
    #expect(ChannelPresentation.defaultRefreshInterval == 60)
}
