import Foundation
import Observation
import Sub2Core

/// 60 §14.2: the editor's one call on top of the detail's (S6D1-12, C-35). Written here rather than beside the sheet so the flow
/// below can be tested on macOS.
protocol ProxyEditSource: ProxyDetailSource {
    func createProxy(_ request: ProxyCreateRequest, idempotencyKey: UUID, onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<AdminProxy>
}

extension ClientProxySource: ProxyEditSource {
    func createProxy(_ request: ProxyCreateRequest, idempotencyKey: UUID, onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<AdminProxy> {
        try await client.createProxy(request, idempotencyKey: idempotencyKey, onEvent: onEvent)
    }
}

/// 60 §14.4: 添加 / 保存 / 续期 of the proxy sheet. The add carries the key made when 添加 was tapped and keeps it for the same
/// form (R05); an unknown result stays on the sheet with 核对 (by name) and 用同一编号重试. An edit is sent once without a key
/// (R06) and a lost reply is read back. Done, it closes the sheet with its receipt: the add's with 撤销 (DELETE, nothing uses it
/// yet), then the catalog reads again and the new proxy once more 3 seconds later for its first probe; an edit of the address
/// tells the detail to wait for the server's new probe (H04, C-34). Answers for an older session are dropped.
@MainActor @Observable
final class ProxyEditFlow {
    enum Phase: Equatable {
        case editing
        case saving(KeyedWriteEvent?)
        case checking
        case failed(String, section: ProxyEditSection?)
        /// The add may have gone through: 核对 looks for it by name (`searched` once it did not find it), or the same key goes
        /// again, not before the date (device clock).
        case addUnconfirmed(retryNotBefore: Date?, searched: Bool)
        /// The edit's reply was lost and reading it back did not answer.
        case updateUnconfirmed
    }
    nonisolated static let probeDelay: Duration = .seconds(3)
    nonisolated static let reconcilePageSize = 20

    let original: AdminProxy?
    private(set) var phase: Phase = .editing
    /// The write landed, or the proxy turned out gone: the sheet closes.
    private(set) var isFinished = false
    /// After an add: the catalog's reload and the probe read.
    @ObservationIgnored private(set) var followUp: Task<Void, Never>?

    @ObservationIgnored private let source: any ProxyEditSource
    @ObservationIgnored private let store: ProxyStore?
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let generation: UUID
    @ObservationIgnored private let isCurrent: @MainActor @Sendable () -> Bool
    /// The server-corrected clock: N days of the expiry count from it.
    @ObservationIgnored private let now: @MainActor () -> Date
    /// The device clock STORE_UNAVAILABLE's cooldown is stamped with.
    @ObservationIgnored private let deviceNow: @MainActor () -> Date
    @ObservationIgnored private let pause: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let makeKey: @Sendable () -> UUID
    @ObservationIgnored private var attempt: ProxyAddAttempt?
    @ObservationIgnored private var sent: (request: ProxyUpdateRequest, draft: ProxyEditDraft)?

    init(original: AdminProxy?, source: any ProxyEditSource, store: ProxyStore?, receipts: ReceiptCenter, generation: UUID,
         isCurrent: @escaping @MainActor @Sendable () -> Bool, now: @escaping @MainActor () -> Date, deviceNow: @escaping @MainActor () -> Date = { Date() },
         pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, makeKey: @escaping @Sendable () -> UUID = { UUID() }) {
        self.original = original; self.source = source; self.store = store; self.receipts = receipts; self.generation = generation
        self.isCurrent = isCurrent; self.now = now; self.deviceNow = deviceNow; self.pause = pause; self.makeKey = makeKey
    }

    var isBusy: Bool {
        switch phase {
        case .saving, .checking: true
        default: false
        }
    }
    /// The form waits while a write runs or its result is open.
    var locksForm: Bool {
        switch phase {
        case .editing, .failed: false
        default: true
        }
    }

    func submit(_ draft: ProxyEditDraft) async {
        guard !locksForm, !isFinished, isCurrent() else { return }
        if let original { await save(draft, original: original) } else { await add(draft) }
    }

    // MARK: - 添加

