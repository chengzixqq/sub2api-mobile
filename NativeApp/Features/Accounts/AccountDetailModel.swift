import Foundation
import Observation
import Sub2Core

/// 20 §2.2 / §2.6: the account detail's data. The first screen is the list's row when there is one; `GET :id` replaces it and
/// keeps its ETag as the edit version. A write's account replaces it at once and leaves the version to be read again before the
/// next PATCH (`etagNeedsRefresh`), since only GET and PATCH send one. Reads carry a ticket and the session's generation, as the
/// old detail did: a reply for an older read or session is dropped. The page runs `poll()` only in the foreground, while it is
/// visible and nothing covers it; 容量 · 今日 · 记录's reads (S2-09) go out on the same ticks and with `refreshAll()`.
@MainActor @Observable
final class AccountDetailModel {
    let accountID: Int
    private(set) var account: UpstreamAccount?
    /// The account came from the server (GET or a write), not from the list.
    private(set) var loadedFromServer = false
    private(set) var isLoading = false
    /// The last read's failure; shown only while nothing but the list's snapshot (or nothing) is there (20 §2.5).
    private(set) var failure: String?
    private(set) var isRemoved = false
    /// GET :id and PATCH's `ETag`, as sent.
    private(set) var etag: String?
    /// A write without an ETag replaced the account: read the version again before the next PATCH.
    private(set) var etagNeedsRefresh = false
    /// Site clock time of the last sync (S2-09's “更新于 HH:MM:SS”).
    private(set) var updatedAt: Date?
    private(set) var catalog: MetaCatalog = .builtin
    /// 20 §2.2 (S2-09): 今日, the 5-hour window and the upstream errors; each fails on its own.
    let today = LoadState<AccountTodayStats>()
    let usageWindow = LoadState<AccountUsageWindow>()
    let upstreamErrors = LoadState<AccountUpstreamErrors>()

    @ObservationIgnored private weak var app: AppModel?
    /// Device time before which the light refresh skips a block still backing off after failures (00 §4.6).
    @ObservationIgnored private var sectionDue: [AccountDetailBlock: Date] = [:]
    @ObservationIgnored private let generation: UUID
    @ObservationIgnored private var readTicket = UUID()
    /// Device time of the last sync: the light refresh only measures elapsed time (20 §0.6).
    @ObservationIgnored private var lastSync: ContinuousClock.Instant?
    @ObservationIgnored private var lastCountdownTarget: Date?

    init(app: AppModel, accountID: Int, preload: UpstreamAccount?) {
        self.app = app
        self.accountID = accountID
        generation = app.sessionGeneration
        account = preload?.id == accountID ? preload : nil
    }

    var page: AccountDetailPageState {
        AccountDetailPageState.resolve(hasAccount: account != nil, loadedFromServer: loadedFromServer, failure: failure, removed: isRemoved)
    }

