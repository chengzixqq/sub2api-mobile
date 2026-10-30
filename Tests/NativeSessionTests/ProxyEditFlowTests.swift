import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 60 §14.4 (S6-14): the add with its key, undo and probe read; the edit sent once and read back; the reasons that stay on the sheet.

private let noon = Date(timeIntervalSince1970: 1_792_123_200)
private let lost = APIError(kind: .transport, message: "无法连接站点")
private let gone = APIError.server(status: 404, reason: ProxyReason.notFound)
private let unconfirmed = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: lost)

private let hk02 = AdminProxy(id: 1, name: "hk-02", scheme: "socks5", host: "203.0.113.24", port: 1080, username: "relay", password: "fixture-pass",
                              status: "active", expiresAt: noon.addingTimeInterval(6 * 86_400), fallbackMode: "proxy", backupProxyID: 2,
                              expiryWarnDays: 7, accountCount: 3, hasAccountCountKey: true, latencyMs: 182, latencyStatus: "success")
private let sg01 = AdminProxy(id: 2, name: "sg-01", scheme: "https", host: "198.51.100.7", port: 443, status: "active", accountCount: 2, hasAccountCountKey: true)
private let jpTokyo = AdminProxy(id: 3, name: "jp-tokyo-1", scheme: "socks5h", host: "192.0.2.88", port: 1080, status: "expired",
                                 expiresAt: noon.addingTimeInterval(-3 * 86_400), fallbackMode: "none", expiryWarnDays: 7, accountCount: 1,
                                 hasAccountCountKey: true)

/// A PUT's plain dto.AdminProxy: `base` with the request applied, without counts or probes.
private func applied(_ request: ProxyUpdateRequest, to base: AdminProxy) -> AdminProxy {
    AdminProxy(id: base.id, name: request.name ?? base.name, scheme: request.scheme ?? base.scheme, host: request.host ?? base.host,
               port: request.port ?? base.port, username: request.username ?? base.username, password: request.password ?? base.password,
               status: request.status?.rawValue ?? base.status, expiresAt: base.expiresAt, fallbackMode: request.fallbackMode?.rawValue ?? base.fallbackMode,
               backupProxyID: base.backupProxyID, expiryWarnDays: request.expiryWarnDays ?? base.expiryWarnDays)
}

private actor StubEditSource: ProxyEditSource {
    typealias Create = @Sendable (_ request: ProxyCreateRequest, _ call: Int) async throws -> AdminProxy
    typealias Update = @Sendable (_ request: ProxyUpdateRequest, _ call: Int) async throws -> AdminProxy
    typealias Read = @Sendable (_ id: Int, _ call: Int) async throws -> AdminProxy
    private var rows: [AdminProxy]
    private let onCreate: Create
    private let onUpdate: Update
    private let onRead: Read?
    private let deleteError: (any Error)?
    private(set) var keys: [UUID] = []
    private(set) var creates: [Data] = []
    private(set) var updates: [ProxyUpdateRequest] = []
    private(set) var reads: [Int] = []
    private(set) var searches: [String] = []
    private(set) var deletes: [Int] = []

    init(rows: [AdminProxy] = [hk02, sg01, jpTokyo], create: @escaping Create = { request, _ in StubEditSource.created(request) },
         update: @escaping Update = { request, _ in applied(request, to: hk02) }, read: Read? = nil, deleteError: (any Error)? = nil) {
        self.rows = rows; onCreate = create; onUpdate = update; onRead = read; self.deleteError = deleteError
    }
    static func created(_ request: ProxyCreateRequest) -> AdminProxy {
        AdminProxy(id: 9, name: request.name, scheme: request.scheme, host: request.host, port: request.port, status: "active",
                   fallbackMode: request.fallbackMode.rawValue, expiryWarnDays: request.expiryWarnDays)
    }

    func proxies(page: Int, query: ProxyListQuery) async throws -> Page<AdminProxy> {
        if !query.search.isEmpty { searches.append(query.search) }
        let matched = rows.filter { query.search.isEmpty || $0.name == query.search }
        return Page(items: matched, total: matched.count, page: page, pageSize: query.pageSize, pages: 1)
    }
    func testProxy(id: Int) async throws -> ProxyTestResult { ProxyTestResult(success: true, latencyMs: 158) }
    func proxy(id: Int) async throws -> AdminProxy {
        reads.append(id)
        if let onRead { return try await onRead(id, reads.count) }
        guard let row = rows.first(where: { $0.id == id }) else { throw gone }
        return row
    }
    func proxyAccounts(id: Int) async throws -> [ProxyAccountRef] { [] }
    func checkProxyQuality(id: Int) async throws -> ProxyQualityResult { ProxyQualityResult() }
    func updateProxy(id: Int, _ request: ProxyUpdateRequest) async throws -> AdminProxy {
        updates.append(request)
        return try await onUpdate(request, updates.count)
    }
    func deleteProxy(id: Int) async throws -> DeleteResult {
        deletes.append(id)
        if let deleteError { throw deleteError }
        rows.removeAll { $0.id == id }
        return .deleted
    }
    func createProxy(_ request: ProxyCreateRequest, idempotencyKey: UUID, onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<AdminProxy> {
        keys.append(idempotencyKey)
        creates.append(try request.requestBody())
        let row = try await onCreate(request, keys.count)
        rows.insert(row, at: 0)
        return WriteOutcome(value: row)
    }
}

private final class SignalLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [ProxyAddressChange] = []
    var changes: [ProxyAddressChange] { lock.withLock { seen } }
    func record(_ change: ProxyAddressChange) { lock.withLock { seen.append(change) } }
}

