import Foundation
import Observation
import Sub2Core

@MainActor @Observable
final class AppModel {
    var profiles: [ServerProfile] = []
    private(set) var activeProfile: ServerProfile?
    private(set) var sessionGeneration = UUID()
    private(set) var client: APIClient?
    private(set) var pendingBalances: [PendingBalanceOperation] = []
    var errorMessage: String?
    var isRestoring = true
    var isConnecting = false
    let isUITesting: Bool
    @ObservationIgnored let credentials: any CredentialStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var connectionAttempt = UUID()
    @ObservationIgnored private var savedActiveID: UUID?

    init(isUITesting: Bool = ProcessInfo.processInfo.arguments.contains("-ui-testing")) {
        self.isUITesting = isUITesting
        credentials = isUITesting ? MemoryCredentialStore() : KeychainCredentialStore()
        defaults = isUITesting ? UserDefaults(suiteName: "com.chengzixqq.sub2mobile.uitesting")! : .standard
        if isUITesting { defaults.removePersistentDomain(forName: "com.chengzixqq.sub2mobile.uitesting") }
        if let data = defaults.data(forKey: "profiles") {
            profiles = (try? JSONDecoder().decode([ServerProfile].self, from: data)) ?? []
        }
        if let raw = defaults.string(forKey: "activeProfile") { savedActiveID = UUID(uuidString: raw) }
        if let data = defaults.data(forKey: "pendingBalances") {
            pendingBalances = (try? JSONDecoder().decode([PendingBalanceOperation].self, from: data)) ?? []
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

    func beginConnection() -> UUID { connectionAttempt = UUID(); return connectionAttempt }
    func cancelConnection() { connectionAttempt = UUID(); isConnecting = false }

    func connect(profile: ServerProfile, credential: Credential, attempt: UUID? = nil) async throws {
        let ticket = attempt ?? beginConnection()
        isConnecting = true
        defer { if ticket == connectionAttempt { isConnecting = false } }
        let candidate = APIClient(server: profile, credential: credential, credentialStore: credentials)
        if !isUITesting { try await candidate.verifyAdministrator() }
        guard ticket == connectionAttempt else { await candidate.cancelAll(); throw CancellationError() }
        let verifiedCredential = await candidate.currentCredential() ?? credential
        try await credentials.save(verifiedCredential, serverID: profile.id)
        guard ticket == connectionAttempt else { await candidate.cancelAll(); throw CancellationError() }
        let previous = client
        sessionGeneration = UUID()
        client = candidate
        activeProfile = profile
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        savedActiveID = profile.id
        persistProfiles()
        await previous?.cancelAll()
    }

    func switchTo(_ profile: ServerProfile) async {
        do {
            guard let credential = try await credentials.load(serverID: profile.id) else {
                throw AppFailure("此站点凭据已清除，请重新登录。")
            }
            try await connect(profile: profile, credential: credential)
        } catch { report(error) }
    }

    func logout() async {
        let old = client
        let id = activeProfile?.id
        cancelConnection()
        sessionGeneration = UUID()
        client = nil
        activeProfile = nil
        savedActiveID = nil
        persistProfiles()
        await old?.cancelAll()
        if let id {
            do { try await credentials.remove(serverID: id) } catch { report(error) }
        }
        do { try await old?.logout() } catch { report(error) }
    }

    func remove(_ profile: ServerProfile) async {
        if activeProfile?.id == profile.id { await logout() }
        do {
            try await credentials.remove(serverID: profile.id)
            profiles.removeAll { $0.id == profile.id }
            persistProfiles()
        } catch { report(error) }
    }

    func remember(_ operation: PendingBalanceOperation) throws {
        if !pendingBalances.contains(where: { $0.id == operation.id }) { pendingBalances.append(operation) }
        do { try persistPending() }
        catch { pendingBalances.removeAll { $0.id == operation.id }; throw error }
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
    private func persistPending() throws { defaults.set(try JSONEncoder().encode(pendingBalances), forKey: "pendingBalances") }
}

struct AppFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
