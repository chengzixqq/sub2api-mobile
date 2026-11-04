import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 30 §8.4–§8.6 (S3-14, S3D1-17): the platform quota section's reads and writes against a stub site — single-platform writes
// with their undo, the whole-table fallback that starts from a fresh read, the reset, and what a failure leaves behind.

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

private let generation = UUID()
private let zone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let checked = Date(timeIntervalSince1970: 1_800_000_000)
private let lost = APIError(kind: .transport, message: "无法连接站点")

private func limits(_ daily: Decimal?, _ weekly: Decimal?, _ monthly: Decimal?) -> PlatformQuotaLimits {
    PlatformQuotaLimits(daily: daily, weekly: weekly, monthly: monthly)
}
private func row(_ platform: String, _ limits: PlatformQuotaLimits, usage: Decimal = 0, readable: Bool = true) -> UserPlatformQuota {
    UserPlatformQuota(platform: platform, daily: PlatformQuotaWindow(usage: usage, limit: limits.daily), weekly: PlatformQuotaWindow(limit: limits.weekly),
                      monthly: PlatformQuotaWindow(limit: limits.monthly), limitsReadable: readable)
}
private func context(_ id: UUID = generation, items: Bool = true, readOnly: Bool = false) -> PlatformQuotaContext {
    PlatformQuotaContext(generation: id, supportsItemWrites: items, isReadOnlyToken: readOnly, serverTimeZone: zone, now: { checked })
}

/// The server's table: Alice's Anthropic 10 / 50 / 不限 with $2.80 used today. Writes change it as the handlers do.
@MainActor private final class StubQuotas: PlatformQuotaSource {
    var platformQuotaContext: PlatformQuotaContext? = context()
    var server: [UserPlatformQuota] = [row("anthropic", limits(10, 50, nil), usage: Decimal(string: "2.8")!)]
    /// Thrown by the next call of that kind (GET, PUT, DELETE, RESTORE, RESET, PUT-ALL) only.
    var failures: [String: any Error] = [:]
    var hold: Gate?
    private(set) var calls: [String] = []
    private(set) var sentLimits: [PlatformQuotaLimits] = []
    private(set) var replaced: [[PlatformQuotaEntry]] = []
    private var deleted: [String: UserPlatformQuota] = [:]

    func metaCatalog() async -> MetaCatalog { .builtin }
    func platformQuotas(userID: Int) async throws -> [UserPlatformQuota] {
        try record("GET")
        return server
    }
    func upsertPlatformQuota(userID: Int, platform: String, limits: PlatformQuotaLimits) async throws -> PlatformQuotaUpsertResult {
        sentLimits.append(limits)
        if let hold { await hold.wait() }
        try record("PUT", platform)
        let old = server.first { $0.platform == platform }
        let fresh = limits.isEmpty ? nil : row(platform, limits, usage: old?.daily.usage ?? 0)
        server = server.filter { $0.platform != platform } + (fresh.map { [$0] } ?? [])
        return PlatformQuotaUpsertResult(platformQuota: fresh, previous: old?.limits)
    }
    func deletePlatformQuota(userID: Int, platform: String) async throws -> PlatformQuotaDeleteResult {
        try record("DELETE", platform)
        guard let old = server.first(where: { $0.platform == platform }) else { throw APIError.server(status: 404, reason: "USER_PLATFORM_QUOTA_NOT_FOUND") }
        deleted[platform] = old
        server.removeAll { $0.platform == platform }
        return PlatformQuotaDeleteResult(removed: true, previous: old.limits)
    }
    func restorePlatformQuota(userID: Int, platform: String) async throws -> PlatformQuotaRestoreResult {
        try record("RESTORE", platform)
        if server.contains(where: { $0.platform == platform }) { throw APIError.server(status: 409, reason: "USER_PLATFORM_QUOTA_ACTIVE_EXISTS") }
        guard let back = deleted.removeValue(forKey: platform) else { throw APIError.server(status: 404, reason: "USER_PLATFORM_QUOTA_NOT_FOUND") }
        server.append(back)
        return PlatformQuotaRestoreResult(platformQuota: back, restored: true)
    }
    func resetPlatformQuotaWindow(userID: Int, platform: String, window: PlatformQuotaWindowKind) async throws -> [UserPlatformQuota] {
        try record("RESET", platform + " " + window.rawValue)
        server = server.map { $0.platform == platform && window == .daily ? row(platform, $0.limits) : $0 }
        return server
    }
    func replaceUserPlatformQuotas(userID: Int, quotas: [PlatformQuotaEntry]) async throws -> [UserPlatformQuota] {
        replaced.append(quotas)
        if let hold { await hold.wait() }
        try record("PUT-ALL")
        // Kept rows keep their use; a row inserted now starts from 0 (user_platform_quota_repo.go UpsertForUser).
        server = quotas.filter { !$0.limits.isEmpty }.map { entry in
            row(entry.platform, entry.limits, usage: server.first { $0.platform == entry.platform }?.daily.usage ?? 0)
        }
        return server
    }
    private func record(_ kind: String, _ detail: String? = nil) throws {
        calls.append(detail.map { kind + " " + $0 } ?? kind)
        if let error = failures.removeValue(forKey: kind) { throw error }
    }
}

