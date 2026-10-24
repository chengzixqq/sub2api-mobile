import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func publicSettings(_ json: String) throws -> PublicSettings {
    try JSONDecoder().decode(PublicSettings.self, from: Data(json.utf8))
}

@Test func loginMethodsKeepSpecOrderTitlesBadgesAndNotes() {
    #expect(LoginMethod.allCases == [.password, .accessToken, .adminKey])
    #expect(LoginMethod.allCases.map(\.title) == ["账号和密码", "管理访问令牌", "Admin Key"])
    #expect(LoginMethod.allCases.map(\.badge) == ["推荐", nil, "不推荐"])
    #expect(LoginMethod.password.note == nil)
    #expect(LoginMethod.accessToken.note == "以签发它的管理员身份操作，可只读、会过期、能单独吊销。")
    #expect(LoginMethod.adminKey.note == "以第一个管理员身份操作，不能做需要二次验证的操作。丢失设备请到 Web 重新生成 Key。")
    #expect(LoginMethod.allCases.map(\.usesKey) == [false, true, true])
    for method in LoginMethod.allCases { #expect(LoginMethod(method.authenticationKind) == method) }
    #expect(LoginMethod.accessToken.authenticationKind == .accessToken)
}

@Test func pastedSatPrefixSwitchesAdminKeyToAccessTokenOnly() {
    #expect(LoginMethod.adminKey.adjusted(forKey: "sat_abc") == .accessToken)
    #expect(LoginMethod.adminKey.adjusted(forKey: "  sat_x\n") == .accessToken)
    #expect(LoginMethod.adminKey.adjusted(forKey: "SAT_x") == .adminKey)
    #expect(LoginMethod.adminKey.adjusted(forKey: "abc") == .adminKey)
    #expect(LoginMethod.accessToken.adjusted(forKey: "abc") == .accessToken)
    #expect(LoginMethod.password.adjusted(forKey: "sat_abc") == .password)
}

struct CaptchaSettingsRow: Sendable, CustomTestStringConvertible {
    let json: String
    let expected: CaptchaRequirement
    var testDescription: String { json }
}
private let captchaSettingsRows: [CaptchaSettingsRow] = [
    CaptchaSettingsRow(json: #"{"captcha_provider":""}"#, expected: .none),
    CaptchaSettingsRow(json: #"{"captcha_provider":"","turnstile_enabled":true}"#, expected: .none),
    CaptchaSettingsRow(json: #"{"captcha_provider":"turnstile","mobile_verify_path":"/mobile/verify"}"#,
                       expected: .bridge(provider: "turnstile", path: "/mobile/verify", showsFallbackHint: false)),
    CaptchaSettingsRow(json: #"{"captcha_provider":"aliyun","mobile_verify_path":""}"#,
                       expected: .bridge(provider: "aliyun", path: "/mobile/verify", showsFallbackHint: true)),
    CaptchaSettingsRow(json: #"{"captcha_provider":"tencent","mobile_verify_path":"//evil.example/x"}"#,
                       expected: .bridge(provider: "tencent", path: "/mobile/verify", showsFallbackHint: true)),
    CaptchaSettingsRow(json: #"{"captcha_provider":"conflict"}"#, expected: .conflict),
    CaptchaSettingsRow(json: #"{"tencent_captcha_enabled":true}"#, expected: .bridge(provider: "tencent", path: "/mobile/verify", showsFallbackHint: true)),
    CaptchaSettingsRow(json: #"{"turnstile_enabled":true,"aliyun_captcha_enabled":true}"#, expected: .conflict),
    CaptchaSettingsRow(json: "{}", expected: .none),
    CaptchaSettingsRow(json: #"{"captcha_provider":"geetest"}"#, expected: .unsupported(provider: "geetest"))
]

@Test(arguments: captchaSettingsRows)
func captchaRequirementFollowsProviderKeyAndLegacySwitches(row: CaptchaSettingsRow) throws {
    #expect(CaptchaRequirement(try publicSettings(row.json)) == row.expected)
}

@Test func captchaBridgePathRejectsUnsafeServerValues() {
    #expect(CaptchaBridge.path(from: "/mobile/verify") == "/mobile/verify")
    #expect(CaptchaBridge.path(from: "/custom/verify-1") == "/custom/verify-1")
    for unsafe in ["//evil.example/x", "https://evil.example", "/a/../b", "/x?y=1", "/x#f", "x", "", "/a b", "/中文"] {
        #expect(CaptchaBridge.path(from: unsafe) == "/mobile/verify", "\(unsafe)")
    }
    #expect(CaptchaBridge.path(from: nil) == "/mobile/verify")
    #expect(CaptchaBridge.providers == ["turnstile", "tencent", "aliyun"])
    #expect(CaptchaBridge.proofLifetime == 120); #expect(CaptchaBridge.timeout == 180)
}

@Test func captchaRequestURLCarriesOnlyNonceAndKeepsPort() throws {
    let site = ServerProfile(name: "桥页", baseURL: URL(string: "https://host.example.invalid:8443")!, authentication: .password)
    let request = CaptchaRequest(server: site, provider: "turnstile", path: "/mobile/verify", showsFallbackHint: false)
    let url = try #require(request.url)
    #expect(url.absoluteString == "https://host.example.invalid:8443/mobile/verify?nonce=\(request.id.uuidString)")
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "nonce", value: request.id.uuidString)])
    #expect(CaptchaRequest(server: site, provider: "turnstile", path: "/mobile/verify", showsFallbackHint: false).id != request.id)
}

@Test func loginAgreementMatchesWebGating() throws {
    let documents = #""login_agreement_documents":[{"id":"terms","title":"服务条款","content_md":"**欢迎**"},{"id":"blank","title":"  ","content_md":"x"}]"#
    let checkbox = try #require(LoginAgreement(try publicSettings(#"{"login_agreement_enabled":true,"login_agreement_mode":"checkbox","login_agreement_revision":"r1",\#(documents)}"#)))
    #expect(checkbox.mode == .checkbox); #expect(checkbox.documents.map(\.id) == ["terms"]); #expect(checkbox.revision == "r1")
    for mode in [#""login_agreement_mode":"modal","#, #""login_agreement_mode":"","#, #""login_agreement_mode":"x","#, ""] {
        let agreement = try #require(LoginAgreement(try publicSettings("{\"login_agreement_enabled\":true,\(mode)\(documents)}")))
        #expect(agreement.mode == .modal)
    }
    #expect(LoginAgreement(try publicSettings(#"{"login_agreement_enabled":true,"login_agreement_documents":[{"id":"a","title":"","content_md":"x"}]}"#)) == nil)
    #expect(LoginAgreement(try publicSettings(#"{"login_agreement_enabled":false,\#(documents)}"#)) == nil)
    #expect(LoginAgreement(try publicSettings(#"{\#(documents)}"#)) == nil)
    let derived = try #require(LoginAgreement(try publicSettings(#"{"login_agreement_enabled":true,"login_agreement_updated_at":"2026-10-01",\#(documents)}"#)))
    #expect(derived.revision == "2026-10-01:terms:服务条款")
    #expect(LoginAgreement(try publicSettings(#"{"login_agreement_enabled":true,"login_agreement_revision":"",\#(documents)}"#))?.revision == ":terms:服务条款")
}

@Test func siteCheckRequiresVersionAndNameFallsBackToSiteName() throws {
    #expect(LoginSite.isSub2(try publicSettings(#"{"version":"0.2.30"}"#)))
    #expect(!LoginSite.isSub2(try publicSettings(#"{"version":""}"#)))
    #expect(!LoginSite.isSub2(try publicSettings("{}")))
    #expect(LoginSite.resolvedName(input: "  ", siteName: "演示站") == "演示站")
    #expect(LoginSite.resolvedName(input: " 我的站 ", siteName: "演示站") == "我的站")
    #expect(LoginSite.resolvedName(input: "", siteName: " ") == nil)
    #expect(LoginSite.resolvedName(input: "", siteName: nil) == nil)
}

@Test func cooldownRoundsUpAndNeverNegative() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(LoginCooldown.remainingSeconds(until: now.addingTimeInterval(2.1), now: now) == 3)
    #expect(LoginCooldown.remainingSeconds(until: now.addingTimeInterval(3), now: now) == 3)
    #expect(LoginCooldown.remainingSeconds(until: now.addingTimeInterval(-1), now: now) == 0)
    #expect(LoginCooldown.remainingSeconds(until: nil, now: now) == 0)
    #expect(LoginCopy.cooldownButton(3) == "3 秒后重试")
}

@Test func captchaLoadFailureIgnoresCancellationAndSeparatesNetwork() {
    #expect(CaptchaLoadFailure.message(domain: NSURLErrorDomain, code: NSURLErrorCancelled) == nil)
    #expect(CaptchaLoadFailure.message(domain: "WebKitErrorDomain", code: 102) == nil)
    for code in [NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut,
                 NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted] {
        #expect(CaptchaLoadFailure.message(domain: NSURLErrorDomain, code: code) == "无法连接站点", "\(code)")
    }
    #expect(CaptchaLoadFailure.message(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist) == "站点未部署手机验证页，请改用 Web 或关闭验证码")
    #expect(CaptchaLoadFailure.message(domain: "WebKitErrorDomain", code: 101) == "站点未部署手机验证页，请改用 Web 或关闭验证码")
    #expect(CaptchaLoadFailure.message(httpStatus: 404) == "站点未部署手机验证页，请改用 Web 或关闭验证码")
    #expect(CaptchaLoadFailure.message(httpStatus: 200) == nil); #expect(CaptchaLoadFailure.message(httpStatus: 304) == nil)
}

@Test func normalizedURLKeepsExistingStationRules() throws {
    #expect(try ServerProfile.normalizedURL(" https://Sub2.Example.com/ ").absoluteString == "https://sub2.example.com")
    #expect(try ServerProfile.normalizedURL("HTTPS://sub2.example.com:8443").absoluteString == "https://sub2.example.com:8443")
    for raw in ["http://example.com", "https://user:pass@example.com", "https://example.com/path", "https://example.com/?q=1",
                "https://example.com/#f", "", "example.com"] {
        let error = try #require(throws: APIError.self, "\(raw)") { try ServerProfile.normalizedURL(raw) }
        #expect(error.localizedDescription.contains("HTTPS"))
        #expect(error.kind == .validation)
    }
}

@Test func connectedReceiptUsesIdentityEmail() {
    #expect(LoginCopy.connectedReceipt(email: "admin@example.com") == "已连接 · 以 admin@example.com 身份操作")
    #expect(LoginCopy.connectedReceipt(email: nil) == "已连接")
    #expect(LoginCopy.connectedReceipt(email: "") == "已连接")
}

@Test func catalogOwnedLoginTextsAreReadFromTheCatalog() {
    #expect(LoginSite.backendModeHint == "站点处于后端模式，仅管理员可登录")
    #expect(CaptchaRequirement.conflict.stopMessage == "站点同时开启了多个验证码服务，请在 Web 后台修正")
    #expect(CaptchaRequirement.unsupported(provider: "geetest").stopMessage == "站点的验证方式暂不支持，请改用 Web 登录或管理访问令牌")
    #expect(CaptchaRequirement.none.stopMessage == nil)
    #expect(CaptchaRequirement.bridge(provider: "turnstile", path: "/mobile/verify", showsFallbackHint: false).stopMessage == nil)
}

private func loginClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}

@Test(arguments: [ScriptStep.fail(URLError(.notConnectedToInternet)),
                  .reply(HTTPResponse(statusCode: 502, headers: ["content-type": "text/html"], data: Data("<html>bad gateway</html>".utf8)))])
func loginIsSentOnceOnNetworkErrorAnd5xx(step: ScriptStep) async throws {
    let transport = ScriptedTransport(script: [step, .reply(okReply("{}"))])
    let error = try #require(await thrownAPIError {
        _ = try await loginClient(transport).login(email: "admin@example.invalid", password: "only-test", deviceName: "iPhone", declaresCaptchaProvider: true)
    })
    #expect(await transport.requests(path: "/auth/login").count == 1)
    #expect(LoginFailure.classify(error, stage: .password)?.action == LoginFailure.Action.none)
    let second = ScriptedTransport(script: [step, .reply(okReply("{}"))])
    _ = await thrownAPIError { _ = try await loginClient(second).completeTOTP(tempToken: "temporary", code: "123456") }
    #expect(await second.requests(path: "/auth/login/2fa").count == 1)
}

@Test(arguments: [(["Retry-After": "7"], #","retry_after":12"#, 7), ([:], #","retry_after":12"#, 12), ([:], "", 30)])
func rateLimitedLoginPrefersRetryAfterHeaderOverBody(headers: [String: String], body: String, seconds: Int) async throws {
    let transport = ScriptedTransport { _ in errorReply(429, reason: "RATE_LIMITED", headers: headers, extra: body) }
    let error = try #require(await thrownAPIError {
        _ = try await loginClient(transport).login(email: "admin@example.invalid", password: "only-test", deviceName: "iPhone", declaresCaptchaProvider: true)
    })
    let failure = try #require(LoginFailure.classify(error, stage: .password))
    #expect(failure.action == .cooldown(seconds: seconds))
    #expect(failure.message == "登录过于频繁，请 \(seconds) 秒后再试")
    #expect(await transport.requests.count == 1)
}
