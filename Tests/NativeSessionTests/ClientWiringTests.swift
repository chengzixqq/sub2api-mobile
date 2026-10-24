import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