@MainActor private final class Hooks {
    private(set) var applied: [String] = []
    private(set) var undone: [String] = []
    private(set) var userGone = 0
    var hooks: PlatformQuotaHooks {
        PlatformQuotaHooks(onApplied: { [weak self] in self?.applied.append($0) }, onUndone: { [weak self] in self?.undone.append($0) },
                           onUserGone: { [weak self] in self?.userGone += 1 })
    }
}

@MainActor private func quietReceipts() -> ReceiptCenter { ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }) }
@MainActor private func loaded(_ stub: StubQuotas, hooks: Hooks = Hooks(), receipts: ReceiptCenter = quietReceipts()) async -> PlatformQuotaStore {
    let store = PlatformQuotaStore(userID: 1, source: stub, receipts: receipts, hooks: hooks.hooks)
    await store.enterSegment()
    return store
}
@MainActor private func settle(until done: @MainActor () -> Bool) async {
    for _ in 0..<500 where !done() { try? await Task.sleep(for: .milliseconds(2)) }
}

// MARK: - 读取

@MainActor @Test func enterSegmentReadsOnceAndPullReadsAgain() async {
    let stub = StubQuotas()
    let store = await loaded(stub)
    await store.enterSegment()
    #expect(stub.calls == ["GET"] && store.rows.map(\.platform) == ["anthropic"])
    await store.refresh()
    #expect(stub.calls == ["GET", "GET"])
    #expect(store.name("anthropic") == "Anthropic" && store.addablePlatforms.first == "openai")
}

@MainActor @Test func listFailureThenRetry() async {
    let stub = StubQuotas()
    stub.failures["GET"] = APIError.server(status: 500, reason: nil)
    let store = await loaded(stub)
    #expect(store.quotas.failureReason != nil && store.quotas.value == nil)
    await store.refresh()
    #expect(store.rows.count == 1 && store.quotas.failureReason == nil)
}

@MainActor @Test func userGoneCallsTheHook() async {
    let stub = StubQuotas(), hooks = Hooks()
    stub.failures["GET"] = APIError.server(status: 404, reason: "USER_NOT_FOUND")
    _ = await loaded(stub, hooks: hooks)
    #expect(hooks.userGone == 1)
}

// MARK: - 单平台写（有 users.platform_quota_item）

