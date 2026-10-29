import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Answers each call through its closure (`call` counts that kind of call from 1) and records what was asked.
private actor StubDetailSource: ProxyDetailSource {
    typealias Handler<T> = @Sendable (_ call: Int) async throws -> T
    private let onProxy: @Sendable (_ id: Int, _ call: Int) async throws -> AdminProxy
    private let onAccounts: Handler<[ProxyAccountRef]>
    private let onTest: Handler<ProxyTestResult>
    private let onQuality: Handler<ProxyQualityResult>
    private let onUpdate: @Sendable (_ request: ProxyUpdateRequest, _ call: Int) async throws -> AdminProxy
    private let onDelete: Handler<DeleteResult>
    private let rows: [AdminProxy]
    private(set) var proxyCalls: [Int] = []
    private(set) var accountCalls = 0
    private(set) var testCalls = 0
    private(set) var qualityCalls = 0
    private(set) var updates: [ProxyUpdateRequest] = []
    private(set) var deleteCalls = 0

    init(rows: [AdminProxy] = [hk02],
         proxy: @escaping @Sendable (_ id: Int, _ call: Int) async throws -> AdminProxy = { id, _ in try stored(id) },
         accounts: @escaping Handler<[ProxyAccountRef]> = { _ in sampleAccounts },
         test: @escaping Handler<ProxyTestResult> = { _ in probe },
         quality: @escaping Handler<ProxyQualityResult> = { _ in passedQuality },
         update: @escaping @Sendable (_ request: ProxyUpdateRequest, _ call: Int) async throws -> AdminProxy = { request, _ in reply(status: request.status) },
         delete: @escaping Handler<DeleteResult> = { _ in .deleted }) {
        self.rows = rows; onProxy = proxy; onAccounts = accounts; onTest = test; onQuality = quality; onUpdate = update; onDelete = delete
    }
    func proxies(page: Int, query: ProxyListQuery) async throws -> Page<AdminProxy> {
        Page(items: rows, total: rows.count, page: page, pageSize: 200, pages: 1)
    }
    func testProxy(id: Int) async throws -> ProxyTestResult { testCalls += 1; return try await onTest(testCalls) }
    func proxy(id: Int) async throws -> AdminProxy { proxyCalls.append(id); return try await onProxy(id, proxyCalls.count) }
    func proxyAccounts(id: Int) async throws -> [ProxyAccountRef] { accountCalls += 1; return try await onAccounts(accountCalls) }
    func checkProxyQuality(id: Int) async throws -> ProxyQualityResult { qualityCalls += 1; return try await onQuality(qualityCalls) }
    func updateProxy(id: Int, _ request: ProxyUpdateRequest) async throws -> AdminProxy {
        updates.append(request)
        return try await onUpdate(request, updates.count)
    }
    func deleteProxy(id: Int) async throws -> DeleteResult { deleteCalls += 1; return try await onDelete(deleteCalls) }
}

/// Holds a call until opened.
private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    var waiting: Int { waiters.count }
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; waiters.forEach { $0.resume() }; waiters = [] }
}

private actor SleepLog {
    private(set) var durations: [Duration] = []
    func record(_ duration: Duration) { durations.append(duration) }
}

@MainActor private final class TestFlag { var value = true }

private let checked = Date(timeIntervalSince1970: 1_800_000_000)
private let failure = APIError.server(status: 502, reason: nil)
private let gone = APIError.server(status: 404, reason: ProxyReason.notFound)
private let lost = APIError(kind: .transport, message: "无法连接站点")

private let hk02 = AdminProxy(id: 1, name: "hk-02", scheme: "socks5", host: "203.0.113.24", port: 1080, username: "relay", password: "fixture-pass",
                              status: "active", fallbackMode: "proxy", backupProxyID: 2, expiryWarnDays: 7, accountCount: 3, hasAccountCountKey: true,
                              fallbackAccountCount: 0, latencyMs: 182, latencyStatus: "success", latencyCheckedAt: checked.addingTimeInterval(-600),
                              ipAddress: "203.0.113.24", countryCode: "HK", qualityScore: 80, qualityGrade: "B")
