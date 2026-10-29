import Foundation
import Observation
import Sub2Core

/// 60 §13.2: the detail's calls on top of the list's (S6D1-12); S6-14's editor adds `createProxy` below it.
protocol ProxyDetailSource: ProxySource {
    func proxy(id: Int) async throws -> AdminProxy
    func proxyAccounts(id: Int) async throws -> [ProxyAccountRef]
    func checkProxyQuality(id: Int) async throws -> ProxyQualityResult
    func updateProxy(id: Int, _ request: ProxyUpdateRequest) async throws -> AdminProxy
    func deleteProxy(id: Int) async throws -> DeleteResult
}

extension ClientProxySource: ProxyDetailSource {
    func proxy(id: Int) async throws -> AdminProxy { try await client.proxy(id: id) }
    func proxyAccounts(id: Int) async throws -> [ProxyAccountRef] { try await client.proxyAccounts(id: id) }
    func checkProxyQuality(id: Int) async throws -> ProxyQualityResult { try await client.checkProxyQuality(id: id) }
    func updateProxy(id: Int, _ request: ProxyUpdateRequest) async throws -> AdminProxy { try await client.updateProxy(id: id, request) }
    func deleteProxy(id: Int) async throws -> DeleteResult { try await client.deleteProxy(id: id) }
}

/// C-34 (H04): an edit changed the proxy's scheme, host, port, username or password and the server probes it again. S6-14 posts it
/// after such a save; the detail of that proxy in that session reads it once 5 seconds later.
struct ProxyAddressChange: Sendable, Equatable {
    let proxyID: Int
    let generation: UUID
}

extension Notification.Name {
    static let proxyAddressDidChange = Notification.Name("Sub2Mobile.proxyAddressDidChange")
}

enum ProxyAddressSignal {
    private static let proxyIDKey = "proxyID"
    private static let generationKey = "generation"

    @MainActor static func post(_ change: ProxyAddressChange) { NotificationCenter.default.post(notification(change)) }
    static func notification(_ change: ProxyAddressChange) -> Notification {
        Notification(name: .proxyAddressDidChange, userInfo: [proxyIDKey: change.proxyID, generationKey: change.generation])
    }
    static func change(in notification: Notification) -> ProxyAddressChange? {
        guard notification.name == .proxyAddressDidChange, let id = notification.userInfo?[proxyIDKey] as? Int,
              let generation = notification.userInfo?[generationKey] as? UUID else { return nil }
        return ProxyAddressChange(proxyID: id, generation: generation)
    }
}

enum ProxyDeleteOutcome: Equatable, Sendable { case deleted, blocked(ProxyDeleteBlock), failed, unconfirmed, ignored }

/// 贰's badges come from the session's availability block, which holds only accounts that need attention; an account it does not
/// list gets none (13.2: no request of its own).
enum ProxyAccountStateLookup {
    static func state(accountID: Int, items: [AccountStatusItem]?, now: Date) -> AccountDisplayState? {
        guard let item = items?.first(where: { $0.id == accountID }) else { return nil }
        return AccountDisplayState(item, now: now)
    }
}

/// 60 §13: one proxy. A row from the session's catalog shows at once, an id alone shows a placeholder; both read `GET :id` and
/// `:id/accounts` side by side, on entry and on pull, never by polling. Every write is sent once without a key (R06); a lost reply
/// is read back. A write's answer is shown here and in ProxyStore. Answers of an older read or session are dropped.
@MainActor @Observable
final class ProxyDetailModel {
    nonisolated static let reprobeDelay: Duration = .seconds(5)

    let id: Int
    let receipts: ReceiptCenter
    private(set) var detail: BlockState<AdminProxy>
    private(set) var accounts: BlockState<[ProxyAccountRef]> = .idle
    /// 404 on entry or on a write: the “已删除” page.
    private(set) var isGone = false
    /// The delete went through; the page is about to pop.
    private(set) var didDelete = false
    private(set) var backupName: String?
    /// The `checked_at` of a test run on this page (“刚刚测试 09:41”).
    private(set) var justTestedAt: Date?
    private(set) var isTesting = false
    private(set) var isCheckingQuality = false
    private(set) var isUpdatingStatus = false
    private(set) var isDeleting = false
    /// H04: “地址已修改，正在重新测试” until the read 5 seconds after the edit.
    private(set) var isReprobing = false