@MainActor @Test func singleItemWriteNeverPutsWholeTable() async {
    let stub = StubQuotas(), hooks = Hooks(), receipts = quietReceipts()
    let store = await loaded(stub, hooks: hooks, receipts: receipts)
    #expect(await store.save(platform: "anthropic", limits: limits(20, 50, nil)))
    #expect(stub.calls == ["GET", "PUT anthropic"] && stub.replaced.isEmpty)
    #expect(store.row("anthropic")?.limits == limits(20, 50, nil) && store.row("anthropic")?.daily.usage == Decimal(string: "2.8"))
    #expect(receipts.current?.text == "已更新 Anthropic 的平台限额" && receipts.current?.action != nil)
    #expect(hooks.applied == ["平台限额（Anthropic）"])
}

@MainActor @Test func undoUsesPreviousOnItemPath() async {
    let stub = StubQuotas(), hooks = Hooks(), receipts = quietReceipts()
    let store = await loaded(stub, hooks: hooks, receipts: receipts)
    await store.save(platform: "anthropic", limits: limits(20, nil, nil))
    receipts.performAction(id: receipts.current!.id)
    await settle { stub.calls.count == 3 && store.busyPlatforms.isEmpty }
    #expect(stub.calls.last == "PUT anthropic" && stub.sentLimits.last == limits(10, 50, nil))
    #expect(store.row("anthropic")?.limits == limits(10, 50, nil) && hooks.undone == ["平台限额（Anthropic）"] && receipts.current == nil)
}

@MainActor @Test func addedPlatformUndoDeletesIt() async {
    let stub = StubQuotas(), receipts = quietReceipts()
    let store = await loaded(stub, receipts: receipts)
    await store.save(platform: "openai", limits: limits(nil, nil, 0))
    #expect(store.row("openai")?.isBanned == true && receipts.current?.text == "已更新 OpenAI 的平台限额")
    receipts.performAction(id: receipts.current!.id)
    await settle { stub.calls.count == 3 && store.busyPlatforms.isEmpty }
    #expect(stub.calls == ["GET", "PUT openai", "DELETE openai"] && store.row("openai") == nil)
}

@MainActor @Test func cancelDeletesAndUndoRestoresUsage() async {
    let stub = StubQuotas(), hooks = Hooks(), receipts = quietReceipts()
    let store = await loaded(stub, hooks: hooks, receipts: receipts)
    #expect(await store.save(platform: "anthropic", limits: PlatformQuotaLimits()))
    #expect(stub.calls == ["GET", "DELETE anthropic"] && store.rows.isEmpty)
    #expect(receipts.current?.text == "已取消 Anthropic 的平台限额" && hooks.applied == ["平台限额（Anthropic）"])
    receipts.performAction(id: receipts.current!.id)
    await settle { stub.calls.count == 3 && store.busyPlatforms.isEmpty }
    #expect(stub.calls.last == "RESTORE anthropic" && store.row("anthropic")?.daily.usage == Decimal(string: "2.8"))
    // Nothing to cancel on a platform without a quota.
    #expect(await store.save(platform: "gemini", limits: PlatformQuotaLimits()))
    #expect(stub.calls.count == 3)
}

@MainActor @Test func restoreConflictShowsFixedCopyAndRefreshes() async {
    let stub = StubQuotas(), receipts = quietReceipts()
    let store = await loaded(stub, receipts: receipts)
    await store.save(platform: "anthropic", limits: PlatformQuotaLimits())
    stub.server = [row("anthropic", limits(1, nil, nil))]
    receipts.performAction(id: receipts.current!.id)
    await settle { receipts.current != nil }
    #expect(stub.calls == ["GET", "DELETE anthropic", "RESTORE anthropic", "GET"])
    #expect(receipts.current?.text == "已有人重新设置了这个平台的限额，无法恢复" && store.row("anthropic")?.limits == limits(1, nil, nil))
}

