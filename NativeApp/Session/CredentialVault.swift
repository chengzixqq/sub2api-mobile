import Foundation
#if canImport(Security)
import Security
#endif
import Sub2Core

actor KeychainCredentialStore: CredentialStore {
    private let service = "com.chengzixqq.sub2mobile.credentials"
    private let memoryOnly: Bool
    private var memoryValues: [UUID: Credential] = [:]
    private var leases: [UUID: UUID] = [:]
    init(memoryOnly: Bool = false) { self.memoryOnly = memoryOnly }

    func load(serverID: UUID) throws -> Credential? {
        if memoryOnly { return memoryValues[serverID] }
        #if canImport(Security)
        var query = baseQuery(serverID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError(status) }
        return try JSONDecoder().decode(Credential.self, from: data)
        #else
        throw VaultError.unsupportedPlatform
        #endif
    }

    func save(_ credential: Credential, serverID: UUID) throws {
        if memoryOnly { memoryValues[serverID] = credential; return }
        #if canImport(Security)
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery(serverID)
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

    func remove(serverID: UUID) throws {
        leases.removeValue(forKey: serverID)
        if memoryOnly { memoryValues.removeValue(forKey: serverID); return }
        #if canImport(Security)
        let status = SecItemDelete(baseQuery(serverID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status) }
        #else
        throw VaultError.unsupportedPlatform
        #endif
    }

    // Keychain calls and lease changes execute synchronously inside this one actor.
    // A late refresh from a revoked client cannot restore a removed credential.
    func commit(_ credential: Credential, serverID: UUID, lease: UUID) throws -> LeasedCredentialStore {
        try save(credential, serverID: serverID)
        leases[serverID] = lease
        return LeasedCredentialStore(vault: self, serverID: serverID, lease: lease)
    }
    func revoke(serverID: UUID, lease: UUID, erase: Bool) throws {
        guard leases[serverID] == lease else { return }
        leases.removeValue(forKey: serverID)
        if erase { try remove(serverID: serverID) }
    }
    func load(serverID: UUID, lease: UUID) throws -> Credential? {
        guard leases[serverID] == lease else { throw CancellationError() }
        return try load(serverID: serverID)
    }
    func save(_ credential: Credential, serverID: UUID, lease: UUID) throws {
        guard leases[serverID] == lease else { throw CancellationError() }
        try save(credential, serverID: serverID)
    }

    #if canImport(Security)
    private func baseQuery(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }
    #endif
}

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

private struct VaultError: LocalizedError {
    let status: Int32
    static let unsupportedPlatform = VaultError(Int32.min)
    init(_ status: Int32) { self.status = status }
    var errorDescription: String? {
        if status == Int32.min { return "当前平台不提供系统安全存储；仅允许显式内存测试模式。" }
        return "无法访问本机安全凭据（\(status)）。请解锁设备后重试。"
    }
}

