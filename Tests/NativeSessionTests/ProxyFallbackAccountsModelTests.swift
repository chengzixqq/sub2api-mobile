import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Answers each call through its handler (`call` counts that kind of call from 1) and records what was asked.
private actor StubFallback {
    typealias Handler<T> = @Sendable (_ call: Int) async throws -> T
    private let onAccounts: Handler<[ProxyFallbackAccount]>
    private let onProxy: Handler<AdminProxy>
    private let onRevert: @Sendable (_ ids: [Int], _ call: Int) async throws -> ProxyFallbackRevertResult
    private(set) var accountCalls: [Int] = []
    private(set) var proxyCalls: [Int] = []
    private(set) var reverts: [[Int]] = []
    private(set) var revertProxyIDs: [Int] = []

    init(accounts: @escaping Handler<[ProxyFallbackAccount]> = { _ in movedRows },
         proxy: @escaping Handler<AdminProxy> = { _ in hk01 },
         revert: @escaping @Sendable (_ ids: [Int], _ call: Int) async throws -> ProxyFallbackRevertResult = { _, _ in allReverted }) {
        onAccounts = accounts; onProxy = proxy; onRevert = revert
    }
    func accounts(_ id: Int) async throws -> [ProxyFallbackAccount] { accountCalls.append(id); return try await onAccounts(accountCalls.count) }
    func proxy(_ id: Int) async throws -> AdminProxy { proxyCalls.append(id); return try await onProxy(proxyCalls.count) }
    func revert(_ id: Int, _ ids: [Int]) async throws -> ProxyFallbackRevertResult {
        revertProxyIDs.append(id); reverts.append(ids)
        return try await onRevert(ids, reverts.count)
    }
    func calls() -> Calls { Calls(accounts: accountCalls.count, proxy: proxyCalls.count, reverts: reverts) }
    nonisolated var endpoints: ProxyFallbackEndpoints {
        ProxyFallbackEndpoints(accounts: { try await self.accounts($0) }, proxy: { try await self.proxy($0) },
                               revert: { try await self.revert($0, $1) })
    }
}

private struct Calls: Equatable {
    var accounts = 0, proxy = 0
    var reverts: [[Int]] = []
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

/// The catalog the page writes the proxy back into.
private struct StubList: ProxySource {
    let rows: [AdminProxy]
    func proxies(page: Int, query: ProxyListQuery) async throws -> Page<AdminProxy> {
        Page(items: rows, total: rows.count, page: page, pageSize: 200, pages: 1)
    }
    func testProxy(id: Int) async throws -> ProxyTestResult { throw APIError.server(status: 502, reason: nil) }
}

@MainActor private final class Recorder {
    var isCurrent = true
    var allows = true
    var asked: [GatedAction] = []
    var clock = checked
    /// How often the page told the detail to read again.
    var told = 0
}

private let checked = Date(timeIntervalSince1970: 1_800_000_000)
private let hk01 = AdminProxy(id: 4, name: "hk-01", scheme: "http", host: "203.0.113.9", port: 3128, status: "active",
                              expiresAt: checked.addingTimeInterval(45 * 86_400), accountCount: 1, hasAccountCountKey: true,
                              fallbackAccountCount: 2, ipAddress: "203.0.113.9")
private let kimi = ProxyFallbackAccount(id: 9, name: "Kimi-01", platform: "kimi", type: "apikey", currentProxyID: 1, currentProxyName: "hk-02")
private let minimax = ProxyFallbackAccount(id: 12, name: "MiniMax-01", platform: "minimax", type: "apikey")
private let movedRows = [minimax, kimi]
private let allReverted = ProxyFallbackRevertResult(revertedIDs: [9, 12])
private let lost = APIError(kind: .transport, message: "无法连接站点")
private let gone = APIError.server(status: 404, reason: ProxyReason.notFound)

private func proxy(status: String = "active", expires: TimeInterval? = 45 * 86_400, moved: Int = 2) -> AdminProxy {
    AdminProxy(id: 4, name: "hk-01", scheme: "http", host: "203.0.113.9", port: 3128, status: status, expiresAt: expires.map { checked.addingTimeInterval($0) },
               accountCount: 1, hasAccountCountKey: true, fallbackAccountCount: moved, ipAddress: "203.0.113.9")
}
@MainActor private func quietReceipts() -> ReceiptCenter { ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }) }
@MainActor private func loadedStore(_ rows: [AdminProxy] = [hk01]) async -> ProxyStore {
    let store = ProxyStore(generation: UUID(), source: StubList(rows: rows), isCurrent: { true })
    await store.reload()
    return store
}
@MainActor private func makePage(_ stub: StubFallback, seed: AdminProxy? = hk01, isSupported: Bool = true, store: ProxyStore? = nil,
                                 signal: AccountListSignal? = nil, receipts: ReceiptCenter = quietReceipts(), recorder: Recorder = Recorder()) -> ProxyFallbackAccountsModel {
    ProxyFallbackAccountsModel(proxyID: 4, seed: seed, isSupported: isSupported, endpoints: stub.endpoints, store: store, accountSignal: signal,
                               receipts: receipts,
                               authorize: { recorder.asked.append($0); return recorder.allows },
                               isCurrent: { recorder.isCurrent }, now: { recorder.clock }, afterRevert: { recorder.told += 1 })
}
private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

