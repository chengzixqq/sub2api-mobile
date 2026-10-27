import Foundation
import Observation
import Sub2Core

/// The detail's reads and writes (60 §16.2, §16.4): the site, or under `-ui-testing` this session's AnnouncementDemoStore.
struct AnnouncementDetailSource: Sendable {
    let load: @Sendable (_ id: Int, _ includeReadStats: Bool) async throws -> Announcement
    let summary: @Sendable (_ id: Int) async throws -> AnnouncementReadSummary
    let update: @Sendable (_ id: Int, _ request: AnnouncementUpdateRequest) async throws -> Announcement
    let delete: @Sendable (_ id: Int) async throws -> AnnouncementDeleteResult

    static func live(_ client: APIClient) -> AnnouncementDetailSource {
        AnnouncementDetailSource(load: { try await client.announcement(id: $0, includeReadStats: $1) },
                                 summary: { try await client.announcementReadSummary(id: $0) },
                                 update: { try await client.updateAnnouncement(id: $0, $1) },
                                 delete: { try await client.deleteAnnouncement(id: $0) })
    }
}

/// 60 §16: one announcement and its read summary, published, archived (with 撤销) or deleted from here. Reads on entry, on pull,
/// on return to the foreground, after its own writes and after other pages' writes (`noteRevision`); never polls. PUT and DELETE
/// carry no key and are never resent: a lost reply is read back (00 §2.4). Results for an older load or session are dropped.
@MainActor @Observable
final class AnnouncementDetailModel {
    enum PublishResult: Equatable, Sendable { case done, reconfirm, failed }

    let id: Int
    let readStatsEnabled: Bool
    private(set) var detail: BlockState<Announcement> = .idle
    private(set) var summary: BlockState<AnnouncementReadSummary> = .idle
    /// 404 on entry or on a write: the “已删除” page.
    private(set) var isGone = false
    private(set) var inFlight: AnnouncementDetailAction?
    private(set) var isDeleting = false

    @ObservationIgnored private let source: AnnouncementDetailSource
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let signal: AnnouncementChangeSignal
    @ObservationIgnored private let isCurrent: @MainActor @Sendable () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Changes with every load and applied write; a reply carrying an older one is dropped.
    @ObservationIgnored private var ticket = UUID()
    /// The signal's revision this detail has read or written itself.
    @ObservationIgnored private var appliedRevision: Int

    init(id: Int, source: AnnouncementDetailSource, readStatsEnabled: Bool, receipts: ReceiptCenter, signal: AnnouncementChangeSignal,
         isCurrent: @escaping @MainActor @Sendable () -> Bool, now: @escaping @MainActor () -> Date = { Date() }) {
        self.id = id; self.source = source; self.readStatsEnabled = readStatsEnabled; self.receipts = receipts; self.signal = signal
        self.isCurrent = isCurrent; self.now = now
        appliedRevision = signal.revision
    }

    var announcement: Announcement? { detail.value }
    var isBusy: Bool { inFlight != nil || isDeleting }
    /// 已读情况 is not offered for a draft.
    var showsReadRow: Bool { announcement.map { $0.status != .draft } ?? false }
    /// nil without `announcements.read_stats` or while no summary was read: the row falls back to the hint (60 §16.3).
    var summaryForDisplay: AnnouncementReadSummary? { readStatsEnabled ? summary.value : nil }

    // MARK: - Reads

    /// The detail (with read_stats under the capability), then the summary unless it is a draft. A failed refresh keeps the
    /// shown detail (00 §4.6).
    func load() async {
        guard isCurrent(), !isGone else { return }
        let ticket = UUID()
        self.ticket = ticket
        detail = detail.withLoading()
        let result = await Self.capture { [source, id, readStatsEnabled] in try await source.load(id, readStatsEnabled) }
        guard ticket == self.ticket else { return }
        guard isCurrent(), !Task.isCancelled else { detail = detail.withCancelledLoad(); return }
        switch result {
        case .success(let announcement):
            detail = .loaded(announcement, at: now())
            await loadSummary(for: announcement, ticket: ticket)
        case .failure(let error) where error is CancellationError: detail = detail.withCancelledLoad()
        case .failure(let error) where AnnouncementWriteFailure.isGone(error): markGone()
        case .failure(let error): detail = detail.withFailure(error.localizedDescription)
        }
    }
    /// Another page wrote (C-34); this detail's own writes have read already.
    func noteRevision(_ revision: Int) async {
        guard revision != appliedRevision else { return }
        appliedRevision = revision
        await load()
    }

