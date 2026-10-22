import Foundation
import Testing
@testable import Sub2Core

private func relaxedProfile(_ name: String, _ kind: AuthenticationKind = .password) -> ServerProfile {
    ServerProfile(name: name, baseURL: URL(string: "https://\(name).example.invalid")!, authentication: kind)
}
private func jsonObject(_ data: Data) throws -> Any { try JSONSerialization.jsonObject(with: data) }
private struct DecodableOnlyItem: Decodable, Sendable, Equatable { let id: Int }

@Test func credentialMigratesStoredSatAdminKeyToAccessToken() throws {
    let decode = { (json: String) in try JSONDecoder().decode(Credential.self, from: Data(json.utf8)) }
    #expect(try decode(#"{"adminKey":{"_0":"sat_fixture"}}"#) == .accessToken("sat_fixture"))
    #expect(try decode(#"{"adminKey":{"_0":"fixture-key"}}"#) == .adminKey("fixture-key"))
    // The backend prefix check is case-sensitive.
    #expect(try decode(#"{"adminKey":{"_0":"SAT_fixture"}}"#) == .adminKey("SAT_fixture"))
    #expect(try decode(#"{"accessToken":{"_0":"sat_new"}}"#) == .accessToken("sat_new"))
}

@Test func credentialEncodingKeepsSynthesizedWireFormat() throws {
    let pair = TokenPair(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSinceReferenceDate: 0))
    let cases: [(Credential, String)] = [(.adminKey("fixture-key"), "adminKey"), (.accessToken("sat_fixture"), "accessToken"), (.tokens(pair), "tokens")]
    for (credential, key) in cases {
        let data = try JSONEncoder().encode(credential)
        let object = try #require(try jsonObject(data) as? [String: Any])
        #expect(Array(object.keys) == [key])
        let inner = try #require(object[key] as? [String: Any])
        #expect(Array(inner.keys) == ["_0"])
        #expect(try JSONDecoder().decode(Credential.self, from: data) == credential)
    }
    let stored = try JSONDecoder().decode(Credential.self, from: Data(#"{"tokens":{"_0":{"accessToken":"a","refreshToken":"r","expiresAt":0}}}"#.utf8))
    #expect(stored == .tokens(pair))
    #expect(throws: (any Error).self) { try JSONDecoder().decode(Credential.self, from: Data(#"{"password":{"_0":"x"}}"#.utf8)) }
}

@Test func credentialFromAPIKeyTrimsAndUsesCaseSensitiveSatPrefix() {
    #expect(Credential.fromAPIKey("sat_abc") == .accessToken("sat_abc"))
    #expect(Credential.fromAPIKey(" \tsat_abc\n") == .accessToken("sat_abc"))
    #expect(Credential.fromAPIKey("k") == .adminKey("k"))
    #expect(Credential.fromAPIKey("  k \n") == .adminKey("k"))
    #expect(Credential.fromAPIKey("SAT_abc") == .adminKey("SAT_abc"))
    #expect(Credential.fromAPIKey("sat_abc").authenticationKind == .accessToken)
    #expect(Credential.adminKey("k").authenticationKind == .adminKey)
    #expect(Credential.tokens(TokenPair(accessToken: "a", refreshToken: "r", expiresAt: Date())).authenticationKind == .password)
}

@Test func authenticationKindDecodesOldAndNewRawValuesAndFallsBackToPassword() throws {
    for kind in [AuthenticationKind.adminKey, .password, .accessToken] {
        let profile = relaxedProfile("kind", kind)
        #expect(try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(profile)) == profile)
    }
    var fields = try #require(try jsonObject(JSONEncoder().encode(relaxedProfile("future", .adminKey))) as? [String: Any])
    #expect(fields["authentication"] as? String == "adminKey")
    fields["authentication"] = "passkey"
    let decoded = try JSONDecoder().decode(ServerProfile.self, from: JSONSerialization.data(withJSONObject: fields))
    #expect(decoded.authentication == .password); #expect(decoded.name == "future")
}

@Test func storedProfilesSkipOnlyUnreadableEntries() throws {
    let first = relaxedProfile("first"), second = relaxedProfile("second", .accessToken)
    var list = try #require(try jsonObject(JSONEncoder().encode([first, second])) as? [Any])
    list.insert(["id": "not-a-uuid", "name": 3], at: 1)
    let listData = try JSONSerialization.data(withJSONObject: list)
    #expect(ServerProfile.storedList(from: listData) == [first, second])
    #expect(ServerProfile.storedList(from: Data("not json".utf8)).isEmpty)

    let archive = [first.id: first, second.id: second]
    let encoded = try jsonObject(JSONEncoder().encode(archive))
    let damaged: Any
    // Dictionaries with UUID keys may be written as an object or as alternating key/value pairs.
    if var pairs = encoded as? [Any] {
        let index = try #require(pairs.indices.first { $0 % 2 == 0 && (pairs[$0] as? String) == second.id.uuidString })
        pairs[index + 1] = ["broken": true]
        damaged = pairs
    } else {
        var object = try #require(encoded as? [String: Any])
        object[second.id.uuidString] = ["broken": true]
        damaged = object
    }
    let damagedData = try JSONSerialization.data(withJSONObject: damaged), intactData = try JSONEncoder().encode(archive)
    #expect(ServerProfile.storedArchive(from: damagedData) == [first.id: first])
    #expect(ServerProfile.storedArchive(from: intactData) == archive)
}

@Test func captchaProofCarriesProviderAndAliyunParam() throws {
    let proof = CaptchaProof(provider: "aliyun", turnstileToken: "fixture-proof", aliyunParam: "fixture-proof")
    let object = try #require(try jsonObject(JSONEncoder().encode(proof)) as? [String: Any])
    #expect(object["captcha_provider"] as? String == "aliyun"); #expect(object["aliyun_captcha_param"] as? String == "fixture-proof")
    #expect(object["turnstile_token"] as? String == "fixture-proof")
    #expect(CaptchaProof(tencentTicket: "t", tencentRandstr: "r").provider == nil)
}

@Test func publicSettingsKeepsRawFieldsFromCurrentServer() throws {
    let json = #"""
    {"captcha_provider":"aliyun","turnstile_enabled":false,"tencent_captcha_enabled":false,"aliyun_captcha_enabled":true,
    "mobile_verify_path":"/mobile/verify","site_name":"Sub2 测试站","site_logo":"https://logo.example.invalid/a.png","version":"0.9.0",
    "server_timezone":"Asia/Shanghai","server_utc_offset":"+08:00","backend_mode_enabled":true,"totp_enabled":true,
    "login_agreement_enabled":true,"login_agreement_mode":"checkbox","login_agreement_revision":"r2","login_agreement_updated_at":"2026-10-01T00:00:00Z",
    "login_agreement_documents":[{"id":"terms","title":"服务条款","content_md":"# 条款\n内容"}],
    "channel_monitor_enabled":true,"channel_monitor_mode":"active","payment_enabled":true,"subscription_enabled":false}
    """#
    let settings = try JSONDecoder().decode(PublicSettings.self, from: Data(json.utf8))
    #expect(settings.hasCaptchaProviderKey); #expect(settings.rawCaptchaProvider == "aliyun"); #expect(settings.captchaProvider == "aliyun")
    #expect(settings.captchaEnabled); #expect(!settings.isCaptchaConflict); #expect(settings.aliyunCaptchaEnabled == true)
    #expect(settings.mobileVerifyPath == "/mobile/verify"); #expect(settings.siteName == "Sub2 测试站")
    #expect(settings.siteLogo == "https://logo.example.invalid/a.png"); #expect(settings.version == "0.9.0")
    #expect(settings.serverTimezone == "Asia/Shanghai"); #expect(settings.serverUTCOffset == "+08:00")
    #expect(settings.backendModeEnabled == true); #expect(settings.totpEnabled == true)
    #expect(settings.loginAgreementEnabled == true); #expect(settings.loginAgreementMode == "checkbox")
    #expect(settings.loginAgreementRevision == "r2"); #expect(settings.loginAgreementUpdatedAt == "2026-10-01T00:00:00Z")
    #expect(settings.loginAgreementDocuments == [LoginAgreementDocument(id: "terms", title: "服务条款", contentMarkdown: "# 条款\n内容")])
    #expect(settings.channelMonitorEnabled == true); #expect(settings.channelMonitorMode == "active")
    #expect(settings.paymentEnabled == true); #expect(settings.subscriptionEnabled == false)
}

@Test func publicSettingsProviderKeyWinsOverLegacyFlags() throws {
    let decode = { (json: String) in try JSONDecoder().decode(PublicSettings.self, from: Data(json.utf8)) }
    let disabled = try decode(#"{"captcha_provider":"","turnstile_enabled":true}"#)
    #expect(disabled.hasCaptchaProviderKey); #expect(disabled.captchaProvider == nil); #expect(!disabled.captchaEnabled)
    let legacy = try decode(#"{"tencent_captcha_enabled":true}"#)
    #expect(!legacy.hasCaptchaProviderKey); #expect(legacy.captchaProvider == "tencent"); #expect(legacy.captchaEnabled)
    let none = try decode("{}")
    #expect(none.captchaProvider == nil); #expect(!none.captchaEnabled); #expect(none.loginAgreementDocuments.isEmpty)
    #expect(none.version == nil); #expect(none.backendModeEnabled == nil)
}

@Test func publicSettingsReportsConflictWithoutThrowing() throws {
    for json in [#"{"captcha_provider":"conflict","turnstile_enabled":true,"tencent_captcha_enabled":true}"#,
                 #"{"turnstile_enabled":true,"tencent_captcha_enabled":true}"#] {
        let settings = try JSONDecoder().decode(PublicSettings.self, from: Data(json.utf8))
        #expect(settings.isCaptchaConflict); #expect(settings.captchaEnabled); #expect(settings.captchaProvider == "conflict")
    }
}

@Test func publicSettingsDistinguishesEmptyAndMissingMobileVerifyPath() throws {
    #expect(try JSONDecoder().decode(PublicSettings.self, from: Data(#"{"mobile_verify_path":""}"#.utf8)).mobileVerifyPath == "")
    #expect(try JSONDecoder().decode(PublicSettings.self, from: Data("{}".utf8)).mobileVerifyPath == nil)
}

@Test func pageAcceptsDeferredEnvelopeWithNullTotal() throws {
    let json = #"{"items":[],"total":null,"page":1,"page_size":20,"pages":null,"has_more":true,"total_exact":false,"query":{"timezone":"UTC"}}"#
    let page = try JSONDecoder().decode(Page<DecodableOnlyItem>.self, from: Data(json.utf8))
    #expect(page.total == nil); #expect(page.pages == nil); #expect(page.hasMore); #expect(page.reportedHasMore == true)
}

@Test func pageDecodesIncrementalEnvelope() throws {
    let json = #"{"items":[{"id":181}],"total":null,"page":1,"page_size":50,"pages":null,"has_more":false,"since_id":100,"latest_id":180}"#
    let page = try JSONDecoder().decode(Page<DecodableOnlyItem>.self, from: Data(json.utf8))
    #expect(page.sinceID == 100); #expect(page.latestID == 180); #expect(!page.hasMore); #expect(page.items == [DecodableOnlyItem(id: 181)])
}

@Test func pageHasMorePrefersServerFlag() throws {
    let flagged = try JSONDecoder().decode(Page<DecodableOnlyItem>.self, from: Data(#"{"items":[],"page":1,"page_size":20,"pages":3,"has_more":false}"#.utf8))
    #expect(!flagged.hasMore)
    let computed = try JSONDecoder().decode(Page<DecodableOnlyItem>.self, from: Data(#"{"items":[],"total":41,"page":2,"page_size":20}"#.utf8))
    #expect(computed.hasMore); #expect(computed.pages == 3)
    let lastByTotal = Page(items: [DecodableOnlyItem](), total: 40, page: 2, pageSize: 20, pages: nil)
    #expect(!lastByTotal.hasMore)
    #expect(!Page(items: [DecodableOnlyItem](), total: nil, page: 1, pageSize: 20, pages: nil).hasMore)
}

@Test func pageRejectsInvalidCounters() {
    for json in [#"{"items":[],"total":-1,"page":1,"page_size":20}"#, #"{"items":[],"total":1,"page":0,"page_size":20}"#,
                 #"{"items":[],"total":1,"page":1,"page_size":0}"#, #"{"items":[],"total":1,"page":1,"page_size":20,"pages":-1}"#] {
        #expect(throws: APIError.self) { try JSONDecoder().decode(Page<DecodableOnlyItem>.self, from: Data(json.utf8)) }
    }
}

@Test func pageMapItemsKeepsMetadataAndAcceptsDecodableOnlyItems() throws {
    let json = #"{"items":[{"id":1},{"id":2}],"total":9,"page":2,"page_size":2,"pages":5,"has_more":true,"since_id":3,"latest_id":8}"#
    let page = try JSONDecoder().decode(Page<DecodableOnlyItem>.self, from: Data(json.utf8))
    let mapped = page.mapItems { $0.id * 10 }
    #expect(mapped.items == [10, 20]); #expect(mapped.total == 9); #expect(mapped.page == 2); #expect(mapped.pageSize == 2)
    #expect(mapped.pages == 5); #expect(mapped.reportedHasMore == true); #expect(mapped.sinceID == 3); #expect(mapped.latestID == 8)
}