@MainActor private struct Harness {
    let stub: StubEditSource
    let store: ProxyStore
    let receipts: ReceiptCenter
    let flow: ProxyEditFlow
    let generation: UUID
}

@MainActor private func harness(_ stub: StubEditSource = StubEditSource(), original: AdminProxy? = nil) async -> Harness {
    let generation = UUID()
    let store = ProxyStore(generation: generation, source: stub, isCurrent: { true })
    await store.reload()
    let receipts = ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
    let flow = ProxyEditFlow(original: original, source: stub, store: store, receipts: receipts, generation: generation, isCurrent: { true },
                             now: { noon }, pause: { _ in })
    return Harness(stub: stub, store: store, receipts: receipts, flow: flow, generation: generation)
}

private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

private func newProxy() -> ProxyEditDraft {
    var draft = ProxyEditDraft.adding()
    draft.name = "fr-par-1"
    draft.host = "198.51.100.9"
    draft.portText = "1080"
    return draft
}

@MainActor @Test func proxyEditAddShowsUndoReloadsAndReadsTheProbe() async {
    let h = await harness()
    await h.flow.submit(newProxy())
    #expect(h.flow.isFinished)
    #expect(h.receipts.current?.text == "代理添加成功")
    #expect(h.receipts.current?.action != nil)
    await h.flow.followUp?.value
    #expect(await h.stub.reads == [9])
    #expect(h.store.proxy(id: 9)?.name == "fr-par-1")

    h.receipts.performAction(id: h.receipts.current!.id)
    #expect(await eventually { await h.stub.deletes == [9] })
    #expect(await eventually { await MainActor.run { h.receipts.current?.text == "已删除代理「fr-par-1」" } })
    #expect(h.store.proxy(id: 9) == nil)
}

@MainActor @Test func proxyEditUndoInUseSaysWhy() async {
    let inUse = APIError.server(status: 409, reason: ProxyReason.inUse)
    let h = await harness(StubEditSource(deleteError: inUse))
    await h.flow.submit(newProxy())
    h.receipts.performAction(id: h.receipts.current!.id)
    #expect(await eventually { await MainActor.run { h.receipts.current?.text == "撤销没有成功：已有账号在用这个代理" } })
}

@MainActor @Test func proxyEditAddUnconfirmedRetriesTheSameKeyAndBytes() async {
    let h = await harness(StubEditSource(create: { request, call in
        if call == 1 { throw unconfirmed }
        return StubEditSource.created(request)
    }))
    await h.flow.submit(newProxy())
    #expect(h.flow.phase == .addUnconfirmed(retryNotBefore: nil, searched: false))
    #expect(h.flow.locksForm && !h.flow.isFinished)
    await h.flow.retrySameKey()
    #expect(h.flow.isFinished)
    let keys = await h.stub.keys, bodies = await h.stub.creates
    #expect(keys.count == 2 && keys[0] == keys[1])
    #expect(bodies.count == 2 && bodies[0] == bodies[1])
}

@MainActor @Test func proxyEditAddCheckFindsItByName() async {
    let h = await harness(StubEditSource(rows: [hk02, sg01, StubEditSource.created(try! newProxy().createRequest(now: noon))], create: { _, _ in throw unconfirmed }))
    await h.flow.submit(newProxy())
    await h.flow.reconcileAdd()
    #expect(await h.stub.searches == ["fr-par-1"])
    #expect(h.flow.isFinished && h.receipts.current?.text == "代理添加成功")

    let missing = await harness(StubEditSource(create: { _, _ in throw unconfirmed }))
    await missing.flow.submit(newProxy())
    await missing.flow.reconcileAdd()
    #expect(missing.flow.phase == .addUnconfirmed(retryNotBefore: nil, searched: true))
}

@MainActor @Test func proxyEditAddRefusedTakesANewKeyNextTime() async {
    let h = await harness(StubEditSource(create: { request, call in
        if call == 1 { throw APIError.server(status: 400, reason: ProxyReason.backupSelf) }
        if call == 2 { throw APIError.server(status: 404, reason: ProxyReason.notFound) }
        return StubEditSource.created(request)
    }))
    var draft = newProxy()
    draft.fallback = .proxy
    draft.backupID = 2
    await h.flow.submit(draft)
    #expect(h.flow.phase == .failed("备用代理不能是它自己", section: .fallback))
    await h.flow.submit(draft)
    #expect(h.flow.phase == .failed("备用代理已不存在，请重新选择", section: .fallback))
    await h.flow.submit(draft)
    let keys = await h.stub.keys
    #expect(keys.count == 3 && Set(keys).count == 3)
}

