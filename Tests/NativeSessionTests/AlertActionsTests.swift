import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-06: AlertActions (10 §7.1) over a stand-in for just its five requests (S1D1-06 allows one; it is not a LiveOpsSource) and a
// host that records what the store is asked to do; the last tests run the real LiveOpsStore over FixtureLiveOpsSource.

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let now = ServerTime.parseTimestamp("2026-10-22T09:41:00+08:00")!
private let timeout = APIError(kind: .transport, message: "连接超时")
private let original = AlertSilenceRef(id: 9, until: now.addingTimeInterval(1_800))

private actor AlertSourceFake: AlertActionSource {
    enum Call: Equatable, Sendable {
        case read(Int), resolve(Int, String), create(rule: Int, platform: String?, group: Int?, until: Date), update(Int, Date), delete(Int)
    }
    struct Replies: Sendable {
        var read: @Sendable (Int) async throws -> AlertEvent = { _ in throw StubMissing() }
        var resolve: @Sendable () async throws -> Void = {}
        var create: @Sendable (Date) async throws -> AlertSilence = { AlertSilence(id: 77, ruleID: 11, until: $0) }
        var update: @Sendable (Int, Date) async throws -> AlertSilence = { AlertSilence(id: $0, until: $1) }
        var delete: @Sendable () async throws -> Void = {}
    }
    private var replies: Replies
    private(set) var calls: [Call] = []
    init(_ replies: Replies) { self.replies = replies }
    func set(_ change: @Sendable (inout Replies) -> Void) { change(&replies) }
    var writes: [Call] { calls.filter { if case .read = $0 { false } else { true } } }

    func alertEvent(id: Int) async throws -> AlertEvent {
        calls.append(.read(id))
        return try await replies.read(id)
    }
    func setAlertEventStatus(id: Int, status: String) async throws {
        calls.append(.resolve(id, status))
        try await replies.resolve()
    }
    func createAlertSilence(ruleID: Int, platform: String?, groupID: Int?, until: Date) async throws -> AlertSilence {
        calls.append(.create(rule: ruleID, platform: platform, group: groupID, until: until))
        return try await replies.create(until)
    }
    func updateAlertSilence(id: Int, until: Date) async throws -> AlertSilence {
        calls.append(.update(id, until))
        return try await replies.update(id, until)
    }
    func deleteAlertSilence(id: Int) async throws {
        calls.append(.delete(id))
        try await replies.delete()
    }
}

@MainActor private final class HostRecorder: AlertActionsHost {
    enum Call: Equatable { case resolved(Int, Date), silence(Int, AlertSilenceRef?), upsert(AlertEvent), remove(Int), refresh, opsDisabled, externalWrite }
    private(set) var calls: [Call] = []
    var isSessionCurrent = true
    var refreshes: Int { calls.filter { $0 == .refresh }.count }

    func markResolved(eventID: Int, at date: Date) { calls.append(.resolved(eventID, date)) }
    func applySilence(eventID: Int, _ silence: AlertSilenceRef?) { calls.append(.silence(eventID, silence)) }
    func upsertAlert(_ event: AlertEvent) { calls.append(.upsert(event)) }
    func removeAlert(eventID: Int) { calls.append(.remove(eventID)) }
    func refreshAlertsAfterWrite() async { calls.append(.refresh) }
    func noteOpsDisabled() async { calls.append(.opsDisabled) }
    func noteExternalWrite() { calls.append(.externalWrite) }
}

/// A write that waits until the test opens it.
private actor Gate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    var waiters: Int { waiting.count }
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

/// Receipts never time out here, so the test reads the last one.
@MainActor private func stillReceipts() -> ReceiptCenter { ReceiptCenter(sleep: { _ in throw CancellationError() }) }

