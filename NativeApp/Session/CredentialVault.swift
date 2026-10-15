import Foundation
import Security
import Sub2Core

actor KeychainCredentialStore: CredentialStore {
    private let service = "com.chengzixqq.sub2mobile.credentials"

    func load(serverID: UUID) throws -> Credential? {
        var query = baseQuery(serverID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError(status) }
        return try JSONDecoder().decode(Credential.self, from: data)
    }

    func save(_ credential: Credential, serverID: UUID) throws {
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
    }

    func remove(serverID: UUID) throws {
        let status = SecItemDelete(baseQuery(serverID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status) }
    }

    private func baseQuery(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }
}

private struct VaultError: LocalizedError {
    let status: OSStatus
    init(_ status: OSStatus) { self.status = status }
    var errorDescription: String? { "无法访问本机安全凭据（\(status)）。请解锁设备后重试。" }
}

actor MemoryCredentialStore: CredentialStore {
    private var values: [UUID: Credential] = [:]
    func load(serverID: UUID) -> Credential? { values[serverID] }
    func save(_ credential: Credential, serverID: UUID) { values[serverID] = credential }
    func remove(serverID: UUID) { values.removeValue(forKey: serverID) }
}