@MainActor @Test func proxyEditSavePostsTheAddressSignalOnlyForNetworkFields() async {
    let log = SignalLog()
    let token = NotificationCenter.default.addObserver(forName: .proxyAddressDidChange, object: nil, queue: nil) { note in
        if let change = ProxyAddressSignal.change(in: note) { log.record(change) }
    }
    defer { NotificationCenter.default.removeObserver(token) }
    let h = await harness(original: hk02)
    var draft = ProxyEditDraft(editing: hk02, now: noon)
    draft.portText = "1081"
    await h.flow.submit(draft)
    #expect(h.flow.isFinished && h.receipts.current?.text == "代理更新成功")
    #expect(log.changes.filter { $0.generation == h.generation } == [ProxyAddressChange(proxyID: 1, generation: h.generation)])
    // The reply has no counts: the catalog's row keeps them, and its old latency is dropped (H04).
    #expect(h.store.proxy(id: 1)?.port == 1081 && h.store.proxy(id: 1)?.accountCount == 3 && h.store.proxy(id: 1)?.latencyMs == nil)

    let quiet = await harness(original: hk02)
    var renamed = ProxyEditDraft(editing: hk02, now: noon)
    renamed.name = "hk-02b"
    await quiet.flow.submit(renamed)
    #expect(quiet.flow.isFinished && !log.changes.contains { $0.generation == quiet.generation })
    #expect(quiet.store.proxy(id: 1)?.name == "hk-02b" && quiet.store.proxy(id: 1)?.latencyMs == 182)
}

@MainActor @Test func proxyEditRenewSaysRestored() async {
    let h = await harness(StubEditSource(update: { request, _ in applied(request, to: jpTokyo) }), original: jpTokyo)
    var draft = ProxyEditDraft(editing: jpTokyo, now: noon)
    draft.selectExpiry(.days(30))
    await h.flow.submit(draft)
    #expect(await h.stub.updates.first?.status == .active)
    #expect(h.receipts.current?.text == "已续期 · jp-tokyo-1 恢复正常")
}

@MainActor @Test func proxyEditLostReplyIsReadBack() async {
    var draft = ProxyEditDraft(editing: hk02, now: noon)
    draft.name = "hk-02b"
    let landed = await harness(StubEditSource(update: { _, _ in throw lost }, read: { _, _ in applied(ProxyUpdateRequest(name: "hk-02b"), to: hk02) }),
                               original: hk02)
    await landed.flow.submit(draft)
    #expect(await landed.stub.updates.count == 1)
    #expect(landed.flow.isFinished && landed.receipts.current?.text == "代理更新成功")

    let other = await harness(StubEditSource(update: { _, _ in throw lost }, read: { _, _ in hk02 }), original: hk02)
    await other.flow.submit(draft)
    #expect(other.flow.phase == .failed("服务器上的代理与这次修改不一致，可以重新保存", section: nil))

    let unknown = await harness(StubEditSource(update: { _, _ in throw lost }, read: { _, call in
        if call == 1 { throw APIError.server(status: 502, reason: nil) }
        return applied(ProxyUpdateRequest(name: "hk-02b"), to: hk02)
    }), original: hk02)
    await unknown.flow.submit(draft)
    #expect(unknown.flow.phase == .updateUnconfirmed && unknown.flow.locksForm)
    await unknown.flow.recheck()
    #expect(unknown.flow.isFinished)
    #expect(await unknown.stub.updates.count == 1)
}

@MainActor @Test func proxyEditMissingBackupOrProxy() async {
    var draft = ProxyEditDraft(editing: hk02, now: noon)
    draft.backupID = 3
    let backup = await harness(StubEditSource(update: { _, _ in throw gone }), original: hk02)
    await backup.flow.submit(draft)
    #expect(backup.flow.phase == .failed("备用代理已不存在，请重新选择", section: .fallback))
    #expect(await backup.stub.reads == [1])

    let itself = await harness(StubEditSource(update: { _, _ in throw gone }, read: { _, _ in throw gone }), original: hk02)
    await itself.flow.submit(draft)
    #expect(itself.flow.isFinished && itself.receipts.current?.text == "对象不存在或已删除")
    #expect(itself.store.proxy(id: 1) == nil)

    var renamed = ProxyEditDraft(editing: hk02, now: noon)
    renamed.name = "hk-02b"
    let plain = await harness(StubEditSource(update: { _, _ in throw gone }), original: hk02)
    await plain.flow.submit(renamed)
    #expect(plain.flow.isFinished)
    #expect(await plain.stub.reads.isEmpty)
}
