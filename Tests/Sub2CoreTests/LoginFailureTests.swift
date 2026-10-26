import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

struct LoginFailureRow: Sendable, CustomTestStringConvertible {
    let status: Int
    let reason: String
    let context: ReasonCatalog.Context
    let stage: LoginStage
    var retryAfter: Int? = nil
    let message: String
    let action: LoginFailure.Action
    var testDescription: String { "\(stage) \(status) \(reason)" }
    var error: APIError {
        APIError.server(status: status, envelope: ErrorEnvelope(reason: reason, retryAfter: retryAfter), context: context, retryAfter: retryAfter)
    }
}

private let passwordRows: [LoginFailureRow] = [
    LoginFailureRow(status: 401, reason: "INVALID_CREDENTIALS", context: .login, stage: .password, message: "邮箱或密码错误", action: .clearPassword),
    LoginFailureRow(status: 400, reason: "TURNSTILE_VERIFICATION_FAILED", context: .login, stage: .password, message: "安全验证未通过，请重新验证", action: .reverify),
    LoginFailureRow(status: 400, reason: "TENCENT_CAPTCHA_VERIFICATION_FAILED", context: .login, stage: .password, message: "安全验证未通过，请重新验证", action: .reverify),
    LoginFailureRow(status: 400, reason: "ALIYUN_CAPTCHA_VERIFICATION_FAILED", context: .login, stage: .password, message: "安全验证未通过，请重新验证", action: .reverify),
    LoginFailureRow(status: 400, reason: "CAPTCHA_PROVIDER_MISMATCH", context: .login, stage: .password, message: "站点验证方式已变更，请重新验证", action: .reloadSettings),
    LoginFailureRow(status: 503, reason: "CAPTCHA_PROVIDER_CONFLICT", context: .login, stage: .password, message: "站点同时开启了多个验证码服务，请在 Web 后台修正", action: .stop),
    LoginFailureRow(status: 403, reason: "BACKEND_MODE_ADMIN_ONLY", context: .login, stage: .password, message: "站点处于后端模式，仅管理员可登录", action: .stop),
    LoginFailureRow(status: 403, reason: "USER_NOT_ACTIVE", context: .login, stage: .password, message: "该账号已被禁用", action: .stop),
    LoginFailureRow(status: 429, reason: "RATE_LIMITED", context: .login, stage: .password, retryAfter: 12, message: "登录过于频繁，请 12 秒后再试", action: .cooldown(seconds: 12))
]

@Test(arguments: passwordRows)
func passwordStageMapsEveryRowOfTheLoginErrorTable(row: LoginFailureRow) throws {
    let failure = try #require(LoginFailure.classify(row.error, stage: row.stage))
    #expect(failure == LoginFailure(message: row.message, action: row.action))
    #expect(failure.message == ReasonCatalog.entry(status: row.status, reason: row.reason, context: .login, retryAfter: row.retryAfter).message)
}

private let twoFactorRows: [LoginFailureRow] = [
    LoginFailureRow(status: 400, reason: "TOTP_INVALID_CODE", context: .twoFactor, stage: .twoFactor, message: "验证码不对，请重新输入", action: .clearCode),
    LoginFailureRow(status: 429, reason: "TOTP_TOO_MANY_ATTEMPTS", context: .twoFactor, stage: .twoFactor, message: "尝试次数过多，请 15 分钟后再试", action: .closeTwoFactor),
    LoginFailureRow(status: 400, reason: "TOTP_LOGIN_SESSION_EXPIRED", context: .twoFactor, stage: .twoFactor, message: "验证超时，请重新登录", action: .restart),
    LoginFailureRow(status: 429, reason: "RATE_LIMITED", context: .twoFactor, stage: .twoFactor, retryAfter: 5, message: "登录过于频繁，请 5 秒后再试", action: .cooldown(seconds: 5))
]

@Test(arguments: twoFactorRows)
func twoFactorStageMapsTOTPRows(row: LoginFailureRow) throws {
    #expect(LoginFailure.classify(row.error, stage: row.stage) == LoginFailure(message: row.message, action: row.action))
}

/// The key methods fail in `admin/me`, which reads them as business errors; the login page shows 00 §1.6 instead.
private let keyRows: [LoginFailureRow] = [
    LoginFailureRow(status: 401, reason: "INVALID_ADMIN_KEY", context: .business, stage: .connect,
                    message: "令牌或 Admin Key 无效（已吊销、已删除，或站点不支持管理访问令牌）", action: .stop),
    LoginFailureRow(status: 401, reason: "ACCESS_TOKEN_EXPIRED", context: .business, stage: .connect, message: "管理访问令牌已过期，请重新签发", action: .stop),
    LoginFailureRow(status: 401, reason: "USER_INACTIVE", context: .business, stage: .connect, message: "该账号已被禁用", action: .stop),
    LoginFailureRow(status: 403, reason: "FORBIDDEN", context: .business, stage: .connect, message: "当前版本仅支持管理员账号", action: .stop),
    LoginFailureRow(status: 403, reason: "BACKEND_MODE_ADMIN_ONLY", context: .business, stage: .connect, message: "站点处于后端模式，仅管理员可登录", action: .stop)
]

