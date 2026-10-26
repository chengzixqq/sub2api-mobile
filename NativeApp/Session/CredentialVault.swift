import Foundation
#if canImport(Security)
import Security
#endif
import Synchronization
import Sub2Core

/// Generic-password items of one Keychain service, by account. `MemorySecureItems` stands in for `-ui-testing` and `swift test`.
protocol SecureItems: Sendable {
    /// nil when the item does not exist; any other failure throws.
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(account: String) throws
}

/// Per site (00 §1.1): the credential under `<site UUID>`, the device ID under `<site UUID>.device` (00 §1.2).
actor KeychainCredentialStore: CredentialStore {
    private let items: any SecureItems
    private var leases: [UUID: UUID] = [:]
    init(memoryOnly: Bool = false) {
        let items: any SecureItems = if memoryOnly { MemorySecureItems() } else { KeychainItems() }
        self.init(items: items)
    }
    init(items: any SecureItems) { self.items = items }

    func load(serverID: UUID) throws -> Credential? {
        try items.read(account: Self.credentialAccount(for: serverID)).map(Self.decodeCredential)
    }
    func save(_ credential: Credential, serverID: UUID) throws {
        try items.write(JSONEncoder().encode(credential), account: Self.credentialAccount(for: serverID))
    }
    /// The kind the saved credential decodes to (a `sat_` saved as an Admin Key is an access token); nil when none is readable.
    func storedAuthentication(serverID: UUID) -> AuthenticationKind? { (try? load(serverID: serverID))?.authenticationKind }
    /// Deleting a site (00 §1.1, §9.6): its credential, lease and device ID.
    func remove(serverID: UUID) throws {
        try eraseCredential(serverID: serverID)
        try removeDeviceID(serverID: serverID)
    }
    /// Signing out and a revoked lease (D07): the credential and lease go, the site keeps its device ID.
    func eraseCredential(serverID: UUID) throws {
        leases.removeValue(forKey: serverID)
        try items.delete(account: Self.credentialAccount(for: serverID))
    }

    /// The site's fixed X-Device-ID. Only a missing or unreadable value is replaced; any other Keychain failure (a locked
    /// device) is thrown, never answered with a new ID.
    func deviceID(serverID: UUID) throws -> UUID {
        if let data = try items.read(account: Self.deviceAccount(for: serverID)),
           let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) { return id }
        let id = UUID()
        try storeDeviceID(id, serverID: serverID)
        return id
    }
    func storeDeviceID(_ id: UUID, serverID: UUID) throws {
        try items.write(Data(id.uuidString.lowercased().utf8), account: Self.deviceAccount(for: serverID))
    }
    func removeDeviceID(serverID: UUID) throws { try items.delete(account: Self.deviceAccount(for: serverID)) }

    static func credentialAccount(for serverID: UUID) -> String { serverID.uuidString }
    static func deviceAccount(for serverID: UUID) -> String { serverID.uuidString + ".device" }
    /// Credential's own decoding migrates old bytes (an Admin Key starting with `sat_` becomes an access token, 00 §9.4);
    /// the migrated value is written back by the next commit.
    static func decodeCredential(_ data: Data) throws -> Credential { try JSONDecoder().decode(Credential.self, from: data) }

    // Keychain calls and lease changes execute synchronously inside this one actor.
    // A late refresh from a revoked client cannot restore a removed credential.
    /// A new login's draft device ID is saved before its credential, so a credential is never stored without the ID it used.
    func commit(_ credential: Credential, serverID: UUID, lease: UUID, deviceID draft: UUID? = nil) throws -> LeasedCredentialStore {
        if let draft { try storeDeviceID(draft, serverID: serverID) }
        try save(credential, serverID: serverID)
        leases[serverID] = lease
        return LeasedCredentialStore(vault: self, serverID: serverID, lease: lease)
    }
    func revoke(serverID: UUID, lease: UUID, erase: Bool) throws {
        guard leases[serverID] == lease else { return }
        leases.removeValue(forKey: serverID)
        if erase { try eraseCredential(serverID: serverID) }
    }
    /// Takes back a connection attempt that failed or was overtaken: its credential while its lease is still current, and
    /// with `forgetDevice` the draft device ID of a site never saved, unless a newer attempt holds a lease on that site.
    func abandon(serverID: UUID, lease: UUID?, forgetDevice: Bool) throws {
        if let lease { try revoke(serverID: serverID, lease: lease, erase: true) }
        if forgetDevice && leases[serverID] == nil { try removeDeviceID(serverID: serverID) }
    }
    func load(serverID: UUID, lease: UUID) throws -> Credential? {
        guard leases[serverID] == lease else { throw CancellationError() }
        return try load(serverID: serverID)
    }
    func save(_ credential: Credential, serverID: UUID, lease: UUID) throws {
        guard leases[serverID] == lease else { throw CancellationError() }
        try save(credential, serverID: serverID)
    }
}

/// What an APIClient may hold (D07): its `remove` only erases the credential of its own lease, never the device ID.
struct LeasedCredentialStore: CredentialStore {
    let vault: KeychainCredentialStore
    let serverID: UUID
    let lease: UUID
    func load(serverID: UUID) async throws -> Credential? {
        guard serverID == self.serverID else { throw CancellationError() }
        return try await vault.load(serverID: serverID, lease: lease)
    }
    func save(_ credential: Credential, serverID: UUID) async throws {
        guard serverID == self.serverID else { throw CancellationError() }
        try await vault.save(credential, serverID: serverID, lease: lease)
    }
    func remove(serverID: UUID) async throws {
        guard serverID == self.serverID else { throw CancellationError() }
        try await vault.revoke(serverID: serverID, lease: lease, erase: true)
    }
}

/// Service `com.chengzixqq.sub2mobile.credentials`, readable only while unlocked and never migrated to another device.
struct KeychainItems: SecureItems {
    private let service = "com.chengzixqq.sub2mobile.credentials"
    func read(account: String) throws -> Data? {
        #if canImport(Security)
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError(status) }
        return data
        #else
        throw VaultError.unsupportedPlatform
        #endif
    }
    func write(_ data: Data, account: String) throws {
        #if canImport(Security)
        let query = baseQuery(account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw VaultError(added) }
        } else if status != errSecSuccess { throw VaultError(status) }
        #else
        throw VaultError.unsupportedPlatform
        #endif
    }
    func delete(account: String) throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status) }
        #else
        throw VaultError.unsupportedPlatform
        #endif
    }
    #if canImport(Security)
    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
    #endif
}

/// Holds the same bytes the Keychain would, for the explicit memory-only mode.
final class MemorySecureItems: SecureItems {
    private let items = Mutex<[String: Data]>([:])
    func read(account: String) throws -> Data? { items.withLock { $0[account] } }
    func write(_ data: Data, account: String) throws { items.withLock { $0[account] = data } }
    func delete(account: String) throws { _ = items.withLock { $0.removeValue(forKey: account) } }
}

private struct VaultError: LocalizedError {
    let status: Int32
    static let unsupportedPlatform = VaultError(Int32.min)
    init(_ status: Int32) { self.status = status }
    var errorDescription: String? {
        if status == Int32.min { return "当前平台不提供系统安全存储；仅允许显式内存测试模式。" }
        return "无法访问本机安全凭据（\(status)）。请解锁设备后重试。"
    }
}