@MainActor @Test func fallbackPageLoadsBothSideBySideAndKeepsRowsOnFailure() async {
    let gate = Gate()
    let fresh = proxy(moved: 2)
    let stub = StubFallback(accounts: { call in
        if call == 1 { await gate.wait(); return movedRows }
        throw APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
    }, proxy: { call in
        if call == 2 { throw APIError.server(status: 502, reason: nil) }
        return fresh
    })
    let store = await loadedStore([proxy(moved: 5)])
    let page = makePage(stub, seed: store.proxy(id: 4), store: store)
    #expect(page.accounts.display == .placeholder)
    #expect(page.proxyName == "hk-01")
    let first = Task { await page.load() }
    // The proxy is read while the list is still held: both are in flight together.
    #expect(await eventually {
        let proxyRead = await stub.proxyCalls.count
        let held = await gate.waiting
        return proxyRead == 1 && held == 1
    })
    #expect(page.accounts.isLoading)
    await gate.open()
    await first.value
    #expect(page.accounts.value == movedRows)
    #expect(page.proxy == fresh && store.proxy(id: 4) == fresh)

    await page.load()
    #expect(page.accounts.failureReason != nil && page.accounts.value == movedRows)
    #expect(page.proxy == fresh)
    #expect(await stub.accountCalls == [4, 4])
    #expect(await stub.proxyCalls == [4, 4])
}

@MainActor @Test func fallbackPageGoneUnsupportedAndCapabilityOff() async {
    let store = await loadedStore()
    let removed = makePage(StubFallback(proxy: { _ in throw gone }), store: store)
    await removed.load()
    #expect(removed.isGone && store.proxy(id: 4) == nil)

    let old = makePage(StubFallback(accounts: { _ in throw APIError.server(status: 404, envelope: nil) }))
    await old.load()
    #expect(old.isUnsupported && old.accounts.failureReason == nil)

    let stub = StubFallback()
    let off = makePage(stub, isSupported: false)
    await off.load()
    #expect(off.isUnsupported)
    #expect(await off.revert(.all) == .ignored)
    #expect(await stub.calls() == Calls())

    let recorder = Recorder()
    recorder.isCurrent = false
    let ended = makePage(stub, recorder: recorder)
    await ended.load()
    #expect(ended.accounts.value == nil && ended.accounts.display == .placeholder)
}

@MainActor @Test func fallbackRevertAllSendsEmptyListOnceAfterFaceID() async {
    let stub = StubFallback(accounts: { call in call == 1 ? movedRows : [] }, proxy: { call in call == 1 ? hk01 : proxy(moved: 0) })
    let signal = AccountListSignal(), receipts = quietReceipts(), recorder = Recorder()
    let store = await loadedStore()
    let page = makePage(stub, store: store, signal: signal, receipts: receipts, recorder: recorder)
    await page.load()
    #expect(await page.revert(.all) == .reverted)
    #expect(recorder.asked == [.batch])
    #expect(await stub.revertProxyIDs == [4])
    #expect(receipts.current?.text == "已恢复 2 个账号到 hk-01" && receipts.current?.tone == .ok)
    #expect(await stub.calls() == Calls(accounts: 2, proxy: 2, reverts: [[]]))
    #expect(page.accounts.value == [] && store.proxy(id: 4)?.fallbackAccountCount == 0)
    #expect(signal.revision == 1 && page.running == nil)

    let denied = Recorder()
    denied.allows = false
    let quiet = quietReceipts()
    let other = StubFallback()
    let refused = makePage(other, receipts: quiet, recorder: denied)
    await refused.load()
    #expect(await refused.revert(.all) == .denied)
    #expect(await other.reverts.isEmpty)
    #expect(quiet.current == nil && refused.running == nil)
}

