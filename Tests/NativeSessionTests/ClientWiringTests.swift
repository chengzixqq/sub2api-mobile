import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
import Sub2Core
@testable import NativeSessionSupport

// D13: the active client is built in one place and keeps the candidate's ETag identity, Date-header clock and the site zone.
@Test func activeClientInheritsCandidateCacheIdentityClockAndSiteZone() async throws {
    let transport = SessionTransport { _ in sessionOK(meJSON(timezone: "Asia/Tokyo", offset: "+09:00")) }
    let candidate = sessionClient(transport)
    let site = try await SiteSession.establish(client: candidate)
    let wiring = await ClientWiring.inherit(from: candidate, site: site, deviceID: sessionDeviceID)
    #expect(wiring.cacheIdentity == ConditionalCache.Identity(userID: 7, authMethod: "jwt"))
    #expect(wiring.serverTimeZone == site.serverTimeZone); #expect(wiring.serverTimeZone.identifier == "Asia/Tokyo")
    #expect(wiring.serverClock === candidate.serverClock); #expect(wiring.deviceID == sessionDeviceID)

    let active = wiring.makeClient(server: sessionServer(), credential: sessionTokens(), store: nil, transport: transport)
    #expect(await active.conditionalCacheIdentity() == wiring.cacheIdentity)
    #expect(await active.serverTimeZone() == site.serverTimeZone)
    #expect(active.serverClock === candidate.serverClock)
    #expect(active.deviceID == sessionDeviceID)
    _ = try await active.me()
    #expect(await transport.requests.last?.value(forHTTPHeaderField: "X-Device-ID") == sessionDevice)
}

private final class WiringInvalidations: Sendable {
    private let values = Mutex<[SessionInvalidation]>([])
    var all: [SessionInvalidation] { values.withLock { $0 } }
    var handler: @Sendable (SessionInvalidation) -> Void { { [self] value in values.withLock { $0.append(value) } } }
}

/// The production hook (D13): the client makeClient builds reports a revoked session exactly once.
@Test func activeClientReportsTheEndedSessionThroughTheWiredHook() async throws {
    let transport = SessionTransport { request in
        request.url?.path == "/api/v1/admin/users/7" ? sessionFailure(401, reason: "TOKEN_REVOKED") : sessionOK(meJSON())
    }
    let candidate = sessionClient(transport)
    let site = try await SiteSession.establish(client: candidate)
    let wiring = await ClientWiring.inherit(from: candidate, site: site, deviceID: sessionDeviceID)
    let log = WiringInvalidations()
    let active = wiring.makeClient(server: sessionServer(), credential: .adminKey("fixture-key"), store: nil, transport: transport,
                                   onSessionInvalid: log.handler)
    for _ in 0..<2 { _ = try? await active.user(id: 7) }
    #expect(log.all.count == 1); #expect(log.all.first?.cause == .expired); #expect(log.all.first?.reason == "TOKEN_REVOKED")
}