@Test(arguments: keyRows)
func keyLoginMapsSection16Copy(row: LoginFailureRow) throws {
    #expect(LoginFailure.classify(row.error, stage: row.stage) == LoginFailure(message: row.message, action: row.action))
}

@Test func nonAdministratorStopsWithTheRoleText() {
    #expect(LoginFailure.classify(APIError.administratorRequired, stage: .connect) == LoginFailure(message: "当前版本仅支持管理员账号", action: .stop))
    #expect(LoginFailure.classify(APIError.administratorRequired, stage: .password)?.action == .stop)
}

private struct LocalFailure: LocalizedError { var errorDescription: String? { "本机出错" } }

@Test func networkServerAndUnknownErrorsNeverEchoServerMessage() throws {
    for stage in [LoginStage.site, .password, .twoFactor, .connect] {
        #expect(LoginFailure.classify(APIError.transport(URLError(.timedOut)), stage: stage) == LoginFailure(message: "无法连接站点", action: .none))
        #expect(LoginFailure.classify(CancellationError(), stage: stage) == nil)
    }
    let html = HTTPResponse(statusCode: 502, headers: ["content-type": "text/html"], data: Data("<html>upstream secret</html>".utf8))
    #expect(LoginFailure.classify(APIError.from(html, context: .login), stage: .password) == LoginFailure(message: "站点暂时不可用", action: .none))
    #expect(LoginFailure.classify(APIError.server(status: 500, reason: nil, context: .login), stage: .password)?.message == "站点暂时不可用")
    #expect(LoginFailure.classify(APIError.server(status: 503, reason: "TURNSTILE_NOT_CONFIGURED", context: .login), stage: .password)
            == LoginFailure(message: "站点暂时不可用", action: .none))
    let leaky = HTTPResponse(statusCode: 400, headers: [:], data: Data(#"{"code":400,"reason":"ODD_REASON","message":"token sk-secret at https://upstream.invalid"}"#.utf8))
    let odd = try #require(LoginFailure.classify(APIError.from(leaky, context: .login), stage: .password))
    #expect(odd == LoginFailure(message: "请求无效（错误码 ODD_REASON）", action: .none))
    #expect(!odd.message.contains("secret"))
    #expect(LoginFailure.classify(LocalFailure(), stage: .password) == LoginFailure(message: "本机出错", action: .none))
}

@Test func siteStageRejectsNonSub2Answers() {
    let notSub2 = LoginFailure(message: "该地址不是 Sub2 站点，请检查站点地址", action: .stop)
    let plain404 = HTTPResponse(statusCode: 404, headers: ["content-type": "text/plain"], data: Data("404 page not found".utf8))
    #expect(LoginFailure.classify(APIError.from(plain404), stage: .site) == notSub2)
    #expect(LoginFailure.classify(APIError.invalidResponse, stage: .site) == notSub2)
    #expect(LoginFailure.notSub2Site == notSub2)
    // Transient failures are not a verdict on the address.
    #expect(LoginFailure.classify(APIError.server(status: 503, reason: nil), stage: .site)?.action == LoginFailure.Action.none)
    #expect(LoginFailure.classify(APIError.transport(URLError(.notConnectedToInternet)), stage: .site)?.action == LoginFailure.Action.none)
}

/// S0-LOW-B: a site or proxy answering a huge Retry-After (here Int.max) gets the same 300-second ceiling as the blocks
/// (BlockRefresh), in the button and in the wording, instead of overflowing the countdown.
@Test(arguments: [301, 86_400, Int.max])
func loginCooldownIsCapped(retryAfter: Int) {
    let row = LoginFailureRow(status: 429, reason: "RATE_LIMITED", context: .login, stage: .password, retryAfter: retryAfter,
                              message: "登录过于频繁，请 300 秒后再试", action: .cooldown(seconds: 300))
    let failure = LoginFailure.classify(row.error, stage: .password)
    #expect(failure?.action == row.action)
    #expect(failure?.message == row.message)
    let exact = LoginFailureRow(status: 429, reason: "RATE_LIMITED", context: .twoFactor, stage: .twoFactor, retryAfter: 300,
                                message: "登录过于频繁，请 300 秒后再试", action: .cooldown(seconds: 300))
    #expect(LoginFailure.classify(exact.error, stage: .twoFactor) == LoginFailure(message: exact.message, action: exact.action))
}
