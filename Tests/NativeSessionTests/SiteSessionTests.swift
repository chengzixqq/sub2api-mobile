import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Sub2Core
@testable import NativeSessionSupport

private let mePath = "/api/v1/admin/me", tokensPath = "/api/v1/admin/access-tokens", settingsPath = "/api/v1/settings/public"

/// `me` answers admin/me; access-tokens answers with `tokens` (or fails); settings/public answers `settings`.
private func siteTransport(me: String, tokens: HTTPResponse? = nil, settings: String = "{}") -> SessionTransport {
    SessionTransport { request in
        switch request.url?.path ?? "" {
        case mePath: return sessionOK(me)
        case tokensPath: return tokens ?? sessionFailure(500)
        case settingsPath: return sessionOK(settings)
        default: return sessionFailure(404, reason: "NOT_FOUND")
        }
    }
}

@Test func jwtSessionStoresCapabilitiesAndServerTimeZoneWithoutTokenProbe() async throws {
    let transport = siteTransport(me: meJSON())
    let client = sessionClient(transport)
    let site = try await SiteSession.establish(client: client)
    #expect(site.has(.dashboardRates)); #expect(site.has(.adminAccessTokens)); #expect(!site.has(.usersQuickTopup))
    #expect(site.capabilities == ["dashboard.rates", "admin.access_tokens"])
    #expect(site.serverTimeZone.identifier == "Asia/Shanghai")
    #expect(await client.serverTimeZone() == site.serverTimeZone)
    #expect(site.authMethod == .jwt); #expect(site.authenticationKind == .password)
    #expect(site.accessTokenScope == nil); #expect(!site.isReadOnlyToken)
    #expect(site.identityEmail == "admin@example.invalid")
    #expect(await transport.paths() == [mePath])
}

