import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private let transportError = APIError(kind: .transport, message: "连接超时")
private let siteDown = APIError.server(status: 500, reason: nil)
private let mixedMetadata = ["group_id": "1", "group_name": "高级组", "current_platform": "Anthropic", "other_platform": "Antigravity"]

private func account(name: String = "主力", notes: String? = nil, groups: [Int] = []) -> UpstreamAccount {
    UpstreamAccount(id: 4, name: name, platform: "anthropic", type: "apikey", notes: notes, groupIDs: groups)
}
private func versioned(_ account: UpstreamAccount, _ etag: String?) -> VersionedAccount { VersionedAccount(account: account, etag: etag) }
private func conflict(_ etag: String) -> APIError {
    APIError.server(status: 412, envelope: ErrorEnvelope(reason: "ACCOUNT_VERSION_CONFLICT", metadata: ["current_etag": etag]))
}
private func change(_ request: AccountPatchRequest, names: [String] = ["名称"], undo: AccountPatchRequest? = AccountPatchRequest(name: "主力")) -> AccountEditChange {
    AccountEditChange(fieldNames: names, request: request, undo: undo)
}
private let base = AccountEditBase(account: account(), etag: "\"cv-3\"")
private let rename = change(AccountPatchRequest(name: "新名"))

/// Records each call with the generation it carried and answers from per-call scripts; an empty script answers like a server
/// that applied the write. `afterWrite` runs before a write answers (a session switch meanwhile).
@MainActor private final class PatchSource: AccountPatchSource {
    enum Call: Equatable {
        case read
        case patch(body: String, ifMatch: String, generation: UUID)
        case put(body: String, key: UUID?, generation: UUID)
        case check(groupIDs: [Int], generation: UUID)
    }
    private(set) var session: AccountWriteSession?
    var hasMixedChannelDetails = true
    private(set) var calls: [Call] = []
    var readReplies: [Result<VersionedAccount, any Error>] = []
    var patchReplies: [Result<VersionedAccount, any Error>] = []
    var putReplies: [Result<UpstreamAccount, any Error>] = []
    var checkReplies: [Result<MixedChannelCheck, any Error>] = []
    var afterWrite: (@MainActor () -> Void)?

    init(patch: Bool = true, idempotentWrites: Bool = true, readOnly: Bool = false) {
        session = AccountWriteSession(generation: UUID(), idempotentWrites: idempotentWrites, recoverSchedulable: true, patch: patch,
                                      isReadOnlyToken: readOnly)
    }
    var generation: UUID { session?.generation ?? UUID() }
    func switchSession() {
        guard let old = session else { return }
        session = AccountWriteSession(generation: UUID(), idempotentWrites: old.idempotentWrites, recoverSchedulable: true, patch: old.patch,
                                      isReadOnlyToken: old.isReadOnlyToken)
    }
    var writes: [Call] { calls.filter { if case .read = $0 { false } else { true } } }

    var accountWriteSession: AccountWriteSession? { session }
    func serverNow() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
    func recoverAccountState(id: Int, schedulable: Bool?, generation: UUID) async throws -> UpstreamAccount { throw siteDown }
    func setAccountSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID?, generation: UUID) async throws -> WriteOutcome<UpstreamAccount> {
        throw siteDown
    }
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        calls.append(.read)
        return try Self.next(&readReplies) ?? versioned(account(), "\"cv-3\"")
    }
    func patchAccount(id: Int, body: AccountPatchRequest, ifMatch: String, generation: UUID) async throws -> VersionedAccount {
        calls.append(.patch(body: Self.text(body), ifMatch: ifMatch, generation: generation))
        try admit(generation)
        let reply = try Self.next(&patchReplies) ?? versioned(account(name: body.name ?? "主力"), "\"cv-4\"")
        afterWrite?()
        return reply
    }
    func fullUpdateAccount(id: Int, patch: AccountPatchRequest, base: UpstreamAccount?, idempotencyKey: UUID?,
                           generation: UUID) async throws -> UpstreamAccount {
        calls.append(.put(body: Self.text(patch), key: idempotencyKey, generation: generation))
        try admit(generation)
        let reply = try Self.next(&putReplies) ?? account(name: patch.name ?? "主力")
        afterWrite?()
        return reply
    }
    func checkMixedChannel(platform: String, groupIDs: [Int], accountID: Int?, generation: UUID) async throws -> MixedChannelCheck {
        calls.append(.check(groupIDs: groupIDs, generation: generation))
        try admit(generation)
        return try Self.next(&checkReplies) ?? MixedChannelCheck(hasRisk: false)
    }

    private func admit(_ generation: UUID) throws {
        guard generation == session?.generation else { throw CancellationError() }
    }
    private static func next<T>(_ script: inout [Result<T, any Error>]) throws -> T? {
        guard !script.isEmpty else { return nil }
        return try script.removeFirst().get()
    }
    static func text(_ request: AccountPatchRequest) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(request)) ?? Data(), as: UTF8.self)
    }
}