@MainActor private final class Bench {
    let source: AlertSourceFake
    let host = HostRecorder()
    let receipts = stillReceipts()
    let actions: AlertActions
    init(_ replies: AlertSourceFake.Replies = .init()) {
        source = AlertSourceFake(replies)
        actions = AlertActions(source: source, receipts: receipts, timeZone: { shanghai }, now: { now })
        actions.host = host
    }
    var receipt: Receipt? { receipts.current }
    func tapReceiptButton() { if let id = receipts.current?.id { receipts.performAction(id: id) } }
}

private func firing(id: Int = 41, ruleID: Int? = 11, platform: String? = nil, groupID: Int? = 2, silence: AlertSilenceRef? = nil,
                    silenceSupported: Bool = true) -> AlertEvent {
    AlertEvent(id: id, ruleID: ruleID, severity: "P1", status: "firing", title: "P1: 标准组错误率", metricValue: 5.2, platform: platform,
               groupID: groupID, firedAt: now.addingTimeInterval(-720), silence: silence, silenceSupported: silenceSupported,
               groupName: groupID == nil ? nil : "标准组")
}

// MARK: 手动解决

@MainActor @Test func resolveMarksResolvedShowsReceiptWithoutUndoThenRereads() async {
    let reread = firing().resolvedLocally(at: now)
    let bench = Bench(.init(read: { _ in reread }))
    #expect(await bench.actions.resolve(firing()) == .succeeded)
    #expect(await bench.source.calls == [.resolve(41, "manual_resolved"), .read(41)])
    #expect(bench.host.calls == [.resolved(41, now), .upsert(reread), .refresh])
    #expect(bench.receipt?.text == "已手动解决" && bench.receipt?.action == nil)
    #expect(!bench.actions.isRunning(41) && bench.actions.inFlight.isEmpty)
}

@MainActor @Test func resolveRereadMissingEventRemovesItAndReportsMissing() async {
    let bench = Bench(.init(read: { _ in throw APIError.server(status: 404, reason: "OPS_ALERT_EVENT_NOT_FOUND") }))
    #expect(await bench.actions.resolve(firing()) == .eventMissing)
    #expect(bench.host.calls == [.resolved(41, now), .remove(41), .refresh])
    #expect(bench.receipt?.text == "这条告警不存在或已被清理")
}

@MainActor @Test func resolveTimeoutConfirmedByReadBackCountsAsSuccess() async {
    let resolvedAt = now.addingTimeInterval(-2)
    let reread = firing().resolvedLocally(at: resolvedAt)
    let bench = Bench(.init(read: { _ in reread }, resolve: { throw timeout }))
    #expect(await bench.actions.resolve(firing()) == .succeeded)
    #expect(await bench.source.calls == [.resolve(41, "manual_resolved"), .read(41)])
    #expect(bench.host.calls == [.resolved(41, resolvedAt), .upsert(reread), .refresh])
    #expect(bench.receipt?.text == "已手动解决" && bench.receipt?.action == nil)
}

@MainActor @Test func resolveUnansweredStillFiringOffersRetryThatSendsAgain() async {
    let bench = Bench(.init(read: { _ in firing() }, resolve: { throw APIError.server(status: 504, envelope: nil) }))
    #expect(await bench.actions.resolve(firing()) == .notApplied)
    #expect(bench.host.calls.isEmpty)
    #expect(bench.receipt?.text == "操作没有生效，可以重试" && bench.receipt?.action?.title == "重试")
    #expect(await bench.source.writes.count == 1)
    await bench.source.set { $0.resolve = {} }
    bench.tapReceiptButton()
    await waitUntil { bench.host.refreshes == 1 }
    #expect(await bench.source.writes == [.resolve(41, "manual_resolved"), .resolve(41, "manual_resolved")])
    #expect(bench.receipt?.text == "已手动解决")
}

@MainActor @Test func resolveTimeoutWithFailedReadBackIsUnconfirmed() async {
    let bench = Bench(.init(read: { _ in throw timeout }, resolve: { throw timeout }))
    #expect(await bench.actions.resolve(firing()) == .unconfirmed)
    #expect(bench.host.calls.isEmpty)
    #expect(bench.receipt?.text == "结果未确认，请刷新核对后再操作" && bench.receipt?.action == nil)
    #expect(await bench.source.writes.count == 1)
}