    private func add(_ draft: ProxyEditDraft) async {
        do {
            attempt = try ProxyAddAttempt.next(previous: attempt, draft: draft, now: now(), makeKey: makeKey)
        } catch {
            phase = .failed(Self.message(ProxyWriteFailure.classify(error, sentBackup: false)), section: nil)
            return
        }
        await sendAdd()
    }
    private func sendAdd() async {
        guard let attempt else { return }
        phase = .saving(nil)
        let handler: KeyedWriteEventHandler = { [weak self] event in await self?.note(event) }
        let result = await Self.capture { [source] in try await source.createProxy(attempt.request, idempotencyKey: attempt.key, onEvent: handler) }
        guard isCurrent() else { return }
        switch result {
        case .success(let outcome): finishAdd(outcome.value, draft: attempt.draft)
        case .failure(let error): addFailed(error, attempt: attempt)
        }
    }
    private func note(_ event: KeyedWriteEvent) {
        guard case .saving = phase else { return }
        phase = .saving(event)
    }
    private func addFailed(_ error: any Error, attempt sent: ProxyAddAttempt) {
        let failure = ProxyWriteFailure.classify(error, sentBackup: sent.request.backupProxyID != nil)
        switch failure {
        case .cancelled: phase = .editing
        case .unconfirmed(let notBefore): phase = .addUnconfirmed(retryNotBefore: notBefore, searched: false)
        case .rejected(let message, let section):
            attempt = nil
            phase = .failed(message, section: section)
        case .backupGone:
            attempt = nil
            phase = .failed(ProxyEditCopy.backupGone, section: .fallback)
            reloadCatalog()
        case .needsNewKey, .gone:
            attempt = nil
            phase = .failed(Self.message(failure), section: nil)
        }
    }

    /// The same key and bytes again, after what is left of the cooldown when one was given.
    func retrySameKey() async {
        guard case .addUnconfirmed(let notBefore, _) = phase, !isFinished, isCurrent() else { return }
        if let wait = cooldownLeft(until: notBefore) {
            phase = .saving(nil)
            try? await pause(.seconds(wait))
            guard isCurrent() else { return }
        }
        await sendAdd()
    }
    /// 00 §2.5.4 核对: a proxy of the same name, protocol, host and port is this add.
    func reconcileAdd() async {
        guard case .addUnconfirmed(let notBefore, _) = phase, let attempt, !isFinished, isCurrent() else { return }
        phase = .checking
        let request = attempt.request, query = ProxyListQuery(search: request.name, pageSize: Self.reconcilePageSize)
        let result = await Self.capture { [source] in try await source.proxies(page: 1, query: query) }
        guard isCurrent() else { return }
        if case .success(let page) = result, let found = page.items.first(where: { Self.isSame($0, as: request) }) {
            return finishAdd(found, draft: attempt.draft)
        }
        phase = .addUnconfirmed(retryNotBefore: notBefore, searched: true)
    }

    private func finishAdd(_ row: AdminProxy, draft: ProxyEditDraft) {
        attempt = nil
        phase = .editing
        receipts.show(Receipt(text: draft.successReceipt(saved: row), undo: undoAction(id: row.id, name: ProxyPresentation.displayName(row))))
        isFinished = true
        let id = row.id, source = source, store = store, isCurrent = isCurrent, pause = pause
        followUp = Task { @MainActor in
            await store?.reload()
            do { try await pause(Self.probeDelay) } catch { return }
            guard isCurrent(), let fresh = try? await source.proxy(id: id), isCurrent() else { return }
            store?.replace(fresh)
        }
    }
    /// 撤销: only Sendable parts, so it still works after the sheet is gone.
    private func undoAction(id: Int, name: String) -> @MainActor @Sendable () -> Void {
        let source = source, store = store, receipts = receipts, isCurrent = isCurrent
        return {
            Task { @MainActor in
                guard isCurrent() else { return }
                do {
                    _ = try await source.deleteProxy(id: id)
                    guard isCurrent() else { return }
                    store?.remove(id: id)
                    receipts.show(Receipt(text: DeleteConfirmationCopy.deletedReceipt(objectNoun: ProxyDetailCopy.objectNoun, displayName: name),
                                          systemImage: "trash"))
                } catch {
                    guard isCurrent(), !(error is CancellationError) else { return }
                    let inUse = (error as? APIError).map(ProxyDeleteBlock.isInUseConflict) ?? false
                    let text = inUse ? ProxyEditCopy.undoFailed(inUse: true) : ProxyEditCopy.undoFailed(reason: error.localizedDescription)
                    receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .critical))
                }
            }
        }
    }

    // MARK: - 保存 / 续期

