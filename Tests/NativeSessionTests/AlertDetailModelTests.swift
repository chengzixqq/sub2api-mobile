import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-12: the alert detail's state (AlertDetailModel) and LiveOpsStore's reads and copies for it (10 §3.2, §3.5, §3.6).

private let groupRule = AlertEventRule(id: 11, name: "标准组错误率", metricType: "error_rate", comparison: ">", threshold: 5, windowMinutes: 5)
private let notFound = APIError.server(status: 404, reason: "OPS_ALERT_EVENT_NOT_FOUND")
private let serverFailure = APIError.server(status: 500, reason: nil)
/// A site that sends `rule` and `group_name` itself, so no event read asks for `alert-rules` or `groups/all`, and that has
/// `status-summary` for the group row.
private let detailSite = liveOpsSite(liveOpsCapabilities + [.opsAlertEventDetails, .accountsStatusSummary])
/// The same without `accounts.status_summary`: the group row counts D02 from `groups/all` and the accounts (10 §0.2).
private let noSummarySite = liveOpsSite(liveOpsCapabilities + [.opsAlertEventDetails])

private func groupEvent(_ id: Int = 41, metric: Double = 5.2, status: String = "firing", rule: AlertEventRule? = groupRule) -> AlertEvent {
    AlertEvent(id: id, ruleID: 11, severity: "P1", status: status, title: "P1: 标准组错误率", metricValue: metric, thresholdValue: 5, groupID: 12,
               firedAt: Date().addingTimeInterval(-720), rule: rule, groupName: "标准组")
}
private func platformEvent(_ id: Int = 40) -> AlertEvent { firingEvent(id, severity: "P2", platform: "anthropic") }
private func serverEvent(_ id: Int = 37) -> AlertEvent {
    AlertEvent(id: id, ruleID: 13, severity: "P1", status: "firing",
               rule: AlertEventRule(id: 13, name: "内存使用率", metricType: "memory_usage_percent", comparison: ">", threshold: 85))
}
private func standardGroup(_ id: Int = 12) -> AccountStatusGroupSummary {
    AccountStatusGroupSummary(groupID: id, groupName: "标准组", platform: "openai", counts: AccountStateCounts(total: 2, available: 1, error: 1))
}
private let anthropicChannels = ChannelOverview(items: [ChannelItem(platform: "anthropic", groupID: 1, currentStatus: ChannelCurrentStatus(state: "healthy"))])
private func isChannelRead(_ call: StubLiveOpsSource.Call) -> Bool { if case .channels = call { true } else { false } }
private func isScopeRead(_ call: StubLiveOpsSource.Call) -> Bool { call == .summary || isChannelRead(call) }

/// A store whose firing list holds `listed`, and a detail for `id` over it.
@MainActor private func bench(_ source: StubLiveOpsSource, listed: [AlertEvent] = [], id: Int = 41, site: SiteSession? = detailSite,
                              sleeper: PollSleeper = PollSleeper()) async -> (harness: LiveOpsHarness, model: AlertDetailModel) {
    let harness = LiveOpsHarness(source, site: site)
    if !listed.isEmpty {
        await source.update { $0.alertEvents = { _, _ in listed } }
        await harness.store.refreshFiringAlerts(maxAge: 0)
    }
    return (harness, AlertDetailModel(eventID: id, store: harness.store, sleep: { try await sleeper.sleep($0) }))
}

// MARK: 事件

@MainActor @Test func firstScreenShowsTheListedEventThenTheRead() async {
    let source = StubLiveOpsSource(.init(alertEvent: { _ in groupEvent(metric: 6.1) }))
    let (harness, model) = await bench(source, listed: [groupEvent()])
    #expect(model.event?.metricValue == 5.2 && model.phase == .loading)
    await model.load(refreshScope: false)
    #expect(model.phase == .ready && model.event?.metricValue == 6.1)
    #expect(harness.store.firingAlerts.map(\.metricValue) == [6.1])
    #expect(await source.count { $0 == .alertEvent(41) } == 1)
}

