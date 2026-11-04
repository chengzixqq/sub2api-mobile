import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-08: turning ops monitoring on and off from the App (10 §7.2, U10; 00 §2.4; S1D1-02, S1D1-07) and its UI fixtures.

private let onStatus = OpsMonitoringStatus(configEnabled: true, monitoringEnabled: true, realtimeMonitoringEnabled: true, effective: true)
private let settingOffStatus = OpsMonitoringStatus(configEnabled: true, monitoringEnabled: false, effective: false, disabledReason: "setting_off")
private let configOffStatus = OpsMonitoringStatus(configEnabled: false, monitoringEnabled: true, effective: false, disabledReason: "config_off")
private let closedHome = homeReply(ops: HomeSection(status: .disabled, reason: "OPS_DISABLED"), alerts: HomeSection(status: .disabled, reason: "OPS_DISABLED"))
private let transportFailure = APIError(kind: .transport, message: "无法连接站点")

private func isWrite(_ call: StubLiveOpsSource.Call) -> Bool {
    switch call {
    case .setOpsMonitoring, .enableOpsLegacy: true
    default: false
    }
}
private func isAlertList(_ call: StubLiveOpsSource.Call) -> Bool { if case .alertEvents = call { true } else { false } }

/// A site whose `/admin/me` says monitoring is off (setting_off) unless told otherwise; `legacy` is one without `/admin/me`.
private func switchSite(withStatus: Bool = true, legacy: Bool = false, opsEnabled: Bool? = false, reason: String? = "setting_off") -> SiteSession {
    let capabilities = legacy ? [] : liveOpsCapabilities + (withStatus ? [.opsMonitoringStatus] : [])
    let me = AdminMe(user: .init(id: 1, role: "admin"), features: .init(opsMonitoringEnabled: opsEnabled, opsMonitoringDisabledReason: reason),
                     server: .init(serverTimezone: liveOpsZone.identifier, serverUTCOffset: liveOpsZone.rawUTCOffset,
                                   capabilities: Set(capabilities.map(\.rawValue))),
                     isLegacyServer: legacy)
    return SiteSession(me: me, credential: sessionTokens(), accessTokenScope: nil, serverTimeZone: liveOpsZone, clockOffset: 0, probedAt: Date())
}
/// Home answers `reply`, the alert reads answer empty; the switch handlers are the test's.
private func switchHandlers(home reply: @escaping @Sendable (Int) -> DashboardHome = { _ in homeReply() }) -> StubLiveOpsSource.Handlers {
    let tally = Tally()
    return .init(home: { _ in reply(tally.next()) }, alertEvents: { _, _ in [] }, alertCounts: { AlertCounts(firing: 0) })
}

// MARK: 开启

@MainActor @Test func enableWithStatusCapabilitySendsOnePutAndRefreshesEverything() async {
    var handlers = switchHandlers()
    handlers.setOpsMonitoring = { _ in onStatus }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite())
    #expect(h.store.opsDisabled && h.store.opsDisabledReason == .settingOff && h.store.canEnableOpsInApp)
    #expect(await h.store.enableOpsMonitoring() == .enabled)
    #expect(await source.calls.filter(isWrite) == [.setOpsMonitoring(true)])
    #expect(h.receipts.current?.text == "已开启运维监控" && h.receipts.current?.tone == .ok)
    #expect(await source.homeCalls == [true])
    #expect(await source.count(isAlertList) == 1)
    #expect(h.store.opsRevision == 1 && !h.store.opsDisabled && !h.store.isTogglingOps)
    #expect(await h.sleeper.seconds.isEmpty)
}

@MainActor @Test func enableEffectiveFalseConfigOffSwitchesNoticeToConfigOff() async {
    var handlers = switchHandlers()
    handlers.setOpsMonitoring = { _ in configOffStatus }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite())
    #expect(await h.store.enableOpsMonitoring() == .configOff)
    #expect(h.store.opsDisabled && h.store.opsDisabledReason == .configOff)
    #expect(h.receipts.current?.text == "运维监控已在服务器配置中关闭" && h.receipts.current?.tone == .neutral)
    #expect(await source.homeCalls.isEmpty)
    #expect(await h.sleeper.seconds.isEmpty)
    #expect(h.store.opsRevision == 0)
}

