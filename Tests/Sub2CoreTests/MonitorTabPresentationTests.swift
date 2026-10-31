import Foundation
import Testing
@testable import Sub2Core

// S1-13: the monitor tab's segments, subtitles and counts and the overview's run section (10 §4.1–§4.3).

private let now = HomeTestData.now
private let shanghai = HomeTestData.shanghai
private let serverShanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private func utc(_ text: String) -> Date { ServerTime.parseTimestamp(text)! }

@Test func segmentTitleShowsCountOnlyWhenPositive() {
    #expect(MonitorTabPresentation.segmentTitle("告警", count: 2) == "告警 2")
    #expect(MonitorTabPresentation.segmentTitle("告警", count: 0) == "告警")
    #expect(MonitorTabPresentation.segmentTitle("告警", count: nil) == "告警")
    #expect(MonitorTabPresentation.segmentTitle("渠道", count: 12) == "渠道 12")
    #expect(MonitorTabPresentation.segmentTitle("渠道", count: 1_200) == "渠道 1,200")
}

@Test func overviewSubtitleFollowsRefreshStatus() {
    func subtitle(_ status: HomeRefreshStatus?) -> String { MonitorTabPresentation.overviewSubtitle(status, now: now, timeZone: shanghai) }
    #expect(subtitle(nil) == "运行与服务器")
    #expect(subtitle(.loading) == "运行与服务器 · 正在加载…")
    #expect(subtitle(.updated(at: now.addingTimeInterval(-20))) == "运行与服务器 · 刚刚更新")
    #expect(subtitle(.updated(at: now.addingTimeInterval(-300))) == "运行与服务器 · 5 分钟前更新")
    #expect(subtitle(.updated(at: now.addingTimeInterval(-7_200))) == "运行与服务器 · 更新于 今天 08:00")
    #expect(subtitle(.partial) == "运行与服务器 · 部分数据未更新")
}

@Test func channelsAndAlertsSubtitles() {
    #expect(MonitorTabPresentation.channelsSubtitle(updatedAt: nil, now: now, timeZone: shanghai) == "渠道 · 近 90 分钟")
    #expect(MonitorTabPresentation.channelsSubtitle(updatedAt: now.addingTimeInterval(-20), now: now, timeZone: shanghai)
            == "渠道 · 近 90 分钟 · 刚刚更新")
    #expect(MonitorTabPresentation.alertsSubtitle(firingCount: nil) == "告警")
    #expect(MonitorTabPresentation.alertsSubtitle(firingCount: 0) == "告警 · 0 条进行中")
    #expect(MonitorTabPresentation.alertsSubtitle(firingCount: 3) == "告警 · 3 条进行中")
}

/// The phrase moved out of the overview's subtitle reads the same there.
@Test func refreshPhraseMatchesHomeSubtitleSuffix() {
    let statuses: [HomeRefreshStatus] = [.loading, .updated(at: now.addingTimeInterval(-20)), .updated(at: now.addingTimeInterval(-300)),
                                         .updated(at: now.addingTimeInterval(-7_200)), .partial]
    for status in statuses {
        let home = HomePresentation.subtitle(now: now, status: status, serverTimeZone: serverShanghai, deviceTimeZone: shanghai)
        #expect(home.hasSuffix(" · " + HomePresentation.refreshPhrase(status, now: now, timeZone: shanghai)), "\(status)")
    }
    #expect(HomePresentation.refreshPhrase(.updated(at: now.addingTimeInterval(-7_200)), now: now, timeZone: shanghai) == "更新于 今天 08:00")
}