private let writeFailures: [(APIError, String, AlertActionOutcome)] = [
    (APIError.server(status: 404, reason: "OPS_DISABLED"), "运维监控已关闭，无法处理告警", .opsDisabled),
    (APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), "只读访问令牌不能处理告警", .failed),
    (APIError.server(status: 400, reason: nil), "操作未完成（程序错误）", .failed),
    (APIError.server(status: 400, reason: "INVALID_UNTIL"), "静默时间无效（须在 30 天内）", .failed),
    (APIError.server(status: 500, reason: "INTERNAL_ERROR"), "站点暂时不可用", .failed)
]

@MainActor @Test(arguments: writeFailures.indices)
func writeFailureLeavesLocalStateAndShowsReason(index: Int) async {
    let (error, text, outcome) = writeFailures[index]
    let bench = Bench(.init(resolve: { throw error }))
    #expect(await bench.actions.resolve(firing()) == outcome)
    #expect(bench.host.calls == (outcome == .opsDisabled ? [.opsDisabled, .externalWrite] : []))
    #expect(bench.receipt?.text == text && bench.receipt?.action == nil)
    #expect(await bench.source.calls == [.resolve(41, "manual_resolved")])
}

// MARK: 静默

@MainActor @Test func silenceSendsRuleScopeAndServerUntilAndUndoDeletesCreatedSilence() async {
    let until = now.addingTimeInterval(3_600)
    let silenced = firing().withSilence(AlertSilenceRef(id: 77, until: until))
    let bench = Bench(.init(read: { _ in silenced }))
    #expect(await bench.actions.silence(firing(), for: .hour) == .succeeded)
    #expect(await bench.source.calls == [.create(rule: 11, platform: nil, group: 2, until: until), .read(41)])
    #expect(bench.host.calls == [.silence(41, AlertSilenceRef(id: 77, until: until)), .upsert(silenced), .refresh])
    #expect(bench.receipt?.text == "已静默 1 小时" && bench.receipt?.action?.title == "撤销")
    await bench.source.set { $0.read = { _ in firing() } }
    bench.tapReceiptButton()
    await waitUntil { bench.host.refreshes == 2 }
    #expect(await bench.source.writes.last == .delete(77))
    #expect(Array(bench.host.calls.suffix(3)) == [.silence(41, nil), .upsert(firing()), .refresh])
    #expect(bench.receipt == nil)
}

@MainActor @Test func silenceOfPlatformScopeSendsPlatformWithoutGroup() async {
    let event = firing(platform: "anthropic", groupID: nil)
    let bench = Bench(.init(read: { _ in event }))
    #expect(await bench.actions.silence(event, for: .week) == .succeeded)
    #expect(await bench.source.writes == [.create(rule: 11, platform: "anthropic", group: nil, until: now.addingTimeInterval(604_800))])
    #expect(bench.receipt?.text == "已静默 7 天")
}

@MainActor @Test func silenceTimeoutCountsReadBackSilenceAsSuccessWithItsUndo() async {
    let found = AlertSilenceRef(id: 88, until: now.addingTimeInterval(3_600))
    let bench = Bench(.init(read: { _ in firing().withSilence(found) }, create: { _ in throw timeout }))
    #expect(await bench.actions.silence(firing(), for: .hour) == .succeeded)
    #expect(bench.host.calls == [.silence(41, found), .upsert(firing().withSilence(found)), .refresh])
    #expect(bench.receipt?.text == "已静默 1 小时" && bench.receipt?.action?.title == "撤销")
    bench.tapReceiptButton()
    await waitUntil { await bench.source.writes.count == 2 }
    #expect(await bench.source.writes.last == .delete(88))
}

