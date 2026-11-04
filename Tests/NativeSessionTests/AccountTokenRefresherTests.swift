import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// The site clock of every case: 2026-10-24T08:00:00Z, 16:00 in Shanghai.
private let refreshNow = Date(timeIntervalSince1970: 1_792_828_800)
private let refreshTransportError = APIError(kind: .transport, message: "无法连接站点")
private let refreshUnconfirmed = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)

private func oauthAccount(expiresAt: String? = "2026-10-24T10:00:00Z", refreshedAt: TimeInterval? = 0, hasStatus: Bool = true) -> UpstreamAccount {
    let status = AccountTokenStatus(expiresAt: expiresAt, lifetimeSeconds: 28_800,
                                    refreshedAt: refreshedAt.map { ServerTime.utcTimestamp(refreshNow.addingTimeInterval($0)) }, autoRefresh: true)
    return UpstreamAccount(id: 1, name: "Claude-官方-01", platform: "anthropic", type: "oauth", tokenStatus: hasStatus ? status : nil)
}

/// Records each refresh with its key and generation and answers from scripts; an empty script answers with a fresh token.
/// Calls wait at `gate` when one is set, and answer whatever the session has become meanwhile.
@MainActor private final class ScriptedRefreshSource: AccountRefreshSource {
    struct Call: Equatable { let id: Int; let key: UUID?; let generation: UUID }
    private(set) var session: AccountWriteSession?
    private(set) var calls: [Call] = []
    private(set) var reads = 0
    var refreshReplies: [Result<AccountRefreshResult, any Error>] = []
    var readReplies: [Result<VersionedAccount, any Error>] = []
    var gate: SessionGate?
    let siteTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    init(idempotentWrites: Bool = true, readOnly: Bool = false) {
        session = AccountWriteSession(generation: UUID(), idempotentWrites: idempotentWrites, recoverSchedulable: true, patch: true,
                                      isReadOnlyToken: readOnly)
    }
    var generation: UUID { session?.generation ?? UUID() }
    func switchSession() {
        guard let old = session else { return }
        session = AccountWriteSession(generation: UUID(), idempotentWrites: old.idempotentWrites, recoverSchedulable: true, patch: true,
                                      isReadOnlyToken: old.isReadOnlyToken)
    }

    var accountWriteSession: AccountWriteSession? { session }
    func serverNow() -> Date { refreshNow }
    func refreshAccount(id: Int, idempotencyKey: UUID?, generation: UUID) async throws -> AccountRefreshResult {
        calls.append(Call(id: id, key: idempotencyKey, generation: generation))
        if let gate { await gate.wait() }
        guard !refreshReplies.isEmpty else { return AccountRefreshResult(account: oauthAccount()) }
        return try refreshReplies.removeFirst().get()
    }
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        reads += 1
        guard !readReplies.isEmpty else { return VersionedAccount(account: oauthAccount(), etag: "\"cv-2\"") }
        return try readReplies.removeFirst().get()
    }
}

@MainActor private final class RefreshHarness {
    let source: ScriptedRefreshSource
    let receipts = ReceiptCenter(sleep: { try await Task.sleep(for: $0 * 1_000) })
    private(set) var changed: [UpstreamAccount] = []
    private(set) var missing: [Int] = []
    private(set) var keys: [UUID] = []
    private(set) var refresher: AccountTokenRefresher!

    init(_ source: ScriptedRefreshSource = ScriptedRefreshSource()) {
        self.source = source
        refresher = AccountTokenRefresher(source: source, receipts: receipts, onChange: { [weak self] in self?.changed.append($0) },
                                          onMissing: { [weak self] in self?.missing.append($0) },
                                          makeKey: { [weak self] in let key = UUID(); self?.keys.append(key); return key },
                                          waitUntil: { _ in })
    }
    var receiptText: String? { receipts.current?.text }
    var receiptButton: String? { receipts.current?.action?.title }
    func tapReceipt() async {
        guard let receipt = receipts.current else { return }
        receipts.performAction(id: receipt.id)
        await refreshSettle { !self.refresher.isRunning(1) }
    }
}

