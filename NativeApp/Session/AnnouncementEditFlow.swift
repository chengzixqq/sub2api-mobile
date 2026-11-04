import Foundation
import Observation
import Sub2Core

/// The edit sheet's writes (60 §17.2): the site, or under `-ui-testing` this session's AnnouncementDemoStore.
struct AnnouncementEditSource: Sendable {
    let create: @Sendable (_ request: AnnouncementCreateRequest, _ key: UUID, _ keyed: Bool, _ onEvent: KeyedWriteEventHandler?) async throws
        -> WriteOutcome<Announcement>
    let update: @Sendable (_ id: Int, _ request: AnnouncementUpdateRequest) async throws -> Announcement
    let load: @Sendable (_ id: Int) async throws -> Announcement
    let recent: @Sendable (_ title: String) async throws -> [Announcement]

    static func live(_ client: APIClient) -> AnnouncementEditSource {
        AnnouncementEditSource(create: { try await client.createAnnouncement($0, idempotencyKey: $1, supportsIdempotentCreate: $2, onEvent: $3) },
                               update: { try await client.updateAnnouncement(id: $0, $1) },
                               load: { try await client.announcement(id: $0, includeReadStats: false) },
                               recent: { try await client.recentAnnouncements(title: $0) })
    }
}

/// A new announcement left at 稍后核对 (S6-高-13): the same key and bytes, the form as sent and where the check stood. AppModel
/// keeps it for the session, in memory only; a sheet opened from it carries on with the same attempt, by title once the key
/// no longer replays (`resumeCheck`).
struct PendingAnnouncementCreate: Equatable {
    let attempt: AnnouncementCreateAttempt
    let draft: AnnouncementDraft
    let phase: AnnouncementEditFlow.Phase
}

/// 60 §17.4: 存草稿 / 保存 / 发布 of the edit sheet. A new announcement's key is made when the administrator confirms and
/// kept for the same bytes (R05); with `announcements.idempotent_create` an unknown result offers the same key again, without
/// it nothing is resent and the title is looked up (H07). A PUT carries no key and is read back when its reply is lost.
/// Results for an older session are dropped; success tells the list and the detail (`onChanged`), shows the receipt and sets
/// `exit`, which closes the sheet. A new one left unconfirmed goes to the session (`keepCreate`) when the sheet closes.
@MainActor @Observable
final class AnnouncementEditFlow {
    enum Phase: Equatable {
        case editing
        case saving(KeyedWriteEvent?)
        case failed(String)
        /// Keyed create: the same key may be sent again (not before the date, on the device clock).
        case createUnconfirmed(retryNotBefore: Date?)
        case checking
        case maybeCreated(AnnouncementRecentMatch)
        case notFoundYet
        case updateUnconfirmed
        case gone
    }
    enum Exit: Equatable { case saved, open(Int) }

    let role: AnnouncementEditRole
    private(set) var phase: Phase = .editing
    private(set) var exit: Exit?

    @ObservationIgnored private let original: Announcement?
    @ObservationIgnored private let source: AnnouncementEditSource
    @ObservationIgnored private let keyedCreate: Bool
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let onChanged: @MainActor () -> Void
    /// The server-corrected clock: when the administrator confirmed, matched against `created_at` (H07).
    @ObservationIgnored private let now: @MainActor () -> Date
    /// The device clock RequestClock stamps STORE_UNAVAILABLE's cooldown with.
    @ObservationIgnored private let deviceNow: @MainActor () -> Date
    @ObservationIgnored private let pause: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var attempt: AnnouncementCreateAttempt?
    @ObservationIgnored private var pending: (update: AnnouncementUpdateRequest?, receipt: Receipt)?
    /// The session's record of a new one left unconfirmed: set at 稍后核对, nil once this sheet settled the one it holds.
    @ObservationIgnored private let keepCreate: @MainActor (PendingAnnouncementCreate?) -> Void
    @ObservationIgnored private var sentDraft: AnnouncementDraft?
    @ObservationIgnored private var holdsRecord = false