/// One AccountPatchFlow with its receipts (they stay up: the timer sleeps for an hour) and what it reported.
@MainActor private final class Harness {
    let source: PatchSource
    let receipts = ReceiptCenter(sleep: { try await Task.sleep(for: $0 * 1_000) })
    private(set) var changed: [AccountEditBase] = []
    private(set) var removed = 0
    private(set) var reloads = 0
    private(set) var keys: [UUID] = []
    private(set) var flow: AccountPatchFlow!

    init(_ source: PatchSource = PatchSource()) {
        self.source = source
        flow = AccountPatchFlow(source: source, receipts: receipts, accountID: 4, onChange: { [weak self] in self?.changed.append($0) },
                                onRemoved: { [weak self] in self?.removed += 1 }, onReload: { [weak self] in self?.reloads += 1 },
                                makeKey: { [weak self] in let key = UUID(); self?.keys.append(key); return key })
    }
    var receiptText: String? { receipts.current?.text }
    var receiptButton: String? { receipts.current?.action?.title }
    /// Taps the receipt's button and waits until the calls it started have gone out.
    func tapReceipt(expecting calls: Int) async {
        guard let receipt = receipts.current else { return }
        receipts.performAction(id: receipt.id)
        var spins = 0
        while source.calls.count < calls || receipts.current?.id == receipt.id, spins < 10_000 { await Task.yield(); spins += 1 }
        for _ in 0..<50 { await Task.yield() }
    }
}

// MARK: - Saving

@MainActor @Test func savePatchesWithIfMatchAndOffersUndoWithNewETag() async {
    let h = Harness()
    let saved = await h.flow.save(rename, base: base)
    #expect(saved?.etag == "\"cv-4\"" && saved?.account.name == "新名")
    #expect(h.source.calls == [.patch(body: #"{"name":"新名"}"#, ifMatch: "\"cv-3\"", generation: h.source.generation)])
    #expect(h.flow.phase == .idle && h.flow.prompt == nil && h.flow.savedRevision == 1)
    #expect(h.changed.map(\.etag) == ["\"cv-4\""])
    #expect(h.receiptText == "已保存：名称" && h.receiptButton == "撤销")
    await h.tapReceipt(expecting: 2)
    #expect(h.source.calls.last == .patch(body: #"{"name":"主力"}"#, ifMatch: "\"cv-4\"", generation: h.source.generation))
    #expect(h.receipts.current == nil && h.changed.count == 2)
}

@MainActor @Test func customReceiptReplacesTheStandardOne() async {
    let h = Harness()
    await h.flow.save(rename, base: base) { _ in Receipt(text: "已更换 API Key", systemImage: "key") }
    #expect(h.receiptText == "已更换 API Key")
    let quiet = Harness()
    await quiet.flow.save(rename, base: base) { _ in nil }
    #expect(quiet.receipts.current == nil && quiet.flow.savedRevision == 1)
    let noUndo = Harness()
    await noUndo.flow.save(change(AccountPatchRequest(name: "新名"), undo: nil), base: base)
    #expect(noUndo.receiptText == "已保存：名称" && noUndo.receiptButton == nil)
}

@MainActor @Test func patchFlowReadOnlyTokenSendsNothing() async {
    let h = Harness(PatchSource(readOnly: true))
    #expect(await h.flow.save(rename, base: base) == nil)
    #expect(h.source.calls.isEmpty && h.flow.phase == .failed(AccountActionCopy.readOnly.text))
    #expect(h.receipts.current == nil)
}