    private func loadSummary(for announcement: Announcement, ticket: UUID) async {
        guard readStatsEnabled, announcement.status != .draft else { summary = .idle; return }
        summary = summary.withLoading()
        let result = await Self.capture { [source, id] in try await source.summary(id) }
        guard ticket == self.ticket else { return }
        guard isCurrent(), !Task.isCancelled else { summary = summary.withCancelledLoad(); return }
        switch result {
        case .success(let value): summary = .loaded(value, at: now())
        case .failure(let error) where error is CancellationError: summary = summary.withCancelledLoad()
        case .failure(let error): summary = summary.withFailure(error.localizedDescription)
        }
    }

    // MARK: - Writes

    /// 发布 (a draft) or 重新发布 (archived): `{"status":"active"}`. `.reconfirm` sends the caller back to its confirmation.
    func publish() async -> PublishResult {
        guard let action = AnnouncementDetailPresentation.writeAction(for: announcement?.status), action != .archive else { return .failed }
        switch await write(action) {
        case .applied?: return .done
        case .reconfirm?: return .reconfirm
        case .failed?, nil: return .failed
        }
    }
    /// 归档 at once, with 撤销 writing active back. The undo goes out even after the page is left.
    func archive() async {
        guard announcement?.status == .active else { return }
        _ = await write(.archive)
    }

    private enum WriteResult { case applied, reconfirm, failed }

    private func write(_ action: AnnouncementDetailAction) async -> WriteResult? {
        guard let target = action.targetStatus, !isBusy, isCurrent() else { return nil }
        inFlight = action
        let outcome = await send(.status(target), expecting: target)
        inFlight = nil
        guard isCurrent() else { return nil }
        switch outcome {
        case .applied(let fresh):
            applied(fresh)
            receipts.show(action == .archive
                ? Receipt(text: AnnouncementDetailPresentation.archivedReceipt, systemImage: "tray", tone: .neutral, undo: undoArchive())
                : Receipt(text: AnnouncementDetailPresentation.publishedReceipt, systemImage: "megaphone"))
            await load()
            return .applied
        case .reconfirm: return .reconfirm
        case .failed(let failure):
            show(failure) { AnnouncementDetailPresentation.writeFailed(action, reason: $0) }
            return .failed
        case .ignored: return nil
        }
    }

    /// One write's end. `applied` carries the announcement the server returned or read back.
    private enum SendOutcome { case applied(Announcement), reconfirm, failed(AnnouncementWriteFailure), ignored }

    private func send(_ request: AnnouncementUpdateRequest, expecting target: AnnouncementStatus) async -> SendOutcome {
        do {
            let updated = try await source.update(id, request)
            return isCurrent() ? .applied(updated) : .ignored
        } catch {
            guard isCurrent() else { return .ignored }
            let failure = AnnouncementWriteFailure.classify(error)
            switch failure {
            case .cancelled: return .ignored
            case .reconfirm(let notice):
                receipts.show(Receipt(text: notice, systemImage: "checkmark.shield", tone: .caution))
                return .reconfirm
            case .unconfirmed: return await readBack(expecting: target)
            case .gone, .rejected: return .failed(failure)
            }
        }
    }
    /// 00 §2.4: done when the status reads the target; anything else stays unconfirmed.
    private func readBack(expecting target: AnnouncementStatus) async -> SendOutcome {
        do {
            let fresh = try await source.load(id, false)
            guard isCurrent() else { return .ignored }
            return fresh.status == target ? .applied(fresh) : .failed(.unconfirmed)
        } catch {
            guard isCurrent() else { return .ignored }
            return .failed(AnnouncementWriteFailure.isGone(error) ? .gone : .unconfirmed)
        }
    }
    /// Shows what the server holds now, drops loads still running and tells the list (C-34).
    private func applied(_ fresh: Announcement) {
        ticket = UUID()
        detail = .loaded(fresh, at: now())
        bump()
    }
    private func show(_ failure: AnnouncementWriteFailure, rejected text: (String) -> String) {
        switch failure {
        case .gone: markGone()
        case .unconfirmed: receipts.show(Self.unconfirmedReceipt)
        case .rejected(let reason): receipts.show(Receipt(text: text(reason), systemImage: "exclamationmark.triangle", tone: .critical))
        case .reconfirm, .cancelled: break
        }
    }

    // MARK: - Undo