    /// `GET :id`; 404 ACCOUNT_NOT_FOUND turns the page into “已删除”. False when the page cancelled the read (its gate closed)
    /// before it answered: it then counts neither for the 60 seconds nor for a countdown's window end.
    @discardableResult
    func load() async -> Bool {
        guard let app, isLive else { return true }
        let ticket = UUID()
        readTicket = ticket
        isLoading = true
        // The next light refresh counts from here, so a foreground read and the timer do not both go out.
        let previousSync = lastSync
        lastSync = .now
        defer { if readTicket == ticket { isLoading = false } }
        do {
            let versioned = try await app.accountWithVersion(id: accountID)
            guard readTicket == ticket, isLive else { return true }
            apply(versioned)
        } catch {
            guard readTicket == ticket, isLive else { return true }
            if Task.isCancelled { lastSync = previousSync; return false }
            guard !(error is CancellationError) else { return true }
            if AccountDetailPresentation.isRemoved(error) { isRemoved = true; return true }
            failure = error.localizedDescription
            lastSync = .now
        }
        return true
    }
    /// Pull to refresh and the return to the foreground: the account and every section again.
    func refreshAll() async {
        async let sections: Void = refreshSections(userInitiated: true)
        await load()
        await sections
        await refreshUsageWindowIfMissing()
    }
    /// runtime/batch for this id; a changed status or switch, or an id the reply left out, reads the account again. Without
    /// `accounts.runtime_batch`, or while only the list's snapshot is shown, it is a `GET :id`. A failure keeps the last values.
    func lightRefresh() async {
        guard let app, isLive, !isLoading else { return }
        guard loadedFromServer, let current = account, app.sessionContext?.has(.accountsRuntimeBatch) == true else { await load(); return }
        let ticket = UUID()
        readTicket = ticket
        do {
            let runtime = try await app.accountRuntime(ids: [accountID])
            guard readTicket == ticket, isLive, !Task.isCancelled else { return }
            switch AccountDetailRefresh.apply(runtime, to: current) {
            case .merged(let merged):
                // 容量's counters too (S2-09); the list's merge covers only what its rows show.
                account = runtime[accountID].map { AccountDetailPresentation.mergingCapacity($0, into: merged) } ?? merged
                markSynced()
            case .reload:
                await load()
            }
        } catch {
            guard readTicket == ticket, !Task.isCancelled else { return }
            lastSync = .now
        }
    }
    /// The 60-second loop; the page's task cancels it when its gate closes. While a read started elsewhere (pull to refresh,
    /// the foreground, 重试) is out, `lightRefresh` skips, so the loop waits a whole interval rather than spin the main actor.
    func poll() async {
        while !Task.isCancelled, isLive {
            let elapsed = lastSync.map { Self.seconds(ContinuousClock.Instant.now - $0) }
            let wait = AccountDetailRefresh.delay(sinceLastRefresh: elapsed, readInFlight: isLoading)
            if wait > 0 {
                await readUnreadSections()
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            async let sections: Void = refreshSections(userInitiated: false)
            await lightRefresh()
            await sections
            await refreshUsageWindowIfMissing()
        }
    }
    /// A countdown reached zero (20 §0.2): the account is read once for that window end, unless the page cancelled that read.
    func countdownElapsed(target: Date) async {
        guard lastCountdownTarget != target else { return }
        lastCountdownTarget = target
        let answered = await load()
        if !answered, lastCountdownTarget == target { lastCountdownTarget = nil }
    }
    /// A write's account (20 §2.6); an older read in flight is dropped.
    func applyWrite(_ updated: UpstreamAccount) {
        guard isLive, updated.id == accountID else { return }
        invalidateReads()
        account = updated
        loadedFromServer = true
        failure = nil
        etagNeedsRefresh = true
        markSynced()
    }
    /// GET or PATCH: the account with its version.
    func apply(_ versioned: VersionedAccount) {
        guard isLive, versioned.account.id == accountID else { return }
        account = versioned.account
        etag = versioned.etag
        etagNeedsRefresh = false
        loadedFromServer = true
        failure = nil
        markSynced()
    }
    /// An action found the account gone (20 §0.5).
    func noteMissing() {
        guard isLive else { return }
        invalidateReads()
        isRemoved = true
        today.cancel(); usageWindow.cancel(); upstreamErrors.cancel()
    }
    func loadCatalog() async {
        guard let app else { return }
        let result = await app.metaCatalog()
        if isLive { catalog = result }
    }
    func invalidateReads() {
        readTicket = UUID()
        isLoading = false
    }

    // MARK: 容量 · 今日 · 记录（S2-09）

    /// 20 §2.6: today, the 5-hour window (Anthropic token accounts only) and the upstream errors, side by side, each on its own.
    /// `userInitiated` (pull, foreground) also asks after OPS_DISABLED and during a failure backoff; a block still loading is left be.
    func refreshSections(userInitiated: Bool) async {
        guard isLive, !isRemoved else { return }
        var inFlight: Set<AccountDetailBlock> = []
        if today.isLoading { inFlight.insert(.today) }
        if usageWindow.isLoading { inFlight.insert(.usageWindow) }
        if upstreamErrors.isLoading { inFlight.insert(.upstreamErrors) }
        let blocks = AccountDetailPresentation.blocksToRefresh(account: account, upstream: upstreamErrors.value, userInitiated: userInitiated,
                                                               inFlight: inFlight, dueDates: sectionDue, now: Date())
        async let todayRead: Void = loadToday(if: blocks.contains(.today))
        async let windowRead: Void = loadUsageWindow(if: blocks.contains(.usageWindow))
        await loadUpstreamErrors(if: blocks.contains(.upstreamErrors))
        _ = await (todayRead, windowRead)
    }
    /// 今日's 重试, and the read again once a 429 wait ends.
    func reloadToday() async {
        guard !today.isLoading else { return }
        await loadToday(if: true)
    }
    /// An account opened by id is known only after `GET :id`: its 5-hour window is read then, once.
    func refreshUsageWindowIfMissing() async {
        guard let account, AccountUsageWindow.applies(to: account), Self.isUnread(usageWindow.state) else { return }
        await loadUsageWindow(if: true)
    }
    /// A first read the page cancelled (something covered it) goes out again as soon as the page is back, not a minute later.
    private func readUnreadSections() async {
        async let todayRead: Void = loadToday(if: Self.isUnread(today.state))
        async let windowRead: Void = refreshUsageWindowIfMissing()
        await loadUpstreamErrors(if: Self.isUnread(upstreamErrors.state))
        _ = await (todayRead, windowRead)
    }
    private static func isUnread<Value: Sendable>(_ state: BlockState<Value>) -> Bool {
        if case .idle = state { true } else { false }
    }

    private func loadToday(if needed: Bool) async {
        guard needed, let app, isLive, !isRemoved else { return }
        let id = accountID
        await today.load(isCurrent: { self.isLive && !self.isRemoved }) { try await app.accountTodayStats(id: id) }
        noteBackoff(.today, today.refresh)
    }
    private func loadUsageWindow(if needed: Bool) async {
        guard needed, let app, isLive, !isRemoved else { return }
        let id = accountID
        await usageWindow.load(isCurrent: { self.isLive && !self.isRemoved }) { try await app.accountPassiveUsage(id: id) }
        noteBackoff(.usageWindow, usageWindow.refresh)
    }
    private func loadUpstreamErrors(if needed: Bool) async {
        guard needed, let app, isLive, !isRemoved else { return }
        let id = accountID
        await upstreamErrors.load(isCurrent: { self.isLive && !self.isRemoved }) { try await app.accountUpstreamErrors(id: id) }
        noteBackoff(.upstreamErrors, upstreamErrors.refresh)
    }
    /// After failures the light refresh waits out the backoff (60 → 120 → 240 → 300 seconds); a success clears it. The tolerance
    /// keeps a block on the tick it is due on, since the ticks count from the account's sync, not from this block's answer.
    private func noteBackoff(_ block: AccountDetailBlock, _ refresh: BlockRefresh) {
        guard refresh.consecutiveFailures > 0 else { sectionDue[block] = nil; return }
        let wait = refresh.nextDelay(base: AccountDetailRefresh.interval, at: Date()) - Self.backoffTolerance
        sectionDue[block] = Date().addingTimeInterval(wait)
    }
    private static let backoffTolerance: TimeInterval = 5

    private func markSynced() {
        updatedAt = app?.serverNow()
        lastSync = .now
    }
    private var isLive: Bool { app?.sessionGeneration == generation }
    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    // MARK: 内联编辑（S2-10）

    /// The open edit sheet with its own base; the page does not poll meanwhile (20 §2.6).
    var editor: AccountEditorRequest?
    private(set) var isPreparingEdit = false
    /// The last “编辑” could not read the version: the section headers say “先刷新账号”.
    private(set) var editNeedsRefresh = false
}

extension AccountDetailModel {
    /// S2D1-06: an account the page has read from the server can be edited; the version is read first when needed.
    var canEdit: Bool { loadedFromServer && !isRemoved }

