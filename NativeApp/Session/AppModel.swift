import Foundation
import Observation
import Sub2Core
import SwiftUI

struct SessionContext: Sendable {
    let generation: UUID
    let serverID: UUID
    let client: APIClient
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
    private(set) var pendingBalances: [PendingBalanceOperation] = []
    var errorMessage: String?
    var isRestoring = true
    private(set) var isSigningOut = false
    var isConnecting = false
    let isUITesting: Bool
    let credentials: KeychainCredentialStore
    private let defaults: UserDefaults
    @ObservationIgnored private var connectionAttempt = UUID()
    @ObservationIgnored private var pendingCandidate: APIClient?
    @ObservationIgnored private var activeLease: UUID?
    @ObservationIgnored private var savedActiveID: UUID?
    private let pendingFileURL: URL?
    @ObservationIgnored private var pendingPersistenceAvailable = true
    var sessionContext: SessionContext? {
        guard let client, let activeProfile else { return nil }
        return SessionContext(generation: sessionGeneration, serverID: activeProfile.id, client: client)
    }

    init(isUITesting: Bool = ProcessInfo.processInfo.arguments.contains("-ui-testing")) {
        self.isUITesting = isUITesting
        credentials = KeychainCredentialStore(memoryOnly: isUITesting)
        defaults = isUITesting ? UserDefaults(suiteName: "com.chengzixqq.sub2mobile.uitesting")! : .standard
        pendingFileURL = isUITesting ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sub2Mobile", isDirectory: true).appendingPathComponent("pending-balances.json")
        if isUITesting { defaults.removePersistentDomain(forName: "com.chengzixqq.sub2mobile.uitesting") }
        if let data = defaults.data(forKey: "profiles") {
            profiles = (try? JSONDecoder().decode([ServerProfile].self, from: data)) ?? []
        }
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

    func connect(profile: ServerProfile, credential: Credential, attempt: UUID? = nil) async throws {
        guard !isSigningOut else { throw CancellationError() }
        let ticket = attempt ?? beginConnection()
        guard ticket == connectionAttempt else { throw CancellationError() }
        isConnecting = true
        defer { if ticket == connectionAttempt { isConnecting = false; pendingCandidate = nil } }
        // Verification may refresh a token, but never touches the shared vault.
        let candidate = APIClient(server: profile, credential: credential)
        pendingCandidate = candidate
        defer { Task { await candidate.cancelAll() } }
        if !isUITesting { try await candidate.verifyAdministrator() }
        guard ticket == connectionAttempt else { await candidate.cancelAll(); throw CancellationError() }
        let verifiedCredential = await candidate.currentCredential() ?? credential
        guard ticket == connectionAttempt else { await candidate.cancelAll(); throw CancellationError() }
        let lease = UUID()
        let scopedStore = try await credentials.commit(verifiedCredential, serverID: profile.id, lease: lease)
        guard ticket == connectionAttempt else {
            try await credentials.revoke(serverID: profile.id, lease: lease, erase: true)
            await candidate.cancelAll(); throw CancellationError()
        }
        let previous = client
        let previousProfileID = activeProfile?.id
        let previousLease = activeLease
        sessionGeneration = UUID()
        client = APIClient(server: profile, credential: verifiedCredential, credentialStore: scopedStore)
        activeLease = lease
        activeProfile = profile
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        savedActiveID = profile.id
        persistProfiles()
        await candidate.cancelAll()
        await previous?.cancelAll()
        if let previousProfileID, let previousLease { try await credentials.revoke(serverID: previousProfileID, lease: previousLease, erase: false) }
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
        activeProfile = nil
        activeLease = nil
        savedActiveID = nil
        persistProfiles()
        await old?.cancelAll()
        if let id {
            do {
                if let lease { try await credentials.revoke(serverID: id, lease: lease, erase: true) }
                else { try await credentials.remove(serverID: id) }
            } catch { report(error) }
        }
        do { try await old?.logout() } catch { report(error) }
    }

    func remove(_ profile: ServerProfile) async {
        guard !pendingBalances.contains(where: { $0.serverID == profile.id }) else {
            errorMessage = "此站点仍有结果待确认的余额请求，请先处理原请求，再删除站点。"; return
        }
        let wasActive = activeProfile?.id == profile.id
        if wasActive { await logout() }
        cancelConnection()
        profiles.removeAll { $0.id == profile.id }
        persistProfiles()
        if wasActive { return }
        do {
            try await credentials.remove(serverID: profile.id)
        } catch { report(error) }
    }

    func remember(_ operation: PendingBalanceOperation) throws {
        guard pendingPersistenceAvailable else { throw AppFailure("未决余额记录无法读取，已阻止新请求。请保留应用数据并检查设备存储。") }
        let old = pendingBalances
        if !pendingBalances.contains(where: { $0.id == operation.id }) { pendingBalances.append(operation) }
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

    func requireClient() throws -> APIClient {
        guard let client else { throw AppFailure("请先连接站点。") }
        return client
    }

    func dashboard() async throws -> DashboardSummary {
        if isUITesting { return DemoData.dashboard }
        return try await requireClient().dashboard()
    }
    func accounts(page: Int, search: String, status: String?, platform: String?) async throws -> Page<UpstreamAccount> {
        if isUITesting { return DemoData.accounts(page: page, search: search, status: status, platform: platform) }
        return try await requireClient().accounts(page: page, search: search, status: status, platform: platform)
    }
    func account(id: Int) async throws -> UpstreamAccount {
        if isUITesting { return DemoData.allAccounts.first { $0.id == id }! }
        return try await requireClient().account(id: id)
    }
    func accountTodayStats(id: Int) async throws -> AccountTodayStats {
        if isUITesting { return AccountTodayStats(requests: 12, tokens: 4200, cost: Decimal(string: "0.12")!) }
        return try await requireClient().accountTodayStats(id: id)
    }
    func users(page: Int, search: String, status: String?) async throws -> Page<AdminUser> {
        if isUITesting { return DemoData.users(page: page, search: search, status: status) }
        return try await requireClient().users(page: page, search: search, status: status)
    }
    func user(id: Int) async throws -> AdminUser {
        if isUITesting { return DemoData.allUsers.first { $0.id == id }! }
        return try await requireClient().user(id: id)
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