    /// The receipt's 撤销: only Sendable parts are captured, so it still runs once this model is gone.
    private func undoArchive() -> @MainActor @Sendable () -> Void {
        let undo = AnnouncementArchiveUndo(id: id, source: source, receipts: receipts, signal: signal, isCurrent: isCurrent)
        return { [weak self] in
            Task { @MainActor in
                guard let self else { _ = await undo.run(); return }
                await self.runUndo(undo)
            }
        }
    }
    private func runUndo(_ undo: AnnouncementArchiveUndo) async {
        guard !isBusy, isCurrent() else { return }
        inFlight = .republish
        let result = await undo.run()
        inFlight = nil
        switch result {
        case .applied(let fresh):
            ticket = UUID()
            detail = .loaded(fresh, at: now())
            appliedRevision = signal.revision
            await load()
        case .gone: markGone()
        case .other: break
        }
    }

    // MARK: - Delete

    /// 60 §16.4: deleted, already gone (404) or read back as gone → the signal, then `onDeleted` (the page pops and shows its
    /// receipt). Otherwise a receipt says why.
    func delete(onDeleted: @escaping @MainActor () -> Void) async {
        guard !isBusy, isCurrent() else { return }
        isDeleting = true
        let failure = await sendDelete()
        isDeleting = false
        guard isCurrent() else { return }
        guard let failure else {
            bump()
            onDeleted()
            return
        }
        show(failure) { AnnouncementDetailPresentation.deleteFailed(reason: $0) }
    }

    /// nil once the announcement is gone; `.cancelled` for an outcome the user need not hear about.
    private func sendDelete() async -> AnnouncementWriteFailure? {
        do {
            _ = try await source.delete(id)
            return nil
        } catch {
            switch AnnouncementWriteFailure.classify(error) {
            case .gone: return nil
            case .cancelled: return .cancelled
            case .reconfirm(let notice):
                if isCurrent() { receipts.show(Receipt(text: notice, systemImage: "checkmark.shield", tone: .caution)) }
                return .cancelled
            case .rejected(let reason): return .rejected(reason)
            case .unconfirmed: return await readBackDeleted(after: error)
            }
        }
    }
    /// Still there → the transport's words; unreadable → unconfirmed.
    private func readBackDeleted(after error: any Error) async -> AnnouncementWriteFailure? {
        do {
            _ = try await source.load(id, false)
            return .rejected(error.localizedDescription)
        } catch {
            return AnnouncementWriteFailure.isGone(error) ? nil : .unconfirmed
        }
    }

    // MARK: - Helpers

    private static var unconfirmedReceipt: Receipt {
        Receipt(text: AnnouncementDetailPresentation.unconfirmed, systemImage: "exclamationmark.triangle", tone: .caution)
    }

    private func markGone() {
        ticket = UUID()
        isGone = true
        detail = .idle
        summary = .idle
        bump()
    }
    private func bump() {
        signal.bump()
        appliedRevision = signal.revision
    }
    private nonisolated static func capture<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}

/// 撤销 of 归档: `{"status":"active"}` once, in the session the receipt belongs to. Success says nothing (the button row
/// shows it); a failure says why.
struct AnnouncementArchiveUndo: Sendable {
    enum Outcome { case applied(Announcement), gone, other }

    let id: Int
    let source: AnnouncementDetailSource
    let receipts: ReceiptCenter
    let signal: AnnouncementChangeSignal
    let isCurrent: @MainActor @Sendable () -> Bool

    @MainActor func run() async -> Outcome {
        guard isCurrent() else { return .other }
        do {
            let fresh = try await source.update(id, .status(.active))
            guard isCurrent() else { return .other }
            signal.bump()
            return .applied(fresh)
        } catch {
            guard isCurrent() else { return .other }
            switch AnnouncementWriteFailure.classify(error) {
            case .cancelled: return .other
            case .gone:
                signal.bump()
                receipts.show(failed(error.localizedDescription))
                return .gone
            case .unconfirmed: receipts.show(Receipt(text: AnnouncementDetailPresentation.unconfirmed, systemImage: "exclamationmark.triangle", tone: .caution))
            case .reconfirm(let notice): receipts.show(Receipt(text: notice, systemImage: "checkmark.shield", tone: .caution))
            case .rejected(let reason): receipts.show(failed(reason))
            }
            return .other
        }
    }
    private func failed(_ reason: String) -> Receipt {
        Receipt(text: AnnouncementDetailPresentation.undoFailed(reason: reason), systemImage: "exclamationmark.triangle", tone: .critical)
    }
}