private let sg01 = AdminProxy(id: 2, name: "sg-01", scheme: "https", host: "198.51.100.7", port: 443, status: "active", accountCount: 2, hasAccountCountKey: true)
private let sampleAccounts = [ProxyAccountRef(id: 1, name: "Claude-官方-01", platform: "anthropic", type: "oauth"),
                              ProxyAccountRef(id: 4, name: "OpenAI-主力-01", platform: "openai", type: "apikey")]
private let probe = ProxyTestResult(success: true, message: "Proxy is accessible", latencyMs: 176, ipAddress: "203.0.113.24", countryCode: "HK",
                                    checkedAt: checked)
private let passedQuality = ProxyQualityResult(score: 92, grade: "A", summary: "ok", passedCount: 4, checkedAt: checked,
                                               items: [ProxyQualityItem(target: "base_connectivity", status: "pass")])

private func stored(_ id: Int) throws -> AdminProxy {
    guard let row = [hk02, sg01].first(where: { $0.id == id }) else { throw gone }
    return row
}
/// The PUT's plain `dto.AdminProxy`: hk-02's configuration with the new status, no counts, latency or quality.
private func reply(status: ProxyStatusChange?) -> AdminProxy {
    AdminProxy(id: 1, name: "hk-02", scheme: "socks5", host: "203.0.113.24", port: 1080, username: "relay", password: "fixture-pass",
               status: status?.rawValue ?? "active", fallbackMode: "proxy", backupProxyID: 2, expiryWarnDays: 7)
}
private func withStatus(_ status: String) -> AdminProxy {
    hk02.mergingConfiguration(from: AdminProxy(id: 1, name: "hk-02", scheme: "socks5", host: "203.0.113.24", port: 1080, username: "relay",
                                               password: "fixture-pass", status: status, fallbackMode: "proxy", backupProxyID: 2, expiryWarnDays: 7))
}
private func conflict(_ metadata: [String: String] = [:]) -> APIError {
    APIError.server(status: 409, envelope: ErrorEnvelope(reason: ProxyReason.inUse, metadata: metadata))
}

@MainActor private func makeModel(_ stub: StubDetailSource, seed: AdminProxy? = hk02, store: ProxyStore? = nil, receipts: ReceiptCenter = quietReceipts(),
                                  isCurrent: @escaping @MainActor @Sendable () -> Bool = { true },
                                  sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }) -> ProxyDetailModel {
    ProxyDetailModel(id: 1, seed: seed, source: stub, store: store, receipts: receipts, isCurrent: isCurrent, now: { checked }, sleep: sleep)
}
@MainActor private func quietReceipts() -> ReceiptCenter { ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }) }
@MainActor private func loadedStore(_ stub: StubDetailSource) async -> ProxyStore {
    let store = ProxyStore(generation: UUID(), source: stub, isCurrent: { true })
    await store.reload()
    return store
}

private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

