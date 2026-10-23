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
    private(set) var pendingBalances: [PendingBalanceOperation] = []
    var errorMessage: String?
    var isRestoring = true
    private(set) var isSigningOut = false
    var isConnecting = false
    let isUITesting: Bool
    let credentials: KeychainCredentialStore
    private let defaults: UserDefaults
    @ObservationIgnored private var demoUsersBySession: [UUID: [AdminUser]] = [:]
    @ObservationIgnored private var demoUserUpdates: [UUID: AdminUser] = [:]
    @ObservationIgnored private var connectionAttempt = UUID()
    @ObservationIgnored private var pendingCandidate: APIClient?
    @ObservationIgnored private var activeLease: UUID?
    @ObservationIgnored private var savedActiveID: UUID?
    @ObservationIgnored private var profileArchive: [UUID: ServerProfile] = [:]
    private let pendingFileURL: URL?
    @ObservationIgnored private var pendingPersistenceAvailable = true
    /// Scene state (D18); changed only by `sceneDidChange(to:)` in AppModel+Session.swift.
    var lifecycle = SessionLifecycle()
    /// Keeps suspend and resume reaching the client in order (AppModel+Session.swift).
    @ObservationIgnored var sceneTask: Task<Void, Never>?
    var sessionContext: SessionContext? {
        guard let client, let activeProfile, let siteSession else { return nil }
        return SessionContext(generation: sessionGeneration, serverID: activeProfile.id, client: client, site: siteSession)
    }
    /// `client.device_name` of a new login (00 §1.2).
    var deviceName: String { UIDevice.current.name }

    init(isUITesting: Bool = ProcessInfo.processInfo.arguments.contains("-ui-testing")) {
        self.isUITesting = isUITesting
        credentials = KeychainCredentialStore(memoryOnly: isUITesting)
        defaults = isUITesting ? UserDefaults(suiteName: "com.chengzixqq.sub2mobile.uitesting")! : .standard
        pendingFileURL = isUITesting ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sub2Mobile", isDirectory: true).appendingPathComponent("pending-balances.json")
        if isUITesting { defaults.removePersistentDomain(forName: "com.chengzixqq.sub2mobile.uitesting") }
        if let data = defaults.data(forKey: "profiles") { profiles = ServerProfile.storedList(from: data) }
        if let data = defaults.data(forKey: "profileArchive") { profileArchive = ServerProfile.storedArchive(from: data) }
        if let raw = defaults.string(forKey: "activeProfile") { savedActiveID = UUID(uuidString: raw) }
        if let pendingFileURL, FileManager.default.fileExists(atPath: pendingFileURL.path) {
            do { pendingBalances = try JSONDecoder().decode([PendingBalanceOperation].self, from: Data(contentsOf: pendingFileURL)) }
            catch { pendingPersistenceAvailable = false; errorMessage = "未决余额记录无法读取。请保留应用数据并检查设备存储；已暂停新的余额操作。" }
        }
    }

    func restore() async {
        defer { isRestoring = false }
        guard let id = savedActiveID, let profile = profiles.first(where: { $0.id == id }) else { return }
        do {
            guard let credential = try await credentials.load(serverID: id) else { return }
            try await connect(profile: profile, credential: credential)
        } catch { report(error) }
    }

    static func validatedURL(_ raw: String) throws -> URL {
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw AppFailure("请输入完整 HTTPS 站点地址，例如 https://sub2.example.com；不支持路径、账号或查询参数。")
        }
        components.scheme = "https"
        components.host = host.lowercased()
        components.path = ""
        guard let url = components.url else { throw AppFailure("站点地址无效。") }
        return url
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
        let next = wiring.makeClient(server: profile, credential: verified, store: store)
        publish(profile, generation: generation, site: site, client: next, lease: store.lease)
        await candidate.cancelAll()
        await previous.client?.cancelAll()
        if let id = previous.profileID, let lease = previous.lease { try await credentials.revoke(serverID: id, lease: lease, erase: false) }
    }

    /// `reprobeActiveSession` (back after five minutes) and S0-13 (after compliance and step-up) probe the connected site again.
    /// A token scope already known survives a failed scope probe; a reply for an older session is dropped.
    func reloadSiteSession() async throws {
        guard let client, let current = siteSession, let credential = await client.currentCredential() else { return }
        let generation = sessionGeneration
        let site = try await probe(client, credential: credential, knownScope: current.accessTokenScope)
        guard generation == sessionGeneration else { throw CancellationError() }
        siteSession = site
    }
    /// A write of this session was answered ACCESS_TOKEN_READ_ONLY (00 §1.6 step 3; S0-13 and 00 §2.6.3 call it).
    func markAccessTokenReadOnly(generation: UUID) {
        guard generation == sessionGeneration, let siteSession else { return }
        self.siteSession = siteSession.markingReadOnly()
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
        sessionGeneration = generation
        client = next
        siteSession = site
        activeLease = lease
        activeProfile = profile
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        savedActiveID = profile.id
        persistProfiles()
    }

    func switchTo(_ profile: ServerProfile) async {
        guard !isSigningOut else { return }
        let attempt = beginConnection()
        do {
            guard let credential = try await credentials.load(serverID: profile.id) else {
                throw AppFailure("此站点凭据已清除，请重新登录。")
            }
            try await connect(profile: profile, credential: credential, attempt: attempt)
        } catch { report(error) }
    }

    func logout() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        let old = client
        let id = activeProfile?.id
        let lease = activeLease
        cancelConnection()
        sessionGeneration = UUID()
        client = nil
        siteSession = nil
        activeProfile = nil
        activeLease = nil
        savedActiveID = nil
        persistProfiles()
        await old?.cancelAll()
        if let id {
            do {
                if let lease { try await credentials.revoke(serverID: id, lease: lease, erase: true) }
                else { try await credentials.eraseCredential(serverID: id) }
            } catch { report(error) }
        }
        // Fixture sites are not reachable; S0-11 rewrites this order (00 §1.7.5).
        guard !isUITesting else { return }
        do { try await old?.logout() } catch { report(error) }
    }

    func remove(_ profile: ServerProfile) async {
        if pendingBalances.contains(where: { $0.serverID == profile.id }) { profileArchive[profile.id] = profile }
        let wasActive = activeProfile?.id == profile.id
        if wasActive { await logout() }
        cancelConnection()
        profiles.removeAll { $0.id == profile.id }
        persistProfiles()
        // Signing out above kept the device ID; deleting the site removes it too (00 §1.1). S0-11 completes the order.
        do {
            try await credentials.remove(serverID: profile.id)
        } catch { report(error) }
    }

    /// The only way to obtain a sendable money write: its record is saved first, and a failed save sends nothing (00 §0 rule 4).
    /// S0-12 adds the redeem-batch and compensation overloads.
    func persisted(_ operation: PendingBalanceOperation) throws -> PersistedMoneyWrite<PendingBalanceOperation> {
        try PersistedMoneyWrite(operation) { try remember($0) }
    }

    /// Adds a record, or replaces the one with the same id (for example to save the action id before the result is known).
    func remember(_ operation: PendingBalanceOperation) throws {
        guard pendingPersistenceAvailable else { throw AppFailure("未决余额记录无法读取，已阻止新请求。请保留应用数据并检查设备存储。") }
        let old = pendingBalances
        if let index = pendingBalances.firstIndex(where: { $0.id == operation.id }) { pendingBalances[index] = operation }
        else { pendingBalances.append(operation) }
        do { try persistPending() }
        catch { pendingBalances = old; throw error }
    }

    func resolve(_ operation: PendingBalanceOperation) throws {
        let old = pendingBalances
        pendingBalances.removeAll { $0.id == operation.id }
        do { try persistPending() } catch { pendingBalances = old; throw error }
    }

    func report(_ error: Error) {
        guard !(error is CancellationError) else { return }
        errorMessage = error.localizedDescription
    }

    func profileForRecord(serverID: UUID) -> ServerProfile? { profiles.first { $0.id == serverID } ?? profileArchive[serverID] }

    func requireClient() throws -> APIClient {
        guard let client else { throw AppFailure("请先连接站点。") }
        return client
    }

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
    func dashboardPerformanceTrend(hours: Int) async throws -> PerformanceTrend {
        if isUITesting {
            if ProcessInfo.processInfo.arguments.contains("-ui-performance-error") {
                throw APIError.server(status: 404, reason: "OPS_DISABLED")
            }
            let bucket: PerformanceTrend.Bucket = hours == 1 ? .minute : .fiveMinutes
            let end = Date(timeIntervalSince1970: 1_792_026_000)
            let start = end.addingTimeInterval(-Double(hours) * 3_600)
            let count = Int(Double(hours) * 3_600 / bucket.seconds)
            return PerformanceTrend(bucket: bucket, points: (0..<count).map { index in
                PerformanceTrend.Point(date: start.addingTimeInterval(Double(index) * bucket.seconds), requestCount: 10 + index,
                                       tokenConsumed: 100_000 + index * 10_000)
            })
        }
        let end = Date()
        return try await requireClient().dashboardPerformanceTrend(start: end.addingTimeInterval(-Double(hours) * 3_600), end: end)
    }
    func accounts(page: Int, search: String, status: String?, platform: String?, includeSchedulerScore: Bool = false) async throws -> Page<UpstreamAccount> {
        if isUITesting {
            let result = DemoData.accounts(page: page, search: search, status: status, platform: platform)
            return result.mapItems(accountFixture)
        }
        return try await requireClient().accounts(page: page, search: search, status: status, platform: platform, includeSchedulerScore: includeSchedulerScore)
    }
    func account(id: Int) async throws -> UpstreamAccount {
        if isUITesting { return accountFixture(DemoData.allAccounts.first { $0.id == id }!) }
        return try await requireClient().account(id: id)
    }
    func accountTodayStats(id: Int) async throws -> AccountTodayStats {
        if isUITesting { try await accountStatsFixtureDelay(); return DemoData.accountStats }
        return try await requireClient().accountTodayStats(id: id)
    }
    func accountTodayStats(ids: [Int]) async throws -> [Int: AccountTodayStats] {
        if isUITesting {
            try await accountStatsFixtureDelay()
            return Dictionary(uniqueKeysWithValues: Set(ids).map { ($0, DemoData.accountStats) })
        }
        return try await requireClient().accountTodayStats(ids: ids)
    }
    private func accountFixture(_ initial: UpstreamAccount) -> UpstreamAccount {
        var account = initial
        if ProcessInfo.processInfo.arguments.contains("-ui-account-runtime-missing") { account.currentRPM = nil }
        return account
    }
    private func accountStatsFixtureDelay() async throws {
        if ProcessInfo.processInfo.arguments.contains("-ui-account-slow-stats") { try await Task.sleep(for: .seconds(45)) }
        if ProcessInfo.processInfo.arguments.contains("-ui-account-stats-error") { throw AppFailure("账号今日统计测试失败") }
    }
    func users(page: Int, search: String, status: String?) async throws -> Page<AdminUser> {
        if isUITesting {
            let matches = (demoUsersBySession[sessionGeneration] ?? DemoData.allUsers).filter {
                (search.isEmpty || $0.email.localizedCaseInsensitiveContains(search) || ($0.username?.localizedCaseInsensitiveContains(search) ?? false)) && (status == nil || status == $0.status)
            }
            return Page(items: Array(matches.dropFirst(max(0, page - 1)).prefix(1)), total: matches.count, page: page, pageSize: 1, pages: matches.count)
        }
        return try await requireClient().users(page: page, search: search, status: status)
    }
    func user(id: Int) async throws -> AdminUser {
        if isUITesting {
            guard let result = (demoUsersBySession[sessionGeneration] ?? DemoData.allUsers).first(where: { $0.id == id }) else { throw APIError.invalidResponse }
            return result
        }
        return try await requireClient().user(id: id)
    }
    func createUser(_ operation: PendingUserCreateOperation) async throws -> WriteOutcome<AdminUser> {
        let client = try requireClient()
        if !isUITesting { return try await client.createUser(operation) }
        let generation = sessionGeneration
        guard operation.identity == (await client.userWriteIdentity()), generation == sessionGeneration else { throw CancellationError() }
        var payload = try JSONSerialization.jsonObject(with: operation.body) as! [String: Any]
        payload.removeValue(forKey: "password")
        var users = demoUsersBySession[generation] ?? DemoData.allUsers
        guard !users.contains(where: { $0.email == operation.email }) else {
            throw APIError(kind: .validation, message: "此邮箱已经存在。")
        }
        payload["id"] = (users.map(\.id).max() ?? 0) + 1
        payload["balance"] = payload["balance"] ?? 0
        payload["status"] = "active"
        payload["created_at"] = ISO8601DateFormatter().string(from: Date())
        let user = try JSONDecoder().decode(AdminUser.self, from: JSONSerialization.data(withJSONObject: payload))
        users.insert(user, at: 0); demoUsersBySession[generation] = users
        return WriteOutcome(value: user)
    }
    func updateUser(_ operation: PendingUserUpdateOperation) async throws -> WriteOutcome<AdminUser> {
        let client = try requireClient()
        if !isUITesting { return try await client.updateUser(operation) }
        let generation = sessionGeneration
        guard operation.serverID == activeProfile?.id, operation.identity == (await client.userWriteIdentity()), generation == sessionGeneration else {
            throw APIError.stationMismatch
        }
        if let result = demoUserUpdates[operation.id] { return WriteOutcome(value: result, replayed: true) }
        var users = demoUsersBySession[generation] ?? DemoData.allUsers
        guard let index = users.firstIndex(where: { $0.id == operation.userID }) else { throw APIError.invalidResponse }
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(users[index])) as! [String: Any]
        let changes = try JSONSerialization.jsonObject(with: operation.body) as! [String: Any]
        for (key, value) in changes where key != "password" && key != "adjustment_notes" { payload[key] = value }
        let user = try JSONDecoder().decode(AdminUser.self, from: JSONSerialization.data(withJSONObject: payload))
        users[index] = user; demoUsersBySession[generation] = users; demoUserUpdates[operation.id] = user
        return WriteOutcome(value: user)
    }
    func userUsage(id: Int) async throws -> UserUsageSummary {
        if isUITesting { return UserUsageSummary(totalRequests: 12, totalTokens: 4200, totalCost: Decimal(string: "0.12")!) }
        return try await requireClient().userUsage(id: id)
    }
    func userKeys(id: Int, page: Int) async throws -> Page<UserAPIKey> {
        if isUITesting { return Page(items: DemoData.keys, total: 1, page: 1, pageSize: 20, pages: 1) }
        return try await requireClient().userKeys(id: id, page: page)
    }

    private func persistProfiles() {
        defaults.set(try? JSONEncoder().encode(profiles), forKey: "profiles")
        defaults.set(savedActiveID?.uuidString, forKey: "activeProfile")
        defaults.set(try? JSONEncoder().encode(profileArchive), forKey: "profileArchive")
    }
    private func persistPending() throws {
        guard let pendingFileURL else { return }
        try FileManager.default.createDirectory(at: pendingFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(pendingBalances).write(to: pendingFileURL, options: [.atomic, .completeFileProtection])
    }
}

struct AppFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