@MainActor @Test func silenceTimeoutWithoutSilenceOffersRetry() async {
    let bench = Bench(.init(read: { _ in firing() }, create: { _ in throw timeout }))
    #expect(await bench.actions.silence(firing(), for: .day) == .notApplied)
    #expect(bench.host.calls.isEmpty && bench.receipt?.action?.title == "重试")
    await bench.source.set { $0.create = { AlertSilence(id: 90, until: $0) } }
    bench.tapReceiptButton()
    await waitUntil { bench.host.refreshes == 1 }
    let until = now.addingTimeInterval(86_400)
    #expect(await bench.source.writes == [.create(rule: 11, platform: nil, group: 2, until: until), .create(rule: 11, platform: nil, group: 2, until: until)])
    #expect(bench.host.calls.first == .silence(41, AlertSilenceRef(id: 90, until: until)) && bench.receipt?.text == "已静默 24 小时")
}

@MainActor @Test func changeSilenceUpdatesUntilAndUndoRestoresOriginal() async {
    let event = firing(silence: original)
    let target = now.addingTimeInterval(86_400)
    let bench = Bench(.init(read: { _ in event.withSilence(AlertSilenceRef(id: 9, until: target)) }))
    #expect(await bench.actions.changeSilence(event, to: .day) == .succeeded)
    #expect(await bench.source.writes == [.update(9, target)])
    #expect(bench.host.calls.first == .silence(41, AlertSilenceRef(id: 9, until: target)))
    #expect(bench.receipt?.text == "静默改为至 明天 09:41" && bench.receipt?.action?.title == "撤销")
    bench.tapReceiptButton()
    await waitUntil { bench.host.refreshes == 2 }
    #expect(await bench.source.writes == [.update(9, target), .update(9, original.until!)])
    #expect(bench.host.calls.contains(.silence(41, original)) && bench.receipt == nil)
}

@MainActor @Test func changeSilenceOffersNoUndoWhenOriginalUntilHasPassed() async {
    let event = firing(silence: AlertSilenceRef(id: 9, until: now.addingTimeInterval(-60)))
    let bench = Bench(.init(read: { _ in event }))
    #expect(await bench.actions.changeSilence(event, to: .hour) == .succeeded)
    #expect(bench.receipt?.text == "静默改为至 10:41" && bench.receipt?.action == nil)
}

@MainActor @Test func endSilenceDeletesAndClearsLocalSilence() async {
    let bench = Bench(.init(read: { _ in firing() }))
    #expect(await bench.actions.endSilence(firing(silence: original)) == .succeeded)
    #expect(await bench.source.calls == [.delete(9), .read(41)])
    #expect(bench.host.calls == [.silence(41, nil), .upsert(firing()), .refresh])
    #expect(bench.receipt?.text == "已结束静默" && bench.receipt?.action == nil)
}

@MainActor @Test func silenceNotFoundRereadsEventWithoutApplying() async {
    let notFound = APIError.server(status: 404, reason: "OPS_ALERT_SILENCE_NOT_FOUND")
    let bench = Bench(.init(read: { _ in firing() }, update: { _, _ in throw notFound }, delete: { throw notFound }))
    #expect(await bench.actions.changeSilence(firing(silence: original), to: .hour) == .failed)
    #expect(bench.receipt?.text == "这条静默已不存在")
    #expect(bench.host.calls == [.upsert(firing()), .refresh])
    #expect(await bench.actions.endSilence(firing(silence: original)) == .failed)
    #expect(await bench.source.calls == [.update(9, now.addingTimeInterval(3_600)), .read(41), .delete(9), .read(41)])
    #expect(!bench.host.calls.contains { if case .silence = $0 { true } else { false } })
}