@MainActor @Test func fallbackRevertOneSkipsFaceIDAndIsBlockedWhenTheOriginCannotTakeIt() async {
    let stub = StubFallback(revert: { _, _ in ProxyFallbackRevertResult(revertedIDs: [9]) })
    let recorder = Recorder()
    let page = makePage(stub, recorder: recorder)
    await page.load()
    #expect(await page.revert(.account(9)) == .reverted)
    #expect(recorder.asked.isEmpty)
    #expect(await stub.reverts == [[9]])

    for origin in [proxy(status: "expired"), proxy(status: "inactive"), proxy(expires: 0)] {
        let blocked = StubFallback(proxy: { _ in origin })
        let rule = Recorder()
        let held = makePage(blocked, seed: origin, recorder: rule)
        await held.load()
        #expect(!held.canRevert)
        #expect(await held.revert(.all) == .blocked)
        #expect(rule.asked.isEmpty)
        #expect(await blocked.reverts.isEmpty)
    }
    let unknown = makePage(StubFallback(proxy: { _ in throw lost }), seed: nil)
    await unknown.load()
    #expect(unknown.proxy == nil && !unknown.canRevert)
    #expect(await unknown.revert(.account(9)) == .blocked)

    let clock = Recorder()
    let timed = makePage(StubFallback(), recorder: clock)
    await timed.load()
    #expect(timed.canRevert)
    clock.clock = checked.addingTimeInterval(46 * 86_400)
    #expect(!timed.canRevert)
}

@MainActor @Test func fallbackPartialResultListsFailuresAndBumpsOnlyWhenReverted() async {
    let result = ProxyFallbackRevertResult(revertedIDs: [12], skipped: [.init(id: 9, code: "ACCOUNT_NOT_IN_FALLBACK")],
                                           failed: [.init(id: 11, code: "")])
    let glm = ProxyFallbackAccount(id: 11, name: "GLM-直连-01", platform: "zhipu", type: "apikey")
    let stub = StubFallback(accounts: { call in call == 1 ? [minimax, glm, kimi] : [glm] }, revert: { _, _ in result })
    let signal = AccountListSignal(), receipts = quietReceipts()
    let page = makePage(stub, signal: signal, receipts: receipts)
    await page.load()
    #expect(await page.revert(.all) == .partial)
    #expect(page.failures == [ProxyFallbackFailureLine(id: 11, name: "GLM-直连-01", reason: "服务器没能恢复这个账号", tone: .critical)])
    #expect(receipts.current?.tone == .caution && signal.revision == 1)

    let shadow = StubFallback(accounts: { call in call == 1 ? [glm] : [] }, revert: { _, _ in ProxyFallbackRevertResult(failed: [.init(id: 11, code: "")]) })
    let left = makePage(shadow)
    await left.load()
    #expect(await left.revert(.account(11)) == .partial)
    #expect(left.failures.first?.reason == ProxyFallbackPresentation.maybeReverted && left.failures.first?.tone == .caution)
    // The next attempt starts without the old failures.
    #expect(await left.revert(.account(11)) == .partial)
    #expect(left.failures.count == 1)

    let skippedOnly = StubFallback(revert: { _, _ in ProxyFallbackRevertResult(skipped: [.init(id: 9, code: "ACCOUNT_NOT_FALLBACK_OF_PROXY")]) })
    let quiet = AccountListSignal()
    let skipped = makePage(skippedOnly, signal: quiet)
    await skipped.load()
    #expect(await skipped.revert(.account(9)) == .reverted)
    #expect(quiet.revision == 0)
    #expect(await skippedOnly.accountCalls.count == 2)
}

