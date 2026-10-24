import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private let plainSettings = #"{"version":"0.2.30","site_name":"演示站","captcha_provider":""}"#
private func settings(_ json: String) -> PublicSettings { try! JSONDecoder().decode(PublicSettings.self, from: Data(json.utf8)) }
private func captchaSettings(_ provider: String, path: String = "") -> PublicSettings {
    settings(#"{"version":"0.2.30","site_name":"演示站","captcha_provider":"\#(provider)","mobile_verify_path":"\#(path)"}"#)
}
private let issuedTokens = TokenPair(accessToken: "issued-access", refreshToken: "issued-refresh", expiresAt: Date(timeIntervalSince1970: 1_900_000_000))
private let issued = AuthSession(user: AdminUser(id: 1, email: "admin@example.com", role: "admin"), tokens: issuedTokens)
private func loginError(_ status: Int, _ reason: String, context: ReasonCatalog.Context = .login, retryAfter: Int? = nil,
                        metadata: [String: String]? = nil) -> APIError {
    APIError.server(status: status, envelope: ErrorEnvelope(reason: reason, metadata: metadata, retryAfter: retryAfter), context: context, retryAfter: retryAfter)
}

/// Answers from scripts whose last entry repeats; `loginGate` holds `login` until opened.
private actor StubLoginGateway: LoginGateway {
    struct Login: Sendable { let email: String; let password: String; let proof: CaptchaProof?; let deviceName: String; let declares: Bool }
    private var settingsScript: [Result<PublicSettings, any Error>]
    private var loginScript: [Result<LoginResult, any Error>]
    private var totpScript: [Result<AuthSession, any Error>]
    private let loginGate: SessionGate?
    private(set) var settingsCalls = 0
    private(set) var logins: [Login] = []
    private(set) var codes: [String] = []
    private(set) var cancels = 0

    init(settings: [Result<PublicSettings, any Error>] = [.success(settings(plainSettings))],
         logins: [Result<LoginResult, any Error>] = [.success(.authenticated(issued))],
         totp: [Result<AuthSession, any Error>] = [.success(issued)], loginGate: SessionGate? = nil) {
        settingsScript = settings; loginScript = logins; totpScript = totp; self.loginGate = loginGate
    }
    func publicSettings() async throws -> PublicSettings { settingsCalls += 1; return try Self.next(&settingsScript).get() }
    func login(email: String, password: String, proof: CaptchaProof?, deviceName: String, declaresCaptchaProvider: Bool) async throws -> LoginResult {
        logins.append(Login(email: email, password: password, proof: proof, deviceName: deviceName, declares: declaresCaptchaProvider))
        await loginGate?.wait()
        return try Self.next(&loginScript).get()
    }
    func completeTOTP(tempToken: String, code: String) async throws -> AuthSession { codes.append(code); return try Self.next(&totpScript).get() }
    func cancelAll() async { cancels += 1 }
    func script(settings: [Result<PublicSettings, any Error>]? = nil, logins: [Result<LoginResult, any Error>]? = nil) {
        if let settings { settingsScript = settings }
        if let logins { loginScript = logins }
    }
    private static func next<Value>(_ script: inout [Result<Value, any Error>]) -> Result<Value, any Error> {
        script.count > 1 ? script.removeFirst() : script[0]
    }
}

@MainActor private final class LoginHarness {
    let gateway: StubLoginGateway
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var made: [(profile: ServerProfile, deviceID: UUID)] = []
    var connects: [(profile: ServerProfile, credential: Credential, deviceID: UUID)] = []
    var announced: [String?] = []
    var cancelledConnections = 0
    var storedDeviceID = UUID()
    var connectError: (any Error)?
    private(set) var controller: LoginController!

    init(gateway: StubLoginGateway = StubLoginGateway(), prompt: LoginPrompt? = nil) {
        self.gateway = gateway
        let environment = LoginEnvironment(
            deviceName: "测试 iPhone",
            makeGateway: { [unowned self] profile, deviceID in self.made.append((profile, deviceID)); return self.gateway },
            storedDeviceID: { [unowned self] _ in self.storedDeviceID },
            connect: { [unowned self] profile, credential, deviceID in
                self.connects.append((profile, credential, deviceID))
                if let connectError = self.connectError { throw connectError }
                return "admin@example.com"
            },
            cancelConnection: { [unowned self] in self.cancelledConnections += 1 },
            didConnect: { [unowned self] email in self.announced.append(email) },
            now: { [unowned self] in self.now })
        controller = LoginController(prompt: prompt, environment: environment)
        controller.address = prompt?.profile.baseURL.absoluteString ?? "https://sub2.example.invalid"
    }
    func fillPassword(email: String = "admin@example.com", password: String = "only-test") {
        controller.email = email; controller.password = password
    }
    func completeCaptcha(_ provider: String = "turnstile", token: String = "t-proof") async {
        controller.captchaCompleted(.proof(CaptchaProof(provider: provider, turnstileToken: token)))
        await controller.captchaDismissed()
    }
}

@MainActor @Test func passwordLoginWithoutCaptchaConnectsWithTokensAndAnnouncesIdentity() async throws {
    let harness = LoginHarness()
    harness.fillPassword()
    await harness.controller.submit()
    let logins = await harness.gateway.logins
    #expect(logins.count == 1)
    #expect(logins.first?.proof == nil); #expect(logins.first?.declares == true); #expect(logins.first?.deviceName == "测试 iPhone")
    let connect = try #require(harness.connects.first)
    #expect(connect.credential == .tokens(issuedTokens))
    #expect(connect.deviceID == harness.made.first?.deviceID)
    #expect(connect.profile.authentication == .password)
    #expect(harness.announced == ["admin@example.com"])
    #expect(harness.controller.password.isEmpty); #expect(harness.controller.code.isEmpty)
    #expect(harness.controller.notice == nil); #expect(!harness.controller.isBusy)
}

@MainActor @Test func captchaRequiredOpensBridgeWithServerPathAndHint() async throws {
    let harness = LoginHarness(gateway: StubLoginGateway(settings: [.success(captchaSettings("turnstile"))]))
    harness.fillPassword()
    await harness.controller.submit()
    let request = try #require(harness.controller.captcha)
    #expect(request.provider == "turnstile"); #expect(request.path == "/mobile/verify"); #expect(request.showsFallbackHint)
    #expect(request.server.baseURL.absoluteString == "https://sub2.example.invalid")
    #expect(await harness.gateway.logins.isEmpty)

    let packaged = LoginHarness(gateway: StubLoginGateway(settings: [.success(captchaSettings("turnstile", path: "/mobile/verify"))]))
    packaged.fillPassword()
    await packaged.controller.submit()
    #expect(packaged.controller.captcha?.showsFallbackHint == false)
}

@MainActor @Test func proofIsUsedOnceAndDiscardedAfterInvalidCredentials() async throws {
    let gateway = StubLoginGateway(settings: [.success(captchaSettings("turnstile"))], logins: [.failure(loginError(401, "INVALID_CREDENTIALS"))])
    let harness = LoginHarness(gateway: gateway)
    harness.fillPassword()
    await harness.controller.submit()
    await harness.completeCaptcha()
    let logins = await gateway.logins
    #expect(logins.count == 1); #expect(logins.first?.proof?.turnstileToken == "t-proof")
    #expect(harness.controller.password == ""); #expect(harness.controller.notice == "邮箱或密码错误")
    #expect(!harness.controller.hasProof); #expect(harness.controller.captcha == nil)
    harness.controller.password = "only-test"
    await harness.controller.submit()
    #expect(harness.controller.captcha != nil)
    #expect(await gateway.logins.count == 1)
}

@MainActor @Test func proofIsDroppedWhenExpiredProviderChangedOrNoLongerRequired() async throws {
    let gateway = StubLoginGateway(settings: [.success(captchaSettings("turnstile"))])
    let harness = LoginHarness(gateway: gateway)
    harness.fillPassword()
    await harness.controller.submit()
    let first = try #require(harness.controller.captcha)
    harness.controller.captchaCompleted(.proof(CaptchaProof(provider: "turnstile", turnstileToken: "t-proof")))
    harness.now = harness.now.addingTimeInterval(121)
    await harness.controller.captchaDismissed()
    #expect(harness.controller.captcha != nil); #expect(harness.controller.captcha?.id != first.id)
    #expect(await gateway.logins.isEmpty)

    await gateway.script(settings: [.success(captchaSettings("aliyun"))])
    await harness.completeCaptcha("turnstile")
    #expect(harness.controller.captcha?.provider == "aliyun")
    #expect(await gateway.logins.isEmpty)

    await gateway.script(settings: [.success(settings(plainSettings))])
    await harness.completeCaptcha("aliyun")
    let logins = await gateway.logins
    #expect(logins.count == 1); #expect(logins.first?.proof == nil)
}

@MainActor @Test func captchaConflictAndUnsupportedProviderStopBeforeLogin() async throws {
    for (provider, message) in [("conflict", "站点同时开启了多个验证码服务，请在 Web 后台修正"), ("geetest", "站点的验证方式暂不支持，请改用 Web 登录或管理访问令牌")] {
        let gateway = StubLoginGateway(settings: [.success(captchaSettings(provider))])
        let harness = LoginHarness(gateway: gateway)
        harness.fillPassword()
        await harness.controller.submit()
        #expect(harness.controller.notice == message); #expect(harness.controller.captcha == nil)
        #expect(await gateway.logins.isEmpty); #expect(harness.connects.isEmpty)
    }
}

@MainActor @Test func providerMismatchReloadsSettingsAndReverifiesOnce() async throws {
    let mismatch = loginError(400, "CAPTCHA_PROVIDER_MISMATCH", metadata: ["captcha_provider": "aliyun"])
    let gateway = StubLoginGateway(settings: [.success(captchaSettings("turnstile")), .success(captchaSettings("turnstile")),
                                              .success(captchaSettings("aliyun"))], logins: [.failure(mismatch)])
    let harness = LoginHarness(gateway: gateway)
    harness.fillPassword()
    await harness.controller.submit()
    await harness.completeCaptcha("turnstile")
    #expect(await gateway.settingsCalls == 3)
    #expect(harness.controller.captcha?.provider == "aliyun")
    #expect(harness.controller.notice == "站点验证方式已变更，请重新验证")
    #expect(await gateway.logins.count == 1)

    await harness.completeCaptcha("aliyun")
    #expect(await gateway.logins.count == 2); #expect(await gateway.logins.last?.proof?.provider == "aliyun")
    #expect(harness.controller.captcha == nil)
    #expect(harness.controller.notice == "站点验证方式已变更，请重新验证")
}

@MainActor @Test func verificationFailedReopensBridgeOncePerSubmit() async throws {
    let gateway = StubLoginGateway(settings: [.success(captchaSettings("turnstile"))],
                                   logins: [.failure(loginError(400, "TURNSTILE_VERIFICATION_FAILED"))])
    let harness = LoginHarness(gateway: gateway)
    harness.fillPassword()
    await harness.controller.submit()
    await harness.completeCaptcha()
    #expect(harness.controller.captcha != nil); #expect(harness.controller.notice == "安全验证未通过，请重新验证")
    await harness.completeCaptcha(token: "second")
    #expect(harness.controller.captcha == nil); #expect(harness.controller.notice == "安全验证未通过，请重新验证")
    #expect(await gateway.logins.map { $0.proof?.turnstileToken } == ["t-proof", "second"])
    // A new submit may open it again.
    await harness.controller.submit()
    #expect(harness.controller.captcha != nil)
}

@MainActor @Test func cancelledOrFailedBridgeSendsNothing() async throws {
    let gateway = StubLoginGateway(settings: [.success(captchaSettings("tencent"))])
    let harness = LoginHarness(gateway: gateway)
    harness.fillPassword()
    await harness.controller.submit()
    harness.controller.captchaCompleted(.cancelled)
    await harness.controller.captchaDismissed()
    #expect(harness.controller.captcha == nil); #expect(harness.controller.notice == nil)
    await harness.controller.submit()
    harness.controller.captchaCompleted(.failed("站点未部署手机验证页，请改用 Web 或关闭验证码"))
    await harness.controller.captchaDismissed()
    #expect(harness.controller.notice == "站点未部署手机验证页，请改用 Web 或关闭验证码")
    #expect(await gateway.logins.isEmpty)
}

@MainActor @Test func legacySettingsNeverDeclareCaptchaProvider() async throws {
    let gateway = StubLoginGateway(settings: [.success(settings(#"{"version":"0.2.1","tencent_captcha_enabled":true}"#))])
    let harness = LoginHarness(gateway: gateway)
    harness.fillPassword()
    harness.controller.name = "旧站"
    await harness.controller.submit()
    #expect(harness.controller.captcha?.provider == "tencent")
    await harness.completeCaptcha("tencent")
    let login = try #require(await gateway.logins.first)
    #expect(login.declares == false); #expect(login.proof?.provider == "tencent")
}

@MainActor @Test func twoFactorAutoSubmitsSixDigitsAndMapsTOTPErrors() async throws {
    let challenge = LoginResult.twoFactor(TwoFactorChallenge(tempToken: "temporary", maskedEmail: "a***@example.com"))
    let gateway = StubLoginGateway(logins: [.success(challenge)],
                                   totp: [.failure(loginError(400, "TOTP_INVALID_CODE", context: .twoFactor)), .success(issued)])
    let harness = LoginHarness(gateway: gateway)
    let controller = harness.controller!
    harness.fillPassword()
    await controller.submit()
    #expect(controller.challenge?.maskedEmail == "a***@example.com")
    controller.code = "12a34"
    await controller.codeDidChange()
    #expect(controller.code == "1234"); #expect(await gateway.codes.isEmpty)
    controller.code = "000000"
    await controller.codeDidChange()
    #expect(controller.code == ""); #expect(controller.challenge != nil)
    #expect(controller.twoFactorNotice == "验证码不对，请重新输入")
    controller.code = "1234567"
    await controller.codeDidChange()
    #expect(await gateway.codes == ["000000", "123456"])
    #expect(controller.challenge == nil); #expect(controller.twoFactorNotice == nil)
    #expect(harness.connects.first?.credential == .tokens(issuedTokens))
    #expect(harness.announced == ["admin@example.com"])
}

@MainActor @Test func twoFactorLockoutClosesAndExpiryRestartsWithNewVerification() async throws {
    let challenge = LoginResult.twoFactor(TwoFactorChallenge(tempToken: "temporary"))
    let locked = StubLoginGateway(logins: [.success(challenge)], totp: [.failure(loginError(429, "TOTP_TOO_MANY_ATTEMPTS", context: .twoFactor))])
    let lockedHarness = LoginHarness(gateway: locked)
    lockedHarness.fillPassword()
    await lockedHarness.controller.submit()
    lockedHarness.controller.code = "123456"
    await lockedHarness.controller.codeDidChange()
    #expect(lockedHarness.controller.challenge == nil)
    #expect(lockedHarness.controller.notice == "尝试次数过多，请 15 分钟后再试")
    #expect(lockedHarness.controller.cooldownUntil == nil)

    let gateway = StubLoginGateway(settings: [.success(captchaSettings("turnstile"))], logins: [.success(challenge)],
                                   totp: [.failure(loginError(400, "TOTP_LOGIN_SESSION_EXPIRED", context: .twoFactor))])
    let harness = LoginHarness(gateway: gateway)
    harness.fillPassword()
    await harness.controller.submit()
    await harness.completeCaptcha()
    harness.controller.code = "123456"
    await harness.controller.codeDidChange()
    #expect(harness.controller.challenge == nil); #expect(harness.controller.notice == "验证超时，请重新登录")
    #expect(harness.controller.password == "only-test"); #expect(!harness.controller.hasProof)
    await harness.controller.submit()
    #expect(harness.controller.captcha != nil)
    #expect(await gateway.logins.count == 1)
}

@MainActor @Test func rateLimitedStartsCooldownAndBlocksSubmitUntilElapsed() async throws {
    let gateway = StubLoginGateway(logins: [.failure(loginError(429, "RATE_LIMITED", retryAfter: 5)), .success(.authenticated(issued))])
    let harness = LoginHarness(gateway: gateway)
    let controller = harness.controller!
    harness.fillPassword()
    await controller.submit()
    #expect(controller.cooldownUntil == harness.now.addingTimeInterval(5))
    #expect(controller.cooldownRemaining(at: harness.now) == 5)
    #expect(controller.notice == "登录过于频繁，请 5 秒后再试")
    let calls = await gateway.settingsCalls
    harness.now = harness.now.addingTimeInterval(4.5)
    await controller.submit()
    #expect(await gateway.settingsCalls == calls); #expect(await gateway.logins.count == 1)
    controller.cooldownElapsed()
    #expect(controller.cooldownUntil != nil)
    harness.now = harness.now.addingTimeInterval(0.5)
    controller.cooldownElapsed()
    #expect(controller.cooldownUntil == nil)
    await controller.submit()
    #expect(await gateway.logins.count == 2); #expect(harness.connects.count == 1)
}

@MainActor @Test func networkErrorIsShownButNeverRetried() async throws {
    let gateway = StubLoginGateway(settings: [.success(captchaSettings("turnstile"))], logins: [.failure(URLError(.notConnectedToInternet))])
    let harness = LoginHarness(gateway: gateway)
    harness.fillPassword()
    await harness.controller.submit()
    await harness.completeCaptcha()
    #expect(await gateway.logins.count == 1)
    #expect(harness.controller.notice == "无法连接站点")
    #expect(!harness.controller.hasProof); #expect(harness.controller.captcha == nil)
    #expect(harness.controller.cooldownUntil == nil)
}

@MainActor @Test func agreementCheckboxAndModalGateOnlyPasswordLogin() async throws {
    let documents = #""login_agreement_enabled":true,"login_agreement_revision":"r1","login_agreement_documents":[{"id":"t","title":"服务条款","content_md":"x"}]"#
    let checkbox = settings(#"{"version":"1","site_name":"演示站","login_agreement_mode":"checkbox",\#(documents)}"#)
    let boxed = LoginHarness(gateway: StubLoginGateway(settings: [.success(checkbox)]))
    boxed.fillPassword()
    await boxed.controller.submit()
    #expect(boxed.controller.notice == "请先阅读并同意最新条款后再登录"); #expect(await boxed.gateway.logins.isEmpty)
    #expect(boxed.controller.agreement?.mode == .checkbox)
    boxed.controller.agreementChecked = true
    await boxed.controller.submit()
    #expect(await boxed.gateway.logins.count == 1)

    let modal = settings(#"{"version":"1","site_name":"演示站",\#(documents)}"#)
    let asked = LoginHarness(gateway: StubLoginGateway(settings: [.success(modal)]))
    asked.fillPassword()
    await asked.controller.submit()
    #expect(asked.controller.agreementPrompt?.revision == "r1"); #expect(await asked.gateway.logins.isEmpty)
    asked.controller.rejectAgreement()
    await asked.controller.agreementDismissed()
    #expect(asked.controller.notice == "请先阅读并同意最新条款后再登录"); #expect(await asked.gateway.logins.isEmpty)
    await asked.controller.submit()
    asked.controller.acceptAgreement()
    #expect(asked.controller.agreementPrompt == nil)
    await asked.controller.agreementDismissed()
    #expect(await asked.gateway.logins.count == 1)

    let keyed = LoginHarness(gateway: StubLoginGateway(settings: [.success(modal)]))
    keyed.controller.method = .adminKey; keyed.controller.key = "plain-key"
    await keyed.controller.submit()
    #expect(keyed.controller.agreementPrompt == nil); #expect(keyed.controller.agreement == nil)
    #expect(keyed.connects.first?.credential == .adminKey("plain-key"))
}

@MainActor @Test func keyLoginUsesPrefixCredentialAndChecksSite() async throws {
    let harness = LoginHarness()
    let controller = harness.controller!
    controller.method = .adminKey
    controller.key = " sat_x\n"
    controller.keyDidChange()
    #expect(controller.method == .accessToken)
    await controller.submit()
    #expect(await harness.gateway.settingsCalls == 1); #expect(await harness.gateway.logins.isEmpty)
    let connect = try #require(harness.connects.first)
    #expect(connect.credential == .accessToken("sat_x")); #expect(connect.profile.authentication == .accessToken)
    #expect(connect.profile.name == "演示站"); #expect(controller.key.isEmpty)

    let plain = LoginHarness()
    plain.controller.method = .accessToken; plain.controller.key = "plain-key"
    await plain.controller.submit()
    #expect(plain.connects.first?.credential == .adminKey("plain-key")); #expect(plain.controller.method == .adminKey)

    let empty = LoginHarness()
    empty.controller.method = .adminKey; empty.controller.key = "  "
    await empty.controller.submit()
    #expect(empty.controller.notice == "请完整填写登录凭据")
    #expect(await empty.gateway.settingsCalls == 0); #expect(empty.made.isEmpty)
}

@MainActor @Test func keyLoginSkipsTransientSettingsFailuresButStopsOnNonSub2() async throws {
    let limited = loginError(429, "RATE_LIMITED", context: .business, retryAfter: 9)
    let skipping = LoginHarness(gateway: StubLoginGateway(settings: [.failure(limited)]))
    skipping.controller.method = .adminKey; skipping.controller.key = "plain-key"; skipping.controller.name = "我的站"
    await skipping.controller.submit()
    #expect(skipping.connects.first?.profile.name == "我的站"); #expect(skipping.controller.cooldownUntil == nil)

    let unnamed = LoginHarness(gateway: StubLoginGateway(settings: [.failure(URLError(.timedOut))]))
    unnamed.controller.method = .adminKey; unnamed.controller.key = "plain-key"
    await unnamed.controller.submit()
    #expect(unnamed.controller.notice == "请填写站点名称"); #expect(unnamed.connects.isEmpty)

    let gatewayPage = HTTPResponse(statusCode: 404, headers: ["content-type": "text/plain"], data: Data("404 page not found".utf8))
    let notSub2 = LoginHarness(gateway: StubLoginGateway(settings: [.failure(APIError.from(gatewayPage))]))
    notSub2.controller.method = .adminKey; notSub2.controller.key = "plain-key"; notSub2.controller.name = "我的站"
    await notSub2.controller.submit()
    #expect(notSub2.controller.notice == "该地址不是 Sub2 站点，请检查站点地址"); #expect(notSub2.connects.isEmpty)

    let passwordLimited = LoginHarness(gateway: StubLoginGateway(settings: [.failure(limited)]))
    passwordLimited.fillPassword(); passwordLimited.controller.name = "我的站"
    await passwordLimited.controller.submit()
    #expect(passwordLimited.controller.notice == "登录过于频繁，请 9 秒后再试")
    #expect(await passwordLimited.gateway.logins.isEmpty); #expect(passwordLimited.connects.isEmpty)
}

@MainActor @Test func keyLoginErrorsUseTheLoginWording() async throws {
    let harness = LoginHarness()
    harness.connectError = loginError(401, "USER_INACTIVE", context: .business)
    harness.controller.method = .accessToken; harness.controller.key = "sat_owner-disabled"
    await harness.controller.submit()
    #expect(harness.controller.notice == "该账号已被禁用")
    #expect(harness.announced.isEmpty); #expect(harness.controller.key == "sat_owner-disabled")
}

@MainActor @Test func siteNameFallbackAndNonSub2SiteRejection() async throws {
    let named = LoginHarness()
    named.fillPassword()
    await named.controller.submit()
    #expect(named.connects.first?.profile.name == "演示站")

    let nameless = LoginHarness(gateway: StubLoginGateway(settings: [.success(settings(#"{"version":"1","site_name":""}"#))]))
    nameless.fillPassword()
    await nameless.controller.submit()
    #expect(nameless.controller.notice == "请填写站点名称")
    #expect(await nameless.gateway.logins.isEmpty); #expect(nameless.connects.isEmpty)

    let foreign = LoginHarness(gateway: StubLoginGateway(settings: [.success(settings(#"{"site_name":"别的服务"}"#))]))
    foreign.fillPassword()
    await foreign.controller.submit()
    #expect(foreign.controller.notice == "该地址不是 Sub2 站点，请检查站点地址"); #expect(await foreign.gateway.logins.isEmpty)

    let invalid = LoginHarness()
    invalid.controller.address = "http://sub2.example.invalid"
    invalid.fillPassword()
    await invalid.controller.submit()
    #expect(invalid.controller.notice?.contains("HTTPS") == true); #expect(invalid.made.isEmpty)
    let blank = LoginHarness()
    await blank.controller.submit()
    #expect(blank.controller.notice == "请完整填写登录凭据")
}

@MainActor @Test func addressChangeResetsChallengeProofAndDraftDeviceID() async throws {
    let gateway = StubLoginGateway(settings: [.success(captchaSettings("turnstile"))])
    let harness = LoginHarness(gateway: gateway)
    let controller = harness.controller!
    harness.fillPassword()
    await controller.submit()
    controller.captchaCompleted(.proof(CaptchaProof(provider: "turnstile", turnstileToken: "t-proof")))
    #expect(controller.hasProof)
    controller.address = "https://other.example.invalid"
    controller.addressDidChange()
    #expect(!controller.hasProof); #expect(controller.challenge == nil); #expect(controller.site == nil)
    await controller.captchaDismissed()
    #expect(await gateway.logins.isEmpty)
    await controller.submit()
    #expect(harness.made.count == 2); #expect(harness.made[0].deviceID != harness.made[1].deviceID)
    #expect(harness.made[1].profile.baseURL.absoluteString == "https://other.example.invalid")

    let prefetch = LoginHarness()
    prefetch.controller.address = "not a url"
    await prefetch.controller.prefetchSite(after: .zero)
    #expect(await prefetch.gateway.settingsCalls == 0); #expect(prefetch.controller.site == nil)
    prefetch.controller.address = "https://sub2.example.invalid"
    await prefetch.controller.prefetchSite(after: .zero)
    #expect(prefetch.controller.site?.siteName == "演示站"); #expect(prefetch.controller.namePlaceholder == "演示站")
}

@MainActor @Test func prefetchResultForAnOldAddressIsDropped() async throws {
    let gate = SessionGate()
    let gateway = GatedSettingsGateway(gate: gate)
    let environment = LoginEnvironment(deviceName: "测试 iPhone", makeGateway: { _, _ in gateway }, storedDeviceID: { _ in UUID() },
                                       connect: { _, _, _ in nil }, cancelConnection: {}, didConnect: { _ in })
    let controller = LoginController(prompt: nil, environment: environment)
    controller.address = "https://first.example.invalid"
    let task = Task { await controller.prefetchSite(after: .zero) }
    while !(await gate.arrived) { await Task.yield() }
    controller.address = "https://second.example.invalid"
    controller.addressDidChange()
    await gate.open()
    await task.value
    #expect(controller.site == nil)
}

private actor GatedSettingsGateway: LoginGateway {
    let gate: SessionGate
    init(gate: SessionGate) { self.gate = gate }
    func publicSettings() async throws -> PublicSettings {
        await gate.wait()
        return try JSONDecoder().decode(PublicSettings.self, from: Data(#"{"version":"1","backend_mode_enabled":true}"#.utf8))
    }
    func login(email: String, password: String, proof: CaptchaProof?, deviceName: String, declaresCaptchaProvider: Bool) async throws -> LoginResult {
        throw CancellationError()
    }
    func completeTOTP(tempToken: String, code: String) async throws -> AuthSession { throw CancellationError() }
    func cancelAll() async {}
}

@MainActor @Test func promptReusesSiteIDAndStoredDeviceID() async throws {
    let site = ServerProfile(name: "站点 A", baseURL: URL(string: "https://a.example.invalid")!, authentication: .accessToken)
    let harness = LoginHarness(prompt: LoginPrompt(profile: site, notice: "登录已失效，请重新登录", reusesSiteID: true))
    let controller = harness.controller!
    #expect(controller.name == "站点 A"); #expect(controller.method == .accessToken); #expect(controller.isReLogin)
    #expect(controller.address == "https://a.example.invalid")
    controller.key = "sat_again"
    await controller.submit()
    let connect = try #require(harness.connects.first)
    #expect(connect.profile.id == site.id); #expect(connect.profile.name == "站点 A")
    #expect(connect.deviceID == harness.storedDeviceID); #expect(harness.made.first?.deviceID == harness.storedDeviceID)

    let pending = LoginHarness(prompt: LoginPrompt(profile: site, notice: nil, reusesSiteID: false))
    pending.controller.key = "sat_again"
    await pending.controller.submit()
    #expect(pending.connects.first?.profile.id != site.id); #expect(pending.connects.first?.deviceID != pending.storedDeviceID)
}

@MainActor @Test func cancelWipesSecretsAndCancelsRequests() async throws {
    let gate = SessionGate()
    let gateway = StubLoginGateway(loginGate: gate)
    let harness = LoginHarness(gateway: gateway)
    let controller = harness.controller!
    harness.fillPassword()
    controller.key = "kept-key"; controller.code = "12"
    let submitting = Task { await controller.submit() }
    while !(await gate.arrived) { await Task.yield() }
    await controller.cancel()
    #expect(controller.password.isEmpty); #expect(controller.key.isEmpty); #expect(controller.code.isEmpty)
    #expect(!controller.hasProof)
    #expect(await gateway.cancels == 1); #expect(harness.cancelledConnections == 1)
    await gate.open()
    await submitting.value
    #expect(harness.connects.isEmpty); #expect(harness.announced.isEmpty); #expect(!controller.isBusy)
}