@MainActor @Test func invalidRuleIDHidesSilenceForThatRuleOnly() async {
    let bench = Bench(.init(create: { _ in throw APIError.server(status: 400, reason: "INVALID_RULE_ID") }))
    #expect(bench.actions.availableActions(for: firing()) == [.resolve, .silence])
    #expect(await bench.actions.silence(firing(), for: .hour) == .failed)
    #expect(bench.receipt?.text == "规则已删除，无法静默" && bench.host.calls.isEmpty)
    #expect(bench.actions.availableActions(for: firing(id: 42)) == [.resolve])
    #expect(bench.actions.availableActions(for: firing(id: 43, ruleID: 12)) == [.resolve, .silence])
    #expect(await bench.actions.silence(firing(id: 42), for: .hour) == .ignored)
}

@MainActor @Test func undoFailureShowsUndoFailedReceipt() async {
    let bench = Bench(.init(read: { _ in firing() }, delete: { throw APIError.server(status: 404, reason: "OPS_ALERT_SILENCE_NOT_FOUND") }))
    #expect(await bench.actions.silence(firing(), for: .hour) == .succeeded)
    let before = bench.host.calls.count
    bench.tapReceiptButton()
    await waitUntil { bench.host.refreshes == 2 }
    #expect(bench.receipt?.text == "撤销没有成功：这条静默已不存在")
    #expect(!bench.host.calls.dropFirst(before).contains(.silence(41, nil)))
}

// MARK: 并发、会话与旧服务端

@MainActor @Test func secondTapWhileRunningSendsNothing() async {
    let gate = Gate()
    let bench = Bench(.init(read: { _ in firing().resolvedLocally(at: now) }, resolve: { await gate.wait() }))
    let first = Task { await bench.actions.resolve(firing()) }
    await waitUntil { await gate.waiters == 1 }
    #expect(bench.actions.isRunning(41))
    #expect(await bench.actions.resolve(firing()) == .ignored)
    #expect(await bench.actions.perform(.silence(.hour), on: firing()) == .ignored)
    await gate.open()
    #expect(await first.value == .succeeded)
    #expect(!bench.actions.isRunning(41))
    #expect(await bench.source.writes == [.resolve(41, "manual_resolved")])
}

@MainActor @Test func cancelledOrStaleWritesShowNothing() async {
    let cancelled = Bench(.init(resolve: { throw CancellationError() }))
    #expect(await cancelled.actions.resolve(firing()) == .ignored)
    #expect(cancelled.receipt == nil && cancelled.host.calls.isEmpty)
    let stale = Bench(.init(read: { _ in firing() }))
    stale.host.isSessionCurrent = false
    #expect(await stale.actions.resolve(firing()) == .ignored)
    #expect(await stale.source.calls.isEmpty && stale.receipt == nil)
    let source = AlertSourceFake(.init(read: { _ in firing() }))
    let receipts = stillReceipts()
    let orphan = AlertActions(source: source, receipts: receipts, timeZone: { shanghai }, now: { now })
    #expect(await orphan.resolve(firing()) == .ignored)
    #expect(await source.calls.isEmpty && receipts.current == nil)
}

@MainActor @Test func eventsWithoutSilenceKeyOfferOnlyResolveAndNeverSendSilence() async {
    let legacy = firing(platform: "anthropic", groupID: nil, silenceSupported: false)
    let bench = Bench()
    #expect(bench.actions.availableActions(for: legacy) == [.resolve])
    #expect(await bench.actions.silence(legacy, for: .hour) == .ignored)
    #expect(await bench.actions.perform(.silence(.hour), on: legacy) == .ignored)
    #expect(await bench.actions.endSilence(legacy.withSilence(original)) == .ignored)
    #expect(await bench.source.calls.isEmpty && bench.receipt == nil)
    #expect(bench.actions.availableActions(for: firing().resolvedLocally(at: now)).isEmpty)
}

