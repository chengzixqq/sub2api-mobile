import Foundation
import Testing
@testable import Sub2Core

// S1-15: 监控 · 渠道 (10 §5.3, §5.5).

private func item(_ state: String?, name: String? = "标准组", id: Int = 1, platform: String = "openai", reason: String? = nil,
                  reliability: Double? = nil, success: Int? = nil, errors: Int? = nil, sample: String? = nil, p50: Double? = nil) -> ChannelItem {
    ChannelItem(platform: platform, groupID: id, groupName: name, currentStatus: ChannelCurrentStatus(state: state, reason: reason),
                metrics: ChannelMetrics(reliabilityRate: reliability, channelErrors: errors, successRequests: success, sampleState: sample,
                                        ttft: ChannelLatency(p50Ms: p50)))
}
private let disabledError = APIError.server(status: 403, reason: "CHANNEL_MONITOR_DISABLED")
private let serverFailure = APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
private let listed = ChannelOverview(items: [item("healthy")])
private func state(_ display: BlockDisplay<ChannelOverview>, featureEnabled: Bool? = true, disabledReason: String? = nil,
                   lastError: APIError? = nil) -> ChannelSectionState {
    ChannelSectionPresentation.state(featureEnabled: featureEnabled, disabledReason: disabledReason, display: display, lastError: lastError)
}

@Test func featureOffOrDisabledReplyWinsOverData() {
    let shown = BlockDisplay<ChannelOverview>.value(listed, at: Date(), isRefreshing: false, updateFailed: false)
    #expect(state(shown, featureEnabled: false) == .disabled)
    #expect(state(shown, featureEnabled: nil, disabledReason: "CHANNEL_MONITOR_DISABLED") == .disabled)
    #expect(state(.disabled(reason: "CHANNEL_MONITOR_DISABLED")) == .disabled)
    #expect(state(.failed(reason: "渠道监控未开启"), lastError: disabledError) == .disabled)
}

@Test func firstLoadIsSkeleton() {
    #expect(state(.placeholder) == .loading)
    #expect(state(.placeholder, featureEnabled: nil) == .loading)
}

@Test func failureWithoutValueFailsAndWithValueKeepsList() {
    #expect(state(.failed(reason: "站点暂时不可用"), lastError: serverFailure) == .failed)
    #expect(state(.failed(reason: "网络错误")) == .failed)
    #expect(state(.value(listed, at: Date(), isRefreshing: false, updateFailed: true)) == .list(updateFailed: true))
    #expect(state(.value(listed, at: Date(), isRefreshing: true, updateFailed: false)) == .list(updateFailed: false))
}

@Test func emptyItemsShowEmptyState() {
    #expect(state(.value(ChannelOverview(items: []), at: Date(), isRefreshing: false, updateFailed: false)) == .empty)
    #expect(state(.value(ChannelOverview(items: []), at: Date(), isRefreshing: false, updateFailed: true)) == .empty)
}

@Test func otherForbiddenShowsVendorPlaceholder() {
    let vendor = APIError.server(status: 403, reason: "FORBIDDEN"), administratorOnly = APIError.server(status: 403, reason: nil)
    #expect(state(.failed(reason: nil), lastError: vendor) == .forbidden)
    #expect(state(.failed(reason: nil), lastError: administratorOnly) == .forbidden)
    #expect(ChannelSectionPresentation.disabledReason(disabledError) == "CHANNEL_MONITOR_DISABLED")
    #expect(!ChannelSectionPresentation.isForbidden(disabledError))
    #expect(ChannelSectionPresentation.isForbidden(vendor) && ChannelSectionPresentation.isForbidden(administratorOnly))
    for other in [APIError.server(status: 404, reason: "OPS_DISABLED"), serverFailure, nil] {
        #expect(ChannelSectionPresentation.disabledReason(other) == nil)
        #expect(!ChannelSectionPresentation.isForbidden(other))
    }
}

@Test func countCellsKeepOrderAndCountStaleAsUnknown() {
    let items = ["healthy", "healthy", "healthy", "warning", "critical", "unknown", "stale", "", "weird"].map { item($0) }
    let cells = ChannelSectionPresentation.countCells(items)
    #expect(cells.map(\.key) == ["available", "degraded", "unavailable", "unknown"])
    #expect(cells.map(\.title) == ["可用", "性能下降", "不可用", "未知"])
    #expect(cells.map(\.value) == ["3", "1", "1", "4"])
    #expect(cells.map(\.tone) == [.ok, .caution, .critical, .neutral])
    #expect(cells.map(\.spokenValue) == ["3", "1", "1", "4"])
}