@MainActor @Test func failuresStayInTheSheetOrDisableTheSection() async {
    let stub = StubQuotas(), receipts = quietReceipts()
    let store = await loaded(stub, receipts: receipts)
    stub.failures["PUT"] = APIError.server(status: 400, reason: "INVALID_QUOTA_LIMIT")
    #expect(await store.save(platform: "anthropic", limits: limits(20, nil, nil)) == false)
    #expect(store.sheetError == "限额要大于等于 0、小于 100 亿")
    store.clearSheetError()
    #expect(await store.save(platform: "anthropic", limits: limits(-1, nil, nil)) == false)
    #expect(store.sheetError == "限额要大于等于 0、小于 100 亿" && stub.calls.count == 2)
    stub.failures["PUT"] = lost
    #expect(await store.save(platform: "anthropic", limits: limits(20, nil, nil)))
    #expect(stub.calls.suffix(2) == ["PUT anthropic", "GET"] && receipts.current?.text == "结果未确认，请刷新核对后再操作")
    stub.failures["PUT"] = APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
    #expect(await store.save(platform: "anthropic", limits: limits(30, nil, nil)))
    #expect(store.quotas.disabledReason == "SERVICE_UNAVAILABLE")
}

@MainActor @Test func resetReplacesListAndIsNotUndoable() async {
    let stub = StubQuotas(), hooks = Hooks(), receipts = quietReceipts()
    let store = await loaded(stub, hooks: hooks, receipts: receipts)
    await store.confirmReset(platform: "anthropic", window: .daily)
    #expect(stub.calls == ["GET", "RESET anthropic daily"] && store.row("anthropic")?.daily.usage == 0)
    #expect(receipts.current?.text == "已重置 Anthropic 日用量" && receipts.current?.action == nil && hooks.applied == ["平台限额（Anthropic）"])
}

@MainActor @Test func quotaReadOnlyTokenSendsNothing() async {
    let stub = StubQuotas()
    stub.platformQuotaContext = context(readOnly: true)
    let store = await loaded(stub)
    #expect(await store.save(platform: "anthropic", limits: limits(20, nil, nil)) == false)
    await store.confirmReset(platform: "anthropic", window: .daily)
    #expect(stub.calls == ["GET"])
}

@MainActor @Test func quotaStaleGenerationDropsResult() async {
    let stub = StubQuotas(), hooks = Hooks(), receipts = quietReceipts(), gate = Gate()
    let store = await loaded(stub, hooks: hooks, receipts: receipts)
    stub.hold = gate
    let saving = Task { await store.save(platform: "anthropic", limits: limits(20, nil, nil)) }
    while await gate.waiting == 0 { await Task.yield() }
    stub.platformQuotaContext = context(UUID())
    await gate.open()
    #expect(await saving.value == false)
    #expect(store.row("anthropic")?.limits == limits(10, 50, nil) && receipts.current == nil && hooks.applied.isEmpty)
}

// MARK: - 整表退路（没有 users.platform_quota_item）

@MainActor @Test func fallbackGetsFreshListThenPutsIt() async {
    let stub = StubQuotas(), hooks = Hooks(), receipts = quietReceipts()
    stub.platformQuotaContext = context(items: false)
    let store = await loaded(stub, hooks: hooks, receipts: receipts)
    // Someone else added Zhipu after the page read the list: the PUT starts from the fresh read, not the page's copy.
    stub.server.append(row("zhipu", limits(0, 0, 0)))
    #expect(await store.save(platform: "anthropic", limits: limits(20, nil, nil)))
    #expect(stub.calls == ["GET", "GET", "PUT-ALL"])
    #expect(stub.replaced == [[PlatformQuotaEntry(platform: "anthropic", limits: limits(20, nil, nil)), PlatformQuotaEntry(platform: "zhipu", limits: limits(0, 0, 0))]])
    #expect(store.rows.map(\.platform) == ["anthropic", "zhipu"] && receipts.current?.text == "已更新 Anthropic 的平台限额")
    #expect(hooks.applied == ["平台限额（Anthropic）"])
}