    @ObservationIgnored let source: any ProxyDetailSource
    @ObservationIgnored let store: ProxyStore?
    @ObservationIgnored let isCurrent: @MainActor @Sendable () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var detailTicket = UUID()
    @ObservationIgnored private var accountsTicket = UUID()
    @ObservationIgnored private var reprobeTicket = UUID()
    /// The backup id whose name was read already (once per page).
    @ObservationIgnored private var backupLookup: Int?

    init(id: Int, seed: AdminProxy?, source: any ProxyDetailSource, store: ProxyStore?, receipts: ReceiptCenter,
         isCurrent: @escaping @MainActor @Sendable () -> Bool, now: @escaping @MainActor () -> Date = { Date() },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.id = id; self.source = source; self.store = store; self.receipts = receipts; self.isCurrent = isCurrent
        self.now = now; self.sleep = sleep
        detail = seed.map { .loaded($0, at: now()) } ?? .idle
    }

    var proxy: AdminProxy? { detail.value }
    var isBusy: Bool { isUpdatingStatus || isDeleting || didDelete }
    var displayName: String? { proxy.map(ProxyPresentation.displayName) }

    // MARK: - Reads

    /// The proxy and its accounts side by side; a failed refresh keeps what is shown (00 §4.6).
    func load() async {
        guard isCurrent(), !isGone, !didDelete else { return }
        async let proxyRead: Void = readProxy()
        async let accountsRead: Void = reloadAccounts()
        _ = await (proxyRead, accountsRead)
    }
    /// 贰 alone (its 重试).
    func reloadAccounts() async {
        guard isCurrent(), !isGone else { return }
        let ticket = UUID()
        accountsTicket = ticket
        accounts = accounts.withLoading()
        let result = await Self.capture { [source, id] in try await source.proxyAccounts(id: id) }
        guard ticket == accountsTicket else { return }
        guard isCurrent(), !Task.isCancelled else { accounts = accounts.withCancelledLoad(); return }
        switch result {
        case .success(let list): accounts = .loaded(list, at: now())
        case .failure(let error) where error is CancellationError: accounts = accounts.withCancelledLoad()
        case .failure(let error): accounts = accounts.withFailure(error.localizedDescription)
        }
    }
    /// Another page wrote this row into the session's catalog (the editor, 全部测试): shown as it is there.
    func adopt(_ row: AdminProxy?) {
        guard let row, row.id == id, row != proxy, !isGone, !didDelete, isCurrent() else { return }
        show(row)
    }
    /// H04 after an edit of the address: the server cleared the latency and probes again, so this page reads the proxy once 5
    /// seconds later instead of testing it. A second signal while waiting restarts the wait.
    func beginAddressReprobe() async {
        guard isCurrent(), !isGone, !didDelete else { return }
        let ticket = UUID()
        reprobeTicket = ticket
        isReprobing = true
        do { try await sleep(Self.reprobeDelay) } catch {
            if ticket == reprobeTicket { isReprobing = false }
            return
        }
        guard ticket == reprobeTicket else { return }
        if isCurrent() { await readProxy() }
        if ticket == reprobeTicket { isReprobing = false }
    }

    private func readProxy() async {
        let ticket = UUID()
        detailTicket = ticket
        detail = detail.withLoading()
        let result = await Self.capture { [source, id] in try await source.proxy(id: id) }
        guard ticket == detailTicket else { return }
        guard isCurrent(), !Task.isCancelled else { detail = detail.withCancelledLoad(); return }
        switch result {
        case .success(let fresh):
            show(fresh)
            await resolveBackupName(fresh)
        case .failure(let error) where error is CancellationError: detail = detail.withCancelledLoad()
        case .failure(let error) where ProxyDetailFailure.isGone(error): markGone()
        case .failure(let error): detail = detail.withFailure(error.localizedDescription)
        }
    }
    /// 壹's “备用 sg‑01”: the catalog's name, otherwise the backup read once. A failed read leaves “备用 —”.
    private func resolveBackupName(_ proxy: AdminProxy) async {
        guard proxy.fallbackMode == ProxyFallbackMode.proxy.rawValue, let backupID = proxy.backupProxyID else { backupName = nil; return }
        if let name = store?.name(for: backupID) { backupName = name; return }
        guard backupLookup != backupID else { return }
        backupLookup = backupID
        guard case .success(let backup) = await Self.capture({ [source] in try await source.proxy(id: backupID) }), isCurrent() else { return }
        let name = backup.name.trimmingCharacters(in: .whitespacesAndNewlines)
        backupName = name.isEmpty ? nil : name
    }

