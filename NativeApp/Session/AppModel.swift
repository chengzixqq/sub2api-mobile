import Foundation
import Observation
import Sub2Core
import SwiftUI
import UIKit

struct SessionContext: Sendable {
    let generation: UUID
    let serverID: UUID
    let client: APIClient
    let site: SiteSession
    /// Pages gate features with this, for example `session?.has(.dashboardRates)` (00 §5, D08).
    func has(_ capability: Capability) -> Bool { site.has(capability) }
    var isReadOnlyToken: Bool { site.isReadOnlyToken }
}

private struct SessionContextKey: EnvironmentKey { static let defaultValue: SessionContext? = nil }
extension EnvironmentValues {
    var sessionContext: SessionContext? {
        get { self[SessionContextKey.self] }
        set { self[SessionContextKey.self] = newValue }
    }
}

@MainActor @Observable
final class AppModel {
    var profiles: [ServerProfile] = []
    private(set) var activeProfile: ServerProfile?
    private(set) var sessionGeneration = UUID()
    private(set) var client: APIClient?
    /// Published together with `client` (D13); nil while no site is connected.
    private(set) var siteSession: SiteSession?
    /// Money writes awaiting a result (00 §2.5.5); read and changed through AppModel+Pending.swift.
    private(set) var pendingMoney = PendingMoneyLedger()
    /// The global compliance and step-up sheet (AppModel+Security.swift); reset whenever the session changes.
    let securityPrompts = SecurityPromptCenter()
    /// The one receipt (10 §0.7-6); app-level, so a switch's receipt outlives the rebuilt tabs.
    let receipts = ReceiptCenter(announce: { AccessibilityNotification.Announcement($0).post() })
    /// This phone's settings (60 §3.2) and the Face ID coverage list applied to them (60 §3.4); kept across sites.
    let preferences: AppPreferences
    let biometricGate: BiometricGate
    var errorMessage: String? {
        didSet { if errorMessage != errorDetails?.message { errorDetails = nil } }
    }
    /// The “详情” of the error now in the root alert (00 §3.4); set only by `report`, dropped with the message it belongs to.
    private(set) var errorDetails: ErrorDetails?
    var isRestoring = true
    /// Set while signing out or deleting the connected site (AppModel+Session.swift).
    var isSigningOut = false
    /// Deleted sites whose server steps are still running; the settings page shows them in progress (D19).
    var removingSites: [ServerProfile] = []
    /// The site login page to show: the root page without a connected site, a sheet over it otherwise (00 §1.1).
    var loginPrompt: LoginPrompt?
    var isConnecting = false
    let isUITesting: Bool
    let credentials: KeychainCredentialStore
    let pushRecords: PushDeviceRecords
    private let defaults: UserDefaults
    @ObservationIgnored var demoUsersBySession: [UUID: [AdminUser]] = [:]
    /// `-ui-count-user-loads`: the user list's username field reads “读取 N 次”, so a reload is visible (D18).
    @ObservationIgnored var demoUserLoads = 0
    @ObservationIgnored var demoUserUpdates: [UUID: AdminUser] = [:]
    @ObservationIgnored private var connectionAttempt = UUID()
    @ObservationIgnored private var pendingCandidate: APIClient?
    @ObservationIgnored private var activeLease: UUID?
    @ObservationIgnored private var savedActiveID: UUID?
    /// Deleted sites that still have records awaiting reconciliation (AppModel+Session.swift adds to it).
    @ObservationIgnored var profileArchive: [UUID: ServerProfile] = [:]
    private let pendingFiles: PendingMoneyFiles
    /// Scene state (D18); changed only by `sceneDidChange(to:)` in AppModel+Session.swift.
    var lifecycle = SessionLifecycle()
    /// Keeps suspend and resume reaching the client in order (AppModel+Session.swift).
    @ObservationIgnored var sceneTask: Task<Void, Never>?

    // MARK: - 阶段 1 · 会话级状态
    // 阶段 1 的条目在这里追加
    /// C-9, 10 §0.5: the session's home blocks, alert list and ops state; pages read it here (X03). Rebuilt with the session.
    private(set) var liveOps: LiveOpsStore?

