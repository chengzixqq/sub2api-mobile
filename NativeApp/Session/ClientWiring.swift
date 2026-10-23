import Foundation
import Sub2Core

/// The only place the active APIClient is built (D13). It keeps what the candidate learned while connecting: the ETag
/// identity set by me() (S0-05), the Date-header clock (S0-07) and the site session's zone, plus the site's device ID.
/// S0-11 and S0-13 pass the session owner's hooks to `makeClient`.
struct ClientWiring: Sendable {
    let deviceID: UUID
    let cacheIdentity: ConditionalCache.Identity?
    let serverTimeZone: ServerTimeZone
    let serverClock: ServerClock

    static func inherit(from candidate: APIClient, site: SiteSession, deviceID: UUID) async -> ClientWiring {
        ClientWiring(deviceID: deviceID, cacheIdentity: await candidate.conditionalCacheIdentity(),
                     serverTimeZone: site.serverTimeZone, serverClock: candidate.serverClock)
    }
    /// `store` is the lease of this session (D07), never the vault itself.
    func makeClient(server: ServerProfile, credential: Credential, store: (any CredentialStore)?,
                    transport: any HTTPTransport = URLSessionTransport(),
                    onSessionInvalid: (@Sendable (SessionInvalidation) -> Void)? = nil,
                    securityInterceptor: SecurityInterceptor? = nil) -> APIClient {
        APIClient(server: server, credential: credential, credentialStore: store, deviceID: deviceID, transport: transport,
                  cacheIdentity: cacheIdentity, serverTimeZone: serverTimeZone, serverClock: serverClock, onSessionInvalid: onSessionInvalid,
                  securityInterceptor: securityInterceptor)
    }
}
