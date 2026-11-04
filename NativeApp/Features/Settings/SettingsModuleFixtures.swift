import Foundation
import Sub2Core

/// 60 §5's `-ui-testing` launch arguments and row ids; SessionsView reads the fixture below through them.
enum SessionFixture {
    /// This device signed in before the server tracked sessions: the list has no current entry, and 让其他所有设备下线 ends
    /// this device too, so the next read answers 401 TOKEN_REVOKED (BACKLOG “让其他设备下线可能连本机一起下线”).
    static let legacyCurrentArgument = "-ui-sessions-legacy-current"
    /// The session's first list read fails with 503 SERVICE_UNAVAILABLE.
    static let unavailableArgument = "-ui-sessions-unavailable"
    /// The list read right after 让其他所有设备下线 fails with 503 SERVICE_UNAVAILABLE; the next one succeeds.
    static let reloadFailsArgument = "-ui-sessions-reload-fails"
    static let currentID = "5e5510000000000000000000000000a1"
    static let webID = "5e5510000000000000000000000000b2"
    static let legacyID = "5e5510000000000000000000000000c3"
    static let spareID = "5e5510000000000000000000000000d4"
}

// Stage 6's settings-module fixtures (登录设备; S6-02 adds the access tokens after this block). Writes change memory only.
extension DemoData {
    /// Newest first, as the server sorts them; times follow the first read of the session.
    static func authSessionSeed(now: Date, arguments: [String]) -> [AuthSessionItem] {
        let stamp = { (seconds: TimeInterval) in ServerTime.utcTimestamp(now.addingTimeInterval(seconds)) }
        let day: TimeInterval = 86_400
        let this = arguments.contains(SessionFixture.legacyCurrentArgument)
            ? AuthSessionItem(id: SessionFixture.spareID, deviceName: "备用 iPhone", clientType: "ios", userAgent: "Sub2Mobile-iOS/1.0",
                              ip: "192.0.2.10", createdAt: stamp(-5 * day), lastSeenAt: stamp(-600), expiresAt: stamp(25 * day))
            : AuthSessionItem(id: SessionFixture.currentID, deviceName: "演示 iPhone", clientType: "ios", userAgent: "Sub2Mobile-iOS/1.0",
                              ip: "203.0.113.24", createdAt: stamp(-2 * day), lastSeenAt: stamp(-180), expiresAt: stamp(28 * day), current: true)
        let web = AuthSessionItem(id: SessionFixture.webID, deviceName: "", clientType: "web",
                                  userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Safari/605.1.15",
                                  ip: "198.51.100.7", createdAt: stamp(-9 * day), lastSeenAt: stamp(-7_200), expiresAt: stamp(21 * day))
        // A pre-deployment session: the server wrote neither client_type nor the device name.
        let legacy = AuthSessionItem(id: SessionFixture.legacyID, deviceName: "", clientType: "", userAgent: "", ip: "",
                                     createdAt: stamp(-day), lastSeenAt: stamp(-day), expiresAt: stamp(29 * day))
        return [this, web, legacy]
    }