    // MARK: - 测试连接、质量检测

    /// 13.4 / 12.4: the result lands here and in the catalog, a failed probe too; an HTTP failure keeps the old value.
    func test() async {
        guard let shown = proxy, !isTesting, !isBusy, isCurrent() else { return }
        isTesting = true
        defer { isTesting = false }
        do {
            let result = try await source.testProxy(id: id)
            guard isCurrent() else { return }
            justTestedAt = result.checkedAt ?? now()
            show((proxy ?? shown).applying(result))
        } catch {
            guard isCurrent(), !(error is CancellationError) else { return }
            if ProxyDetailFailure.isGone(error) { return markGone() }
            receipts.show(Receipt(text: ProxyDetailCopy.testRequestFailed, systemImage: "exclamationmark.triangle", tone: .critical))
        }
    }
    /// The score, grade, summary and time; a failed base probe still writes them, with the failure receipt.
    func checkQuality() async {
        guard let shown = proxy, !isCheckingQuality, !isBusy, isCurrent() else { return }
        isCheckingQuality = true
        defer { isCheckingQuality = false }
        do {
            let result = try await source.checkProxyQuality(id: id)
            guard isCurrent() else { return }
            show((proxy ?? shown).applying(result))
            let notice = ProxyQualityNotice(result)
            receipts.show(Receipt(text: notice.text, systemImage: notice.tone == .ok ? "checkmark.shield" : "exclamationmark.octagon", tone: notice.tone))
        } catch {
            guard isCurrent(), !(error is CancellationError) else { return }
            if ProxyDetailFailure.isGone(error) { return markGone() }
            receipts.show(Receipt(text: ProxyDetailCopy.qualityFailed, systemImage: "exclamationmark.octagon", tone: .critical))
        }
    }

    // MARK: - 停用 / 启用

    /// Straight away, with 撤销 (60 §0.4). An expired proxy, or a stopped one past its day (`serverNow` is the server's clock),
    /// is renewed in the editor instead, so nothing is sent for it.
    func toggleStatus(now serverNow: Date) async {
        guard let shown = proxy, !isBusy, isCurrent() else { return }
        let toggle = ProxyStatusToggle(shown, now: serverNow)
        guard let target = toggle.target, let back = toggle.undoTarget else { return }
        isUpdatingStatus = true
        let outcome = await ProxyStatusWrite(id: id, source: source, isCurrent: isCurrent).send(target, onto: shown)
        isUpdatingStatus = false
        guard isCurrent() else { return }
        switch outcome {
        case .applied(let updated):
            show(updated)
            let name = ProxyPresentation.displayName(updated)
            let text = toggle == .disable ? ProxyDetailCopy.disabled(name: name, accountCount: max(0, updated.accountCount ?? 0))
                : ProxyDetailCopy.enabled(name: name)
            receipts.show(Receipt(text: text, systemImage: toggle == .disable ? "minus.circle" : "checkmark.circle",
                                  tone: toggle == .disable ? .neutral : .ok, undo: undoAction(back)))
        case .failed(let failure, let fresh):
            if let fresh { show(fresh) }
            report(failure) { ProxyDetailCopy.statusFailed(toggle, reason: $0) }
        case .ignored: break
        }
    }

    /// The receipt's 撤销: only Sendable parts are captured, so the write still goes out once this page is gone (then onto the
    /// catalog's row, if it has one).
    private func undoAction(_ status: ProxyStatusChange) -> @MainActor @Sendable () -> Void {
        let write = ProxyStatusWrite(id: id, source: source, isCurrent: isCurrent)
        let receipts = receipts, store = store
        return { [weak self] in
            Task { @MainActor in
                if let self { return await self.runUndo(status, write: write) }
                let base = store?.proxy(id: write.id)
                switch await write.send(status, onto: base) {
                case .applied(let updated): if base != nil { store?.replace(updated) }
                case .failed(let failure, _): ProxyStatusWrite.report(failure, to: receipts) { ProxyDetailCopy.undoFailed(reason: $0) }
                case .ignored: break
                }
            }
        }
    }
    private func runUndo(_ status: ProxyStatusChange, write: ProxyStatusWrite) async {
        guard let shown = proxy, !isBusy, isCurrent() else { return }
        isUpdatingStatus = true
        let outcome = await write.send(status, onto: shown)
        isUpdatingStatus = false
        guard isCurrent() else { return }
        switch outcome {
        case .applied(let updated): show(updated)
        case .failed(let failure, let fresh):
            if let fresh { show(fresh) }
            report(failure) { ProxyDetailCopy.undoFailed(reason: $0) }
        case .ignored: break
        }
    }