@Test func zeroCountIsNotTintedAndMissingIsDash() {
    let calm = ChannelSectionPresentation.countCells([item("healthy"), item("healthy")])
    #expect(calm.map(\.value) == ["2", "0", "0", "0"])
    #expect(calm.map(\.tone) == [.ok, nil, nil, nil])
    let missing = ChannelSectionPresentation.countCells(nil)
    #expect(missing.map(\.value) == Array(repeating: DisplayFormat.missing, count: 4))
    #expect(missing.allSatisfy { $0.tone == nil })
    #expect(missing.map(\.spokenValue) == Array(repeating: "无数据", count: 4))
}

@Test func rowsFollowPresentationOrderAndJoinRail() {
    let items = [item("healthy", name: "标准组", id: 2), item("critical", name: "Kimi 组", id: 8), item("unknown", name: "默认组", id: 3),
                 item("warning", name: "Claude Code 组", id: 5), item("healthy", name: "高级组", id: 1)]
    let rows = ChannelSectionPresentation.rows(items)
    #expect(rows.map(\.groupID) == ChannelPresentation.sorted(items).map(\.groupID))
    #expect(rows.map(\.groupID) == [8, 5, 3, 2, 1])
    #expect(rows.map(\.railPosition) == [.top, .bottom, nil, nil, nil])
    #expect(ChannelSectionPresentation.rows([item("warning")]).map(\.railPosition) == [.single])
    #expect(ChannelSectionPresentation.rows([]).isEmpty)
}

@Test func trailingShowsReliabilityOnlyForAvailable() {
    func trailing(_ item: ChannelItem) -> ChannelRowDisplay.Trailing? { ChannelSectionPresentation.rows([item]).first?.trailing }
    #expect(trailing(item("healthy", reliability: 0.996)) == .reliability("99.6%"))
    #expect(trailing(item("healthy")) == .reliability("—"))
    #expect(trailing(item("warning", reliability: 0.975)) == .badge("性能下降", .caution))
    #expect(trailing(item("critical")) == .badge("不可用", .critical))
    #expect(trailing(item("stale", reliability: 0.99)) == .badge("未知", .neutral))
}

@Test func rowTitlePlatformNameAndSpokenText() throws {
    let unnamed = try #require(ChannelSectionPresentation.rows([item("healthy", name: "  ", id: 12, platform: "")]).first)
    #expect(unnamed.title == "分组 #12" && unnamed.platformName.isEmpty)
    #expect(unnamed.spokenLabel == "分组 #12")
    let standard = item("healthy", name: "标准组", id: 2, reliability: 0.999, p50: 900)
    let row = try #require(ChannelSectionPresentation.rows([standard]).first)
    #expect(row.title == "标准组" && row.platformName == "OpenAI" && row.status == .available && row.tone == .ok)
    #expect(row.spokenLabel == "标准组，OpenAI")
    #expect(row.spokenValue == "可用，可用率 99.9% · 首字 900ms")
    #expect(row.note == ChannelPresentation.note(standard))
    #expect(row.strip.count == ChannelPresentation.stripLength && row.id == 2)
    let kimi = try #require(ChannelSectionPresentation.rows([item("critical", name: "Kimi 组", id: 8, platform: "kimi", success: 690,
                                                                 errors: 310)]).first)
    #expect(kimi.platformName == "Kimi" && kimi.spokenValue == "不可用，错误率 31.0% · 首字 —")
}

@Test func sectionTextsMatchSpec() {
    #expect(ChannelSectionPresentation.range == "90m")
    #expect(ChannelSectionPresentation.sectionTitle == "渠道")
    #expect(ChannelSectionPresentation.sectionMeta == "可用率 · 首字")
    #expect(ChannelSectionPresentation.sectionOrdinal == "壹")
    #expect(ChannelSectionPresentation.disabledTitle == "渠道监控未开启")
    #expect(ChannelSectionPresentation.disabledDetail == "可在 Web 后台的渠道监控设置中开启")
    #expect(ChannelSectionPresentation.emptyTitle == "还没有渠道数据")
    #expect(ChannelSectionPresentation.failedTitle == "渠道加载失败")
    #expect(ChannelSectionPresentation.channelMonitorDisabledReason == "CHANNEL_MONITOR_DISABLED")
}
