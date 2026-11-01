import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 60 §7.4–§7.6 (S6-24): the push page's reads, optimistic subscription saves, tests and deletes of other targets.

/// Records every call; each kind answers through its closure with its call number (from 1).
private actor StubPushSource: PushSettingsSource {
    typealias DevicesHandler = @Sendable (_ call: Int) async throws -> [PushDevice]
    typealias ConfigHandler = @Sendable (_ call: Int) async throws -> PushAPNsConfig
    typealias UpdateHandler = @Sendable (_ call: Int, _ id: Int, _ subscription: PushSubscription) async throws -> PushDevice
    typealias TestHandler = @Sendable (_ call: Int) async throws -> PushTestResult
    typealias DeleteHandler = @Sendable (_ call: Int) async throws -> Void
    private let onDevices: DevicesHandler
    private let onConfig: ConfigHandler
    private let onUpdate: UpdateHandler
    private let onTest: TestHandler
    private let onDelete: DeleteHandler
    private(set) var deviceReads = 0
    private(set) var configReads = 0
    private(set) var updates: [PushSubscription] = []
    private(set) var tests = 0
    private(set) var deletes = 0

    init(devices: @escaping DevicesHandler = { _ in sampleDevices }, config: @escaping ConfigHandler = { _ in readyConfig },
         update: @escaping UpdateHandler = { _, id, subscription in device(id, subscription: subscription.normalized) },
         test: @escaping TestHandler = { _ in PushTestResult(delivered: true, providerStatus: 200) },
         delete: @escaping DeleteHandler = { _ in }) {
        onDevices = devices; onConfig = config; onUpdate = update; onTest = test; onDelete = delete
    }
    func pushDevices() async throws -> [PushDevice] { deviceReads += 1; return try await onDevices(deviceReads) }
    func pushConfig() async throws -> PushAPNsConfig { configReads += 1; return try await onConfig(configReads) }
    func updatePushSubscription(id: Int, _ subscription: PushSubscription) async throws -> PushDevice {
        updates.append(subscription)
        return try await onUpdate(updates.count, id, subscription)
    }
    func testPushDevice(id: Int) async throws -> PushTestResult { tests += 1; return try await onTest(tests) }
    func deletePushDevice(id: Int) async throws { deletes += 1; try await onDelete(deletes) }
    func registerPushDevice(_ registration: PushDeviceRegistration) async throws -> (device: PushDevice, created: Bool) {
        throw CancellationError()
    }
}

@MainActor private final class TestFlag { var value = true }

private func device(_ id: Int, platform: PushPlatform = .ios, enabled: Bool = true, subscription: PushSubscription? = .default) -> PushDevice {
    PushDevice(id: id, platform: platform, deviceName: id == 12 ? "我的 Bark" : nil, enabled: enabled, subscription: subscription)
}
private let sampleDevices = [device(13, platform: .webhook), device(11), device(12, platform: .bark)]
private let readyConfig = PushAPNsConfig(enabled: true, teamID: "ABCDE12345", keyID: "KEY1234567", privateKeyConfigured: true, ready: true)
private let notReadyConfig = PushAPNsConfig(enabled: false, ready: false)
private let notFound = APIError.server(status: 404, reason: "PUSH_DEVICE_NOT_FOUND")
private let serverError = APIError.server(status: 500, reason: nil)
private let unavailable = APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
private let lost = APIError(kind: .transport, message: "网络连接已断开")
private let resolved = PushSubscriptionEdit.setting(.opsAlertResolved, on: true, in: .default)

/// A receipt center whose receipts never time out during a test.
@MainActor private func stillReceipts() -> ReceiptCenter { ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }) }

@MainActor private struct Bench {
    let model: PushSettingsModel
    let receipts: ReceiptCenter
    let current: TestFlag
}
@MainActor private func makeBench(_ source: any PushSettingsSource) -> Bench {
    let receipts = stillReceipts(), current = TestFlag()
    return Bench(model: PushSettingsModel(source: source, receipts: receipts, isCurrent: { current.value }), receipts: receipts, current: current)
}

/// Up to five seconds: under `swift test --parallel` a child task can take a while to be scheduled.
private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

// MARK: - 读取（7.5、7.6）