@Test func refreshStatusCombinesBlocks() {
    let t1 = now.addingTimeInterval(-90), t2 = now.addingTimeInterval(-30)
    let empty = MonitorBlockSnapshot(hasValue: false, failed: false, updatedAt: nil)
    #expect(MonitorTabPresentation.refreshStatus([empty, empty]) == .loading)
    #expect(MonitorTabPresentation.refreshStatus([MonitorBlockSnapshot(hasValue: true, failed: false, updatedAt: t1), empty]) == .loading)
    #expect(MonitorTabPresentation.refreshStatus([MonitorBlockSnapshot(hasValue: false, failed: true, updatedAt: nil), empty]) == .partial)
    #expect(MonitorTabPresentation.refreshStatus([MonitorBlockSnapshot(hasValue: true, failed: true, updatedAt: t1),
                                                  MonitorBlockSnapshot(hasValue: true, failed: false, updatedAt: t2)]) == .partial)
    #expect(MonitorTabPresentation.refreshStatus([MonitorBlockSnapshot(hasValue: true, failed: false, updatedAt: t2),
                                                  MonitorBlockSnapshot(hasValue: true, failed: false, updatedAt: t1)]) == .updated(at: t1))

    #expect(MonitorBlockSnapshot(BlockState<Int>.loaded(1, at: t1)) == MonitorBlockSnapshot(hasValue: true, failed: false, updatedAt: t1))
    #expect(MonitorBlockSnapshot(BlockState<Int>.failed(reason: nil, previous: nil, at: nil))
            == MonitorBlockSnapshot(hasValue: false, failed: true, updatedAt: nil))
    #expect(MonitorBlockSnapshot(BlockState<Int>.failed(reason: "加载失败", previous: 3, at: t2))
            == MonitorBlockSnapshot(hasValue: true, failed: true, updatedAt: t2))
    #expect(MonitorBlockSnapshot(BlockState<Int>.loading(previous: 3, at: t2)) == MonitorBlockSnapshot(hasValue: true, failed: false, updatedAt: t2))
    #expect(MonitorBlockSnapshot(BlockState<Int>.idle) == MonitorBlockSnapshot(hasValue: false, failed: false, updatedAt: nil))
}

/// 10 §4.1: critical + warning of the channel list once it is read (S1-15), otherwise of the home block.
@Test func channelsAttentionCountPrefersChannelList() {
    let items = ["healthy", "warning", "critical", "stale"].enumerated().map {
        ChannelItem(platform: "openai", groupID: $0.offset + 1, currentStatus: ChannelCurrentStatus(state: $0.element))
    }
    #expect(MonitorTabPresentation.channelsAttentionCount(items: items, home: HomeChannels(warning: 5, critical: 5)) == 2)
    #expect(MonitorTabPresentation.channelsAttentionCount(items: [], home: HomeChannels(warning: 5)) == 0)
    #expect(MonitorTabPresentation.channelsAttentionCount(items: nil, home: HomeChannels(total: 4, warning: 1, critical: 2)) == 3)
    #expect(MonitorTabPresentation.channelsAttentionCount(items: nil, home: nil) == nil)
}

/// The fresh list while it is not cut off at its limit; otherwise the exact count.
@Test func firingCountUsesFreshListUnlessTruncated() {
    #expect(MonitorTabPresentation.firingCount(listCount: 2, listLimit: 100, counts: AlertCounts(firing: 5)) == 2)
    #expect(MonitorTabPresentation.firingCount(listCount: nil, listLimit: 100, counts: AlertCounts(firing: 5)) == 5)
    #expect(MonitorTabPresentation.firingCount(listCount: 100, listLimit: 100, counts: AlertCounts(firing: 130)) == 130)
    #expect(MonitorTabPresentation.firingCount(listCount: 100, listLimit: 100, counts: nil) == 100)
    #expect(MonitorTabPresentation.firingCount(listCount: nil, listLimit: 100, counts: nil) == nil)
}

@Test func alertsRowJoinsTitlesAndCautionsWhenFiring() {
    let firing = MonitorTabPresentation.alertsRow(firingCount: 2, titles: ["标准组错误率 5.2%", "Anthropic 上游错误率 6.1%"])
    #expect(firing == MonitorAlertsRow(title: "告警中 2 条", detail: "标准组错误率 5.2%、Anthropic 上游错误率 6.1%", tone: .caution))
    #expect(MonitorTabPresentation.alertsRow(firingCount: 0, titles: []) == MonitorAlertsRow(title: "告警中 0 条", detail: "没有告警", tone: nil))
    #expect(MonitorTabPresentation.alertsRow(firingCount: nil, titles: []) == MonitorAlertsRow(title: "告警中 —", detail: nil, tone: nil))
    // Counted before the list arrived: no titles yet, and never “没有告警” beside a count.
    #expect(MonitorTabPresentation.alertsRow(firingCount: 3, titles: []) == MonitorAlertsRow(title: "告警中 3 条", detail: nil, tone: .caution))
}

