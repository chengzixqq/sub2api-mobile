import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private let transportError = APIError(kind: .transport, message: "连接超时")
private let siteDown = APIError.server(status: 500, reason: nil)
private let gone = APIError.server(status: 404, reason: AccountWriteReason.notFound)

private func fallen(originName: String? = "hk-01") -> UpstreamAccount {
    UpstreamAccount(id: 9, name: "Kimi-01", platform: "kimi", type: "apikey", proxy: AccountProxy(id: 1, name: "hk-02"), proxyID: 1,
                    proxyFallbackOriginID: 4, proxyFallbackOriginName: originName)
}
private func revertedAccount() -> UpstreamAccount {
    UpstreamAccount(id: 9, name: "Kimi-01", platform: "kimi", type: "apikey", proxy: AccountProxy(id: 4, name: "hk-01"), proxyID: 4)
}
private let grok = UpstreamAccount(id: 10, name: "Grok-旧-01", platform: "grok", type: "apikey", status: "inactive")

/// Records each call with the generation it carried and answers from per-call scripts; an empty script answers like a server
/// that ran the write. `afterWrite` runs before a write answers (a session switch meanwhile).
@MainActor private final class DetailSource: AccountDetailWriteSource {
    enum Call: Equatable { case read(Int), revert(Int, UUID), delete(Int, UUID) }
    private(set) var session: AccountWriteSession?
    private(set) var calls: [Call] = []
    var readReplies: [Result<VersionedAccount, any Error>] = []
    var revertReplies: [Result<Void, any Error>] = []
    var deleteReplies: [Result<DeleteResult, any Error>] = []
    var afterWrite: (@MainActor () -> Void)?

    init(readOnly: Bool = false) {
        session = AccountWriteSession(generation: UUID(), idempotentWrites: true, recoverSchedulable: true, patch: true, isReadOnlyToken: readOnly)
    }
    var generation: UUID { session?.generation ?? UUID() }
    func switchSession() {
        session = AccountWriteSession(generation: UUID(), idempotentWrites: true, recoverSchedulable: true, patch: true, isReadOnlyToken: false)
    }
    var reverts: Int { calls.filter { if case .revert = $0 { true } else { false } }.count }
    var deletes: Int { calls.filter { if case .delete = $0 { true } else { false } }.count }
    var reads: Int { calls.filter { if case .read = $0 { true } else { false } }.count }

    var accountWriteSession: AccountWriteSession? { session }
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        calls.append(.read(id))
        return try Self.next(&readReplies) ?? VersionedAccount(account: revertedAccount(), etag: "\"cv-3\"")
    }
    func revertAccountProxyFallback(id: Int, generation: UUID) async throws {
        calls.append(.revert(id, generation))
        guard generation == session?.generation else { throw CancellationError() }
        _ = try Self.next(&revertReplies)
        afterWrite?()
    }
    func deleteAccount(id: Int, generation: UUID) async throws -> DeleteResult {
        calls.append(.delete(id, generation))
        guard generation == session?.generation else { throw CancellationError() }
        let reply = try Self.next(&deleteReplies) ?? .deleted
        afterWrite?()
        return reply
    }
    private static func next<T>(_ script: inout [Result<T, any Error>]) throws -> T? {
        guard !script.isEmpty else { return nil }
        return try script.removeFirst().get()
    }
}

/// One AccountProxyRevert with its receipts (they stay up: the timer sleeps for an hour) and what it reported.
@MainActor private final class RevertHarness {
    let source: DetailSource
    let receipts = ReceiptCenter(sleep: { try await Task.sleep(for: $0 * 1_000) })
    private(set) var accounts: [VersionedAccount] = []
    private(set) var stale = 0
    private(set) var listChanges = 0
    private(set) var origins: [Int] = []
    private(set) var revert: AccountProxyRevert!

    init(_ source: DetailSource = DetailSource()) {
        self.source = source
        revert = AccountProxyRevert(source: source, receipts: receipts, onAccount: { [weak self] in self?.accounts.append($0) },
                                    onStale: { [weak self] in self?.stale += 1 }, onListChanged: { [weak self] in self?.listChanges += 1 })
    }
    func run(_ account: UpstreamAccount) async -> AccountProxyRevertOutcome {
        await revert.revert(account, openOrigin: { [weak self] in self?.origins.append($0) })
    }
    var text: String? { receipts.current?.text }
    var button: String? { receipts.current?.action?.title }
    func tapButton() async {
        guard let id = receipts.current?.id else { return }
        receipts.performAction(id: id)
        for _ in 0..<100 { await Task.yield() }
    }
}