@MainActor @Test func loadReadsDevicesAndConfigConcurrently() async {
    let gate = SessionGate()
    let source = StubPushSource(devices: { _ in await gate.wait(); return sampleDevices }, config: { _ in notReadyConfig })
    let bench = makeBench(source), model = bench.model
    let loading = Task { await model.load() }
    #expect(await eventually { await gate.arrived })
    #expect(await eventually { await source.configReads == 1 })
    #expect(await eventually { @MainActor in model.shownConfig != nil })
    #expect(model.deviceList == nil)
    await gate.open()
    await loading.value
    #expect(bench.model.deviceList?.map(\.id) == [11, 12, 13])
    #expect(bench.model.showsNotReadyBanner)
    #expect(!bench.model.listFailed && !bench.model.refreshFailed)
}

@MainActor @Test func configFailureHidesTheAPNsPartsButKeepsTheSwitchUsable() async {
    let gate = SessionGate()
    let source = StubPushSource(config: { call in
        if call == 1 { await gate.wait() }
        throw APIError.server(status: 403, reason: "FORBIDDEN")
    })
    let bench = makeBench(source)
    let loading = Task { await bench.model.load() }
    #expect(await eventually { await gate.arrived })
    #expect(bench.model.isConfigPending)
    await gate.open()
    await loading.value
    #expect(bench.model.shownConfig == nil)
    #expect(!bench.model.showsNotReadyBanner && !bench.model.isConfigPending)
    #expect(bench.model.deviceList?.count == 3)
}

@MainActor @Test func listFailureWithoutAListIsListFailedAndARefreshFailureKeepsTheList() async {
    let source = StubPushSource(devices: { call in
        if call == 2 { return sampleDevices }
        throw unavailable
    })
    let bench = makeBench(source)
    await bench.model.load()
    #expect(bench.model.listFailed && !bench.model.refreshFailed)
    await bench.model.reloadDevices()
    #expect(!bench.model.listFailed && !bench.model.refreshFailed)
    await bench.model.reloadDevices()
    #expect(!bench.model.listFailed && bench.model.refreshFailed)
    #expect(bench.model.deviceList?.map(\.id) == [11, 12, 13])
}

@MainActor @Test func repliesOfAnOlderLoadOrSessionAreDropped() async {
    let gate = SessionGate()
    let source = StubPushSource(devices: { call in
        if call == 1 { await gate.wait(); return [device(12, platform: .bark)] }
        return sampleDevices
    }, test: { _ in throw serverError })
    let bench = makeBench(source)
    let older = Task { await bench.model.reloadDevices() }
    #expect(await eventually { await gate.arrived })
    await bench.model.reloadDevices()
    await gate.open()
    await older.value
    #expect(bench.model.deviceList?.map(\.id) == [11, 12, 13])

    bench.current.value = false
    #expect(await bench.model.test(id: 12) == .cancelled)
    #expect(bench.receipts.current == nil)
    await bench.model.reloadDevices()
    #expect(bench.model.deviceList?.count == 3)
}

// MARK: - 改订阅（7.4）

@MainActor @Test func subscriptionChangeShowsAtOnceAndTheEchoReplacesIt() async throws {
    let gate = SessionGate()
    let listed = #"{"items":[{"id":11,"platform":"ios","subscription":{"events":["ops_alert.fired","account.error"],"min_severity":"P1","group_ids":[],"platforms":[],"quiet_hours":null}}]}"#
    let echo = #"{"id":11,"platform":"ios","subscription":{"events":["ops_alert.fired","ops_alert.resolved","account.error"],"min_severity":"P1","group_ids":[],"platforms":[],"quiet_hours":null}}"#
    let transport = SessionTransport { request in
        guard request.httpMethod == "PUT" else { return sessionOK(listed) }
        await gate.wait()
        return sessionOK(echo)
    }
    let bench = makeBench(sessionClient(transport))
    await bench.model.reloadDevices()
    let saving = Task { await bench.model.updateSubscription(id: 11, to: resolved) }
    #expect(await eventually { await gate.arrived })
    #expect(bench.model.subscription(for: 11) == resolved)
    #expect(bench.model.isSavingSubscription(id: 11))
    await gate.open()
    await saving.value
    #expect(bench.model.device(id: 11)?.subscription == resolved)
    #expect(bench.model.pendingSubscriptions.isEmpty && !bench.model.isSavingSubscription(id: 11))
    let requests = await transport.requests
    let put = try #require(requests.last { $0.httpMethod == "PUT" })
    #expect(put.url?.path.hasSuffix("admin/push/devices/11/subscription") == true)
    let data = try #require(put.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(body.keys) == ["events", "min_severity", "group_ids", "platforms", "quiet_hours"])
    #expect(body["events"] as? [String] == ["ops_alert.fired", "ops_alert.resolved", "account.error"])
}