@MainActor @Test func anUnlistedEventWaitsForTheRead() async {
    let source = StubLiveOpsSource(.init(alertEvent: { id in groupEvent(id) }))
    let (_, model) = await bench(source, id: 99)
    #expect(model.event == nil && model.phase == .loading)
    await model.load(refreshScope: false)
    #expect(model.phase == .ready && model.event?.id == 99)
}

@MainActor @Test func goneAndOpsDisabledRepliesSwitchThePhase() async {
    let gone = await bench(StubLiveOpsSource(.init(alertEvent: { _ in throw notFound })), listed: [groupEvent()])
    await gone.model.load(refreshScope: true)
    #expect(gone.model.phase == .notFound && gone.model.event == nil && gone.model.scopeKind == nil)
    let off = await bench(StubLiveOpsSource(.init(alertEvent: { _ in throw opsDisabledError })), listed: [groupEvent()])
    await off.model.load(refreshScope: false)
    #expect(off.model.phase == .opsDisabled && off.model.event == nil && off.harness.store.opsDisabled)
}

@MainActor @Test func anInvalidEventIDGoesBack() async {
    for error in [APIError.server(status: 400, reason: nil), APIError(kind: .validation, message: "无效的对象编号。")] {
        let (_, model) = await bench(StubLiveOpsSource(.init(alertEvent: { _ in throw error })), id: 0)
        await model.load(refreshScope: true)
        #expect(model.dismissRequested)
    }
    let (_, other) = await bench(StubLiveOpsSource(.init(alertEvent: { _ in throw serverFailure })))
    await other.load(refreshScope: true)
    #expect(!other.dismissRequested && other.phase == .failed)
}

@MainActor @Test func aFailedReadKeepsTheShownEvent() async {
    let (_, model) = await bench(StubLiveOpsSource(.init(alertEvent: { _ in throw serverFailure })), listed: [groupEvent()])
    await model.load(refreshScope: false)
    #expect(model.phase == .ready && model.event?.id == 41 && model.eventLoad.lastError == serverFailure)
    #expect(model.eventState.value?.id == 41 && model.eventState.failureReason != nil)
    let source = StubLiveOpsSource(.init(alertEvent: { _ in throw serverFailure }))
    let (_, empty) = await bench(source)
    await empty.load(refreshScope: false)
    #expect(empty.phase == .failed && empty.event == nil)
    await source.update { $0.alertEvent = { _ in groupEvent() } }
    await empty.load(refreshScope: false)
    #expect(empty.phase == .ready && empty.event?.id == 41 && empty.eventState.failureReason == nil)
}

/// S1D1-16: an old server's event gets its rule through the store's one lookup, read again on a pull.
@MainActor @Test func anOldServersEventGetsItsRuleOncePerPull() async {
    let source = StubLiveOpsSource(.init(summary: { AccountStatusSummary() }, alertEvent: { _ in groupEvent(rule: nil) }, alertRules: { [groupRule] }))
    let (_, model) = await bench(source, site: liveOpsSite())
    await model.load(refreshScope: true)
    await model.load(refreshScope: false)
    #expect(model.event?.rule == groupRule)
    #expect(await source.count { $0 == .alertRules } == 1)
    await model.load(refreshScope: true, pullToRefresh: true)
    #expect(await source.count { $0 == .alertRules } == 2)
}

@MainActor @Test func aReadThatFoundItEndedLeavesTheFiringList() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, alertEvent: { _ in groupEvent(status: "resolved") }))
    let (harness, model) = await bench(source, listed: [groupEvent()])
    await model.load(refreshScope: false)
    #expect(model.event?.status == "resolved" && harness.store.firingAlerts.isEmpty)
    await harness.store.refreshHome(noCache: false)
    #expect(await source.homeCalls == [true])
}

// MARK: 范围