@MainActor private func refreshSettle(_ done: @MainActor () -> Bool) async {
    var spins = 0
    while !done(), spins < 10_000 { await Task.yield(); spins += 1 }
}

@MainActor @Test func refreshCarriesKeyOnlyWithIdempotentWrites() async {
    let keyed = RefreshHarness()
    #expect(await keyed.refresher.refresh(oauthAccount()) == .refreshed)
    #expect(keyed.source.calls == [.init(id: 1, key: keyed.keys.first, generation: keyed.source.generation)])
    #expect(keyed.keys.count == 1 && keyed.refresher.inFlight.isEmpty)
    let unkeyed = RefreshHarness(ScriptedRefreshSource(idempotentWrites: false))
    #expect(await unkeyed.refresher.refresh(oauthAccount()) == .refreshed)
    #expect(unkeyed.source.calls.map(\.key) == [nil] && unkeyed.keys.isEmpty)
}

@MainActor @Test func refreshSuccessAppliesAccountAndShowsReceipt() async {
    let h = RefreshHarness()
    await h.refresher.refresh(oauthAccount(expiresAt: "2026-10-24T09:00:00Z"))
    #expect(h.changed.map(\.tokenStatus?.expiresAt) == ["2026-10-24T10:00:00Z"])
    #expect(h.receiptText == "已刷新令牌 · 新令牌 18:00 到期")
    #expect(h.receiptButton == nil && h.receipts.current?.tone == .ok)
}

@MainActor @Test func refreshWarningReceipt() async {
    let source = ScriptedRefreshSource()
    source.refreshReplies = [.success(AccountRefreshResult(account: oauthAccount(), warning: AccountRefreshResult.missingProjectIDWarning))]
    let h = RefreshHarness(source)
    await h.refresher.refresh(oauthAccount())
    #expect(h.receiptText == "已刷新令牌，project_id 暂未取到（会自动重试）")
    #expect(h.changed.count == 1)
}

@MainActor @Test func refreshBusinessFailureShowsReasonWithoutRetry() async {
    let source = ScriptedRefreshSource()
    source.refreshReplies = [.failure(APIError.server(status: 400, reason: "SPARK_SHADOW_NO_REFRESH"))]
    let h = RefreshHarness(source)
    #expect(await h.refresher.refresh(oauthAccount()) == .failed)
    #expect(h.receiptText == "刷新令牌没有成功：影子账号的凭据跟随母账号，请刷新母账号的令牌")
    #expect(h.receipts.current?.tone == .critical && h.receiptButton == nil)
    #expect(h.changed.isEmpty && source.reads == 0)
}

@MainActor @Test func keyedUnknownRefreshConfirmedByReadBack() async {
    let source = ScriptedRefreshSource()
    source.refreshReplies = [.failure(refreshUnconfirmed)]
    // refreshed_at is stored in whole seconds and may trail the App's clock a little.
    source.readReplies = [.success(VersionedAccount(account: oauthAccount(refreshedAt: -1), etag: nil))]
    let h = RefreshHarness(source)
    #expect(await h.refresher.refresh(oauthAccount()) == .refreshed)
    #expect(h.receiptText == "已刷新令牌 · 新令牌 18:00 到期")
    #expect(source.calls.count == 1 && source.reads == 1 && h.changed.count == 1)
}