    @MainActor static func authSessions(generation: UUID) throws -> [AuthSessionItem] {
        if ProcessInfo.processInfo.arguments.contains(SessionFixture.unavailableArgument), !failedSessionReads.contains(generation) {
            failedSessionReads.insert(generation)
            throw APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
        }
        if failingReloads.remove(generation) != nil { throw APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE") }
        if revokedThisDevice.contains(generation) { throw APIError.server(status: 401, reason: "TOKEN_REVOKED") }
        return storedAuthSessions(generation: generation)
    }
    /// Settings → 当前站点 shows the fixture's own count (60 §3.6), so it follows the writes on 登录设备.
    @MainActor static func authSessionFixtureCount(generation: UUID) -> Int { storedAuthSessions(generation: generation).count }
    /// 404 SESSION_NOT_FOUND for an id that is gone; true when the revoked session was this device's.
    @MainActor static func revokeAuthSession(id: String, generation: UUID) throws -> Bool {
        let sessions = storedAuthSessions(generation: generation)
        guard let revoked = sessions.first(where: { $0.id == id }) else { throw APIError.server(status: 404, reason: "SESSION_NOT_FOUND") }
        authSessionsByGeneration[generation] = sessions.filter { $0.id != id }
        if revoked.current { revokedThisDevice.insert(generation) }
        return revoked.current
    }
    /// keep_current only works for a session with a sid: without a current entry every session ends, this device's too.
    @MainActor static func revokeOtherAuthSessions(generation: UUID) {
        let sessions = storedAuthSessions(generation: generation)
        if !sessions.contains(where: \.current) { revokedThisDevice.insert(generation) }
        if ProcessInfo.processInfo.arguments.contains(SessionFixture.reloadFailsArgument) { failingReloads.insert(generation) }
        authSessionsByGeneration[generation] = sessions.filter(\.current)
    }

    @MainActor private static var authSessionsByGeneration: [UUID: [AuthSessionItem]] = [:]
    @MainActor private static var revokedThisDevice: Set<UUID> = []
    @MainActor private static var failingReloads: Set<UUID> = []
    @MainActor private static var failedSessionReads: Set<UUID> = []
    @MainActor private static func storedAuthSessions(generation: UUID) -> [AuthSessionItem] {
        if let stored = authSessionsByGeneration[generation] { return stored }
        let seed = authSessionSeed(now: Date(), arguments: ProcessInfo.processInfo.arguments)
        authSessionsByGeneration[generation] = seed
        return seed
    }
}

/// 60 §6's `-ui-testing` launch arguments and token ids; AccessTokensView and SettingsSiteStatus read the fixture below.
enum AccessTokenFixture {
    /// The account has no token left (U02: the App issues none).
    static let emptyArgument = "-ui-access-tokens-empty"
    /// Every list read fails with 503 SERVICE_UNAVAILABLE, so 设置 shows no count either.
    static let failureArgument = "-ui-access-tokens-failure"
    static let thisAppID = 1
    static let scriptID = 2
    static let temporaryID = 3
}

// 60 §6: the account's access tokens. Revoking changes memory only.
extension DemoData {
    /// Newest first, as the server sorts them. The first is this App's own when it signed in with `sat_`, read-only under
    /// `-ui-readonly-token`; the last expires within a week and was never used.
    static func accessTokenSeed(now: Date, signedInWithToken: Bool, readOnly: Bool) -> [AdminAccessToken] {
        let stamp = { (seconds: TimeInterval) in ServerTime.utcTimestamp(now.addingTimeInterval(seconds)) }
        let day: TimeInterval = 86_400
        return [
            AdminAccessToken(id: AccessTokenFixture.thisAppID, name: "本机 iPhone", prefix: "sat_3f9a", last4: "c71e", scope: readOnly ? "read" : "write",
                             expiresAt: stamp(87 * day), lastUsedAt: stamp(-180), lastUsedIP: "203.0.113.24", createdAt: stamp(-day),
                             current: signedInWithToken),
            AdminAccessToken(id: AccessTokenFixture.scriptID, name: "监控脚本", prefix: "sat_9b20", last4: "41ad", scope: "read",
                             expiresAt: stamp(60 * day), lastUsedAt: stamp(-26 * 3_600), lastUsedIP: "198.51.100.7", createdAt: stamp(-2 * day)),
            AdminAccessToken(id: AccessTokenFixture.temporaryID, name: "临时排查", prefix: "sat_d71c", last4: "08f3", scope: "write",
                             expiresAt: stamp(5 * day), lastUsedIP: "", createdAt: stamp(-3 * day))
        ]
    }

    @MainActor static func accessTokens(context: SessionContext) throws -> [AdminAccessToken] {
        if ProcessInfo.processInfo.arguments.contains(AccessTokenFixture.failureArgument) {
            throw APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
        }
        return storedAccessTokens(context: context)
    }
    /// Settings → 当前站点 counts the fixture's own tokens (60 §3.6), so it follows the revocations; nil when the list fails.
    @MainActor static func accessTokenFixtureCount(context: SessionContext) -> Int? {
        guard let tokens = try? accessTokens(context: context) else { return nil }
        return SettingsPresentation.activeTokenCount(tokens, now: Date())
    }
    /// Revoking this App's own token answers `current: true`, which ends the session; a token gone already is a 404.
    @MainActor static func revokeAccessTokenFixture(_ token: AdminAccessToken, generation: UUID) -> AccessTokenRevocation.Outcome {
        let tokens = accessTokensByGeneration[generation] ?? []
        guard let revoked = tokens.first(where: { $0.id == token.id }) else { return AccessTokenRevocation.Outcome(kind: .alreadyGone) }
        accessTokensByGeneration[generation] = tokens.filter { $0.id != token.id }
        return AccessTokenRevocation.Outcome(kind: revoked.current ? .revokedCurrent : .revoked)
    }

    @MainActor private static var accessTokensByGeneration: [UUID: [AdminAccessToken]] = [:]
    @MainActor private static func storedAccessTokens(context: SessionContext) -> [AdminAccessToken] {
        if let stored = accessTokensByGeneration[context.generation] { return stored }
        let seed = ProcessInfo.processInfo.arguments.contains(AccessTokenFixture.emptyArgument) ? []
            : accessTokenSeed(now: Date(), signedInWithToken: context.site.authenticationKind == .accessToken, readOnly: context.isReadOnlyToken)
        accessTokensByGeneration[context.generation] = seed
        return seed
    }
}