@MainActor @Test func performRoutesChoicesAndDialogUsesServerClock() async {
    let bench = Bench(.init(read: { _ in firing(silence: original) }))
    #expect(bench.actions.dialog(for: .changeSilence, event: firing(silence: original)).message.hasPrefix("当前静默至 10:11\n"))
    #expect(await bench.actions.perform(.silence(.week), on: firing(silence: original)) == .succeeded)
    #expect(await bench.actions.perform(.endSilence, on: firing(silence: original)) == .succeeded)
    #expect(await bench.actions.perform(.silence(.hour), on: firing(platform: "anthropic", groupID: nil)) == .succeeded)
    #expect(await bench.actions.perform(.resolve, on: firing()) == .succeeded)
    #expect(await bench.source.writes == [.update(9, now.addingTimeInterval(604_800)), .delete(9),
                                          .create(rule: 11, platform: "anthropic", group: nil, until: now.addingTimeInterval(3_600)),
                                          .resolve(41, "manual_resolved")])
}

// MARK: LiveOpsStore 作为宿主

@MainActor private func storeWithTwoFiring() async -> (LiveOpsStore, StubLiveOpsSource) {
    let pair = [firingEvent(1, severity: "P1"), firingEvent(2, severity: "P2")]
    let source = StubLiveOpsSource(.init(home: { _ in
        homeReply(alerts: .ok(HomeAlerts(firingCount: 2, bySeverity: ["P0": 0, "P1": 1, "P2": 1, "P3": 0], top: pair)))
    }, alertEvents: { _, _ in pair }, alertCounts: { AlertCounts(firing: 2, bySeverity: ["P1": 1, "P2": 1]) }))
    let store = LiveOpsHarness(source).store
    await store.refreshHome(noCache: false)
    await store.refreshFiringAlerts()
    await store.recent.load(isCurrent: { true }) { RecentAlerts() }
    return (store, source)
}

@MainActor @Test func storeUpsertAndRemoveKeepListsAndCountsConsistent() async {
    let (store, _) = await storeWithTwoFiring()
    let silence = AlertSilenceRef(id: 501, until: Date().addingTimeInterval(3_600))
    let silenced = firingEvent(2, severity: "P2").withSilence(silence)
    store.upsertAlert(silenced)
    #expect(store.firingAlerts.first { $0.id == 2 } == silenced && store.home.alerts.value?.top.first { $0.id == 2 } == silenced)
    #expect(store.alertCounts?.firing == 2 && store.recentAlerts.isEmpty)
    let ended = firingEvent(1, severity: "P1").resolvedLocally(at: Date())
    store.upsertAlert(ended)
    #expect(store.firingAlerts.map(\.id) == [2] && store.home.alerts.value?.top.map(\.id) == [2])
    #expect(store.alertCounts?.firing == 1 && store.alertCounts?.count(severity: "P1") == 0 && store.home.alerts.value?.firingCount == 1)
    #expect(store.recentAlerts == [ended])
    store.removeAlert(eventID: 2)
    #expect(store.firingAlerts.isEmpty && store.alertCounts?.firing == 0 && store.home.alerts.value?.firingCount == 0)
    store.removeAlert(eventID: 1)
    #expect(store.recentAlerts.isEmpty && store.alertCounts?.firing == 0)
}

@MainActor @Test func storeRefreshAfterWriteRereadsListAndCountsAndBypassesHomeCache() async {
    let (store, source) = await storeWithTwoFiring()
    let lists = await source.count { if case .alertEvents = $0 { true } else { false } }
    let counts = await source.count { $0 == .alertCounts }
    await store.refreshAlertsAfterWrite()
    #expect(await source.count { if case .alertEvents = $0 { true } else { false } } == lists + 1)
    #expect(await source.count { $0 == .alertCounts } == counts + 1)
    await store.refreshHome(noCache: false)
    #expect(await source.homeCalls.last == true)
    #expect(store.alertActions.host === store)
}

// MARK: 夹具联调（-ui-testing）

