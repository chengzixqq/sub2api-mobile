import Foundation
import Sub2Core

/// The connected site as `/admin/me` and its follow-up probes described it (00 §1.9, §9.5; 60 §0.3). Pages read it through
/// `SessionContext`; a change replaces the whole value.
struct SiteSession: Sendable {
    let me: AdminMe
    /// `auth_method`, inferred from the credential when the server leaves it out (D09).
    let authMethod: AdminAuthMethod?
    let authenticationKind: AuthenticationKind
    let serverTimeZone: ServerTimeZone
    /// Server minus phone time when the probe finished (00 §6.3); the live value stays on the client's ServerClock.
    let clockOffset: TimeInterval
    /// `read` / `write` of the `sat_` token in use; nil until known, which counts as writable (00 §1.6 step 3, R14).
    private(set) var accessTokenScope: String?
    /// R18 banner data: a login without a refresh token must sign in again when the access expires (00 §1.4 step 5).
    /// Derived from the credential, so it survives a restart.
    let refreshTokenUnavailable: Bool
    let accessTokenExpiresAt: Date?
    /// S0-11 probes again when the App returns after more than five minutes.
    let probedAt: Date

    init(me: AdminMe, credential: Credential, accessTokenScope: String?, serverTimeZone: ServerTimeZone, clockOffset: TimeInterval, probedAt: Date) {
        self.me = me
        authMethod = AdminAuthMethod.resolved(reported: me.authMethod, credential: credential)
        authenticationKind = credential.authenticationKind
        self.accessTokenScope = authMethod == .adminAccessToken ? accessTokenScope : nil
        self.serverTimeZone = serverTimeZone; self.clockOffset = clockOffset; self.probedAt = probedAt
        if case .tokens(let pair) = credential, pair.refreshToken.isEmpty {
            refreshTokenUnavailable = true; accessTokenExpiresAt = pair.expiresAt
        } else {
            refreshTokenUnavailable = false; accessTokenExpiresAt = nil
        }
    }

    var capabilities: Set<String> { me.capabilities }
    func has(_ capability: Capability) -> Bool { me.has(capability) }
    /// Same rule as the backend's `ReadOnly()`; only a known scope makes a token read-only.
    var isReadOnlyToken: Bool { authMethod == .adminAccessToken && AdminAccessToken.isReadOnly(scope: accessTokenScope) }
    var identityEmail: String? { me.user?.email }
    var authMethodLabel: String {
        AuthPresentation.methodLabel(authMethod: authMethod, fallback: authenticationKind, accessTokenScope: accessTokenScope)
    }
    var operatorNote: String? { AuthPresentation.operatorNote(authMethod: authMethod, email: identityEmail) }
    /// After a write was answered ACCESS_TOKEN_READ_ONLY (00 §1.6 step 3); other sign-in methods are never read-only.
    func markingReadOnly() -> SiteSession {
        guard authMethod == .adminAccessToken else { return self }
        var marked = self
        marked.accessTokenScope = "read"
        return marked
    }
    /// A reload result keeps a read-only mark `latest` received while it was probing; a token's scope never changes.
    func keepingReadOnlyMark(of latest: SiteSession) -> SiteSession {
        latest.isReadOnlyToken && !isReadOnlyToken ? markingReadOnly() : self
    }

    /// `/admin/me` (with the old-server fallback), the administrator check (1.11), the `sat_` scope (60 §0.3) and the server zone
    /// (00 §6.3), all through `client`, which also takes the zone. A failed scope probe keeps `knownScope` (nil on first
    /// connect, i.e. writable); cancellation is never swallowed.
    static func establish(client: APIClient, knownScope: String? = nil, now: Date = Date()) async throws -> SiteSession {
        let me = try await client.me()
        guard me.isAdministrator else { throw APIError.administratorRequired }
        guard let credential = await client.currentCredential() else { throw APIError.authenticationRequired }
        var scope: String?
        if AdminAuthMethod.resolved(reported: me.authMethod, credential: credential) == .adminAccessToken {
            scope = try await currentTokenScope(client: client, me: me) ?? knownScope
        }
        let zone = try await serverTimeZone(client: client, me: me)
        await client.setServerTimeZone(zone)
        return SiteSession(me: me, credential: credential, accessTokenScope: scope, serverTimeZone: zone,
                           clockOffset: client.serverClock.offset, probedAt: now)
    }
    /// `admin/access-tokens` sits behind the compliance guard (423), so an unaccepted site waits for S0-13's reload.
    private static func currentTokenScope(client: APIClient, me: AdminMe) async throws -> String? {
        guard me.compliance.required != true else { return nil }
        do { return try await client.accessTokens().first(where: \.current)?.scope }
        catch is CancellationError { throw CancellationError() }
        catch { return nil }
    }
    /// `/admin/me` first; without a zone there, one `settings/public` read (an old server's me() already merged it), then the phone's.
    private static func serverTimeZone(client: APIClient, me: AdminMe) async throws -> ServerTimeZone {
        if let zone = ServerTimeZone.resolve(me: me, publicSettings: nil) { return zone }
        guard !me.isLegacyServer else { return .device }
        do { return ServerTimeZone.resolve(me: nil, publicSettings: try await client.publicSettings()) ?? .device }
        catch is CancellationError { throw CancellationError() }
        catch { return .device }
    }
}
