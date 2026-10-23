import Foundation

/// One entry of `GET /api/v1/auth/sessions` (00 §1.8, 60 §5.2). Sessions issued before the server tracked them have no
/// `client_type`; times stay raw strings until they are displayed.
public struct AuthSessionItem: Identifiable, Decodable, Sendable, Equatable {
    public let id: String
    public let deviceName: String?
    public let clientType: String?
    public let userAgent: String?
    public let ip: String?
    public let createdAt: String?
    public let lastSeenAt: String?
    public let expiresAt: String?
    /// The session this App is signed in with.
    public let current: Bool

    enum CodingKeys: String, CodingKey {
        case id, ip, current
        case deviceName = "device_name", clientType = "client_type", userAgent = "user_agent"
        case createdAt = "created_at", lastSeenAt = "last_seen_at", expiresAt = "expires_at"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName); clientType = try c.decodeIfPresent(String.self, forKey: .clientType)
        userAgent = try c.decodeIfPresent(String.self, forKey: .userAgent); ip = try c.decodeIfPresent(String.self, forKey: .ip)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt); lastSeenAt = try c.decodeIfPresent(String.self, forKey: .lastSeenAt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        current = try c.decodeIfPresent(Bool.self, forKey: .current) ?? false
    }
}

extension APIClient {
    /// Only an account sign-in has sessions; a key would be refused by the server, so nothing is sent.
    public func sessions() async throws -> [AuthSessionItem] {
        try requireAccountSession()
        let reply: AuthSessionList = try await request("auth/sessions", timeout: RequestTimeout.probe)
        return reply.items ?? []
    }
    /// `true` when the revoked session is this App's own: the caller then signs out of the site (00 §1.8).
    @discardableResult
    public func revokeSession(id: String) async throws -> Bool {
        try requireAccountSession()
        guard Self.isSessionID(id) else { throw APIError(kind: .validation, message: "无效的会话编号。") }
        let reply: RevocationReply = try await request("auth/sessions/\(id)", method: "DELETE", timeout: RequestTimeout.probe)
        return reply.current ?? false
    }
    /// The body is always `{"keep_current":true}`: without it the server signs out every session, this one included (00 §1.8).
    public func revokeOtherSessions() async throws {
        try requireAccountSession()
        let _: EmptyReply = try await request("auth/revoke-all-sessions", method: "POST", body: encode(["keep_current": true]),
                                              timeout: RequestTimeout.probe)
    }

    private func requireAccountSession() throws {
        guard case .tokens? = currentCredential() else { throw APIError(kind: .validation, message: "登录设备只适用于账号登录。") }
    }
    /// Session ids are hex strings; anything outside this set could change the path.
    static func isSessionID(_ id: String) -> Bool {
        (1...128).contains(id.utf8.count) && id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
}

/// `{message, current}` of a revocation (60 §5.4, §6.4); a missing `current` is not this App's.
struct RevocationReply: Decodable, Sendable { let current: Bool? }
private struct AuthSessionList: Decodable, Sendable { let items: [AuthSessionItem]? }
