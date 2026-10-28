import Foundation
import Observation
import Sub2Core

/// 60 §8.4 / §9.4 writes of one code: `updateRedeemCodes`, `deleteRedeemCode` and the read-back `redeemCode(id:)`, or the
/// UI-test fixtures (RedeemFixtures).
struct RedeemWriteSource: Sendable {
    let update: @Sendable (_ ids: [Int], _ fields: RedeemBatchUpdateFields) async throws -> Int
    let delete: @Sendable (_ id: Int) async throws -> RedeemDeleteResult
    let code: @Sendable (_ id: Int) async throws -> AdminRedeemCode

    static func live(_ client: APIClient) -> RedeemWriteSource {
        RedeemWriteSource(update: { try await client.updateRedeemCodes(ids: $0, fields: $1) },
                          delete: { try await client.deleteRedeemCode(id: $0) }, code: { try await client.redeemCode(id: $0) })
    }
}

/// The list the writes show on (S6-04's RedeemCodesModel, S6D1-05): a card changed, gone or read again, and the counts.
@MainActor protocol RedeemCodeWritesHost: AnyObject {
    var generation: UUID { get }
    func replaceLocally(_ code: AdminRedeemCode)
    func removeLocally(id: Int)
    func refreshCard(id: Int) async
    func refreshStats() async
}

/// How a save of the edit sheet ended; the sheet closes on `saved` and `gone`.
enum RedeemSaveOutcome: Equatable, Sendable { case saved, switchedToNotesOnly, rejected(String), unconfirmed, gone, ignored }

/// 禁用 / 启用 (optimistic, with 撤销), 删除 and the edit sheet's save for one list. Absolute values without a key, so nothing is
/// resent on its own: a lost reply is read back once (00 §2.4). One write per code at a time; replies after the session ended
/// are dropped, and a list of another session is never touched. Without a list (`.redeemEdit(id:)`) `onChange` tells the
/// shown list to read again.
@MainActor @Observable
final class RedeemCodeWrites {
    private(set) var inFlight: Set<Int> = []
    @ObservationIgnored weak var host: (any RedeemCodeWritesHost)?

    @ObservationIgnored private let source: RedeemWriteSource
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let generation: UUID
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Receipts name a time the administrator picked: the phone's zone (00 §6.3).
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let onChange: @MainActor () -> Void

    init(source: RedeemWriteSource, receipts: ReceiptCenter, generation: UUID, isCurrent: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date = { Date() }, timeZone: TimeZone = .current, onChange: @escaping @MainActor () -> Void = {}) {
        self.source = source; self.receipts = receipts; self.generation = generation; self.isCurrent = isCurrent
        self.now = now; self.timeZone = timeZone; self.onChange = onChange
    }

    func isRunning(_ id: Int) -> Bool { inFlight.contains(id) }

    // MARK: - 禁用 / 启用

    /// An unused code is disabled, a disabled one enabled; others are left alone.
    func toggleStatus(_ code: AdminRedeemCode) async {
        guard !code.isRedeemed, let target = Self.toggled(code.codeStatus) else { return }
        await setStatus(code, to: target, isUndo: false)
    }

    private static func toggled(_ status: RedeemCodeStatus?) -> RedeemBatchUpdateFields.Status? {
        switch status {
        case .unused?: .disabled
        case .disabled?: .unused
        case .used?, .expired?, nil: nil
        }
    }

    private func setStatus(_ code: AdminRedeemCode, to target: RedeemBatchUpdateFields.Status, isUndo: Bool) async {
        guard begin(code.id) else { return }
        let changed = code.replacing(status: target.rawValue)
        list?.replaceLocally(changed)
        let result = await send(RedeemBatchUpdateFields(status: target), id: code.id)
        // 撤销 may be tapped while the card and the counts are read again.
        inFlight.remove(code.id)
        switch result {
        case .ignored: return
        case .applied(let fresh):
            if let fresh { list?.replaceLocally(fresh) }
            if !isUndo { receipts.show(toggleReceipt(target, undo: changed, to: code.status)) }
            await refresh(code.id)
        case .failed(let failure):
            if failure != .gone { list?.replaceLocally(code) }
            await toggleFailed(failure, id: code.id)
        }
    }
    /// 撤销 writes the old status back; done says nothing more, the badge shows it (as 归档's undo).
    private func toggleReceipt(_ target: RedeemBatchUpdateFields.Status, undo changed: AdminRedeemCode, to old: String) -> Receipt {
        var undo: (@MainActor @Sendable () -> Void)?
        if let previous = RedeemBatchUpdateFields.Status(rawValue: old) {
            undo = { Task { await self.setStatus(changed, to: previous, isUndo: true) } }
        }
        return target == .disabled
            ? Receipt(text: RedeemEditCopy.disabled, systemImage: "minus.circle", tone: .neutral, undo: undo)
            : Receipt(text: RedeemEditCopy.enabled, systemImage: "checkmark.circle", undo: undo)
    }
    private func toggleFailed(_ failure: RedeemWriteFailure, id: Int) async {
        switch failure {
        case .cancelled: return
        case .used:
            warn(RedeemEditCopy.toggleUsed)
            await list?.refreshCard(id: id)
        case .gone: await gone(id)
        case .unconfirmed:
            caution(RedeemEditCopy.unconfirmed)
            await list?.refreshCard(id: id)
        case .reconfirm(let notice): caution(notice)
        case .expiresAtInvalid, .groupInvalid, .other: warn(failure.message)
        }
    }