@MainActor @Test func fallbackOriginUnavailableAndProxyGone() async {
    let stub = StubFallback(revert: { _, _ in throw APIError.server(status: 409, reason: "PROXY_FALLBACK_ORIGIN_UNAVAILABLE") })
    let receipts = quietReceipts()
    let page = makePage(stub, receipts: receipts)
    await page.load()
    #expect(await page.revert(.all) == .originUnavailable)
    #expect(receipts.current?.text == "原代理仍已过期或已停用，请先续期或启用后再恢复" && receipts.current?.tone == .critical)
    #expect(await stub.calls() == Calls(accounts: 2, proxy: 2, reverts: [[]]))

    let deleted = StubFallback(revert: { _, _ in throw gone })
    let quiet = quietReceipts()
    let store = await loadedStore()
    let removed = makePage(deleted, store: store, receipts: quiet)
    await removed.load()
    #expect(await removed.revert(.account(9)) == .proxyGone)
    #expect(removed.isGone && quiet.current == nil && store.proxy(id: 4) == nil)
}

@MainActor @Test func fallbackLostReplyIsReadBackAndNeverResent() async {
    let stub = StubFallback(accounts: { call in call == 1 ? movedRows : [] }, revert: { _, _ in throw lost })
    let signal = AccountListSignal(), receipts = quietReceipts()
    let page = makePage(stub, signal: signal, receipts: receipts)
    await page.load()
    #expect(await page.revert(.all) == .unconfirmed)
    #expect(await stub.calls() == Calls(accounts: 2, proxy: 2, reverts: [[]]))
    #expect(receipts.current?.text == "已恢复 2 个账号到 hk-01" && signal.revision == 1)

    let still = StubFallback(accounts: { call in call == 1 ? movedRows : [minimax] }, revert: { _, call in
        if call == 1 { throw lost }
        return ProxyFallbackRevertResult(revertedIDs: [12])
    })
    let held = quietReceipts(), recorder = Recorder()
    let retried = makePage(still, receipts: held, recorder: recorder)
    await retried.load()
    #expect(await retried.revert(.all) == .unconfirmed)
    #expect(held.current?.text == "恢复结果未确认 · 还有 1 个没有恢复" && held.current?.action?.title == "重试")
    let receipt = held.current!.id
    held.performAction(id: receipt)
    #expect(await eventually { await still.reverts.count == 2 })
    #expect(await still.reverts == [[], []])
    #expect(await eventually { @MainActor in recorder.asked == [.batch, .batch] })

    let unreadable = StubFallback(accounts: { call in
        if call == 1 { return movedRows }
        throw lost
    }, revert: { _, _ in throw APIError.server(status: 504, reason: nil) })
    let unknown = quietReceipts()
    let blind = makePage(unreadable, receipts: unknown)
    await blind.load()
    #expect(await blind.revert(.account(9)) == .unconfirmed)
    #expect(unknown.current?.text == "结果未确认，请刷新核对后再操作" && unknown.current?.action?.title == "重试")
}

@MainActor @Test func fallbackRejectedRunningAndSessionChange() async {
    let receipts = quietReceipts()
    let rejected = makePage(StubFallback(revert: { _, _ in throw APIError.server(status: 400, reason: "TOO_MANY_ACCOUNTS") }), receipts: receipts)
    await rejected.load()
    #expect(await rejected.revert(.all) == .failed)
    #expect(receipts.current?.text.hasPrefix("恢复没有成功：") == true && receipts.current?.tone == .critical)

    let gate = Gate()
    let held = StubFallback(revert: { _, _ in await gate.wait(); return allReverted })
    let recorder = Recorder(), quiet = quietReceipts(), signal = AccountListSignal()
    let page = makePage(held, signal: signal, receipts: quiet, recorder: recorder)
    await page.load()
    let first = Task { await page.revert(.all) }
    #expect(await eventually { await gate.waiting == 1 })
    #expect(page.running == .all)
    #expect(await page.revert(.all) == .ignored)
    #expect(await page.revert(.account(9)) == .ignored)
    recorder.isCurrent = false
    await gate.open()
    #expect(await first.value == .ignored)
    #expect(await held.reverts.count == 1)
    #expect(quiet.current == nil && signal.revision == 0)

    let cancelled = quietReceipts()
    let stopped = makePage(StubFallback(revert: { _, _ in throw CancellationError() }), receipts: cancelled)
    await stopped.load()
    #expect(await stopped.revert(.account(9)) == .ignored)
    #expect(cancelled.current == nil)
}