@MainActor @Test func enable409ConfigDisabledIsConfigOffWithoutRetry() async {
    var handlers = switchHandlers()
    handlers.setOpsMonitoring = { _ in throw APIError.server(status: 409, reason: "OPS_CONFIG_DISABLED") }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite())
    #expect(await h.store.enableOpsMonitoring() == .configOff)
    #expect(await source.calls == [.setOpsMonitoring(true)])
    #expect(h.store.opsDisabled && h.store.opsDisabledReason == .configOff)
}

@MainActor @Test func enableReadOnlyTokenRefusalKeepsStateAndSaysReadOnly() async {
    var handlers = switchHandlers()
    handlers.setOpsMonitoring = { _ in throw APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY") }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite())
    #expect(await h.store.enableOpsMonitoring() == .failed("只读访问令牌不能修改设置"))
    #expect(h.receipts.current?.text == "只读访问令牌不能修改设置" && h.receipts.current?.tone == .critical)
    #expect(h.store.opsDisabled && h.store.opsDisabledReason == .settingOff && !h.store.isTogglingOps)
    #expect(await source.calls == [.setOpsMonitoring(true)])
    #expect(await h.sleeper.seconds.isEmpty)
}

@MainActor @Test func enableForbiddenSaysPermission() async {
    var handlers = switchHandlers()
    handlers.setOpsMonitoring = { _ in throw APIError.server(status: 403, reason: "FORBIDDEN") }
    let h = LiveOpsHarness(StubLiveOpsSource(handlers), site: switchSite())
    #expect(await h.store.enableOpsMonitoring() == .failed("当前身份没有修改运维设置的权限"))
    #expect(h.store.opsDisabled && h.store.opsDisabledReason == .settingOff)
}

@MainActor @Test func enableLegacyWithoutCapabilityUsesSettingsPut() async {
    var handlers = switchHandlers()
    handlers.enableOpsLegacy = {}
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite(withStatus: false))
    #expect(h.store.opsWriteRoute == .legacySettings && h.store.canEnableOpsInApp && !h.store.canDisableOpsMonitoring)
    #expect(await h.store.enableOpsMonitoring() == .enabled)
    #expect(await source.calls.filter(isWrite) == [.enableOpsLegacy])
    #expect(await source.count { $0 == .monitoringStatus } == 0)
    #expect(h.receipts.current?.text == "已开启运维监控" && !h.store.opsDisabled)
}

@MainActor @Test func legacyServerWithoutAdminMeNeverSendsSettingsPut() async {
    var handlers = switchHandlers()
    handlers.enableOpsLegacy = {}
    handlers.setOpsMonitoring = { _ in onStatus }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite(legacy: true))
    #expect(h.store.opsWriteRoute == .unavailable && !h.store.canEnableOpsInApp && !h.store.canDisableOpsMonitoring)
    #expect(await h.store.enableOpsMonitoring() == .failed("站点版本较旧，暂不支持此功能"))
    #expect(await h.store.disableOpsMonitoring() == .failed("站点版本较旧，暂不支持此功能"))
    #expect(await source.calls.isEmpty)
}

// MARK: 开启后的复查（30 秒内再自动重试一次，D09）