    // MARK: - 阶段 2 · 会话级状态
    // 阶段 2 的条目在这里追加
    /// C-11: the account tab's error count; the account list and LiveOpsStore write it. Rebuilt with the session.
    private(set) var accountBadge = AccountErrorBadge()
    /// C-10: the session's group names and order, loaded on first use (AppModel+Accounts.swift); nil without a site.
    private(set) var groupDirectory: GroupDirectory?
    /// 20 §1.6: the badge's 60-second foreground fetch (AppModel+Accounts.swift), one loop per session.
    @ObservationIgnored var accountBadgeTask: Task<Void, Never>?

    // MARK: - 阶段 3 · 会话级状态
    // 阶段 3 的条目在这里追加
    /// C-12: bumped after a balance write, a save or a compensation; the user page watches it. Rebuilt with the session.
    private(set) var userChanges: UserChangeSignal?

    // MARK: - 阶段 4 · 会话级状态
    // 阶段 4 的条目在这里追加
    /// X21 / C-13: page state shared along one tab's stack (analytics, usage-record lists). Rebuilt with the session.
    private(set) var pageStates: PageStateRegistry?

    // MARK: - 阶段 5 · 会话级状态
    // 阶段 5 的条目在这里追加

    // MARK: - 阶段 6 · 会话级状态
    // 阶段 6 的条目在这里追加

    // MARK: - 阶段 1 · App 级状态
    // 阶段 1 的条目在这里追加

    // MARK: - 阶段 2 · App 级状态
    // 阶段 2 的条目在这里追加

    // MARK: - 阶段 3 · App 级状态
    // 阶段 3 的条目在这里追加

    // MARK: - 阶段 4 · App 级状态
    // 阶段 4 的条目在这里追加

    // MARK: - 阶段 5 · App 级状态
    // 阶段 5 的条目在这里追加

    // MARK: - 阶段 6 · App 级状态
    // 阶段 6 的条目在这里追加

    // MARK: - 连接与会话
    var sessionContext: SessionContext? {
        guard let client, let activeProfile, let siteSession else { return nil }
        return SessionContext(generation: sessionGeneration, serverID: activeProfile.id, client: client, site: siteSession)
    }
    /// `client.device_name` of a new login (00 §1.2).
    var deviceName: String { UIDevice.current.name }

    init(isUITesting: Bool = ProcessInfo.processInfo.arguments.contains("-ui-testing")) {
        self.isUITesting = isUITesting
        credentials = KeychainCredentialStore(memoryOnly: isUITesting)
        let defaults = isUITesting ? UserDefaults(suiteName: "com.chengzixqq.sub2mobile.uitesting")! : .standard
        if isUITesting { defaults.removePersistentDomain(forName: "com.chengzixqq.sub2mobile.uitesting") }
        self.defaults = defaults
        pushRecords = PushDeviceRecords(defaults: defaults)
        pendingFiles = isUITesting ? .memoryOnly : .applicationSupport()
        let preferences = AppPreferences(defaults: defaults)
        self.preferences = preferences
        let authenticator: any BiometricAuthenticating = if isUITesting { DemoData.biometricAuthenticator(preferences) } else { SystemBiometricAuthenticator() }
        biometricGate = BiometricGate(preferences: preferences, authenticator: authenticator)
        // MARK: - 阶段 1 · App 级状态
        // 阶段 1 的条目在这里追加
        // MARK: - 阶段 2 · App 级状态
        // 阶段 2 的条目在这里追加
        // MARK: - 阶段 3 · App 级状态
        // 阶段 3 的条目在这里追加
        // MARK: - 阶段 4 · App 级状态
        // 阶段 4 的条目在这里追加
        // MARK: - 阶段 5 · App 级状态
        // 阶段 5 的条目在这里追加
        // MARK: - 阶段 6 · App 级状态
        // 阶段 6 的条目在这里追加
        if let data = defaults.data(forKey: "profiles") { profiles = ServerProfile.storedList(from: data) }
        if let data = defaults.data(forKey: "profileArchive") { profileArchive = ServerProfile.storedArchive(from: data) }
        if let raw = defaults.string(forKey: "activeProfile") { savedActiveID = UUID(uuidString: raw) }
        pendingMoney = PendingMoneyLedger.load(from: pendingFiles)
    }