    // MARK: - 删除

    /// After the delete confirmation (60 §0.4): deleted or already gone (404) → the card leaves with “已删除兑换码「····d4e8」”
    /// and the counts are read again; no undo.
    func delete(_ code: AdminRedeemCode) async {
        guard begin(code.id) else { return }
        defer { inFlight.remove(code.id) }
        var failure: RedeemWriteFailure?
        do { _ = try await source.delete(code.id) } catch { failure = RedeemWriteFailure.classify(error) }
        guard isCurrent() else { return }
        switch failure {
        case nil, .gone?: await deleted(code)
        case .unconfirmed?: await readBackDeleted(code)
        case .used?:
            warn(RedeemEditCopy.deleteUsed)
            await list?.refreshCard(id: code.id)
        case .cancelled?: return
        case .reconfirm(let notice)?: caution(notice)
        case .expiresAtInvalid?, .groupInvalid?, .other?: warn(failure?.message ?? "")
        }
    }
    /// A DELETE without an answer: a 404 now means it went through; still there or unreadable stays unconfirmed.
    private func readBackDeleted(_ code: AdminRedeemCode) async {
        do {
            _ = try await source.code(code.id)
            guard isCurrent() else { return }
            caution(RedeemEditCopy.unconfirmed)
            await list?.refreshCard(id: code.id)
        } catch {
            guard isCurrent() else { return }
            if RedeemWriteFailure.classify(error) == .gone { return await deleted(code) }
            caution(RedeemEditCopy.unconfirmed)
        }
    }
    private func deleted(_ code: AdminRedeemCode) async {
        list?.removeLocally(id: code.id)
        let text = DeleteConfirmationCopy.deletedReceipt(objectNoun: RedeemEditCopy.objectNoun, displayName: RedeemPresentation.deleteSubject(code.code))
        receipts.show(Receipt(text: text, systemImage: "trash"))
        await refreshStats()
    }

    // MARK: - 保存

    /// 60 §9.4: only the changed keys. Saved → its receipt, the card and the counts read again; 409 leaves the sheet open in
    /// notes-only mode; a lost reply that reads back as sent counts as saved.
    func save(_ draft: RedeemEditDraft) async -> RedeemSaveOutcome {
        let id = draft.original.id, fields = draft.fields(now: now())
        guard !fields.isEmpty, begin(id) else { return .ignored }
        let result = await send(fields, id: id)
        inFlight.remove(id)
        switch result {
        case .ignored: return .ignored
        case .applied(let fresh):
            if let fresh { list?.replaceLocally(fresh) }
            receipts.show(Receipt(text: draft.successReceipt(for: fields, now: now(), timeZone: timeZone)))
            await refresh(id)
            return .saved
        case .failed(let failure):
            return await saveFailed(failure, id: id)
        }
    }
    private func saveFailed(_ failure: RedeemWriteFailure, id: Int) async -> RedeemSaveOutcome {
        switch failure {
        case .cancelled: return .ignored
        case .used:
            await list?.refreshCard(id: id)
            return .switchedToNotesOnly
        case .gone:
            await gone(id)
            return .gone
        case .unconfirmed: return .unconfirmed
        case .expiresAtInvalid, .groupInvalid, .reconfirm, .other: return .rejected(failure.message)
        }
    }

    // MARK: - Sending

    private enum SendResult { case applied(AdminRedeemCode?), failed(RedeemWriteFailure), ignored }

    /// Once; an unanswered write reads the code back and counts as done only when every key sent is there.
    private func send(_ fields: RedeemBatchUpdateFields, id: Int) async -> SendResult {
        do {
            _ = try await source.update([id], fields)
            return isCurrent() ? .applied(nil) : .ignored
        } catch {
            guard isCurrent() else { return .ignored }
            let failure = RedeemWriteFailure.classify(error)
            guard failure == .unconfirmed else { return .failed(failure) }
            return await readBack(fields, id: id)
        }
    }
    private func readBack(_ fields: RedeemBatchUpdateFields, id: Int) async -> SendResult {
        do {
            let fresh = try await source.code(id)
            guard isCurrent() else { return .ignored }
            return fields.isReflected(in: fresh) ? .applied(fresh) : .failed(.unconfirmed)
        } catch {
            guard isCurrent() else { return .ignored }
            return .failed(RedeemWriteFailure.classify(error) == .gone ? .gone : .unconfirmed)
        }
    }

    // MARK: - Helpers

    /// The list of this session only.
    private var list: (any RedeemCodeWritesHost)? { host.flatMap { $0.generation == generation ? $0 : nil } }
    private func begin(_ id: Int) -> Bool {
        guard !inFlight.contains(id), isCurrent() else { return false }
        inFlight.insert(id)
        return true
    }
    /// 8.6: after a write only that card and the counts.
    private func refresh(_ id: Int) async {
        guard let list else { return onChange() }
        await list.refreshCard(id: id)
        await list.refreshStats()
    }
    private func refreshStats() async {
        guard let list else { return onChange() }
        await list.refreshStats()
    }
    private func gone(_ id: Int) async {
        list?.removeLocally(id: id)
        receipts.show(Receipt(text: RedeemEditCopy.gone, systemImage: "trash", tone: .neutral))
        await refreshStats()
    }
    private func warn(_ text: String) { receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .critical)) }
    private func caution(_ text: String) { receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .caution)) }
}