@Test func fallbackRevertNeedsBothVendorPermissions() {
    func vendor(_ permissions: AdminMe.WorkspacePermissions?) -> AdminMe { AdminMe(workspace: AdminMe.Workspace(id: 3, permissions: permissions)) }
    let owner = AdminMe()
    #expect(ProxyAccess.canRevertFallback(me: owner, isReadOnlyToken: false))
    #expect(ProxyAccess.canRevertFallback(me: nil, isReadOnlyToken: false))
    #expect(!ProxyAccess.canRevertFallback(me: owner, isReadOnlyToken: true))
    #expect(ProxyAccess.canRevertFallback(me: vendor(.init(accountManage: true, proxyManage: true)), isReadOnlyToken: false))
    #expect(!ProxyAccess.canRevertFallback(me: vendor(.init(proxyManage: true)), isReadOnlyToken: false))
    #expect(!ProxyAccess.canRevertFallback(me: vendor(.init(accountManage: true)), isReadOnlyToken: false))
    #expect(!ProxyAccess.canRevertFallback(me: vendor(nil), isReadOnlyToken: false))
}

// MARK: - S6-13 审查修正

/// 60 §13.4 “之后重拉本页、详情与列表”: a revert answered or read back tells the detail to read the proxy and 贰 again, since the
/// catalog's row reaches only a detail whose proxy the catalog holds. Nothing sent, or nothing the server took, tells nothing.
@MainActor @Test func fallbackRevertTellsTheDetailToReadAgain() async {
    let answered = Recorder()
    let page = makePage(StubFallback(accounts: { call in call == 1 ? movedRows : [] }), recorder: answered)
    await page.load()
    #expect(await page.revert(.all) == .reverted)
    #expect(answered.told == 1)

    let lostReply = Recorder()
    let readBack = makePage(StubFallback(accounts: { call in call == 1 ? movedRows : [minimax] }, revert: { _, _ in throw lost }), recorder: lostReply)
    await readBack.load()
    #expect(await readBack.revert(.account(9)) == .unconfirmed)
    #expect(lostReply.told == 1)

    let denied = Recorder()
    denied.allows = false
    let refused = makePage(StubFallback(), recorder: denied)
    await refused.load()
    #expect(await refused.revert(.all) == .denied)
    let expired = Recorder()
    let blocked = makePage(StubFallback(proxy: { _ in proxy(status: "expired") }), seed: proxy(status: "expired"), recorder: expired)
    await blocked.load()
    #expect(await blocked.revert(.all) == .blocked)
    let origin = Recorder()
    let unavailable = makePage(StubFallback(revert: { _, _ in throw APIError.server(status: 409, reason: ProxyReason.fallbackOriginUnavailable) }),
                               recorder: origin)
    await unavailable.load()
    #expect(await unavailable.revert(.all) == .originUnavailable)
    let rejected = Recorder()
    let tooMany = makePage(StubFallback(revert: { _, _ in throw APIError.server(status: 400, reason: "TOO_MANY_ACCOUNTS") }), recorder: rejected)
    await tooMany.load()
    #expect(await tooMany.revert(.all) == .failed)
    #expect([denied, expired, origin, rejected].allSatisfy { $0.told == 0 })
}

@Test func fallbackSignalNamesItsProxyAndSession() {
    let generation = UUID()
    let posted = ProxyFallbackSignal.notification(proxyID: 4, generation: generation)
    #expect(ProxyFallbackSignal.matches(posted, proxyID: 4, generation: generation))
    #expect(!ProxyFallbackSignal.matches(posted, proxyID: 1, generation: generation))
    #expect(!ProxyFallbackSignal.matches(posted, proxyID: 4, generation: UUID()))
    let address = ProxyAddressSignal.notification(ProxyAddressChange(proxyID: 4, generation: generation))
    #expect(!ProxyFallbackSignal.matches(address, proxyID: 4, generation: generation))
}