    func restore() async {
        defer { isRestoring = false }
        // A prewarmed launch may run init while the device is still locked: read those files again before telling the user,
        // and before a login prompt decides whether the site id is reused (D17).
        reloadUnreadablePendingRecords()
        if let notice = pendingMoney.unreadableNotice { errorMessage = notice }
        guard let id = savedActiveID, let profile = profiles.first(where: { $0.id == id }) else { return }
        do {
            guard let credential = try await credentials.load(serverID: id) else {
                openSiteLogin(profile, notice: Self.credentialClearedNotice)
                return
            }
            try await connect(profile: profile, credential: credential)
        } catch { await connectionFailed(error, profile: profile) }
    }

    func beginConnection() -> UUID {
        cancelConnection()
        return connectionAttempt
    }
    func cancelConnection() {
        connectionAttempt = UUID(); isConnecting = false
        let pending = pendingCandidate; pendingCandidate = nil
        Task { await pending?.cancelAll() }
    }
    func isCurrent(_ attempt: UUID) -> Bool { attempt == connectionAttempt }

    /// 00 §1.1: the site is saved only after /admin/me accepted the credential, and a failed attempt never replaces the connected one.
    /// `draft` is the device ID a new login already sent; it is saved with the credential, otherwise the site's own is read.
    func connect(profile requested: ServerProfile, credential: Credential, deviceID draft: UUID? = nil, attempt: UUID? = nil) async throws {
        guard !isSigningOut else { throw CancellationError() }
        let ticket = attempt ?? beginConnection()
        guard ticket == connectionAttempt else { throw CancellationError() }
        isConnecting = true
        defer { if ticket == connectionAttempt { isConnecting = false; pendingCandidate = nil } }
        // A site saved before sat_ support was stored as an Admin Key site (00 §9.4).
        var profile = requested
        profile.authentication = credential.authenticationKind
        let deviceID: UUID
        if let draft { deviceID = draft } else { deviceID = try await credentials.deviceID(serverID: profile.id) }
        guard ticket == connectionAttempt else { throw CancellationError() }
        // Verification may refresh a token, but never touches the shared vault.
        let candidate = APIClient(server: profile, credential: credential, deviceID: deviceID)
        pendingCandidate = candidate
        defer { Task { await candidate.cancelAll() } }
        let site = try await probe(candidate, credential: credential, knownScope: nil)
        guard ticket == connectionAttempt else { throw CancellationError() }
        let verified = await candidate.currentCredential() ?? credential
        let wiring = await ClientWiring.inherit(from: candidate, site: site, deviceID: deviceID)
        let store = try await commit(verified, profile: profile, draft: draft, ticket: ticket)
        let previous = (client: client, profileID: activeProfile?.id, lease: activeLease)
        let generation = UUID()
        let next = wiring.makeClient(server: profile, credential: verified, store: store,
                                     onSessionInvalid: sessionInvalidHandler(serverID: profile.id, generation: generation),
                                     securityInterceptor: makeSecurityInterceptor(generation: generation))
        publish(profile, generation: generation, site: site, client: next, lease: store.lease)
        seedPendingFixture(serverID: profile.id)
        // Not awaited: connecting ends here while the compliance sheet waits for the administrator (S0-16).
        Task { await presentComplianceIfRequired() }
        await candidate.cancelAll()
        await previous.client?.cancelAll()
        await previous.client?.clearConditionalCache()
        if let id = previous.profileID, let lease = previous.lease { try await credentials.revoke(serverID: id, lease: lease, erase: false) }
    }