@MainActor @Test func fallbackKeepsPlatformsOutsideCatalog() async {
    let stub = StubQuotas()
    stub.platformQuotaContext = context(items: false)
    stub.server.append(row("future_ai", limits(7, nil, nil)))
    let store = await loaded(stub)
    await store.save(platform: "openai", limits: limits(nil, 5, nil))
    #expect(stub.replaced.first?.map(\.platform) == ["anthropic", "future_ai", "openai"])
    #expect(stub.replaced.first?[1].limits == limits(7, nil, nil) && stub.replaced.first?[0].limits == limits(10, 50, nil))
}

@MainActor @Test func fallbackAbortsWhenAnyLimitUnreadable() async {
    let stub = StubQuotas(), hooks = Hooks(), receipts = quietReceipts()
    stub.platformQuotaContext = context(items: false)
    stub.server.append(row("gemini", limits(nil, nil, nil), readable: false))
    let store = await loaded(stub, hooks: hooks, receipts: receipts)
    #expect(await store.save(platform: "anthropic", limits: limits(20, nil, nil)))
    #expect(stub.calls == ["GET", "GET"] && stub.replaced.isEmpty && hooks.applied.isEmpty)
    #expect(receipts.current?.text == "平台限额读取不完整，不能保存，请在 Web 端修改")
}

@MainActor @Test func fallbackUndoOfCancelWarnsUsageRestartsFromZero() async {
    let stub = StubQuotas(), hooks = Hooks(), receipts = quietReceipts()
    stub.platformQuotaContext = context(items: false)
    let store = await loaded(stub, hooks: hooks, receipts: receipts)
    await store.save(platform: "anthropic", limits: PlatformQuotaLimits())
    #expect(stub.replaced == [[]] && receipts.current?.text == "已取消 Anthropic 的平台限额")
    receipts.performAction(id: receipts.current!.id)
    await settle { stub.replaced.count == 2 && receipts.current != nil }
    #expect(stub.calls == ["GET", "GET", "PUT-ALL", "GET", "PUT-ALL"])
    #expect(stub.replaced.last == [PlatformQuotaEntry(platform: "anthropic", limits: limits(10, 50, nil))])
    #expect(receipts.current?.text == "已撤销，Anthropic 的已用额度会从 0 重新计算" && receipts.current?.tone == .caution)
    #expect(store.row("anthropic")?.daily.usage == 0 && hooks.undone == ["平台限额（Anthropic）"])
}

@MainActor @Test func fallbackWritesTakeTurns() async {
    // A save on another platform waits for the fallback's 撤销 to land and starts from the table it left: neither PUT drops the other.
    let stub = StubQuotas(), hooks = Hooks(), receipts = quietReceipts(), gate = Gate()
    stub.platformQuotaContext = context(items: false)
    let store = await loaded(stub, hooks: hooks, receipts: receipts)
    await store.save(platform: "anthropic", limits: PlatformQuotaLimits())
    stub.hold = gate
    receipts.performAction(id: receipts.current!.id)
    while await gate.waiting == 0 { await Task.yield() }
    let saving = Task { await store.save(platform: "openai", limits: limits(nil, nil, 0)) }
    while !store.busyPlatforms.contains("openai") { await Task.yield() }
    for _ in 0..<20 { await Task.yield() }
    #expect(stub.calls == ["GET", "GET", "PUT-ALL", "GET"])
    await gate.open()
    #expect(await saving.value)
    #expect(stub.calls == ["GET", "GET", "PUT-ALL", "GET", "PUT-ALL", "GET", "PUT-ALL"])
    #expect(stub.replaced.last == [PlatformQuotaEntry(platform: "anthropic", limits: limits(10, 50, nil)), PlatformQuotaEntry(platform: "openai", limits: limits(nil, nil, 0))])
    #expect(stub.server.map(\.platform) == ["anthropic", "openai"] && store.rows.map(\.platform) == ["anthropic", "openai"])
    #expect(hooks.undone == ["平台限额（Anthropic）"] && receipts.current?.text == "已更新 OpenAI 的平台限额" && store.busyPlatforms.isEmpty)
}