@MainActor @Test func legacyStillDisabledAfterRecheckIsConfigOff() async {
    var handlers = switchHandlers(home: { _ in closedHome })
    handlers.enableOpsLegacy = {}
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite(withStatus: false), sleeper: PollSleeper(parks: true))
    let store = h.store
    let enabling = Task { await store.enableOpsMonitoring() }
    await waitUntil { await h.sleeper.parkedCount == 1 }
    #expect(store.isTogglingOps && h.receipts.current == nil)
    #expect(await h.sleeper.seconds == [30])
    #expect(await source.homeCalls == [true])
    await h.sleeper.releaseAll()
    #expect(await enabling.value == .configOff)
    #expect(await source.homeCalls == [true, true])
    #expect(store.opsDisabled && store.opsDisabledReason == .configOff && !store.isTogglingOps)
    #expect(!OpsDisabledPresentation.offersEnable(reason: store.opsDisabledReason, isAdministrator: true, route: store.opsWriteRoute))
    #expect(h.receipts.current?.text == "运维监控已在服务器配置中关闭" && h.receipts.current?.tone == .neutral)
    await store.refreshHome(noCache: false)
    #expect(await h.sleeper.seconds == [30])
}

@MainActor @Test func firstRefreshStillDisabledRechecksOnceAfter30Seconds() async {
    var handlers = switchHandlers(home: { _ in closedHome })
    handlers.setOpsMonitoring = { _ in onStatus }
    handlers.monitoringStatus = { settingOffStatus }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite(), sleeper: PollSleeper(parks: true))
    let store = h.store
    let enabling = Task { await store.enableOpsMonitoring() }
    await waitUntil { await h.sleeper.parkedCount == 1 }
    #expect(h.receipts.current?.text == "已开启运维监控" && store.isTogglingOps && store.opsDisabled)
    #expect(await source.count { $0 == .monitoringStatus } == 0)
    await h.sleeper.releaseAll()
    #expect(await enabling.value == .enabled)
    #expect(await source.homeCalls == [true, true])
    #expect(await source.count { $0 == .monitoringStatus } == 1)
    #expect(store.opsDisabled && store.opsDisabledReason == .settingOff && !store.isTogglingOps && store.opsRevision == 2)
    await store.refreshHome(noCache: false)
    #expect(await h.sleeper.seconds == [30])
    #expect(await source.count { $0 == .monitoringStatus } == 1)
}

@MainActor @Test func recheckThatSucceedsHidesNotice() async {
    var handlers = switchHandlers(home: { call in call == 1 ? closedHome : homeReply() })
    handlers.setOpsMonitoring = { _ in onStatus }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite())
    #expect(await h.store.enableOpsMonitoring() == .enabled)
    #expect(await h.sleeper.seconds == [30])
    #expect(!h.store.opsDisabled && h.store.opsRevision == 2 && h.receipts.current?.text == "已开启运维监控")
    #expect(await source.count { $0 == .monitoringStatus } == 0)
}

@MainActor @Test func enableIgnoresDisabledSignalsDuringRecheckDelay() async {
    var handlers = switchHandlers(home: { call in call == 1 ? homeReply() : closedHome })
    handlers.setOpsMonitoring = { _ in onStatus }
    handlers.monitoringStatus = { onStatus }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite())
    #expect(await h.store.enableOpsMonitoring() == .enabled)
    #expect(!h.store.opsDisabled && !h.store.isTogglingOps)
    #expect(await h.sleeper.seconds.isEmpty)
    // Another instance that has not read the switch yet.
    h.advance(by: 29)
    await h.store.refreshHome(noCache: false)
    await h.store.recordOpsResponse(APIError.server(status: 404, reason: "OPS_DISABLED"))
    #expect(!h.store.opsDisabled)
    #expect(await source.count { $0 == .monitoringStatus } == 0)
    h.advance(by: 2)
    await h.store.recordOpsResponse(APIError.server(status: 404, reason: "OPS_DISABLED"))
    #expect(h.store.opsDisabled)
}

// MARK: 结果未知时读回（00 §2.4：不带 key 的写不自动重发）

@MainActor @Test func timeoutReadsBackStatusAndNeverResends() async {
    var handlers = switchHandlers()
    handlers.setOpsMonitoring = { _ in throw transportFailure }
    handlers.monitoringStatus = { onStatus }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite())
    #expect(await h.store.enableOpsMonitoring() == .enabled)
    #expect(await source.calls.filter(isWrite) == [.setOpsMonitoring(true)])
    #expect(await source.count { $0 == .monitoringStatus } == 1)
    #expect(!h.store.opsDisabled && h.receipts.current?.text == "已开启运维监控")
}