    private func save(_ draft: ProxyEditDraft, original: AdminProxy) async {
        let request = draft.updateRequest(now: now())
        guard request.hasChanges else { isFinished = true; return }
        sent = (request, draft)
        phase = .saving(nil)
        let result = await Self.capture { [source] in try await source.updateProxy(id: original.id, request) }
        guard isCurrent() else { return }
        switch result {
        case .success(let reply): finishSave(shown(original).mergingConfiguration(from: reply))
        case .failure(let error): await saveFailed(error, request: request)
        }
    }
    private func saveFailed(_ error: any Error, request: ProxyUpdateRequest) async {
        let failure = ProxyWriteFailure.classify(error, sentBackup: Self.sendsBackup(request))
        switch failure {
        case .cancelled: phase = .editing
        case .unconfirmed: await readBack()
        case .gone: finishGone()
        case .backupGone: await checkBackupGone()
        case .rejected(let message, let section): phase = .failed(message, section: section)
        case .needsNewKey: phase = .failed(Self.message(failure), section: nil)
        }
    }
    /// The read-back again after it did not answer.
    func recheck() async {
        guard phase == .updateUnconfirmed, !isFinished, isCurrent() else { return }
        await readBack()
    }
    /// 00 §2.4: saved when every key sent reads as sent; another value is shown and may be saved again; no answer stays unknown.
    private func readBack() async {
        guard let sent, let original else { return }
        phase = .checking
        let result = await Self.capture { [source] in try await source.proxy(id: original.id) }
        guard isCurrent() else { return }
        switch result {
        case .success(let fresh):
            let row = fresh.keepingCounts(of: shown(original))
            if sent.request.matches(fresh) { return finishSave(row) }
            store?.replace(row)
            phase = .failed(ProxyEditCopy.readBackMismatch, section: nil)
        case .failure(let error) where ProxyDetailFailure.isGone(error): finishGone()
        case .failure: phase = .updateUnconfirmed
        }
    }
    /// 404 PROXY_NOT_FOUND after sending a backup: the backup, unless the proxy itself is gone too.
    private func checkBackupGone() async {
        guard let original else { return }
        phase = .checking
        let result = await Self.capture { [source] in try await source.proxy(id: original.id) }
        guard isCurrent() else { return }
        if case .failure(let error) = result, ProxyDetailFailure.isGone(error) { return finishGone() }
        if case .success(let fresh) = result { store?.replace(fresh.keepingCounts(of: shown(original))) }
        phase = .failed(ProxyEditCopy.backupGone, section: .fallback)
        reloadCatalog()
    }
    private func finishSave(_ row: AdminProxy) {
        guard let sent else { return }
        store?.replace(row)
        if sent.request.touchesNetwork { ProxyAddressSignal.post(ProxyAddressChange(proxyID: row.id, generation: generation)) }
        receipts.show(Receipt(text: sent.draft.successReceipt(saved: row)))
        phase = .editing
        isFinished = true
    }
    private func finishGone() {
        if let id = original?.id { store?.remove(id: id) }
        receipts.show(Receipt(text: Self.message(.gone), systemImage: "trash", tone: .critical))
        phase = .editing
        isFinished = true
    }

    // MARK: - Helpers

    /// The catalog's row (with its counts and probe), else the proxy the sheet opened with.
    private func shown(_ original: AdminProxy) -> AdminProxy { store?.proxy(id: original.id) ?? original }
    /// The backup candidates read again after a backup turned out missing.
    private func reloadCatalog() {
        guard let store else { return }
        Task { await store.reload() }
    }
    /// Counted on the device clock that set it and never longer than the cooldown.
    private func cooldownLeft(until notBefore: Date?) -> TimeInterval? {
        guard let notBefore else { return nil }
        let left = min(notBefore.timeIntervalSince(deviceNow()), IdempotencyPolicy.storeUnavailableCooldown)
        return left > 0 ? left : nil
    }
    private nonisolated static func message(_ failure: ProxyWriteFailure) -> String {
        switch failure {
        case .rejected(let message, _), .needsNewKey(let message): message
        case .backupGone: ProxyEditCopy.backupGone
        case .gone: APIError.server(status: 404, reason: ProxyReason.notFound).localizedDescription
        case .unconfirmed, .cancelled: KeyedWriteFailure.unconfirmedMessage
        }
    }
    private nonisolated static func sendsBackup(_ request: ProxyUpdateRequest) -> Bool {
        if case .set? = request.backupProxyID { return true }
        return false
    }
    private nonisolated static func isSame(_ proxy: AdminProxy, as request: ProxyCreateRequest) -> Bool {
        let trim = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trim(proxy.name) == trim(request.name) && trim(proxy.scheme).lowercased() == request.scheme && trim(proxy.host) == trim(request.host)
            && proxy.port == request.port
    }
    private nonisolated static func capture<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