    /// The account and its version for a PATCH: `GET :id` first while the page only has the list's copy, or when the site has
    /// `accounts.patch` and the version is missing or stale after a write without one (S2D1-06). nil when it cannot be read; the
    /// headers then say “先刷新账号”.
    func editVersion() async -> AccountEditBase? {
        guard let app, isLive, !isRemoved, let account else { return nil }
        let versionMissing = app.accountWriteSession?.patch == true && (etag == nil || etagNeedsRefresh)
        guard !loadedFromServer || versionMissing else { return AccountEditBase(account: account, etag: etag) }
        do {
            let versioned = try await app.accountWithVersion(id: accountID)
            guard isLive else { return nil }
            invalidateReads()
            apply(versioned)
            editNeedsRefresh = false
            return AccountEditBase(versioned)
        } catch {
            guard isLive, !(error is CancellationError) else { return nil }
            if AccountDetailPresentation.isRemoved(error) { noteMissing() } else { editNeedsRefresh = true }
            return nil
        }
    }
    /// Opens the section's sheet on the account's current version (also 修改过期时间…, S2D1-20).
    func beginEdit(_ section: AccountEditSection) async {
        guard editor == nil, !isPreparingEdit else { return }
        isPreparingEdit = true
        defer { isPreparingEdit = false }
        guard let base = await editVersion(), let flow = makePatchFlow() else { return }
        editor = AccountEditorRequest(section: section, base: base, flow: flow)
    }
    /// C-14 for this account: what it saves or reads back replaces the page's account and version; a deleted account closes the
    /// sheet and shows “已删除”; 重新载入 reads the whole page again.
    func makePatchFlow() -> AccountPatchFlow? {
        guard let app else { return nil }
        return AccountPatchFlow(model: app, accountID: accountID, onChange: { [weak self] in self?.applyEdit($0) },
                                onRemoved: { [weak self] in
                                    self?.editor = nil
                                    self?.noteMissing()
                                },
                                onReload: { [weak self] in
                                    guard let self else { return }
                                    Task { await self.refreshAll() }
                                })
    }
    func applyEdit(_ base: AccountEditBase) {
        invalidateReads()
        apply(VersionedAccount(account: base.account, etag: base.etag))
    }
}
