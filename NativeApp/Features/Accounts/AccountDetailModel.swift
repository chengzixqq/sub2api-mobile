import Foundation
import Observation
import Sub2Core

/// 20 §2.2 / §2.6: the account detail's data. The first screen is the list's row when there is one; `GET :id` replaces it and
/// keeps its ETag as the edit version. A write's account replaces it at once and leaves the version to be read again before the
/// next PATCH (`etagNeedsRefresh`), since only GET and PATCH send one. Reads carry a ticket and the session's generation, as the
/// old detail did: a reply for an older read or session is dropped. The page runs `poll()` only in the foreground, while it is
/// visible and nothing covers it; later items add their sections' reads to `refreshAll()` and `lightRefresh()`.
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

    @ObservationIgnored private weak var app: AppModel?
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

    /// `GET :id`; 404 ACCOUNT_NOT_FOUND turns the page into “已删除”.
    func load() async {
        guard let app, isLive else { return }
        let ticket = UUID()
        readTicket = ticket
        isLoading = true
        // The next light refresh counts from here, so a foreground read and the timer do not both go out.
        lastSync = .now
        defer { if readTicket == ticket { isLoading = false } }
        do {
            let versioned = try await app.accountWithVersion(id: accountID)
            guard readTicket == ticket, isLive, !Task.isCancelled else { return }
            apply(versioned)
        } catch {
            guard readTicket == ticket, isLive, !(error is CancellationError), !Task.isCancelled else { return }
            if AccountDetailPresentation.isRemoved(error) { isRemoved = true; return }
            failure = error.localizedDescription
            lastSync = .now
        }
    }
    /// Pull to refresh: everything again (S2-09 adds today, the 5-hour window and the upstream errors).
    func refreshAll() async { await load() }
    /// runtime/batch for this id; a changed status or switch, or an id the reply left out, reads the account again. Without
    /// `accounts.runtime_batch`, or while only the list's snapshot is shown, it is a `GET :id`. A failure keeps the last values.
    func lightRefresh() async {
        guard let app, isLive, !isLoading else { return }
        guard loadedFromServer, let current = account, app.sessionContext?.has(.accountsRuntimeBatch) == true else { return await load() }
        let ticket = UUID()
        readTicket = ticket
        do {
            let runtime = try await app.accountRuntime(ids: [accountID])
            guard readTicket == ticket, isLive, !Task.isCancelled else { return }
            switch AccountDetailRefresh.apply(runtime, to: current) {
            case .merged(let merged):
                account = merged
                markSynced()
            case .reload:
                await load()
            }
        } catch {
            guard readTicket == ticket, !(error is CancellationError) else { return }
            lastSync = .now
        }
    }
    /// The 60-second loop; the page's task cancels it when its gate closes.
    func poll() async {
        while !Task.isCancelled, isLive {
            let elapsed = lastSync.map { Self.seconds(ContinuousClock.Instant.now - $0) }
            let wait = AccountDetailRefresh.delay(sinceLastRefresh: elapsed)
            if wait > 0 { do { try await Task.sleep(for: .seconds(wait)) } catch { return } }
            guard !Task.isCancelled else { return }
            await lightRefresh()
        }
    }
    /// A countdown reached zero (20 §0.2): the account is read once for that window end.
    func countdownElapsed(target: Date) async {
        guard lastCountdownTarget != target else { return }
        lastCountdownTarget = target
        await load()
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

    private func markSynced() {
        updatedAt = app?.serverNow()
        lastSync = .now
    }
    private var isLive: Bool { app?.sessionGeneration == generation }
    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