@MainActor @Test func groupScopePrefersAvailabilityThenStatusSummary() async {
    let listing = StubLiveOpsSource(.init(home: { _ in homeReply(availability: .ok(AccountStatusSummary(groups: [standardGroup()]))) },
                                          alertEvent: { _ in groupEvent() }))
    let first = await bench(listing)
    await first.harness.store.refreshHome(noCache: false)
    await first.model.load(refreshScope: true)
    #expect(first.model.groupLoad.value == .found(standardGroup()))
    #expect(await listing.count { $0 == .summary } == 0)
    let asking = StubLiveOpsSource(.init(summary: { AccountStatusSummary(groups: [standardGroup()]) }, alertEvent: { _ in groupEvent() }))
    let second = await bench(asking)
    await second.model.load(refreshScope: true)
    #expect(second.model.groupLoad.value == .found(standardGroup()))
    #expect(await asking.count { $0 == .summary } == 1)
    let missing = StubLiveOpsSource(.init(summary: { AccountStatusSummary(groups: [standardGroup(3)]) }, alertEvent: { _ in groupEvent() }))
    let third = await bench(missing)
    await third.model.load(refreshScope: true)
    #expect(third.model.groupLoad.value == .deleted)
}

@MainActor @Test func withoutStatusSummaryTheGroupRowCountsD02Locally() async throws {
    let errored = UpstreamAccount(id: 7, name: "OpenAI-备用-A", platform: "openai", type: "apikey", status: "error", schedulable: false, groupIDs: [12])
    let healthy = UpstreamAccount(id: 4, name: "OpenAI-主力-01", platform: "openai", type: "apikey", groupIDs: [12])
    let source = StubLiveOpsSource(.init(summary: { AccountStatusSummary(groups: [standardGroup()]) }, alertEvent: { _ in groupEvent() },
                                         allGroups: { [AdminGroup(id: 12, name: "标准组", accountCount: 2, activeAccountCount: 1)] },
                                         accounts: { page, query in AccountListPage(items: [errored, healthy], total: 2, page: page, pageSize: query.pageSize, pages: 1) }))
    let (_, model) = await bench(source, site: noSummarySite)
    await model.load(refreshScope: true)
    guard case .found(let group)? = model.groupLoad.value else { Issue.record("\(String(describing: model.groupLoad.value))"); return }
    #expect(group.groupName == "标准组" && group.counts.total == 2 && group.counts.available == 1 && group.counts.needsAttention == 1)
    #expect(await source.count { $0 == .summary } == 0)
    #expect(await source.count { $0 == .allGroups(includeInactive: true) } == 1)
    #expect(await source.count { $0 == .accounts(page: 1, pageSize: HomeFallback.localAccountPageSize) } == 1)
    await source.update { $0.allGroups = { [AdminGroup(id: 3, name: "其他组", accountCount: 1, activeAccountCount: 1)] } }
    await model.retryGroup()
    #expect(model.groupLoad.value == .deleted)
    #expect(await source.count { $0 == .summary } == 0)
}

@MainActor @Test func aScopeFailureStaysInItsRow() async {
    let source = StubLiveOpsSource(.init(summary: { throw serverFailure }, alertEvent: { _ in groupEvent() }))
    let (_, model) = await bench(source, listed: [groupEvent()])
    await model.load(refreshScope: true)
    #expect(model.phase == .ready && model.groupLoad.value == nil && model.groupLoad.lastError == serverFailure)
    await source.update { $0.summary = { AccountStatusSummary(groups: [standardGroup()]) } }
    await model.retryGroup()
    #expect(model.groupLoad.value == .found(standardGroup()))
    let channelOff = StubLiveOpsSource(.init(alertEvent: { _ in platformEvent() },
                                             channels: { throw APIError.server(status: 403, reason: "CHANNEL_MONITOR_DISABLED") }))
    let platform = await bench(channelOff, listed: [platformEvent()], id: 40)
    await platform.model.load(refreshScope: true)
    #expect(platform.model.phase == .ready && platform.model.channelMonitorDisabled)
}

@MainActor @Test func channelScopePrefersTheMonitorsList() async {
    let source = StubLiveOpsSource(.init(alertEvent: { _ in platformEvent() }, channels: { anthropicChannels }))
    let (harness, model) = await bench(source, listed: [platformEvent()], id: 40)
    await harness.store.channels.load(isCurrent: { true }) { anthropicChannels }
    await model.load(refreshScope: true)
    #expect(model.channelLoad.value == anthropicChannels)
    #expect(await source.count(isChannelRead) == 0)
    await model.load(refreshScope: true, pullToRefresh: true)
    #expect(await source.count { $0 == .channels(range: "90m", refresh: false) } == 1)
    let unlisted = await bench(source, listed: [platformEvent()], id: 40)
    await unlisted.model.load(refreshScope: true)
    #expect(unlisted.model.channelLoad.value == anthropicChannels)
    #expect(await source.count(isChannelRead) == 2)
}