@MainActor @Test func proxyDetailLoadSeedPlaceholderGoneFailure() async {
    let fresh = hk02.applying(probe)
    let stub = StubDetailSource(rows: [hk02, sg01], proxy: { id, _ in id == 1 ? fresh : try stored(id) })
    let store = await loadedStore(stub)
    let seeded = makeModel(stub, store: store)
    #expect(seeded.detail.display == .value(hk02, at: checked, isRefreshing: false, updateFailed: false))
    await seeded.load()
    #expect(await stub.proxyCalls == [1])
    #expect(await stub.accountCalls == 1)
    #expect(seeded.proxy == fresh && store.proxy(id: 1) == fresh)
    #expect(seeded.accounts.value == sampleAccounts)
    // The backup is in the catalog: no second GET.
    #expect(seeded.backupName == "sg-01")

    let lonely = StubDetailSource(proxy: { id, _ in try stored(id) })
    let placeholder = makeModel(lonely, seed: nil)
    #expect(placeholder.detail.display == .placeholder && placeholder.proxy == nil)
    await placeholder.load()
    #expect(placeholder.proxy == hk02)
    // Not in any catalog: the backup's name is read once.
    #expect(await lonely.proxyCalls == [1, 2])
    #expect(placeholder.backupName == "sg-01")
    await placeholder.load()
    #expect(await lonely.proxyCalls == [1, 2, 1])

    let deleted = StubDetailSource(rows: [hk02], proxy: { _, _ in throw gone })
    let deletedStore = await loadedStore(deleted)
    let goneModel = makeModel(deleted, store: deletedStore)
    await goneModel.load()
    #expect(goneModel.isGone && goneModel.proxy == nil && deletedStore.proxy(id: 1) == nil)

    let broken = StubDetailSource(proxy: { _, _ in throw failure })
    let unseeded = makeModel(broken, seed: nil)
    await unseeded.load()
    #expect(unseeded.detail.display == .failed(reason: failure.localizedDescription))
    let kept = makeModel(broken)
    await kept.load()
    #expect(kept.detail.display == .value(hk02, at: checked, isRefreshing: false, updateFailed: true))

    let noAccounts = StubDetailSource(accounts: { _ in throw failure })
    let partial = makeModel(noAccounts)
    await partial.load()
    #expect(partial.proxy == hk02 && partial.accounts.display == .failed(reason: failure.localizedDescription))
    await partial.reloadAccounts()
    #expect(await noAccounts.accountCalls == 2)
    #expect(await noAccounts.proxyCalls == [1, 2])
}

@MainActor @Test func proxyDetailTestConnection() async {
    let stub = StubDetailSource(rows: [hk02])
    let store = await loadedStore(stub)
    let model = makeModel(stub, store: store)
    await model.test()
    #expect(model.justTestedAt == checked && model.proxy?.latencyMs == 176 && store.proxy(id: 1)?.latencyMs == 176)
    #expect(model.receipts.current == nil)

    let failedProbe = StubDetailSource(test: { _ in ProxyTestResult(success: false, message: "dial tcp: i/o timeout", checkedAt: checked) })
    let probed = makeModel(failedProbe)
    await probed.test()
    #expect(probed.proxy?.latencyStatus == "failed" && probed.proxy?.latencyMessage == "dial tcp: i/o timeout" && probed.justTestedAt == checked)

    let gate = Gate()
    let refused = StubDetailSource(test: { _ in await gate.wait(); throw failure })
    let kept = makeModel(refused)
    let first = Task { await kept.test() }
    #expect(await eventually { await gate.waiting == 1 })
    #expect(kept.isTesting)
    await kept.test()
    await gate.open()
    await first.value
    #expect(await refused.testCalls == 1)
    #expect(kept.receipts.current?.text == "测试请求失败，请稍后再试" && kept.receipts.current?.tone == .critical)
    #expect(kept.proxy == hk02 && kept.justTestedAt == nil && !kept.isTesting)
}

@MainActor @Test func proxyDetailQualityCheck() async {
    let model = makeModel(StubDetailSource())
    await model.checkQuality()
    #expect(model.proxy?.qualityScore == 92 && model.proxy?.qualityGrade == "A" && model.proxy?.qualityChecked == checked)
    #expect(model.proxy?.latencyMs == 182)
    #expect(model.receipts.current?.text == "质量检测完成：评分 92（A）" && model.receipts.current?.tone == .ok)

    let weak = ProxyQualityResult(score: 78, grade: "B", failedCount: 1, checkedAt: checked,
                                  items: [ProxyQualityItem(target: "base_connectivity", status: "fail")])
    let failedBase = makeModel(StubDetailSource(quality: { _ in weak }))
    await failedBase.checkQuality()
    #expect(failedBase.proxy?.qualityScore == 78 && failedBase.proxy?.qualityStatus == "failed")
    #expect(failedBase.receipts.current?.text == "代理质量检测失败" && failedBase.receipts.current?.tone == .critical)

    let broken = StubDetailSource(quality: { _ in throw failure })
    let unchanged = makeModel(broken)
    await unchanged.checkQuality()
    #expect(unchanged.proxy == hk02 && !unchanged.isCheckingQuality)
    #expect(unchanged.receipts.current?.text == "代理质量检测失败")
    #expect(await broken.qualityCalls == 1)
}