@MainActor @Test func rejectedPatchSaysReasonAndRemovedAccountLeaves() async {
    let h = Harness()
    h.source.patchReplies = [.failure(APIError.server(status: 400, reason: "INVALID_PATCH"))]
    await h.flow.save(rename, base: base)
    #expect(h.flow.phase == .failed("服务器拒绝了这次修改（INVALID_PATCH）") && h.receipts.current == nil)
    let gone = Harness()
    gone.source.patchReplies = [.failure(APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND"))]
    await gone.flow.save(rename, base: base)
    #expect(gone.removed == 1 && gone.flow.savedRevision == 0)
}

// MARK: - 412

@MainActor @Test func conflictOnUntouchedFieldResendsExactlyOnce() async {
    let h = Harness()
    h.source.patchReplies = [.failure(conflict("\"cv-5\"")), .success(versioned(account(name: "新名", notes: "别人"), "\"cv-6\""))]
    h.source.readReplies = [.success(versioned(account(notes: "别人"), "\"cv-5\""))]
    let saved = await h.flow.save(rename, base: base)
    let generation = h.source.generation
    #expect(h.source.calls == [.patch(body: #"{"name":"新名"}"#, ifMatch: "\"cv-3\"", generation: generation), .read,
                               .patch(body: #"{"name":"新名"}"#, ifMatch: "\"cv-5\"", generation: generation)])
    #expect(saved?.etag == "\"cv-6\"" && h.flow.prompt == nil && h.receiptText == "已保存：名称")
}

@MainActor @Test func secondConflictAfterSilentResendAsks() async {
    let h = Harness()
    h.source.patchReplies = [.failure(conflict("\"cv-5\"")), .failure(conflict("\"cv-6\""))]
    h.source.readReplies = [.success(versioned(account(notes: "别人"), "\"cv-5\"")), .success(versioned(account(notes: "再改"), "\"cv-6\""))]
    await h.flow.save(rename, base: base)
    #expect(h.source.writes.count == 2)
    guard case .overwrite(_, let current, let tag)? = h.flow.prompt else { Issue.record("expected the overwrite question"); return }
    #expect(current?.account.notes == "再改" && tag == "\"cv-6\"")
}

@MainActor @Test func conflictOnSameFieldAsksAndOverwriteSendsNewETag() async {
    let h = Harness()
    h.source.patchReplies = [.failure(conflict("\"cv-5\""))]
    h.source.readReplies = [.success(versioned(account(name: "第三个名字"), "\"cv-5\""))]
    #expect(await h.flow.save(rename, base: base) == nil)
    guard case .overwrite(_, let current, let tag)? = h.flow.prompt else { Issue.record("expected the overwrite question"); return }
    #expect(current?.account.name == "第三个名字" && tag == "\"cv-5\"" && h.flow.phase == .idle)
    #expect(h.changed.map(\.account.name) == ["第三个名字"] && h.receipts.current == nil)
    await h.flow.overwrite()
    #expect(h.source.calls.last == .patch(body: #"{"name":"新名"}"#, ifMatch: "\"cv-5\"", generation: h.source.generation))
    #expect(h.flow.prompt == nil && h.flow.savedRevision == 1 && h.receiptText == "已保存：名称")
}

@MainActor @Test func conflictWithFailedReadUsesMetadataETag() async {
    let h = Harness()
    h.source.patchReplies = [.failure(conflict("\"cv-8\""))]
    h.source.readReplies = [.failure(siteDown)]
    await h.flow.save(rename, base: base)
    guard case .overwrite(_, let current, let tag)? = h.flow.prompt else { Issue.record("expected the overwrite question"); return }
    #expect(current == nil && tag == "\"cv-8\"")
    await h.flow.overwrite()
    #expect(h.source.calls.last == .patch(body: #"{"name":"新名"}"#, ifMatch: "\"cv-8\"", generation: h.source.generation))
}

@MainActor @Test func reloadAfterConflictHandsTheSheetTheServerCopy() async {
    let h = Harness()
    h.source.patchReplies = [.failure(conflict("\"cv-5\""))]
    h.source.readReplies = [.success(versioned(account(name: "第三个名字"), "\"cv-5\""))]
    await h.flow.save(rename, base: base)
    await h.flow.reloadAfterConflict()
    #expect(h.flow.prompt == nil && h.flow.reloadRevision == 1 && h.flow.reloadedBase?.account.name == "第三个名字")
    #expect(h.source.calls.count == 2 && h.flow.phase == .idle)
    let unread = Harness()
    unread.source.patchReplies = [.failure(conflict("\"cv-5\""))]
    unread.source.readReplies = [.failure(siteDown), .success(versioned(account(name: "读到了"), "\"cv-5\""))]
    await unread.flow.save(rename, base: base)
    await unread.flow.reloadAfterConflict()
    #expect(unread.flow.reloadedBase?.etag == "\"cv-5\"" && unread.source.calls.last == .read)
}

// MARK: - Unknown results

@MainActor @Test func timeoutReadBackDecides() async {
    let applied = Harness()
    applied.source.patchReplies = [.failure(transportError)]
    applied.source.readReplies = [.success(versioned(account(name: "新名"), "\"cv-4\""))]
    #expect(await applied.flow.save(rename, base: base)?.etag == "\"cv-4\"")
    #expect(applied.receiptText == "已保存：名称")

    let missed = Harness()
    missed.source.patchReplies = [.failure(transportError)]
    await missed.flow.save(rename, base: base)
    #expect(missed.flow.phase == .notApplied && missed.receipts.current == nil)
    await missed.flow.retry()
    #expect(missed.source.writes == [.patch(body: #"{"name":"新名"}"#, ifMatch: "\"cv-3\"", generation: missed.source.generation),
                                     .patch(body: #"{"name":"新名"}"#, ifMatch: "\"cv-3\"", generation: missed.source.generation)])
    #expect(missed.flow.phase == .idle && missed.flow.savedRevision == 1)

    let unread = Harness()
    unread.source.patchReplies = [.failure(transportError)]
    unread.source.readReplies = [.failure(siteDown), .success(versioned(account(name: "新名"), "\"cv-4\""))]
    await unread.flow.save(rename, base: base)
    #expect(unread.flow.phase == .unconfirmed)
    await unread.flow.recheck()
    #expect(unread.flow.phase == .idle && unread.flow.savedRevision == 1 && unread.source.writes.count == 1)
}

@MainActor @Test func secretReadBackComparesTheVersion() async {
    let secret = change(AccountPatchRequest(credentialsPatch: ["api_key": .set("sk-new")]), names: ["API Key"], undo: nil)
    let same = Harness()
    same.source.patchReplies = [.failure(transportError)]
    same.source.readReplies = [.success(versioned(account(), "\"cv-3\""))]
    await same.flow.save(secret, base: base)
    #expect(same.flow.phase == .notApplied)
    let moved = Harness()
    moved.source.patchReplies = [.failure(transportError)]
    moved.source.readReplies = [.success(versioned(account(), "\"cv-4\""))]
    await moved.flow.save(secret, base: base)
    #expect(moved.flow.phase == .unconfirmed)
}

// MARK: - 409

@MainActor @Test func precheckWithoutDetailsCapabilityAsksBeforeWriting() async {
    let source = PatchSource()
    source.hasMixedChannelDetails = false
    source.checkReplies = [.success(MixedChannelCheck(hasRisk: true, details: .init(groupID: 1, groupName: "高级组", currentPlatform: "Anthropic",
                                                                                   otherPlatform: "Antigravity")))]
    let h = Harness(source)
    await h.flow.save(change(AccountPatchRequest(groupIDs: [1]), names: ["分组"]), base: base)
    #expect(h.source.calls == [.check(groupIDs: [1], generation: source.generation)])
    guard case .mixedChannel(_, let warning)? = h.flow.prompt else { Issue.record("expected the warning"); return }
    #expect(warning.groupName == "高级组")
    await h.flow.confirmMixedChannel()
    #expect(h.source.calls.last == .patch(body: #"{"confirm_mixed_channel_risk":true,"group_ids":[1]}"#, ifMatch: "\"cv-3\"",
                                          generation: source.generation))
    #expect(h.receiptText == "已保存：分组")
}

@MainActor @Test func mixedChannelConflictWithDetailsAsksAndCancelKeepsDraft() async {
    let h = Harness()
    h.source.patchReplies = [.failure(APIError.server(status: 409, envelope: ErrorEnvelope(reason: "MIXED_CHANNEL_WARNING", metadata: mixedMetadata)))]
    await h.flow.save(change(AccountPatchRequest(groupIDs: [1]), names: ["分组"]), base: base)
    guard case .mixedChannel? = h.flow.prompt else { Issue.record("expected the warning"); return }
    #expect(!h.source.calls.contains(.check(groupIDs: [1], generation: h.source.generation)))
    h.flow.dismissPrompt()
    #expect(h.flow.prompt == nil && h.flow.phase == .idle && h.flow.savedRevision == 0)
}

@MainActor @Test func putFallbackKeepsKeyOnRetryAndChangesItForTheConfirmation() async {
    let source = PatchSource(patch: false)
    source.putReplies = [.failure(transportError)]
    source.readReplies = [.success(versioned(account(), nil))]
    let h = Harness(source)
    await h.flow.save(change(AccountPatchRequest(groupIDs: [1]), names: ["分组"]), base: base)
    #expect(h.flow.phase == .notApplied)
    source.putReplies = [.failure(APIError.server(status: 409, envelope: ErrorEnvelope(reason: "MIXED_CHANNEL_WARNING", metadata: mixedMetadata)))]
    await h.flow.retry()
    await h.flow.confirmMixedChannel()
    let first = h.keys.first, second = h.keys.last
    #expect(h.keys.count == 2 && first != second)
    #expect(source.writes == [.put(body: #"{"group_ids":[1]}"#, key: first, generation: source.generation),
                              .put(body: #"{"group_ids":[1]}"#, key: first, generation: source.generation),
                              .put(body: #"{"confirm_mixed_channel_risk":true,"group_ids":[1]}"#, key: second, generation: source.generation)])
}

@MainActor @Test func legacyCredentialsPutNeedsTheWeb() async {
    let source = PatchSource(patch: false)
    source.putReplies = [.failure(APIError(kind: .unsupported, reason: AccountWriteReason.legacyCredentialsPut,
                                           message: AccountWriteReason.legacyCredentialsPutMessage))]
    let h = Harness(source)
    await h.flow.save(change(AccountPatchRequest(credentialsPatch: ["base_url": .set("https://example.invalid")]), names: ["Base URL"]), base: base)
    #expect(h.flow.phase == .needsWeb("这个站点版本过旧，凭据相关设置请在 Web 中修改"))
}

// MARK: - Undo and sessions

@MainActor @Test func undoConflictOffersReload() async {
    let h = Harness()
    await h.flow.save(rename, base: base)
    h.source.patchReplies = [.failure(conflict("\"cv-9\""))]
    await h.tapReceipt(expecting: 2)
    #expect(h.receiptText == "撤销没有成功：账号已被修改" && h.receiptButton == "重新载入")
    #expect(h.source.calls.count == 2)
    await h.tapReceipt(expecting: 2)
    #expect(h.reloads == 1)
}

@MainActor @Test func sessionChangeDropsTheResult() async {
    let h = Harness()
    h.source.afterWrite = { [weak source = h.source] in source?.switchSession() }
    #expect(await h.flow.save(rename, base: base) == nil)
    #expect(h.changed.isEmpty && h.receipts.current == nil && h.flow.savedRevision == 0 && h.flow.phase == .idle)
}

@MainActor @Test func undoAfterSessionChangeSendsNothing() async {
    let h = Harness()
    await h.flow.save(rename, base: base)
    let old = h.source.generation
    h.source.switchSession()
    await h.tapReceipt(expecting: 1)
    #expect(h.source.calls.count == 1 && h.receipts.current == nil && h.changed.count == 1)
    #expect(h.source.calls.first == .patch(body: #"{"name":"新名"}"#, ifMatch: "\"cv-3\"", generation: old))
}