@MainActor @Test func editsWhileSavingAreCoalescedIntoOneMorePut() async {
    let gate = SessionGate()
    let source = StubPushSource(update: { call, id, subscription in
        if call == 1 { await gate.wait() }
        return device(id, subscription: subscription.normalized)
    })
    let bench = makeBench(source)
    await bench.model.reloadDevices()
    let first = Task { await bench.model.updateSubscription(id: 11, to: resolved) }
    #expect(await eventually { await gate.arrived })
    let severe = PushSubscriptionEdit.setting(minSeverity: .p0, in: resolved)
    let last = PushSubscriptionEdit.setting(quietHours: true, in: severe)
    for next in [severe, PushSubscriptionEdit.setting(minSeverity: .p2, in: resolved), last] {
        await bench.model.updateSubscription(id: 11, to: next)
        #expect(bench.model.subscription(for: 11) == next)
    }
    await gate.open()
    await first.value
    #expect(await source.updates == [resolved, last])
    #expect(bench.model.pendingSubscriptions.isEmpty)
    #expect(bench.model.subscription(for: 11) == last.normalized)
    await bench.model.updateSubscription(id: 11, to: last)
    #expect(await source.updates.count == 2)
}

@MainActor @Test func failedSubscriptionSaveRollsBackWithAReceipt() async {
    let source = StubPushSource(update: { _, _, _ in throw serverError })
    let bench = makeBench(source)
    await bench.model.reloadDevices()
    await bench.model.updateSubscription(id: 11, to: resolved)
    #expect(bench.model.subscription(for: 11) == .default)
    #expect(bench.model.pendingSubscriptions.isEmpty)
    #expect(bench.receipts.current?.text.hasPrefix("推送内容没有保存：") == true)
    #expect(bench.receipts.current?.tone == .critical)
    #expect(await source.deviceReads == 1)
    #expect(await source.updates.count == 1)
}

@MainActor @Test func lostOrGoneSubscriptionReplyRollsBackAndReloads() async {
    let lostSource = StubPushSource(update: { _, _, _ in throw lost })
    let lostBench = makeBench(lostSource)
    await lostBench.model.reloadDevices()
    await lostBench.model.updateSubscription(id: 11, to: resolved)
    #expect(lostBench.model.subscription(for: 11) == .default)
    #expect(lostBench.receipts.current?.text == "推送内容没有保存：网络连接已断开")
    #expect(await lostSource.deviceReads == 2)
    #expect(await lostSource.updates.count == 1)

    let goneSource = StubPushSource(devices: { call in call == 1 ? sampleDevices : sampleDevices.filter { $0.id != 11 } },
                                    update: { _, _, _ in throw notFound })
    let goneBench = makeBench(goneSource)
    await goneBench.model.reloadDevices()
    await goneBench.model.updateSubscription(id: 11, to: resolved)
    #expect(goneBench.model.device(id: 11) == nil)
    #expect(goneBench.model.subscription(for: 11) == nil)
    #expect(await goneSource.deviceReads == 2)
}

// MARK: - 测试（7.4）