    /// `reprobeActiveSession` (back after five minutes) and S0-13 (after compliance and step-up) probe the connected site again.
    /// A token scope already known, or marked read-only meanwhile, survives a failed scope probe; a reply for an older session
    /// is dropped. The generation is read with the client, before anything suspends, and a replaced client is never probed.
    func reloadSiteSession() async throws {
        let generation = sessionGeneration
        guard let client, let current = siteSession, let credential = await client.currentCredential() else { return }
        guard generation == sessionGeneration else { throw CancellationError() }
        let site = try await probe(client, credential: credential, knownScope: current.accessTokenScope)
        guard generation == sessionGeneration, let latest = siteSession else { throw CancellationError() }
        siteSession = site.keepingReadOnlyMark(of: latest)
    }
    /// A write of this session was answered ACCESS_TOKEN_READ_ONLY (00 §1.6 step 3; S0-13 and 00 §2.6.3 call it).
    func markAccessTokenReadOnly(generation: UUID) {
        guard generation == sessionGeneration, let siteSession else { return }
        self.siteSession = siteSession.markingReadOnly()
    }

    /// Reports arrive on the client's actor; `invalidateSession` checks them against this site and generation (D13).
    private func sessionInvalidHandler(serverID: UUID, generation: UUID) -> @Sendable (SessionInvalidation) -> Void {
        { [weak self] invalidation in
            Task { @MainActor [weak self] in await self?.invalidateSession(invalidation, serverID: serverID, generation: generation) }
        }
    }
    private func probe(_ client: APIClient, credential: Credential, knownScope: String?) async throws -> SiteSession {
        if isUITesting { return DemoData.siteSession(credential: credential) }
        return try await SiteSession.establish(client: client, knownScope: knownScope)
    }
    /// The draft device ID goes in before the credential; an attempt that fails here or is overtaken right after takes both
    /// back, and the draft of a site that was never saved is forgotten (D07).
    private func commit(_ credential: Credential, profile: ServerProfile, draft: UUID?, ticket: UUID) async throws -> LeasedCredentialStore {
        guard ticket == connectionAttempt else { throw CancellationError() }
        let lease = UUID()
        let store: LeasedCredentialStore
        do { store = try await credentials.commit(credential, serverID: profile.id, lease: lease, deviceID: draft) }
        catch {
            try? await credentials.abandon(serverID: profile.id, lease: nil, forgetDevice: forgetsDraft(draft, of: profile))
            throw error
        }
        guard ticket == connectionAttempt else {
            try await credentials.abandon(serverID: profile.id, lease: lease, forgetDevice: forgetsDraft(draft, of: profile))
            throw CancellationError()
        }
        return store
    }
    private func forgetsDraft(_ draft: UUID?, of profile: ServerProfile) -> Bool {
        draft != nil && !profiles.contains { $0.id == profile.id }
    }
    /// One synchronous step, so no page sees a client without its site session. The generation is made before the client so
    /// S0-11's callbacks can capture it (D13).
    private func publish(_ profile: ServerProfile, generation: UUID, site: SiteSession, client next: APIClient, lease: UUID) {
        securityPrompts.reset()
        // The previous site's receipt (and its button) never shows over the new session; a switch shows its own after this.
        receipts.clear()
        sessionGeneration = generation
        client = next
        siteSession = site
        activeLease = lease
        activeProfile = profile
        // MARK: - 阶段 1 · 会话级状态
        // 阶段 1 的条目在这里追加
        let liveSource: any LiveOpsSource = if isUITesting {
            FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: ProcessInfo.processInfo.arguments), base: next.serverClock.now())
        } else { ClientLiveOpsSource(client: next) }
        liveOps = LiveOpsStore(generation: generation, source: liveSource, site: { [weak self] in self?.siteSession },
                               isCurrent: { [weak self] in self?.sessionGeneration == generation }, errorBadge: { [weak self] in self?.accountBadge },
                               serverNow: { [clock = next.serverClock] in clock.now() })
        // MARK: - 阶段 2 · 会话级状态
        // 阶段 2 的条目在这里追加
        accountBadge = AccountErrorBadge()
        groupDirectory = makeGroupDirectory(client: next)
        accountBadgeTask?.cancel()
        accountBadgeTask = Task { [weak self] in await self?.runAccountBadgeRefresh(generation: generation) }
        // MARK: - 阶段 3 · 会话级状态
        // 阶段 3 的条目在这里追加
        userChanges = UserChangeSignal()
        // MARK: - 阶段 4 · 会话级状态
        // 阶段 4 的条目在这里追加
        pageStates = PageStateRegistry()
        // MARK: - 阶段 5 · 会话级状态
        // 阶段 5 的条目在这里追加
        // MARK: - 阶段 6 · 会话级状态
        // 阶段 6 的条目在这里追加
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        savedActiveID = profile.id
        loginPrompt = nil
        persistProfiles()
    }

    enum SessionExit { case savedSites, siteLogin(notice: String?) }
    /// The local erasure of signing out, deleting, invalidation and forgetting (00 §0 rule 13, §1.7.5 step 4): one synchronous
    /// step leaves no page with the old client, then the client is cancelled, its ETag cache cleared and the credential
    /// erased (the device ID stays). Returns the copies the server-side teardown needs.
    func endActiveSession(cancelsConnection: Bool, then exit: SessionExit) async -> EndedSession? {
        guard let profile = activeProfile else { return nil }
        let old = client, lease = activeLease
        if cancelsConnection { cancelConnection() }
        securityPrompts.reset()
        receipts.clear()
        sessionGeneration = UUID()
        client = nil; siteSession = nil; activeProfile = nil; activeLease = nil; savedActiveID = nil
        // MARK: - 阶段 1 · 会话级状态
        // 阶段 1 的条目在这里追加
        liveOps = nil
        // MARK: - 阶段 2 · 会话级状态
        // 阶段 2 的条目在这里追加
        accountBadge = AccountErrorBadge()
        groupDirectory = nil
        accountBadgeTask?.cancel()
        accountBadgeTask = nil
        // MARK: - 阶段 3 · 会话级状态
        // 阶段 3 的条目在这里追加
        userChanges = nil
        // MARK: - 阶段 4 · 会话级状态
        // 阶段 4 的条目在这里追加
        pageStates = nil
        // MARK: - 阶段 5 · 会话级状态
        // 阶段 5 的条目在这里追加
        // MARK: - 阶段 6 · 会话级状态
        // 阶段 6 的条目在这里追加
        if case .siteLogin(let notice) = exit { openSiteLogin(profile, notice: notice) }
        persistProfiles()
        await old?.cancelAll()
        // Read after cancelAll, so a refresh landing now can no longer replace it.
        let credential = await old?.currentCredential()
        await old?.clearConditionalCache()
        do {
            if let lease { try await credentials.revoke(serverID: profile.id, lease: lease, erase: true) }
            else { try await credentials.eraseCredential(serverID: profile.id) }
        } catch { report(error) }
        guard let old else { return nil }
        return EndedSession(profile: profile, credential: credential, deviceID: old.deviceID)
    }

    /// The only writer of `pendingMoney`: the ledger saves its file first and is replaced only when that worked.
    func updatePendingMoney(_ change: (PendingMoneyLedger, PendingMoneyFiles) throws -> PendingMoneyLedger) rethrows {
        pendingMoney = try change(pendingMoney, pendingFiles)
    }

    func report(_ error: Error) {
        guard !(error is CancellationError) else { return }
        let details = ErrorDetails(error)
        errorMessage = error.localizedDescription
        errorDetails = details
    }

    func profileForRecord(serverID: UUID) -> ServerProfile? { profiles.first { $0.id == serverID } ?? profileArchive[serverID] }

    func requireClient() throws -> APIClient {
        guard let client else { throw AppFailure("请先连接站点。") }
        return client
    }

    // MARK: - 概览
    func dashboard() async throws -> DashboardSummary {
        if isUITesting {
            if ProcessInfo.processInfo.arguments.contains("-ui-missing-account-cost") {
                let original = try JSONEncoder().encode(DemoData.dashboard.stats)
                var fields = try JSONSerialization.jsonObject(with: original) as! [String: Any]
                fields.removeValue(forKey: "today_account_cost")
                fields.removeValue(forKey: "total_account_cost")
                let stats = try JSONDecoder().decode(DashboardStats.self, from: JSONSerialization.data(withJSONObject: fields))
                return DashboardSummary(stats: stats, trend: [])
            }
            return DemoData.dashboard
        }
        return try await requireClient().dashboard()
    }
    func dashboardCostSnapshot() async throws -> DashboardCostSnapshot {
        if isUITesting {
            if ProcessInfo.processInfo.arguments.contains("-ui-cost-snapshot-error") {
                throw APIError(kind: .transport, message: "费用快照超时，请重试。")
            }
            return DashboardCostSnapshot(actual: Decimal(string: "12.34")!, account: Decimal(string: "4.56")!,
                                         totalActual: Decimal(string: "1234.56")!, totalAccount: Decimal(string: "456.78")!)
        }
        return try await requireClient().dashboardCostSnapshot()
    }
    func dashboardTrend() async throws -> DashboardTrendReply {
        if isUITesting {
            if ProcessInfo.processInfo.arguments.contains("-ui-dashboard-slow-trend") {
                try await Task.sleep(for: .seconds(8))
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-dashboard-detail-errors") {
                throw APIError(kind: .transport, message: "趋势请求超时，请重试。")
            }
            let points = ProcessInfo.processInfo.arguments.contains("-ui-trend-long-series") ? DemoData.longHourlyTrend : DemoData.dashboard.trend
            return DashboardTrendReply(points: points, timeZone: DemoData.serverTimeZone.timeZone)
        }
        return try await requireClient().dashboardTrend()
    }
    func dashboardMonitoring() async throws -> OpsSnapshot {
        if isUITesting {
            if ProcessInfo.processInfo.arguments.contains("-ui-dashboard-detail-errors") {
                throw APIError(kind: .transport, message: "监控请求超时，请重试。")
            }
            return DemoData.dashboard.monitoring!
        }
        return try await requireClient().dashboardMonitoring()
    }
    func dashboardPerformanceTrend(hours: Int, groupID: Int? = nil, model: String? = nil,
                                   modelSource: ModelSource? = nil) async throws -> PerformanceTrend {
        if isUITesting {
            if ProcessInfo.processInfo.arguments.contains("-ui-performance-error") {
                throw APIError.server(status: 404, reason: "OPS_DISABLED")
            }
            // “Now” is 23 seconds past a minute: 6 and 24 hours get a partial first and last bucket, 1 hour stays 60 full ones.
            let window = OpsQuery.trailingWindow(hours: hours, endingAt: Date(timeIntervalSince1970: 1_792_026_083))
            let bucket = OpsBucket.forWindow(window.end.timeIntervalSince(window.start))
            let points = bucket.starts(from: window.start, to: window.end).enumerated().map { index, date in
                PerformanceTrend.Point(date: date, requestCount: 10 + index, tokenConsumed: 100_000 + index * 10_000)
            }
            return PerformanceTrend(bucket: bucket, windowStart: window.start, windowEnd: window.end, points: points)
        }
        // Read together before the await (D13), so a site switch cannot pair one site's capability with another's client.
        let client = try requireClient()
        let supportsModelFilter = siteSession?.has(.opsDashboardModelFilter) ?? false
        let query = OpsQuery.trailingWindow(hours: hours, endingAt: client.serverClock.now(), groupID: groupID, model: model,
                                            modelSource: modelSource)
        return try await client.dashboardPerformanceTrend(query, supportsModelFilter: supportsModelFilter)
    }

    // MARK: - 账号
    // The account wrappers and their fixture branches live in AppModel+Accounts.swift (S2-03, S2-04).

    // MARK: - 用户
    // The user wrappers and their fixture branches live in AppModel+Users.swift (S3-01).

    // MARK: - 站点列表保存
    func persistProfiles() {
        defaults.set(try? JSONEncoder().encode(profiles), forKey: "profiles")
        defaults.set(savedActiveID?.uuidString, forKey: "activeProfile")
        defaults.set(try? JSONEncoder().encode(profileArchive), forKey: "profileArchive")
    }
}

struct AppFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