@MainActor @Test func scopeReadsFollowTheEventsDimension() async {
    let events = [41: groupEvent(), 40: platformEvent(), 37: serverEvent()]
    let source = StubLiveOpsSource(.init(summary: { AccountStatusSummary() }, alertEvent: { id in events[id] ?? groupEvent(id) },
                                         channels: { anthropicChannels }))
    let group = await bench(source, id: 41)
    await group.model.load(refreshScope: true)
    #expect(await source.calls.filter(isScopeRead) == [.summary])
    let platform = await bench(source, id: 40)
    await platform.model.load(refreshScope: true)
    #expect(await source.calls.filter(isScopeRead) == [.summary, .channels(range: "90m", refresh: false)])
    let server = await bench(source, id: 37)
    await server.model.load(refreshScope: true)
    await group.model.load(refreshScope: false)
    #expect(await source.calls.filter(isScopeRead).count == 2)
}

// MARK: 写后与轮询

@MainActor @Test func localWritesPatchTheDetailAndMoveItsRevision() async {
    let (harness, model) = await bench(StubLiveOpsSource(.init(alertEvent: { _ in groupEvent() })), listed: [groupEvent()])
    let store = harness.store
    await model.load(refreshScope: false)
    let silence = AlertSilenceRef(id: 601, until: Date().addingTimeInterval(3_600))
    store.applySilence(eventID: 41, silence)
    #expect(model.event?.silence == silence && store.alertRevision(id: 41) == 1)
    store.applySilence(eventID: 41, nil)
    #expect(model.event?.silence == nil && store.alertRevision(id: 41) == 2)
    store.markResolved(eventID: 41, at: Date())
    #expect(model.event?.status == AlertEvent.manualResolved && store.alertRevision(id: 41) == 3 && store.firingAlerts.isEmpty)
    store.markResolved(eventID: 77, at: Date())
    #expect(store.alertRevision(id: 77) == 1 && store.alert(id: 77) == nil)
    store.removeAlert(eventID: 41)
    #expect(model.event == nil && store.alertRevision(id: 41) == 4)
}

@MainActor @Test func aWriteReadBackReachesAnOpenDetail() async {
    let (harness, model) = await bench(StubLiveOpsSource(.init(alertEvent: { _ in groupEvent() })), listed: [groupEvent()])
    await model.load(refreshScope: false)
    await harness.store.upsertAlert(groupEvent(metric: 7.4))
    #expect(model.event?.metricValue == 7.4)
}

@MainActor @Test func pollingReadsOnlyTheEventAndWaitsOutA429() async throws {
    let tally = Tally()
    let source = StubLiveOpsSource(.init(summary: { AccountStatusSummary() }, alertEvent: { _ in
        if tally.next() == 2 { throw APIError.server(status: 429, envelope: nil, retryAfter: 30) }
        return groupEvent()
    }, channels: { anthropicChannels }))
    let sleeper = PollSleeper(stopAfter: 4)
    let (_, model) = await bench(source, listed: [groupEvent()], sleeper: sleeper)
    await model.polling()
    let waits = await sleeper.seconds
    try #require(waits.count == 4)
    #expect(waits[0] == 60 && waits[1] == 60)
    #expect(waits[2] > 25 && waits[2] <= 30 && waits[3] > 25 && waits[3] <= 30)
    #expect(await source.count { $0 == .alertEvent(41) } == 2)
    #expect(await source.count(isScopeRead) == 0)
    #expect(model.phase == .ready)
}

@MainActor @Test func pollingStopsOnceTheEventIsGone() async {
    let sleeper = PollSleeper(stopAfter: 5)
    let (_, model) = await bench(StubLiveOpsSource(.init(alertEvent: { _ in throw notFound })), listed: [groupEvent()], sleeper: sleeper)
    await model.polling()
    #expect(await sleeper.seconds.count == 1)
    #expect(model.phase == .notFound)
}