    init(original: Announcement?, source: AnnouncementEditSource, keyedCreate: Bool, receipts: ReceiptCenter,
         isCurrent: @escaping @MainActor () -> Bool, onChanged: @escaping @MainActor () -> Void, now: @escaping @MainActor () -> Date = { Date() },
         deviceNow: @escaping @MainActor () -> Date = { Date() },
         pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         keepCreate: @escaping @MainActor (PendingAnnouncementCreate?) -> Void = { _ in }, restoring record: PendingAnnouncementCreate? = nil) {
        self.original = original; self.source = source; self.keyedCreate = keyedCreate; self.receipts = receipts
        self.isCurrent = isCurrent; self.onChanged = onChanged; self.now = now; self.deviceNow = deviceNow; self.pause = pause
        self.keepCreate = keepCreate
        role = AnnouncementEditRole(original: original)
        guard original == nil, let record else { return }
        attempt = record.attempt
        sentDraft = record.draft
        pending = (nil, Self.receipt(publishing: record.attempt.request.status == .active, role: role))
        phase = record.phase
        holdsRecord = true
    }

    var isBusy: Bool {
        switch phase {
        case .saving, .checking: true
        default: false
        }
    }
    /// 00 §2.5.4: the server may have run the save; closing now asks first (稍后核对).
    var isUnconfirmed: Bool {
        switch phase {
        case .createUnconfirmed, .maybeCreated, .notFoundYet, .updateUnconfirmed: true
        default: false
        }
    }
    /// The form waits while a save runs or its result is open.
    var locksForm: Bool {
        switch phase {
        case .editing, .failed: false
        default: true
        }
    }
    private var acceptsSave: Bool { !locksForm && exit == nil && isCurrent() }

    // MARK: - Saves

    /// 存草稿 (a new one as a draft, a draft as it is) or 保存.
    func saveTrailing(_ draft: AnnouncementDraft) async {
        guard acceptsSave else { return }
        let receipt = Self.receipt(publishing: false, role: role)
        if let original {
            await update(draft.updateRequest(from: original, status: nil), of: original, receipt: receipt)
        } else {
            await create(draft, status: role.trailingStatus ?? .draft, receipt: receipt)
        }
    }
    /// 发布 / 重新发布, after the confirmation: status active.
    func publish(_ draft: AnnouncementDraft) async {
        guard acceptsSave else { return }
        let receipt = Self.receipt(publishing: true, role: role)
        if let original {
            await update(draft.updateRequest(from: original, status: .active), of: original, receipt: receipt)
        } else {
            await create(draft, status: .active, receipt: receipt)
        }
    }

    private func create(_ draft: AnnouncementDraft, status: AnnouncementStatus, receipt: Receipt) async {
        do {
            attempt = try AnnouncementCreateAttempt.next(for: draft.createRequest(status: status), previous: attempt, now: now())
        } catch {
            phase = .failed(AnnouncementEditFailure.classify(error).message)
            return
        }
        sentDraft = draft
        pending = (nil, receipt)
        await sendCreate()
    }
    private func sendCreate() async {
        guard let attempt else { return }
        phase = .saving(nil)
        let handler: KeyedWriteEventHandler = { [weak self] event in await self?.note(event) }
        let result = await Self.capture { [source, keyedCreate] in try await source.create(attempt.request, attempt.key, keyedCreate, handler) }
        guard isCurrent() else { return }
        switch result {
        case .success: finish()
        case .failure(let error): await createFailed(error)
        }
    }
    private func note(_ event: KeyedWriteEvent) {
        guard case .saving = phase else { return }
        phase = .saving(event)
    }
    private func createFailed(_ error: any Error) async {
        let failure = AnnouncementEditFailure.classify(error)
        switch failure {
        case .cancelled: phase = .editing
        case .unconfirmed(let retryNotBefore):
            if keyedCreate { phase = .createUnconfirmed(retryNotBefore: retryNotBefore) } else { await checkRecent() }
        case .rejected, .keyConflict, .gone:
            attempt = nil
            phase = .failed(failure.message)
        }
    }

    private func update(_ request: AnnouncementUpdateRequest, of original: Announcement, receipt: Receipt) async {
        guard !request.isEmpty else { exit = .saved; return }
        pending = (request, receipt)
        phase = .saving(nil)
        let result = await Self.capture { [source] in try await source.update(original.id, request) }
        guard isCurrent() else { return }
        switch result {
        case .success: finish()
        case .failure(let error):
            switch AnnouncementEditFailure.classify(error) {
            case .cancelled: phase = .editing
            case .gone: markGone()
            case .unconfirmed: await readBack()
            case let failure: phase = .failed(failure.message)
            }
        }
    }

    // MARK: - Unknown results