@MainActor private func fixtureStore(_ arguments: [String] = []) async -> (LiveOpsStore, FixtureLiveOpsSource, ReceiptCenter) {
    let source = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: arguments), base: now)
    let site = liveOpsSite(Capability.allCases)
    let receipts = stillReceipts()
    let store = LiveOpsStore(generation: UUID(), source: source, site: { site }, isCurrent: { true }, serverNow: { now }, receipts: receipts)
    await store.refreshHome(noCache: false)
    await store.refreshFiringAlerts()
    return (store, source, receipts)
}

@MainActor @Test func fixtureResolveMovesEventOutOfFiringAndCountsDrop() async throws {
    let (store, source, receipts) = await fixtureStore()
    let alertA = try #require(store.firingAlerts.first { $0.id == LiveOpsFixtureIDs.alertA })
    #expect(await store.alertActions.resolve(alertA) == .succeeded)
    #expect(store.firingAlerts.map(\.id) == [LiveOpsFixtureIDs.anthropicFiringEventID])
    #expect(store.alertCounts?.firing == 1 && receipts.current?.text == "已手动解决")
    await store.refreshFiringAlerts(maxAge: 0)
    #expect(store.firingAlerts.map(\.id) == [LiveOpsFixtureIDs.anthropicFiringEventID])
    #expect(store.firingAlerts.first?.silence?.id == LiveOpsFixtureIDs.anthropicSilence)
    await store.refreshHome(noCache: false)
    #expect(store.home.alerts.value?.firingCount == 1 && store.home.alerts.value?.top.map(\.id) == [LiveOpsFixtureIDs.anthropicFiringEventID])
    let resolved = try await source.alertEvent(id: LiveOpsFixtureIDs.alertA)
    #expect(resolved.status == AlertEvent.manualResolved && resolved.resolvedByUserName == "admin")
}