@MainActor @Test func unreadableReadBackIsUnconfirmed() async {
    var handlers = switchHandlers(home: { _ in closedHome })
    handlers.setOpsMonitoring = { _ in throw APIError.server(status: 504, reason: nil) }
    handlers.monitoringStatus = { throw APIError.server(status: 500, reason: nil) }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite())
    #expect(await h.store.enableOpsMonitoring() == .unconfirmed)
    #expect(h.receipts.current?.text == "结果未确认，请刷新核对后再操作" && h.receipts.current?.tone == .caution)
    #expect(await source.homeCalls == [true])
    #expect(await source.calls.filter(isWrite).count == 1)
    #expect(h.store.opsDisabled && h.store.opsDisabledReason == .settingOff && !h.store.isTogglingOps)

    var legacyHandlers = switchHandlers(home: { _ in closedHome })
    legacyHandlers.enableOpsLegacy = { throw transportFailure }
    let legacySource = StubLiveOpsSource(legacyHandlers)
    let legacy = LiveOpsHarness(legacySource, site: switchSite(withStatus: false))
    #expect(await legacy.store.enableOpsMonitoring() == .unconfirmed)
    #expect(await legacySource.count { $0 == .monitoringStatus } == 0)
    #expect(await legacySource.homeCalls == [true])
    #expect(await legacy.sleeper.seconds.isEmpty)
}

// MARK: 关闭（U10：只走 monitoring-status）

@MainActor @Test func disableSendsPutFalseShowsReceiptAndNotice() async {
    var handlers = switchHandlers(home: { _ in closedHome })
    handlers.setOpsMonitoring = { _ in settingOffStatus }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite(opsEnabled: true, reason: nil))
    #expect(!h.store.opsDisabled && h.store.canDisableOpsMonitoring)
    #expect(await h.store.disableOpsMonitoring() == .disabled)
    #expect(await source.calls.filter(isWrite) == [.setOpsMonitoring(false)])
    #expect(h.receipts.current?.text == "已关闭运维监控")
    #expect(h.store.opsDisabled && h.store.opsDisabledReason == .settingOff && h.store.opsRevision == 1 && !h.store.canDisableOpsMonitoring)
    #expect(await source.homeCalls == [true])
    #expect(await source.count { $0 == .monitoringStatus } == 0)
    #expect(h.store.firingAlerts.isEmpty)
}

@MainActor @Test func disableIgnoresAvailableSignalsDuringRecheckDelay() async {
    var handlers = switchHandlers()
    handlers.setOpsMonitoring = { _ in settingOffStatus }
    let h = LiveOpsHarness(StubLiveOpsSource(handlers), site: switchSite(opsEnabled: true, reason: nil))
    #expect(await h.store.disableOpsMonitoring() == .disabled)
    #expect(h.store.opsDisabled)
    h.advance(by: 29)
    await h.store.recordOpsResponse(nil)
    #expect(h.store.opsDisabled)
    h.advance(by: 2)
    await h.store.recordOpsResponse(nil)
    #expect(!h.store.opsDisabled)
}

@MainActor @Test func disableWithoutStatusCapabilityDoesNothing() async {
    var handlers = switchHandlers()
    handlers.enableOpsLegacy = {}
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite(withStatus: false, opsEnabled: true, reason: nil))
    #expect(!h.store.canDisableOpsMonitoring)
    #expect(await h.store.disableOpsMonitoring() == .failed("站点版本较旧，暂不支持此功能"))
    #expect(await source.calls.isEmpty)
}

// MARK: 并发与会话