@MainActor @Test func keyedUnknownRefreshOffersRetryWithSameKey() async {
    let source = ScriptedRefreshSource()
    source.refreshReplies = [.failure(refreshUnconfirmed)]
    source.readReplies = [.success(VersionedAccount(account: oauthAccount(refreshedAt: -3_600), etag: nil))]
    let h = RefreshHarness(source)
    #expect(await h.refresher.refresh(oauthAccount()) == .unconfirmed)
    #expect(h.receiptText == "刷新令牌结果未确认，可用同一编号重试" && h.receiptButton == "重试")
    #expect(h.changed.count == 1)
    await h.tapReceipt()
    #expect(source.calls.count == 2 && source.calls[0].key == source.calls[1].key && source.calls[1].key != nil)
    #expect(h.receiptText == "已刷新令牌 · 新令牌 18:00 到期")
}

/// 00 §2.4: an unkeyed write is never sent again by itself; 重试 waits for the user and still carries no key.
@MainActor @Test func unkeyedLostRefreshWaitsForUserRetry() async {
    let source = ScriptedRefreshSource(idempotentWrites: false)
    source.refreshReplies = [.failure(refreshTransportError)]
    source.readReplies = [.success(VersionedAccount(account: oauthAccount(refreshedAt: -3_600), etag: nil))]
    let h = RefreshHarness(source)
    #expect(await h.refresher.refresh(oauthAccount()) == .notApplied)
    #expect(h.receiptText == "刷新令牌没有生效，可以重试" && h.receiptButton == "重试")
    #expect(source.calls.count == 1)
    await h.tapReceipt()
    #expect(source.calls.map(\.key) == [nil, nil])
}

@MainActor @Test func refreshReadBackFailureOrUnknownShowsUnconfirmed() async {
    let failing = ScriptedRefreshSource(idempotentWrites: false)
    failing.refreshReplies = [.failure(refreshTransportError)]
    failing.readReplies = [.failure(refreshTransportError)]
    let h = RefreshHarness(failing)
    #expect(await h.refresher.refresh(oauthAccount()) == .unconfirmed)
    #expect(h.receiptText == AccountActionCopy.unconfirmed && h.receiptButton == nil)
    // A server without token_status cannot tell either.
    let old = ScriptedRefreshSource(idempotentWrites: false)
    old.refreshReplies = [.failure(refreshTransportError)]
    old.readReplies = [.success(VersionedAccount(account: oauthAccount(hasStatus: false), etag: nil))]
    let legacy = RefreshHarness(old)
    #expect(await legacy.refresher.refresh(oauthAccount()) == .unconfirmed)
    #expect(legacy.receiptText == AccountActionCopy.unconfirmed && legacy.receiptButton == nil)
}

@MainActor @Test func refreshPlainNotFoundCallsOnMissing() async {
    let source = ScriptedRefreshSource()
    source.refreshReplies = [.failure(APIError.server(status: 404, reason: nil))]
    let h = RefreshHarness(source)
    #expect(await h.refresher.refresh(oauthAccount()) == .missing)
    #expect(h.missing == [1])
    #expect(h.receiptText == "刷新令牌没有成功：这个账号已删除或不在本工作区")
}

@MainActor @Test func refreshAfterSessionChangeIsDropped() async {
    let source = ScriptedRefreshSource()
    let gate = SessionGate()
    source.gate = gate
    let h = RefreshHarness(source)
    let running = Task { await h.refresher.refresh(oauthAccount()) }
    await refreshSettle { !source.calls.isEmpty }
    #expect(h.refresher.isRunning(1))
    // A second tap while it runs sends nothing.
    #expect(await h.refresher.refresh(oauthAccount()) == .ignored)
    source.switchSession()
    await gate.open()
    #expect(await running.value == .ignored)
    #expect(source.calls.count == 1 && h.receiptText == nil && h.changed.isEmpty)
}

@MainActor @Test func refreshWithReadOnlyTokenSendsNothing() async {
    let source = ScriptedRefreshSource(readOnly: true)
    let h = RefreshHarness(source)
    #expect(await h.refresher.refresh(oauthAccount()) == .failed)
    #expect(source.calls.isEmpty && h.receiptText == AccountActionCopy.readOnly.text)
}