// MARK: - 恢复原代理

@MainActor @Test func revertSuccessReadsBackWithoutUndo() async {
    let harness = RevertHarness()
    var running: Int?
    harness.source.afterWrite = { running = harness.revert.runningAccountID }
    #expect(await harness.run(fallen()) == .reverted)
    #expect(running == 9 && harness.revert.runningAccountID == nil && !harness.revert.isRunning)
    #expect(harness.source.calls == [.revert(9, harness.source.generation), .read(9)])
    #expect(harness.accounts.map(\.account.proxyID) == [4] && harness.accounts.first?.etag == "\"cv-3\"")
    #expect(harness.listChanges == 1 && harness.stale == 0)
    #expect(harness.text == "已恢复原代理「hk-01」" && harness.button == nil)
}

@MainActor @Test func revertSuccessWhenReadBackFails() async {
    let harness = RevertHarness()
    harness.source.readReplies = [.failure(transportError)]
    #expect(await harness.run(fallen(originName: nil)) == .reverted)
    #expect(harness.text == "已恢复原代理「#4」" && harness.button == nil)
    #expect(harness.stale == 1 && harness.accounts.isEmpty && harness.listChanges == 1)
}

@MainActor @Test func notInFallbackRefreshes() async {
    let harness = RevertHarness()
    harness.source.revertReplies = [.failure(APIError.server(status: 400, reason: AccountWriteReason.notInFallback))]
    #expect(await harness.run(fallen()) == .notInFallback)
    #expect(harness.source.reverts == 1 && harness.source.reads == 1 && harness.accounts.count == 1)
    #expect(harness.text == "这个账号已不在回退状态" && harness.button == nil && harness.listChanges == 1)
}

@MainActor @Test func originUnavailableOffersOriginDetail() async {
    let harness = RevertHarness()
    harness.source.revertReplies = [.failure(APIError.server(status: 409, reason: AccountWriteReason.fallbackOriginUnavailable))]
    #expect(await harness.run(fallen()) == .originUnavailable)
    #expect(harness.source.reads == 0)
    #expect(harness.text == "原代理已删除、停用或过期，续期并启用后才能恢复" && harness.button == "查看原代理")
    await harness.tapButton()
    #expect(harness.origins == [4] && harness.source.reverts == 1)
}

@MainActor @Test func missingAccountMarksStale() async {
    let harness = RevertHarness()
    harness.source.revertReplies = [.failure(gone)]
    #expect(await harness.run(fallen()) == .missing)
    #expect(harness.stale == 1 && harness.text == "恢复原代理没有成功：这个账号已删除或不在本工作区")
}

@MainActor @Test func timeoutReadsBackNeverResends() async {
    let applied = RevertHarness()
    applied.source.revertReplies = [.failure(transportError)]
    #expect(await applied.run(fallen()) == .reverted)
    #expect(applied.source.reverts == 1 && applied.text == "已恢复原代理「hk-01」" && applied.accounts.count == 1)

    let notYet = RevertHarness()
    notYet.source.revertReplies = [.failure(transportError)]
    notYet.source.readReplies = [.success(VersionedAccount(account: fallen(), etag: "\"cv-2\""))]
    #expect(await notYet.run(fallen()) == .unconfirmed)
    #expect(notYet.accounts.map(\.account.proxyFallbackOriginID) == [4])
    #expect(notYet.text == "恢复原代理结果未确认" && notYet.button == "重试" && notYet.source.reverts == 1)
    await notYet.tapButton()
    #expect(notYet.source.reverts == 2 && notYet.text == "已恢复原代理「hk-01」")

    let unread = RevertHarness()
    unread.source.revertReplies = [.failure(transportError)]
    unread.source.readReplies = [.failure(transportError)]
    #expect(await unread.run(fallen()) == .unconfirmed)
    #expect(unread.text == "恢复原代理结果未确认" && unread.button == "重试" && unread.source.reverts == 1)
}

@MainActor @Test func otherRevertFailuresAndGuards() async {
    let failed = RevertHarness()
    failed.source.revertReplies = [.failure(siteDown)]
    #expect(await failed.run(fallen()) == .failed)
    #expect(failed.text == "恢复原代理没有成功：\(AccountActionCopy.reason(for: siteDown))" && failed.source.reads == 0)

    let plain = RevertHarness()
    #expect(await plain.run(revertedAccount()) == .ignored)
    #expect(plain.source.calls.isEmpty && plain.text == nil)

    let readOnly = RevertHarness(DetailSource(readOnly: true))
    #expect(await readOnly.run(fallen()) == .failed)
    #expect(readOnly.source.calls.isEmpty && readOnly.text == AccountActionCopy.readOnly.text)

    let switched = RevertHarness()
    switched.source.afterWrite = { switched.source.switchSession() }
    #expect(await switched.run(fallen()) == .ignored)
    #expect(switched.text == nil && switched.listChanges == 0 && switched.accounts.isEmpty)

    let cancelled = RevertHarness()
    cancelled.source.revertReplies = [.failure(CancellationError())]
    #expect(await cancelled.run(fallen()) == .ignored)
    #expect(cancelled.text == nil)
}