@MainActor @Test func testOutcomesShowReceiptsAndReload() async {
    let refused = APIError.server(status: 502, envelope: ErrorEnvelope(reason: "PUSH_DELIVERY_FAILED",
                                                                      metadata: ["provider_reason": "BadDeviceToken", "provider_status": "400"]))
    let cases: [(answer: (any Error)?, outcome: PushTestOutcome, receipt: String?)] = [
        (nil, .sent, "已发送测试推送，请看通知"),
        (refused, .refused("推送服务没有接受：BadDeviceToken（400）"), "推送服务没有接受：BadDeviceToken（400）"),
        (APIError.server(status: 503, reason: "PUSH_NOT_CONFIGURED"), .refused("站点没有配好 APNs"), "站点没有配好 APNs"),
        (notFound, .gone, nil)]
    for item in cases {
        let answer = item.answer, removes = item.outcome == .gone
        let source = StubPushSource(devices: { call in call > 1 && removes ? sampleDevices.filter { $0.id != 12 } : sampleDevices },
                                    test: { _ in
                                        if let answer { throw answer }
                                        return PushTestResult(delivered: true, providerStatus: 200)
                                    })
        let bench = makeBench(source)
        await bench.model.reloadDevices()
        #expect(await bench.model.test(id: 12) == item.outcome)
        #expect(bench.receipts.current?.text == item.receipt)
        #expect(await source.deviceReads == 2)
        #expect(await source.tests == 1)
        if item.outcome == .gone { #expect(bench.model.device(id: 12) == nil) }
    }
}

@MainActor @Test func onlyOneTestRunsAtATime() async {
    let gate = SessionGate()
    let source = StubPushSource(test: { _ in await gate.wait(); return PushTestResult(delivered: true, providerStatus: 200) })
    let bench = makeBench(source)
    await bench.model.reloadDevices()
    let first = Task { await bench.model.test(id: 11) }
    #expect(await eventually { await gate.arrived })
    #expect(bench.model.testingID == 11)
    #expect(await bench.model.test(id: 12) == .cancelled)
    await gate.open()
    #expect(await first.value == .sent)
    #expect(bench.model.testingID == nil)
    #expect(await source.tests == 1)
}

// MARK: - 删除其他接收方式（7.4）

@MainActor @Test func deleteRemovesTheTargetAndNotFoundCountsAsDeleted() async {
    for answer in [nil, notFound] as [(any Error)?] {
        let source = StubPushSource(delete: { _ in if let answer { throw answer } })
        let bench = makeBench(source)
        await bench.model.reloadDevices()
        #expect(await bench.model.delete(id: 12) == .deleted)
        #expect(bench.model.device(id: 12) == nil)
        #expect(await source.deletes == 1)
        #expect(bench.receipts.current == nil)
    }
}

@MainActor @Test func lostDeleteReplyIsReadBackNeverResent() async {
    let stillThere = StubPushSource(delete: { _ in throw lost })
    let kept = makeBench(stillThere)
    await kept.model.reloadDevices()
    #expect(await kept.model.delete(id: 12) == .failed)
    #expect(kept.receipts.current?.text == "删除没有成功：网络连接已断开")
    #expect(kept.model.device(id: 12) != nil)

    let gone = StubPushSource(devices: { call in call == 1 ? sampleDevices : sampleDevices.filter { $0.id != 12 } }, delete: { _ in throw lost })
    let deleted = makeBench(gone)
    await deleted.model.reloadDevices()
    #expect(await deleted.model.delete(id: 12) == .deleted)
    #expect(deleted.model.device(id: 12) == nil)

    let unreadable = StubPushSource(devices: { call in
        if call == 1 { return sampleDevices }
        throw unavailable
    }, delete: { _ in throw lost })
    let unknown = makeBench(unreadable)
    await unknown.model.reloadDevices()
    #expect(await unknown.model.delete(id: 12) == .unconfirmed)
    #expect(unknown.receipts.current?.text == "删除结果未确认，请刷新核对后再操作")
    for source in [stillThere, gone, unreadable] { #expect(await source.deletes == 1) }
}

@MainActor @Test func rejectedDeleteKeepsTheTargetWithTheReason() async {
    let gate = SessionGate()
    let source = StubPushSource(delete: { call in
        if call == 1 { await gate.wait() }
        throw serverError
    })
    let bench = makeBench(source)
    await bench.model.reloadDevices()
    let first = Task { await bench.model.delete(id: 12) }
    #expect(await eventually { await gate.arrived })
    #expect(bench.model.deletingID == 12)
    #expect(await bench.model.delete(id: 13) == .ignored)
    await gate.open()
    #expect(await first.value == .failed)
    #expect(bench.model.device(id: 12) != nil)
    #expect(bench.receipts.current?.text == "删除没有成功：" + PushPresentation.failureMessage(serverError))
    #expect(bench.receipts.current?.tone == .critical)
    #expect(await source.deletes == 1)
}

// MARK: - 本地修改

@MainActor @Test func replaceInsertsInIDOrder() async {
    let bench = makeBench(StubPushSource(devices: { _ in [device(12, platform: .bark), device(13, platform: .webhook)] }))
    await bench.model.reloadDevices()
    bench.model.replace(device(11))
    #expect(bench.model.deviceList?.map(\.id) == [11, 12, 13])
    bench.model.replace(device(12, platform: .bark, enabled: false))
    #expect(bench.model.deviceList?.map(\.id) == [11, 12, 13])
    #expect(bench.model.device(id: 12)?.enabled == false)
    bench.model.remove(id: 99)
    #expect(bench.model.deviceList?.count == 3)
    bench.model.remove(id: 11)
    #expect(bench.model.deviceList?.map(\.id) == [12, 13])
}

/// An echo that lands while a reload is out is laid over that reload's answer.
@MainActor @Test func echoDuringAReloadSurvivesIt() async {
    let gate = SessionGate()
    let source = StubPushSource(devices: { call in
        if call == 2 { await gate.wait() }
        return sampleDevices
    })
    let bench = makeBench(source)
    await bench.model.reloadDevices()
    let reload = Task { await bench.model.reloadDevices() }
    #expect(await eventually { await gate.arrived })
    await bench.model.updateSubscription(id: 11, to: resolved)
    await gate.open()
    await reload.value
    #expect(bench.model.device(id: 11)?.subscription == resolved.normalized)
}

@MainActor @Test func replaceConfigUpdatesTheBannerAtOnce() async {
    let source = StubPushSource(config: { _ in notReadyConfig })
    let bench = makeBench(source)
    await bench.model.load()
    #expect(bench.model.showsNotReadyBanner)
    bench.model.replaceConfig(readyConfig)
    #expect(!bench.model.showsNotReadyBanner)
    #expect(bench.model.shownConfig == readyConfig)
    #expect(await source.configReads == 1)
}

@MainActor @Test func reloadConfigReadsOnlyTheConfig() async {
    let gate = SessionGate()
    let source = StubPushSource(config: { call in
        if call == 1 { await gate.wait(); return notReadyConfig }
        return readyConfig
    })
    let bench = makeBench(source)
    let older = Task { await bench.model.reloadConfig() }
    #expect(await eventually { await gate.arrived })
    await bench.model.reloadConfig()
    await gate.open()
    await older.value
    #expect(bench.model.shownConfig == readyConfig)
    #expect(await source.deviceReads == 0)
    #expect(await source.configReads == 2)
}

// MARK: - 删除确认文案（60 §7.4）

@MainActor @Test func pushDeleteCopyFollowsTheSpec() {
    let noun = PushPresentation.targetObjectNoun
    #expect(DeleteConfirmationCopy.title(objectNoun: noun, displayName: "我的 Bark") == "删除接收方式「我的 Bark」？")
    let message = DeleteConfirmationCopy.message(siteLine: DeleteConfirmationCopy.siteLine(siteName: "演示站点"),
                                                 consequences: [PushPresentation.deleteTargetConsequence], confirmation: .typeName)
    #expect(message == "站点 演示站点 · 删除后不能恢复。\n这个地址不再收到推送，要恢复需重新添加。")
    #expect(DeleteConfirmationCopy.confirmTitle(objectNoun: noun, confirmation: .typeName) == "删除接收方式")
    #expect(DeleteConfirmationCopy.confirmTitle(objectNoun: noun, confirmation: .biometric) == "用 Face ID 删除")
    #expect(DeleteConfirmationCopy.deletedReceipt(objectNoun: noun, displayName: "我的 Bark") == "已删除接收方式「我的 Bark」")
    let webhook = PushDevice(id: 13, platform: .webhook, endpointHost: "hooks.example.com", deviceName: nil)
    #expect(PushPresentation.targetName(webhook) == "hooks.example.com")
}
