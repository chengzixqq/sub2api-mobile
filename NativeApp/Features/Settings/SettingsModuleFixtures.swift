import Foundation
import Sub2Core

/// 60 §5's `-ui-testing` launch arguments and row ids; SessionsView reads the fixture below through them.
enum SessionFixture {
    /// This device signed in before the server tracked sessions: the list has no current entry, and 让其他所有设备下线 ends
    /// this device too, so the next read answers 401 TOKEN_REVOKED (BACKLOG “让其他设备下线可能连本机一起下线”).
    static let legacyCurrentArgument = "-ui-sessions-legacy-current"
    /// The session's first list read fails with 503 SERVICE_UNAVAILABLE.
    static let unavailableArgument = "-ui-sessions-unavailable"
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
        authSessionsByGeneration[generation] = sessions.filter(\.current)
    }

    @MainActor private static var authSessionsByGeneration: [UUID: [AuthSessionItem]] = [:]
    @MainActor private static var revokedThisDevice: Set<UUID> = []
    @MainActor private static var failedSessionReads: Set<UUID> = []
    @MainActor private static func storedAuthSessions(generation: UUID) -> [AuthSessionItem] {
        if let stored = authSessionsByGeneration[generation] { return stored }
        let seed = authSessionSeed(now: Date(), arguments: ProcessInfo.processInfo.arguments)
        authSessionsByGeneration[generation] = seed
        return seed
    }
}