@MainActor @Test func secondToggleWhileBusyIsIgnored() async {
    let gate = SessionGate()
    var handlers = switchHandlers()
    handlers.setOpsMonitoring = { _ in await gate.wait(); return onStatus }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite())
    let store = h.store
    let first = Task { await store.enableOpsMonitoring() }
    await waitUntil { await gate.arrived }
    #expect(store.isTogglingOps)
    #expect(await store.enableOpsMonitoring() == nil)
    #expect(await store.disableOpsMonitoring() == nil)
    await gate.open()
    #expect(await first.value == .enabled)
    #expect(await source.calls.filter(isWrite) == [.setOpsMonitoring(true)])
}

@MainActor @Test func lateResultAfterSessionEndIsDropped() async {
    let gate = SessionGate()
    var handlers = switchHandlers()
    handlers.setOpsMonitoring = { _ in await gate.wait(); return onStatus }
    let source = StubLiveOpsSource(handlers)
    let h = LiveOpsHarness(source, site: switchSite())
    let store = h.store, before = h.store.opsSwitch
    let enabling = Task { await store.enableOpsMonitoring() }
    await waitUntil { await gate.arrived }
    h.isCurrent = false
    await gate.open()
    #expect(await enabling.value == nil)
    #expect(h.receipts.current == nil && store.opsSwitch == before)
    #expect(await source.homeCalls.isEmpty)
    #expect(await h.sleeper.seconds.isEmpty)
}

// MARK: 判定关闭后读取原因（10 §7.2 判定）

@MainActor @Test func disabledDetectionReadsReasonOncePerTransition() async {
    var handlers = switchHandlers(home: { call in call == 3 ? homeReply() : closedHome })
    handlers.monitoringStatus = { settingOffStatus }
    let source = StubLiveOpsSource(handlers)
    let store = LiveOpsHarness(source, site: switchSite(opsEnabled: true, reason: nil)).store
    await store.refreshHome(noCache: false)
    #expect(await source.count { $0 == .monitoringStatus } == 1)
    #expect(store.opsDisabledReason == .settingOff)
    await store.refreshHome(noCache: false)
    #expect(await source.count { $0 == .monitoringStatus } == 1)
    await store.refreshHome(noCache: false)
    #expect(!store.opsDisabled)
    await store.refreshHome(noCache: false)
    #expect(await source.count { $0 == .monitoringStatus } == 2)

    let withoutStatus = StubLiveOpsSource(switchHandlers(home: { _ in closedHome }))
    let legacy = LiveOpsHarness(withoutStatus, site: switchSite(withStatus: false, opsEnabled: true, reason: nil)).store
    await legacy.refreshHome(noCache: false)
    #expect(legacy.opsDisabled && legacy.opsDisabledReason == .unknown)
    #expect(await withoutStatus.count { $0 == .monitoringStatus } == 0)

    let tally = Tally()
    var flaky = switchHandlers(home: { _ in closedHome })
    flaky.monitoringStatus = {
        guard tally.next() > 1 else { throw APIError.server(status: 500, reason: nil) }
        return configOffStatus
    }
    let retried = StubLiveOpsSource(flaky)
    let again = LiveOpsHarness(retried, site: switchSite(opsEnabled: true, reason: nil)).store
    await again.refreshHome(noCache: false)
    await again.refreshHome(noCache: false)
    #expect(await retried.count { $0 == .monitoringStatus } == 2)
    #expect(again.opsDisabledReason == .configOff)
}

@MainActor @Test func newestSignalOutranksAdminMeSnapshot() async {
    var handlers = switchHandlers()
    handlers.monitoringStatus = { onStatus }
    let source = StubLiveOpsSource(handlers)
    let store = LiveOpsHarness(source, site: switchSite()).store
    #expect(store.opsDisabled && store.opsDisabledReason == .settingOff)
    await store.refreshHome(noCache: false)
    #expect(!store.opsDisabled)
    await store.noteOpsDisabled()
    // A reason read that disagrees (another instance) does not reopen it; the next signal decides.
    #expect(store.opsDisabled)
    #expect(await source.count { $0 == .monitoringStatus } == 1)
    store.noteOpsAvailable()
    #expect(!store.opsDisabled)
}

