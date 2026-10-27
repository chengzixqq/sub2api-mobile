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

/// 60 §17.4: 存草稿 / 保存 / 发布 of the edit sheet. A new announcement's key is made when the administrator confirms and
/// kept for the same bytes (R05); with `announcements.idempotent_create` an unknown result offers the same key again, without
/// it nothing is resent and the title is looked up (H07). A PUT carries no key and is read back when its reply is lost.
/// Results for an older session are dropped; success tells the list and the detail (`onChanged`), shows the receipt and sets
/// `exit`, which closes the sheet.
@MainActor @Observable
final class AnnouncementEditFlow {
    enum Phase: Equatable {
        case editing
        case saving(KeyedWriteEvent?)
        case failed(String)
        /// Keyed create: the same key may be sent again (not before the date).
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
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var attempt: AnnouncementCreateAttempt?
    @ObservationIgnored private var pending: (update: AnnouncementUpdateRequest?, receipt: Receipt)?

    init(original: Announcement?, source: AnnouncementEditSource, keyedCreate: Bool, receipts: ReceiptCenter,
         isCurrent: @escaping @MainActor () -> Bool, onChanged: @escaping @MainActor () -> Void, now: @escaping @MainActor () -> Date = { Date() }) {
        self.original = original; self.source = source; self.keyedCreate = keyedCreate; self.receipts = receipts
        self.isCurrent = isCurrent; self.onChanged = onChanged; self.now = now
        role = AnnouncementEditRole(original: original)
    }

    var isBusy: Bool {
        switch phase {
        case .saving, .checking: true
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
        let receipt = Receipt(text: role.trailingReceipt, systemImage: "tray.and.arrow.down")
        if let original {
            await update(draft.updateRequest(from: original, status: nil), of: original, receipt: receipt)
        } else {
            await create(draft.createRequest(status: role.trailingStatus ?? .draft), receipt: receipt)
        }
    }
    /// 发布 / 重新发布, after the confirmation: status active.
    func publish(_ draft: AnnouncementDraft) async {
        guard acceptsSave else { return }
        let receipt = Receipt(text: AnnouncementEditRole.publishReceipt, systemImage: "megaphone")
        if let original {
            await update(draft.updateRequest(from: original, status: .active), of: original, receipt: receipt)
        } else {
            await create(draft.createRequest(status: .active), receipt: receipt)
        }
    }

    private func create(_ request: AnnouncementCreateRequest, receipt: Receipt) async {
        do {
            attempt = try AnnouncementCreateAttempt.next(for: request, previous: attempt, now: now())
        } catch {
            phase = .failed(AnnouncementEditFailure.classify(error).message)
            return
        }
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

    /// Keyed create: the same key and bytes again, after Retry-After when one was given.
    func retrySameKey() async {
        guard case .createUnconfirmed(let notBefore) = phase, exit == nil, isCurrent() else { return }
        if let notBefore, notBefore > now() {
            phase = .saving(nil)
            try? await Task.sleep(for: .seconds(notBefore.timeIntervalSince(now())))
            guard isCurrent() else { return }
        }
        await sendCreate()
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

    private func finish() {
        onChanged()
        if let receipt = pending?.receipt { receipts.show(receipt) }
        exit = .saved
        phase = .editing
    }
    private func markGone() {
        onChanged()
        phase = .gone
    }
    private nonisolated static func capture<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