@MainActor @Test func proxyDetailToggleStatusUndoAndReadBack() async throws {
    let stub = StubDetailSource()
    let model = makeModel(stub)
    await model.toggleStatus()
    #expect(await stub.updates == [ProxyUpdateRequest(status: .inactive)])
    #expect(model.proxy == withStatus("inactive"))
    #expect(model.proxy?.accountCount == 3 && model.proxy?.latencyMs == 182 && model.proxy?.qualityScore == 80)
    let receipt = try #require(model.receipts.current)
    #expect(receipt.text == "已停用 hk-02 · 在用的 3 个账号不受影响" && receipt.action?.title == "撤销")
    model.receipts.performAction(id: receipt.id)
    #expect(await eventually { await stub.updates.count == 2 })
    #expect(await stub.updates.last == ProxyUpdateRequest(status: .active))
    #expect(await eventually { await MainActor.run { model.proxy?.status == "active" && !model.isUpdatingStatus } })

    let undoFails = StubDetailSource(update: { request, call in
        guard call == 1 else { throw APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY") }
        return reply(status: request.status)
    })
    let failing = makeModel(undoFails)
    await failing.toggleStatus()
    let undo = try #require(failing.receipts.current)
    failing.receipts.performAction(id: undo.id)
    #expect(await eventually { await MainActor.run { failing.receipts.current?.text.hasPrefix("撤销没有成功：") == true } })
    #expect(failing.proxy?.status == "inactive")

    // A lost reply is read back: applied, not applied, unknown.
    let landed = StubDetailSource(proxy: { _, _ in withStatus("inactive") }, update: { _, _ in throw lost })
    let applied = makeModel(landed)
    await applied.toggleStatus()
    #expect(applied.proxy?.status == "inactive" && applied.receipts.current?.text == "已停用 hk-02 · 在用的 3 个账号不受影响")
    #expect(await landed.updates.count == 1)
    let missed = makeModel(StubDetailSource(proxy: { _, _ in hk02 }, update: { _, _ in throw lost }))
    await missed.toggleStatus()
    #expect(missed.proxy?.status == "active" && missed.receipts.current?.text == "停用没有成功：" + lost.localizedDescription)
    let unknown = makeModel(StubDetailSource(proxy: { _, _ in throw lost }, update: { _, _ in throw lost }))
    await unknown.toggleStatus()
    #expect(unknown.receipts.current?.text == "结果未确认，请刷新核对后再操作" && unknown.receipts.current?.tone == .caution)

    let readOnly = APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")
    let refused = makeModel(StubDetailSource(update: { _, _ in throw readOnly }))
    await refused.toggleStatus()
    #expect(refused.receipts.current?.text == "停用没有成功：" + readOnly.localizedDescription && refused.proxy == hk02)

    let inactive = withStatus("inactive")
    let enabling = StubDetailSource()
    let enable = makeModel(enabling, seed: inactive)
    await enable.toggleStatus()
    #expect(await enabling.updates == [ProxyUpdateRequest(status: .active)])
    #expect(enable.receipts.current?.text == "已启用 hk-02")

    let expired = StubDetailSource()
    let renew = makeModel(expired, seed: withStatus("expired"))
    await renew.toggleStatus()
    #expect(await expired.updates.isEmpty)
}

@MainActor @Test func proxyDetailDeleteFlows() async {
    let stub = StubDetailSource(rows: [hk02])
    let store = await loadedStore(stub)
    let model = makeModel(stub, store: store)
    #expect(await model.delete() == .deleted)
    #expect(store.proxy(id: 1) == nil && model.receipts.current?.text == "已删除代理「hk-02」")
    #expect(await model.delete() == .ignored)
    #expect(await stub.deleteCalls == 1)
    #expect(await makeModel(StubDetailSource(delete: { _ in .alreadyGone })).delete() == .deleted)

    let moved = StubDetailSource(delete: { _ in throw conflict(["fallback_account_count": "2"]) })
    #expect(await makeModel(moved).delete() == .blocked(.fallback(name: "hk-02", accounts: 2)))
    #expect(await moved.proxyCalls.isEmpty)
    let busy = StubDetailSource(proxy: { _, _ in withStatus("active") }, delete: { _ in throw conflict() })
    let inUse = makeModel(busy, seed: AdminProxy(id: 1, name: "hk-02", accountCount: 0, hasAccountCountKey: true))
    #expect(await inUse.delete() == .blocked(.inUse(name: "hk-02", accounts: 3)))
    #expect(await busy.proxyCalls == [1])
    #expect(await busy.deleteCalls == 1)
    #expect(inUse.proxy?.accountCount == 3)

    let vanished = StubDetailSource(proxy: { _, _ in throw gone }, delete: { _ in throw lost })
    #expect(await makeModel(vanished).delete() == .deleted)
    let still = makeModel(StubDetailSource(proxy: { _, _ in hk02 }, delete: { _ in throw lost }))
    #expect(await still.delete() == .failed)
    #expect(still.receipts.current?.text == "删除没有成功：" + lost.localizedDescription)
    let unknown = StubDetailSource(proxy: { _, _ in throw failure }, delete: { _ in throw lost })
    let unknownModel = makeModel(unknown)
    #expect(await unknownModel.delete() == .unconfirmed)
    #expect(await unknown.deleteCalls == 1)
    #expect(unknownModel.receipts.current?.text == "结果未确认，请刷新核对后再操作")
}

@MainActor @Test func proxyDetailAddressReprobeAndSessionGuard() async {
    let gate = Gate(), log = SleepLog()
    let stub = StubDetailSource()
    let model = makeModel(stub, sleep: { duration in await log.record(duration); await gate.wait() })
    let first = Task { await model.beginAddressReprobe() }
    #expect(await eventually { await gate.waiting == 1 })
    #expect(model.isReprobing)
    let second = Task { await model.beginAddressReprobe() }
    #expect(await eventually { await gate.waiting == 2 })
    await gate.open()
    await first.value
    await second.value
    #expect(await log.durations == [.seconds(5), .seconds(5)])
    #expect(await stub.proxyCalls.filter { $0 == 1 } == [1])
    #expect(await stub.testCalls == 0)
    #expect(!model.isReprobing)

    let flag = TestFlag()
    let ended = StubDetailSource()
    let stale = makeModel(ended, isCurrent: { flag.value })
    flag.value = false
    await stale.test()
    await stale.load()
    await stale.toggleStatus()
    #expect(await ended.testCalls == 0)
    #expect(await ended.proxyCalls.isEmpty)
    #expect(await ended.updates.isEmpty)
    let gated = Gate()
    let late = StubDetailSource(test: { _ in await gated.wait(); return probe })
    let lateFlag = TestFlag()
    let lateModel = makeModel(late, isCurrent: { lateFlag.value })
    let running = Task { await lateModel.test() }
    #expect(await eventually { await gated.waiting == 1 })
    lateFlag.value = false
    await gated.open()
    await running.value
    #expect(lateModel.proxy == hk02 && lateModel.receipts.current == nil)

    let error = AccountStatusItem(id: 4, name: "OpenAI-主力-01", platform: "openai", state: .error, status: "error")
    #expect(ProxyAccountStateLookup.state(accountID: 4, items: [error], now: checked)?.state == .error)
    #expect(ProxyAccountStateLookup.state(accountID: 1, items: [error], now: checked) == nil)
    #expect(ProxyAccountStateLookup.state(accountID: 4, items: nil, now: checked) == nil)
}

@Test func proxyAddressSignalRoundTrips() {
    let change = ProxyAddressChange(proxyID: 3, generation: UUID())
    let note = ProxyAddressSignal.notification(change)
    #expect(note.name == .proxyAddressDidChange && ProxyAddressSignal.change(in: note) == change)
    #expect(ProxyAddressSignal.change(in: Notification(name: .proxyAddressDidChange)) == nil)
    #expect(ProxyAddressSignal.change(in: Notification(name: .proxyAddressDidChange, userInfo: ["proxyID": 3])) == nil)
}