@MainActor @Test func homeLastErrorFollowsMainPathOrFallbackBlock() async {
    let main = StubLiveOpsSource(.init(home: { _ in throw APIError.server(status: 500, reason: "INTERNAL_ERROR") }))
    let store = LiveOpsHarness(main).store
    await store.refreshHome(noCache: false)
    #expect(store.homeLastError(for: .stats)?.statusCode == 500 && store.homeLastError(for: .ops)?.statusCode == 500)

    let fallback = StubLiveOpsSource(.init(stats: { throw APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE") }))
    let legacy = LiveOpsHarness(fallback, site: liveOpsSite([])).store
    await legacy.refreshHome(noCache: false)
    #expect(legacy.isOnFallback && legacy.homeLastError(for: .stats)?.statusCode == 503 && legacy.homeLastError(for: .ops) == nil)
}

// MARK: 夹具（-ui-ops-disabled / -ui-ops-config-off）

@Test func fixtureSwitchParsesLaunchArguments() {
    #expect(OpsFixtureSwitch.from(arguments: []) == .on)
    #expect(OpsFixtureSwitch.from(arguments: ["-ui-ops-disabled"]) == .settingOff)
    #expect(OpsFixtureSwitch.from(arguments: ["-ui-ops-config-off"]) == .configOff)
    #expect(OpsFixtureSwitch.from(arguments: ["-ui-ops-disabled", "-ui-ops-config-off"]) == .configOff)
    #expect([OpsFixtureSwitch.on, .settingOff, .configOff].map(\.disabledReason) == [nil, "setting_off", "config_off"])
    #expect(LiveOpsFixtures.Options(arguments: ["-ui-ops-config-off"]).ops == .configOff)
}

@Test func fixtureSourceTogglesInMemory() async throws {
    let base = Date()
    let off = FixtureLiveOpsSource(options: .init(ops: .settingOff), base: base)
    #expect(try await off.dashboardHome(timezone: liveOpsZone, include: nil, noCache: false).ops.status == .disabled)
    #expect(await off.opsMonitoringStatus().reason == .settingOff)
    #expect(try await off.setOpsMonitoring(enabled: true).effective == true)
    #expect(try await off.dashboardHome(timezone: liveOpsZone, include: nil, noCache: false).ops.status == .ok)
    #expect(await off.opsMonitoringStatus().effective == true)
    _ = try await off.opsOverview(timeRange: "5m")
    #expect(try await off.setOpsMonitoring(enabled: false).reason == .settingOff)
    await #expect(throws: APIError.self) { try await off.opsOverview(timeRange: "5m") }

    let config = FixtureLiveOpsSource(options: .init(ops: .configOff), base: base)
    #expect(await config.opsMonitoringStatus().reason == .configOff)
    await #expect(throws: APIError.server(status: 409, reason: "OPS_CONFIG_DISABLED")) { try await config.setOpsMonitoring(enabled: true) }
    await config.enableOpsMonitoringLegacy()
    #expect(try await config.dashboardHome(timezone: liveOpsZone, include: nil, noCache: false).ops.status == .disabled)
}

@MainActor @Test func fixtureStoreEnablesSettingOffSite() async {
    let base = Date()
    let source = FixtureLiveOpsSource(options: .init(ops: .settingOff), base: base)
    let site = liveOpsSite(Capability.allCases, opsEnabled: false)
    let receipts = ReceiptCenter(sleep: { _ in throw CancellationError() })
    let store = LiveOpsStore(generation: UUID(), source: source, site: { site }, isCurrent: { true }, serverNow: { base }, receipts: receipts)
    await store.refreshHome(noCache: false)
    #expect(store.opsDisabled && store.opsDisabledReason == .settingOff)
    #expect(await store.enableOpsMonitoring() == .enabled)
    #expect(!store.opsDisabled && store.home.ops.value != nil && receipts.current?.text == "已开启运维监控")
}