    // MARK: - 删除

    /// 13.4: deleted or already gone → out of the catalog, “已删除代理「X」”, and the page pops. 409 PROXY_IN_USE → one of the two
    /// boxes (without the count in metadata the proxy is read again for it). A lost reply is read back.
    func delete() async -> ProxyDeleteOutcome {
        guard let shown = proxy, !isBusy, isCurrent() else { return .ignored }
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await source.deleteProxy(id: id)
            return isCurrent() ? finishDeleted(shown) : .ignored
        } catch {
            guard isCurrent() else { return .ignored }
            if let api = error as? APIError, ProxyDeleteBlock.isInUseConflict(api) { return await blocked(by: api, shown: shown) }
            switch ProxyDetailFailure.classify(error) {
            case .cancelled: return .ignored
            case .gone: return finishDeleted(shown)
            case .reconfirm(let notice):
                receipts.show(Receipt(text: notice, systemImage: "checkmark.shield", tone: .caution))
                return .ignored
            case .rejected(let reason):
                receipts.show(Self.failureReceipt(ProxyDetailCopy.deleteFailed(reason: reason)))
                return .failed
            case .unconfirmed: return await readBackDeleted(after: error, shown: shown)
            }
        }
    }

    private func blocked(by error: APIError, shown: AdminProxy) async -> ProxyDeleteOutcome {
        if let block = ProxyDeleteBlock.fromConflict(error, name: ProxyPresentation.displayName(shown)) { return .blocked(block) }
        let fresh = try? await source.proxy(id: id)
        guard isCurrent() else { return .ignored }
        if let fresh { show(fresh) }
        return .blocked(ProxyDeleteBlock.resolveInUse(refreshed: fresh, local: shown))
    }
    /// Still there → the transport's words; gone → deleted; unreadable → unconfirmed.
    private func readBackDeleted(after error: any Error, shown: AdminProxy) async -> ProxyDeleteOutcome {
        let result = await Self.capture { [source, id] in try await source.proxy(id: id) }
        guard isCurrent() else { return .ignored }
        switch result {
        case .success(let fresh):
            show(fresh)
            receipts.show(Self.failureReceipt(ProxyDetailCopy.deleteFailed(reason: error.localizedDescription)))
            return .failed
        case .failure(let readError) where ProxyDetailFailure.isGone(readError): return finishDeleted(shown)
        case .failure:
            receipts.show(Self.unconfirmedReceipt)
            return .unconfirmed
        }
    }
    private func finishDeleted(_ shown: AdminProxy) -> ProxyDeleteOutcome {
        didDelete = true
        store?.remove(id: id)
        let name = ProxyPresentation.displayName(shown)
        receipts.show(Receipt(text: DeleteConfirmationCopy.deletedReceipt(objectNoun: ProxyDetailCopy.objectNoun, displayName: name), systemImage: "trash"))
        return .deleted
    }

    // MARK: - Helpers

    /// What the server holds now: drops a read still running and writes the row back to the catalog. An older server's read
    /// without counts keeps the ones shown (H02).
    private func show(_ fresh: AdminProxy) {
        let row = fresh.keepingCounts(of: proxy ?? store?.proxy(id: id))
        detailTicket = UUID()
        detail = .loaded(row, at: now())
        store?.replace(row)
    }
    private func markGone() {
        detailTicket = UUID()
        accountsTicket = UUID()
        isGone = true
        detail = .idle
        accounts = .idle
        store?.remove(id: id)
    }
    private func report(_ failure: ProxyDetailFailure, rejected text: (String) -> String) {
        if failure == .gone { return markGone() }
        ProxyStatusWrite.report(failure, to: receipts, rejected: text)
    }
    private static var unconfirmedReceipt: Receipt {
        Receipt(text: ProxyDetailCopy.unconfirmed, systemImage: "exclamationmark.triangle", tone: .caution)
    }
    private static func failureReceipt(_ text: String) -> Receipt { Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .critical) }
    private nonisolated static func capture<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