@Test func everyProbeRequestCarriesStationDeviceID() async throws {
    let transport = siteTransport(me: meJSON(authMethod: "admin_access_token", timezone: nil, offset: nil),
                                  tokens: sessionOK(tokensJSON([(current: true, scope: "write")])), settings: #"{"server_timezone":"Asia/Tokyo"}"#)
    _ = try await SiteSession.establish(client: sessionClient(transport, credential: .accessToken("sat_fixture")))
    let requests = await transport.requests
    #expect(requests.compactMap { $0.url?.path } == [mePath, tokensPath, settingsPath])
    for request in requests { #expect(request.value(forHTTPHeaderField: "X-Device-ID") == sessionDevice) }
    for request in requests.prefix(2) {
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sat_fixture")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}

@Test func accessTokenSessionReadsScopeOfCurrentToken() async throws {
    let transport = siteTransport(me: meJSON(authMethod: "admin_access_token"),
                                  tokens: sessionOK(tokensJSON([(current: false, scope: "write"), (current: true, scope: "read")])))
    let site = try await SiteSession.establish(client: sessionClient(transport, credential: .accessToken("sat_fixture")))
    #expect(site.accessTokenScope == "read"); #expect(site.isReadOnlyToken)
    #expect(site.authMethodLabel == "访问令牌 · 只读")
}

@Test(arguments: [("write", false, "访问令牌 · 读写"), ("admin", true, "访问令牌 · 只读")])
func tokenScopeFollowsServerReadOnlyRule(scope: String, readOnly: Bool, label: String) async throws {
    let transport = siteTransport(me: meJSON(authMethod: "admin_access_token"), tokens: sessionOK(tokensJSON([(current: true, scope: scope)])))
    let site = try await SiteSession.establish(client: sessionClient(transport, credential: .accessToken("sat_fixture")))
    // Backend ReadOnly() is anything but "write".
    #expect(site.isReadOnlyToken == readOnly); #expect(site.authMethodLabel == label)
}

@Test(arguments: [sessionFailure(500), sessionOK(tokensJSON([(current: false, scope: "read")])), sessionFailure(423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED")])
func accessTokenScopeFailureFallsBackToWritable(tokens: HTTPResponse) async throws {
    let transport = siteTransport(me: meJSON(authMethod: "admin_access_token"), tokens: tokens)
    let site = try await SiteSession.establish(client: sessionClient(transport, credential: .accessToken("sat_fixture")))
    #expect(site.accessTokenScope == nil); #expect(!site.isReadOnlyToken)
    #expect(site.authMethodLabel == "访问令牌")
}

@Test func networkFailureOfTokenProbeFallsBackToWritable() async throws {
    let transport = SessionTransport { request in
        if request.url?.path == tokensPath { throw URLError(.notConnectedToInternet) }
        return sessionOK(meJSON(authMethod: "admin_access_token"))
    }
    let site = try await SiteSession.establish(client: sessionClient(transport, credential: .accessToken("sat_fixture")))
    #expect(site.accessTokenScope == nil); #expect(!site.isReadOnlyToken)
}

@Test func knownScopeSurvivesFailedReprobe() async throws {
    let transport = siteTransport(me: meJSON(authMethod: "admin_access_token"))
    let site = try await SiteSession.establish(client: sessionClient(transport, credential: .accessToken("sat_fixture")), knownScope: "read")
    #expect(site.accessTokenScope == "read"); #expect(site.isReadOnlyToken)
}

/// reloadSiteSession: a write answered ACCESS_TOKEN_READ_ONLY while the reload was probing outlives the probe's fallback scope.
@Test(arguments: [nil, "write"] as [String?])
func readOnlyMarkMadeDuringReloadSurvivesFallbackScope(knownScope: String?) async throws {
    let client = sessionClient(siteTransport(me: meJSON(authMethod: "admin_access_token")), credential: .accessToken("sat_fixture"))
    let reloaded = try await SiteSession.establish(client: client, knownScope: knownScope)
    let latest = try await SiteSession.establish(client: client, knownScope: knownScope)
    #expect(reloaded.keepingReadOnlyMark(of: latest.markingReadOnly()).isReadOnlyToken)
    #expect(reloaded.keepingReadOnlyMark(of: latest).accessTokenScope == knownScope)
    let reported = try await SiteSession.establish(client: sessionClient(
        siteTransport(me: meJSON(authMethod: "admin_access_token"), tokens: sessionOK(tokensJSON([(current: true, scope: "admin")]))),
        credential: .accessToken("sat_fixture")))
    #expect(reported.keepingReadOnlyMark(of: latest.markingReadOnly()).accessTokenScope == "admin")
}

@Test func complianceRequiredSkipsTokenProbe() async throws {
    let transport = siteTransport(me: meJSON(authMethod: "admin_access_token", complianceRequired: true),
                                  tokens: sessionOK(tokensJSON([(current: true, scope: "read")])))
    let site = try await SiteSession.establish(client: sessionClient(transport, credential: .accessToken("sat_fixture")))
    #expect(site.accessTokenScope == nil)
    #expect(!(await transport.paths()).contains(tokensPath))
}

@Test func cancellationDuringTokenProbeIsNotSwallowed() async throws {
    let gate = SessionGate()
    let transport = SessionTransport { request in
        guard request.url?.path == tokensPath else { return sessionOK(meJSON(authMethod: "admin_access_token")) }
        await gate.wait()
        return sessionOK(tokensJSON([(current: true, scope: "write")]))
    }
    let client = sessionClient(transport, credential: .accessToken("sat_fixture"))
    let pending = Task { try await SiteSession.establish(client: client) }
    while !(await gate.arrived) { await Task.yield() }
    await client.cancelAll()
    await gate.open()
    await #expect(throws: CancellationError.self) { _ = try await pending.value }
}

@Test func markingReadOnlyAffectsOnlyAccessTokenSessions() async throws {
    let token = try await SiteSession.establish(client: sessionClient(siteTransport(me: meJSON(authMethod: "admin_access_token")),
                                                                      credential: .accessToken("sat_fixture")))
    let marked = token.markingReadOnly()
    #expect(marked.isReadOnlyToken); #expect(marked.accessTokenScope == "read")
    #expect(!token.isReadOnlyToken); #expect(token.accessTokenScope == nil)
    for (method, credential) in [("jwt", sessionTokens()), ("admin_api_key", Credential.adminKey("fixture-key"))] {
        let site = try await SiteSession.establish(client: sessionClient(siteTransport(me: meJSON(authMethod: method)), credential: credential))
        #expect(!site.markingReadOnly().isReadOnlyToken); #expect(site.markingReadOnly().accessTokenScope == nil)
    }
}

@Test func adminKeySessionDescribesFirstAdministrator() async throws {
    let key = try await SiteSession.establish(client: sessionClient(siteTransport(me: meJSON(authMethod: "admin_api_key")),
                                                                    credential: .adminKey("fixture-key")))
    #expect(key.operatorNote == "以 admin@example.invalid 身份操作（第一个管理员）")
    #expect(key.authMethodLabel == "Admin Key · 以第一个管理员身份操作")
    let jwt = try await SiteSession.establish(client: sessionClient(siteTransport(me: meJSON())))
    #expect(jwt.operatorNote == nil); #expect(jwt.authMethodLabel == "邮箱和密码")
}

@Test func missingAuthMethodIsInferredFromCredential() async throws {
    let site = try await SiteSession.establish(client: sessionClient(siteTransport(me: meJSON(authMethod: nil)), credential: .adminKey("fixture-key")))
    #expect(site.authMethod == .adminAPIKey); #expect(site.authenticationKind == .adminKey)
}

@Test(arguments: [("vendor", #"{"id":3,"name":"代运营"}"#), ("user", "null")])
func nonAdministratorIdentityIsRejected(role: String, workspace: String) async throws {
    let transport = siteTransport(me: meJSON(authMethod: "admin_access_token", role: role, workspace: workspace),
                                  tokens: sessionOK(tokensJSON([(current: true, scope: "write")])))
    await #expect(throws: APIError.administratorRequired) {
        _ = try await SiteSession.establish(client: sessionClient(transport, credential: .accessToken("sat_fixture")))
    }
    #expect(await transport.paths() == [mePath])
}

@Test func refreshTokenUnavailableIsDerivedFromCredential() async throws {
    let expiry = Date().addingTimeInterval(3_000)
    let degraded = try await SiteSession.establish(client: sessionClient(siteTransport(me: meJSON()), credential: sessionTokens(refresh: "", expiresAt: expiry)))
    #expect(degraded.refreshTokenUnavailable); #expect(degraded.accessTokenExpiresAt == expiry)
    let normal = try await SiteSession.establish(client: sessionClient(siteTransport(me: meJSON())))
    #expect(!normal.refreshTokenUnavailable); #expect(normal.accessTokenExpiresAt == nil)
    let key = try await SiteSession.establish(client: sessionClient(siteTransport(me: meJSON(authMethod: "admin_api_key")), credential: .adminKey("k")))
    #expect(!key.refreshTokenUnavailable); #expect(key.accessTokenExpiresAt == nil)
}

@Test func legacyServerFallsBackToPublicSettingsTimeZoneAndEmptyCapabilities() async throws {
    let transport = SessionTransport { request in
        switch request.url?.path ?? "" {
        case mePath: return gatewayNotFound
        case "/api/v1/admin/compliance": return sessionOK(#"{"required":false}"#)
        case settingsPath: return sessionOK(#"{"version":"0.9.0","server_timezone":"Asia/Tokyo","server_utc_offset":"+09:00"}"#)
        default: return sessionFailure(404, reason: "NOT_FOUND")
        }
    }
    let site = try await SiteSession.establish(client: sessionClient(transport, credential: .adminKey("fixture-key")))
    #expect(site.serverTimeZone.identifier == "Asia/Tokyo")
    #expect(site.capabilities.isEmpty); #expect(!site.has(.dashboardRates))
    #expect(site.me.user == nil); #expect(site.operatorNote == nil); #expect(site.identityEmail == nil)
    #expect(site.authMethodLabel == "Admin Key · 以第一个管理员身份操作")
    // The old-server path already read settings/public once.
    #expect((await transport.paths()).filter { $0 == settingsPath }.count == 1)
}

@Test func timeZoneFallsBackToPublicSettingsThenDevice() async throws {
    let fromSettings = siteTransport(me: meJSON(timezone: nil, offset: nil), settings: #"{"server_timezone":"Asia/Tokyo","server_utc_offset":"+09:00"}"#)
    let site = try await SiteSession.establish(client: sessionClient(fromSettings))
    #expect(site.serverTimeZone.identifier == "Asia/Tokyo")
    #expect(await fromSettings.paths() == [mePath, settingsPath])
    let neither = siteTransport(me: meJSON(timezone: nil, offset: "+09:00"))
    let device = try await SiteSession.establish(client: sessionClient(neither))
    #expect(device.serverTimeZone == .device)
}

@Test func clockOffsetComesFromDateHeaderOfProbe() async throws {
    let local = Date(timeIntervalSince1970: 1_800_000_000)
    let serverDate = "Fri, 15 Jan 2027 08:02:00 GMT" // local + 120 s
    let transport = SessionTransport { _ in sessionOK(meJSON(), headers: ["Date": serverDate]) }
    let site = try await SiteSession.establish(client: sessionClient(transport, serverClock: ServerClock(localNow: { local })), now: local)
    #expect(site.clockOffset == 120); #expect(site.probedAt == local)
    let silent = try await SiteSession.establish(client: sessionClient(siteTransport(me: meJSON())))
    #expect(silent.clockOffset == 0)
}