@Test func healthAdaptsOverviewToSharedBands() {
    func health(_ score: Int?, updateFailed: Bool = false) -> HomeRunPresentation.Health {
        MonitorTabPresentation.health(.value(OpsOverview(healthScore: score), at: now, isRefreshing: false, updateFailed: updateFailed))
    }
    #expect(health(92) == .score(MonitorPresentation.health(92), updateFailed: false))
    #expect(health(92).wordText == "良好" && health(92).tone == .ok && health(92).spokenValue == "92，良好")
    #expect(health(60).wordText == "风险" && health(60).tone == .caution)
    #expect(health(59).wordText == "异常" && health(59).tone == .critical)
    #expect(health(70, updateFailed: true) == .score(MonitorPresentation.health(70), updateFailed: true))
    #expect(health(nil) == .unavailable)
    #expect(MonitorTabPresentation.health(.placeholder) == .loading)
    #expect(MonitorTabPresentation.health(.failed(reason: "加载失败")) == .failed)
    #expect(MonitorTabPresentation.health(.failed(reason: nil)).numberText == "—")
    for score in [100, 90, 89, 60, 59, 0] {
        let home = HomeRunPresentation.health(.value(HomeOps(healthScore: score), at: now, isRefreshing: false, updateFailed: false), opsDisabled: false)
        #expect(health(score) == home)
    }
}

@Test func ratesFormatErrorRateAndUpstreamCounts() {
    let rates = MonitorTabPresentation.rates(OpsOverview(errorRate: 0.0086, upstream429Count: 3, upstream529Count: 0))
    #expect([rates.errorRate, rates.upstream429, rates.upstream529] == ["0.9%", "3", "0"])
    for missing in [nil, OpsOverview()] {
        let empty = MonitorTabPresentation.rates(missing)
        #expect([empty.errorRate, empty.upstream429, empty.upstream529] == ["—", "—", "—"])
    }
}

/// Whole minutes, so the server returns exactly 45 full buckets and the same window hits its cache within the minute.
@Test func errorTrendWindowFloorsToWholeMinute() {
    let window = MonitorTabPresentation.errorTrendWindow(now: utc("2026-10-16T02:00:42Z"))
    #expect(window.end == utc("2026-10-16T02:00:00Z") && window.start == utc("2026-10-16T01:15:00Z"))
    let exact = MonitorTabPresentation.errorTrendWindow(now: utc("2026-10-16T02:00:00Z"))
    #expect(exact.end == utc("2026-10-16T02:00:00Z"))
    #expect(exact.end.timeIntervalSince(exact.start) == 2_700)
}

@Test func trendSpokenValueDescribesLatestAndPeak() {
    #expect(MonitorTabPresentation.trendSpokenValue([0.01, nil, 0.012, 0.009]) == "最近 0.9%，最高 1.2%")
    #expect(MonitorTabPresentation.trendSpokenValue([0.01, nil]) == "最近 1.0%，最高 1.0%")
    #expect(MonitorTabPresentation.trendSpokenValue([nil, nil]) == "无数据")
    #expect(MonitorTabPresentation.trendSpokenValue([]) == "无数据")
}

/// 10 §0.1, U01: the same check as the overview's; first-version vendors cannot sign in, so this is a guard only.
@Test func vendorPlaceholderOnlyForWorkspace() {
    let vendor = AdminMe(user: .init(id: 2, role: "admin"), workspace: .init(id: 3))
    let owner = AdminMe(user: .init(id: 1, role: "admin"))
    #expect(MonitorTabPresentation.showsVendorPlaceholder(vendor))
    #expect(!MonitorTabPresentation.showsVendorPlaceholder(owner))
    #expect(MonitorTabPresentation.vendorPlaceholder == "代运营工作区没有运维监控权限")
    #expect(MonitorTabPresentation.trendLabel == "错误率 · 近 45 分钟" && MonitorTabPresentation.trendFailed == "趋势加载失败")
}