    /// Keyed create: the same key and bytes again, after what is left of the cooldown when one was given. Past the replay
    /// window (00 §2.5.5) the server would run the key again, so the title is looked up instead (H07).
    func retrySameKey() async {
        guard case .createUnconfirmed(let notBefore) = phase, exit == nil, isCurrent() else { return }
        if canReplay, let wait = cooldownLeft(until: notBefore) {
            phase = .saving(nil)
            try? await pause(.seconds(wait))
            guard isCurrent() else { return }
        }
        if canReplay { await sendCreate() } else { await checkRecent() }
    }
    /// On opening: a create restored from the session's record past its replay window goes straight to the H07 lookup.
    func resumeCheck() async {
        guard case .createUnconfirmed = phase, !canReplay, exit == nil, isCurrent() else { return }
        await checkRecent()
    }
    /// The H07 lookup again, or the PUT read back again.
    func recheck() async {
        guard exit == nil, isCurrent() else { return }
        switch phase {
        case .notFoundYet, .maybeCreated: await checkRecent()
        case .updateUnconfirmed: await readBack()
        default: break
        }
    }
    /// H07: the one found is opened instead of making another.
    func viewExisting() {
        guard case .maybeCreated(let match) = phase, exit == nil, isCurrent() else { return }
        releaseRecord()
        onChanged()
        exit = .open(match.id)
    }
    /// H07: the same content once more under a new key, at the administrator's word.
    func createAnyway() async {
        switch phase {
        case .notFoundYet, .maybeCreated: break
        default: return
        }
        guard let previous = attempt, exit == nil, isCurrent(),
              let fresh = try? AnnouncementCreateAttempt.next(for: previous.request, previous: nil, now: now()) else { return }
        attempt = fresh
        await sendCreate()
    }

    /// 稍后核对: the sheet closes; the list and the detail read again so what the server did shows. A new one's attempt stays
    /// with the session (S6-高-13), so the next 新建 can offer it first; an edit's goes.
    func checkLater() {
        guard isUnconfirmed, exit == nil, isCurrent() else { return }
        if original == nil, let attempt, let sentDraft {
            keepCreate(PendingAnnouncementCreate(attempt: attempt, draft: sentDraft, phase: phase))
            holdsRecord = true
        }
        onChanged()
    }

    private func checkRecent() async {
        guard let attempt else { return }
        phase = .checking
        let result = await Self.capture { [source] in try await source.recent(attempt.request.title) }
        guard isCurrent() else { return }
        let items = (try? result.get()) ?? []
        if let match = AnnouncementRecentCheck.match(in: items, title: attempt.request.title, confirmedAt: attempt.confirmedAt) {
            phase = .maybeCreated(match)
        } else {
            phase = .notFoundYet
        }
    }
    /// 00 §2.4: saved when every key sent reads as sent; anything else stays unconfirmed and is not resent.
    private func readBack() async {
        guard let original, let request = pending?.update else { return }
        phase = .checking
        let result = await Self.capture { [source] in try await source.load(original.id) }
        guard isCurrent() else { return }
        switch result {
        case .success(let fresh) where request.isReflected(in: fresh): finish()
        case .failure(let error) where AnnouncementWriteFailure.isGone(error): markGone()
        default: phase = .updateUnconfirmed
        }
    }

    // MARK: - Helpers

    /// A create has no business-level dedupe (00 §2.5.5): its key goes out again only while the server still replays it.
    private var canReplay: Bool { attempt?.isReplayable(at: now()) ?? false }
    /// Counted on the device clock that set it, and never longer than the cooldown, so a skewed or reset clock neither skips
    /// the wait nor holds the sheet.
    private func cooldownLeft(until notBefore: Date?) -> TimeInterval? {
        guard let notBefore else { return nil }
        let left = min(notBefore.timeIntervalSince(deviceNow()), IdempotencyPolicy.storeUnavailableCooldown)
        return left > 0 ? left : nil
    }
    private func finish() {
        releaseRecord()
        onChanged()
        if let receipt = pending?.receipt { receipts.show(receipt) }
        exit = .saved
        phase = .editing
    }
    /// The record this sheet took up is settled; a sheet that never held it leaves another attempt's record alone.
    private func releaseRecord() {
        guard holdsRecord else { return }
        holdsRecord = false
        keepCreate(nil)
    }
    /// What a save says when done: 发布 / 重新发布, or 存草稿 / 保存.
    private static func receipt(publishing: Bool, role: AnnouncementEditRole) -> Receipt {
        publishing ? Receipt(text: AnnouncementEditRole.publishReceipt, systemImage: "megaphone")
            : Receipt(text: role.trailingReceipt, systemImage: "tray.and.arrow.down")
    }
    private func markGone() {
        onChanged()
        phase = .gone
    }
    private nonisolated static func capture<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
