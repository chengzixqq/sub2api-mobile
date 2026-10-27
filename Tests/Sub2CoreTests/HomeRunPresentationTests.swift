import Foundation
import Testing
@testable import Sub2Core

// 10 §1.3.5 运行区 (S1-09b): 健康分, 错误率 / 上游 429 / 529 and the channel row.

private let now = HomeTestData.now
private func value<Value>(_ value: Value, updateFailed: Bool = false) -> BlockDisplay<Value> {
    .value(value, at: now, isRefreshing: false, updateFailed: updateFailed)
}

@Test func healthScoreFollowsTheSharedBands() {
    for (score, word, tone) in [(92, "良好", Tone.ok), (60, "风险", .caution), (59, "异常", .critical)] {
        let health = HomeRunPresentation.health(value(HomeOps(healthScore: score)), opsDisabled: false)
        #expect(health == .score(MonitorPresentation.health(score), updateFailed: false))
        #expect(health.wordText == word && health.tone == tone)
    }
    let good = HomeRunPresentation.health(value(HomeOps(healthScore: 92)), opsDisabled: false)
    #expect(good.numberText == "92")
    #expect(good.spokenValue == "92，良好")
    #expect(good.reading.fraction == 0.92)
    #expect(HomeRunPresentation.healthZones == [60, 90])
}

@Test func healthKeepsTheOldScoreWhenARefreshFails() {
    let failed = BlockState<HomeOps>.failed(reason: HomeBlockText.failed, previous: HomeOps(healthScore: 80), at: now)
    #expect(HomeRunPresentation.health(failed.display, opsDisabled: false) == .score(MonitorPresentation.health(80), updateFailed: true))
    let refreshing = BlockState<HomeOps>.loading(previous: HomeOps(healthScore: 80), at: now)
    #expect(HomeRunPresentation.health(refreshing.display, opsDisabled: false) == .score(MonitorPresentation.health(80), updateFailed: false))
}

@Test func healthShowsDashAndNoticeWhenOpsMonitoringIsOff() {
    let disabled = HomeRunPresentation.health(.disabled(reason: "OPS_DISABLED"), opsDisabled: false)
    #expect(disabled == .opsDisabled)
    #expect(disabled.numberText == "—")
    #expect(disabled.wordText == "运维监控未开启")
    #expect(disabled.tone == nil)
    #expect(disabled.spokenValue == "无数据，运维监控未开启")
    #expect(disabled.reading.fraction == nil)
    // The switch may come from rates, /admin/me or a 404 while the ops block still holds a failure or an old value.
    #expect(HomeRunPresentation.health(.failed(reason: HomeBlockText.failed), opsDisabled: true) == .opsDisabled)
    #expect(HomeRunPresentation.health(value(HomeOps(healthScore: 92)), opsDisabled: true) == .opsDisabled)
}

@Test func healthWithoutAValueOffersRetryOrSkeleton() {
    let failed = HomeRunPresentation.health(.failed(reason: HomeBlockText.timedOut), opsDisabled: false)
    #expect(failed == .failed)
    #expect(failed.numberText == "—" && failed.wordText == nil && failed.spokenValue == "无数据")
    #expect(HomeRunPresentation.health(.placeholder, opsDisabled: false) == .loading)
    let unavailable = HomeRunPresentation.health(value(HomeOps(healthScore: nil)), opsDisabled: false)
    #expect(unavailable == .unavailable)
    #expect(unavailable.numberText == "—" && unavailable.wordText == nil && unavailable.spokenValue == "无数据")
}

@Test func runRatesShowDashWhenMonitoringIsOff() {
    let live = HomeRunPresentation.rates(LiveRates(errorRate: 0.0086, upstream429Count: 3, upstream529Count: 0, errorsAvailable: true))
    #expect(live == HomeRunPresentation.RunRates(errorRate: "0.9%", upstream429: "3", upstream529: "0"))
    let grouped = HomeRunPresentation.rates(LiveRates(errorRate: 0, upstream429Count: 12_345, upstream529Count: 1))
    #expect(grouped == HomeRunPresentation.RunRates(errorRate: "0.0%", upstream429: "12,345", upstream529: "1"))
    let off = HomeRunPresentation.RunRates(errorRate: "—", upstream429: "—", upstream529: "—")
    #expect(HomeRunPresentation.rates(LiveRates(rpm: 46, opsMonitoringEnabled: false)) == off)
    #expect(HomeRunPresentation.rates(nil) == off)
    // 00 §6.5: a rate the server marks unavailable is missing, as in the six cells.
    #expect(HomeRunPresentation.rates(LiveRates(errorRate: 0.01, errorsAvailable: false)).errorRate == "—")
}

@Test func channelRowSummarisesCountsAndOnlyTapsWhenItCanHelp() {
    let counts = HomeChannels(total: 6, healthy: 3, warning: 1, critical: 1, unknown: 1)
    let summary = HomeRunPresentation.channels(value(counts))
    #expect(summary == .summary(HomePresentation.channelSummaryLine(counts), updateFailed: false))
    #expect(summary.text == "可用 3 · 性能下降 1 · 不可用 1 · 未知 1")
    #expect(summary.isTappable)
    #expect(HomeRunPresentation.channels(value(HomeChannels(total: 3, healthy: 3))).text == "可用 3")

    let empty = HomeRunPresentation.channels(value(HomeChannels()))
    #expect(empty == .empty && empty.text == "还没有渠道数据" && empty.isTappable)
    let disabled = HomeRunPresentation.channels(.disabled(reason: "CHANNEL_MONITOR_DISABLED"))
    #expect(disabled == .disabled && disabled.text == "渠道监控未开启" && !disabled.isTappable)
    let failed = HomeRunPresentation.channels(.failed(reason: HomeBlockText.failed))
    #expect(failed == .failed && failed.text == "渠道状态加载失败" && !failed.isTappable)
    #expect(HomeRunPresentation.channels(value(counts, updateFailed: true)) == .summary(HomePresentation.channelSummaryLine(counts), updateFailed: true))
    let loading = HomeRunPresentation.channels(.placeholder)
    #expect(loading == .loading && !loading.isTappable)
}