// MARK: - 删除

@MainActor private final class DeleteHarness {
    let source: DetailSource
    let receipts = ReceiptCenter(sleep: { try await Task.sleep(for: $0 * 1_000) })
    private(set) var flow: AccountDeleteFlow!
    private(set) var deletedCalls = 0
    private(set) var receiptWhenDeleted: String??

    init(_ source: DetailSource = DetailSource()) {
        self.source = source
        flow = AccountDeleteFlow(source: source, receipts: receipts)
    }
    func delete(_ account: UpstreamAccount = grok) async -> AccountDeleteOutcome {
        await flow.delete(account) { [weak self] in
            guard let self else { return }
            self.deletedCalls += 1
            self.receiptWhenDeleted = .some(self.receipts.current?.text)
        }
    }
    var text: String? { receipts.current?.text }
}

@MainActor @Test func deleteSuccessPopsBeforeReceipt() async {
    for reply in [DeleteResult.deleted, .alreadyGone] {
        let harness = DeleteHarness()
        harness.source.deleteReplies = [.success(reply)]
        #expect(await harness.delete() == .deleted)
        #expect(harness.deletedCalls == 1 && harness.receiptWhenDeleted == .some(nil))
        #expect(harness.text == "已删除账号「Grok-旧-01」" && harness.source.deletes == 1)
    }
}

@MainActor @Test func deleteFailuresAndReadBack() async {
    let failed = DeleteHarness()
    failed.source.deleteReplies = [.failure(siteDown)]
    #expect(await failed.delete() == .failed)
    #expect(failed.deletedCalls == 0 && failed.source.reads == 0)
    #expect(failed.text == "删除没有成功：\(AccountActionCopy.reason(for: siteDown))")

    let goneOnRead = DeleteHarness()
    goneOnRead.source.deleteReplies = [.failure(transportError)]
    goneOnRead.source.readReplies = [.failure(gone)]
    #expect(await goneOnRead.delete() == .deleted)
    #expect(goneOnRead.deletedCalls == 1 && goneOnRead.text == "已删除账号「Grok-旧-01」")

    let stillThere = DeleteHarness()
    stillThere.source.deleteReplies = [.failure(transportError)]
    stillThere.source.readReplies = [.success(VersionedAccount(account: grok, etag: nil))]
    #expect(await stillThere.delete() == .failed)
    #expect(stillThere.deletedCalls == 0 && stillThere.text == "删除没有成功：\(AccountActionCopy.reason(for: transportError))")

    let unread = DeleteHarness()
    unread.source.deleteReplies = [.failure(transportError)]
    unread.source.readReplies = [.failure(transportError)]
    #expect(await unread.delete() == .unconfirmed)
    #expect(unread.text == "删除结果未确认，请刷新核对后再操作")
    for harness in [failed, goneOnRead, stillThere, unread] { #expect(harness.source.deletes == 1) }

    let switched = DeleteHarness()
    switched.source.afterWrite = { switched.source.switchSession() }
    #expect(await switched.delete() == .ignored)
    #expect(switched.deletedCalls == 0 && switched.text == nil)

    let readOnly = DeleteHarness(DetailSource(readOnly: true))
    #expect(await readOnly.delete() == .failed)
    #expect(readOnly.source.calls.isEmpty && readOnly.text == AccountActionCopy.readOnly.text)
}

@MainActor @Test func deletionCopyAndListSignal() {
    #expect(AccountDeletionCopy.failed(reason: "X") == "删除没有成功：X")
    #expect(AccountDeletionCopy.deleted(name: "Grok-旧-01") == "已删除账号「Grok-旧-01」")
    #expect(DeleteConfirmationCopy.siteLine(siteName: "站点 A") == "站点 站点 A · 删除后不能恢复。")
    let signal = AccountListSignal(), other = AccountListSignal()
    #expect(signal.revision == 0)
    signal.bump(); signal.bump()
    #expect(signal.revision == 2 && other.revision == 0)
}