@MainActor @Test func fixtureSilenceShowsOnEveryCopyAndUndoEndsIt() async throws {
    let (store, source, receipts) = await fixtureStore()
    let alertA = try #require(store.firingAlerts.first { $0.id == LiveOpsFixtureIDs.alertA })
    #expect(store.alertActions.availableActions(for: alertA) == [.resolve, .silence])
    #expect(await store.alertActions.silence(alertA, for: .hour) == .succeeded)
    let silence = try #require(store.firingAlerts.first { $0.id == LiveOpsFixtureIDs.alertA }?.silence)
    #expect(silence.until == now.addingTimeInterval(3_600) && store.home.alerts.value?.top.first { $0.id == LiveOpsFixtureIDs.alertA }?.silence == silence)
    #expect(try await source.alertEvent(id: LiveOpsFixtureIDs.alertA).silence == silence)
    #expect(receipts.current?.text == "已静默 1 小时")
    receipts.performAction(id: try #require(receipts.current?.id))
    await waitUntil { store.firingAlerts.first { $0.id == LiveOpsFixtureIDs.alertA }?.silence == nil && !store.alertActions.isRunning(LiveOpsFixtureIDs.alertA) }
    #expect(try await source.alertEvent(id: LiveOpsFixtureIDs.alertA).silence == nil)
    #expect(store.firingAlerts.first { $0.id == LiveOpsFixtureIDs.anthropicFiringEventID }?.silence?.id == LiveOpsFixtureIDs.anthropicSilence)
}

@MainActor @Test func fixtureWriteFailsArgumentShowsSiteUnavailable() async throws {
    let (store, _, receipts) = await fixtureStore(["-ui-alert-write-fails"])
    let before = store.firingAlerts
    let alertA = try #require(before.first { $0.id == LiveOpsFixtureIDs.alertA })
    #expect(await store.alertActions.resolve(alertA) == .failed)
    #expect(receipts.current?.text == "站点暂时不可用" && store.firingAlerts == before)
    #expect(await store.alertActions.silence(alertA, for: .hour) == .failed)
    #expect(store.firingAlerts == before)
}

@MainActor @Test func fixtureLegacyArgumentDropsSilenceKey() async throws {
    let (store, source, _) = await fixtureStore(["-ui-alert-legacy-silence"])
    #expect(store.firingAlerts.count == 2 && store.firingAlerts.allSatisfy { !$0.silenceSupported && $0.silence == nil })
    #expect(store.firingAlerts.allSatisfy { store.alertActions.availableActions(for: $0) == [.resolve] })
    #expect(store.home.alerts.value?.top.allSatisfy { !$0.silenceSupported } == true)
    #expect(try await source.alertEvent(id: LiveOpsFixtureIDs.anthropicFiringEventID).silenceSupported == false)
    let alertA = try #require(store.firingAlerts.first { $0.id == LiveOpsFixtureIDs.alertA })
    #expect(await store.alertActions.resolve(alertA) == .succeeded)
}

@Test func fixtureAlertWritesFollowServerRules() async throws {
    let source = FixtureLiveOpsSource(options: .init(), base: now)
    try await source.setAlertEventStatus(id: 999, status: AlertEvent.manualResolved)
    var missing: APIError?
    do { _ = try await source.updateAlertSilence(id: 999, until: now) } catch { missing = error as? APIError }
    #expect(missing?.statusCode == 404 && missing?.reason == "OPS_ALERT_SILENCE_NOT_FOUND")
    let created = try await source.createAlertSilence(ruleID: 11, platform: nil, groupID: 2, until: now.addingTimeInterval(600))
    let changed = try await source.updateAlertSilence(id: created.id, until: now.addingTimeInterval(1_200))
    #expect(changed.id == created.id && changed.until == now.addingTimeInterval(1_200))
    #expect(try await source.alertEvent(id: LiveOpsFixtureIDs.alertA).silence == AlertSilenceRef(id: created.id, until: now.addingTimeInterval(1_200)))
    try await source.deleteAlertSilence(id: created.id)
    try await source.deleteAlertSilence(id: created.id)
    #expect(try await source.alertEvent(id: LiveOpsFixtureIDs.alertA).silence == nil)
    let closed = FixtureLiveOpsSource(options: .init(opsDisabled: true), base: now)
    var refused: APIError?
    do { try await closed.setAlertEventStatus(id: LiveOpsFixtureIDs.alertA, status: AlertEvent.manualResolved) } catch { refused = error as? APIError }
    #expect(refused?.statusCode == 404 && refused?.reason == "OPS_DISABLED")
}

@Test func fixtureAlertListAppliesTimeRangeFromSessionStart() async throws {
    let source = FixtureLiveOpsSource(options: .init(), base: now)
    func ids(_ range: String?, status: String? = nil, limit: Int = 50) async throws -> [Int] {
        try await source.alertEvents(status: status, timeRange: range, limit: limit, before: nil, groupID: nil, platform: nil).map(\.id)
    }
    // #41 now − 12m, #40 now − 26m, #37 now − 82m, #35 yesterday 21:52 (11h49m before 09:41).
    let everything = [41, 40, 37, 35]
    #expect(try await ids(nil) == everything)
    #expect(try await ids("24h") == everything)
    #expect(try await ids("unknown") == everything)
    #expect(try await ids("6h") == [41, 40, 37])
    #expect(try await ids("1h") == [41, 40])
    #expect(try await ids("5m").isEmpty)
    #expect(try await ids("1h", status: "firing") == [41, 40])
    #expect(try await ids("6h", status: "resolved") == [37])
    #expect(try await ids(nil, limit: 0) == [41])
    #expect(try await ids(nil, limit: 900) == everything)
}

@Test func alertFixtureArgumentsParse() {
    typealias Options = LiveOpsFixtures.Options
    #expect(Options(arguments: []).alertWritesFail == false && Options(arguments: []).alertsWithoutSilenceKey == false)
    #expect(Options(arguments: ["-ui-alert-write-fails"]) == Options(alertWritesFail: true))
    #expect(Options(arguments: ["-ui-alert-legacy-silence", "-ui-home-calm"]) == Options(variant: .calm, alertsWithoutSilenceKey: true))
}
