import Foundation

/// One entry of `GET /api/v1/admin/access-tokens` (00 §1.3). Times stay raw strings until they are displayed.
public struct AdminAccessToken: Identifiable, Decodable, Sendable, Equatable {
    public let id: Int
    public let name: String?
    public let prefix: String?
    public let last4: String?
    public let scope: String?
    public let expiresAt: String?
    public let lastUsedAt: String?
    public let lastUsedIP: String?
    public let createdAt: String?
    /// The token that authenticated this request.
    public let current: Bool
    /// Backend `ReadOnly()` is anything but "write". An unknown scope counts as writable until the server
    /// answers `ACCESS_TOKEN_READ_ONLY` (00 §1.6).
    public var isReadOnly: Bool { scope.map { $0 != "write" } ?? false }

    enum CodingKeys: String, CodingKey {
        case id, name, prefix, last4, scope, current
        case expiresAt = "expires_at", lastUsedAt = "last_used_at", lastUsedIP = "last_used_ip", createdAt = "created_at"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name); prefix = try c.decodeIfPresent(String.self, forKey: .prefix)
        last4 = try c.decodeIfPresent(String.self, forKey: .last4); scope = try c.decodeIfPresent(String.self, forKey: .scope)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt); lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        lastUsedIP = try c.decodeIfPresent(String.self, forKey: .lastUsedIP); createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        current = try c.decodeIfPresent(Bool.self, forKey: .current) ?? false
    }
}

extension APIClient {
    /// The caller's own tokens; the list is `{items}`, not a paged envelope.
    public func accessTokens() async throws -> [AdminAccessToken] {
        let reply: AccessTokenList = try await request("admin/access-tokens", timeout: RequestTimeout.probe)
        return reply.items ?? []
    }
}

private struct AccessTokenList: Decodable, Sendable { let items: [AdminAccessToken]? }
