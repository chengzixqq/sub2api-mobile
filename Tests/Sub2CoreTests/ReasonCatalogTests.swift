import Foundation
import Testing
@testable import Sub2Core

struct ReasonCatalogCase: Sendable, CustomTestStringConvertible {
    let status: Int
    let reasons: [String]
    let category: ReasonCatalog.Category
    let kind: APIError.Kind
    let action: ReasonCatalog.Action
    let message: String?
    var testDescription: String { "\(status) \(reasons.joined(separator: ","))" }
    init(_ status: Int, _ reasons: [String], _ category: ReasonCatalog.Category, _ kind: APIError.Kind, _ action: ReasonCatalog.Action, _ message: String? = nil) {
        self.status = status; self.reasons = reasons; self.category = category; self.kind = kind; self.action = action; self.message = message
    }
}

private let sessionLost = "登录已失效，请重新登录"
private let unconfirmed = "结果未确认：服务器可能已执行。可以核对，或用同一编号重试，不会重复执行"

/// 00 §3.2 business-context rows; message nil means “请求参数有误（错误码 <reason>）”.
private let businessRows: [ReasonCatalogCase] = [
    ReasonCatalogCase(401, ["TOKEN_EXPIRED"], .renewal, .authentication, .refreshAndResend, sessionLost),
    ReasonCatalogCase(401, ["INVALID_TOKEN", "TOKEN_REVOKED", "USER_NOT_FOUND", "USER_INACTIVE", "REFRESH_TOKEN_INVALID", "REFRESH_TOKEN_EXPIRED",
                      "REFRESH_TOKEN_REUSED", "UNAUTHORIZED", "INVALID_AUTH_HEADER", "EMPTY_TOKEN"], .sessionExpired, .authentication, .clearSession, sessionLost),
    ReasonCatalogCase(401, ["SESSION_BINDING_MISMATCH"], .sessionBinding, .sessionBinding, .clearSession, "网络或设备信息变化导致会话失效，请重新登录"),
    ReasonCatalogCase(401, ["INVALID_ADMIN_KEY"], .invalidCredential, .authentication, .clearCredential, "令牌或 Admin Key 无效，请重新输入"),
    ReasonCatalogCase(401, ["ACCESS_TOKEN_EXPIRED"], .invalidCredential, .authentication, .clearCredential, "管理访问令牌已过期，请重新签发"),
    ReasonCatalogCase(401, ["INVALID_CREDENTIALS"], .invalidCredential, .authentication, .noRetry, "邮箱或密码错误"),
    ReasonCatalogCase(403, ["STEP_UP_REQUIRED"], .stepUp, .stepUp, .stepUp, "该操作需要先完成二次验证"),
    ReasonCatalogCase(403, ["STEP_UP_TOTP_NOT_ENABLED"], .stepUp, .stepUp, .explainStepUpSetup, "需要先在 Web 端开启二次验证"),
    ReasonCatalogCase(403, ["STEP_UP_ADMIN_API_KEY_FORBIDDEN"], .stepUp, .stepUp, .noRetry, "该操作需要账号登录（Admin Key 与管理访问令牌不能二次验证）"),
    ReasonCatalogCase(503, ["STEP_UP_UNAVAILABLE"], .stepUp, .temporary, .retryLater, "二次验证服务暂时不可用"),
    ReasonCatalogCase(400, ["TOTP_INVALID_CODE"], .stepUp, .twoFactor, .twoFactorFlow, "验证码不对，请重新输入"),
    ReasonCatalogCase(400, ["TOTP_LOGIN_SESSION_EXPIRED"], .stepUp, .twoFactor, .twoFactorFlow, "验证超时，请重新登录"),
    ReasonCatalogCase(429, ["TOTP_TOO_MANY_ATTEMPTS"], .stepUp, .twoFactor, .twoFactorFlow, "尝试次数过多，请稍后再试"),
    ReasonCatalogCase(403, ["ACCESS_TOKEN_READ_ONLY"], .readOnly, .readOnly, .noRetry, "当前管理访问令牌只读，不能执行此操作"),
    ReasonCatalogCase(403, ["FORBIDDEN", "WORKSPACE_PERMISSION_DENIED", "USER_NOT_ACTIVE"], .permission, .permission, .noRetry, "当前身份没有执行此操作的权限"),
    ReasonCatalogCase(403, ["WORKSPACE_DISABLED"], .permission, .permission, .clearSession, "你的工作区已被停用"),
    ReasonCatalogCase(403, ["BACKEND_MODE_ADMIN_ONLY", "BACKEND_MODE_SELF_SERVICE_DISABLED"], .permission, .permission, .noRetry, "站点处于后端模式，仅管理员可用"),
    ReasonCatalogCase(423, ["ADMIN_COMPLIANCE_ACK_REQUIRED"], .compliance, .compliance, .complianceFlow, "需要先完成管理员合规确认"),
    ReasonCatalogCase(400, ["TURNSTILE_VERIFICATION_FAILED", "TENCENT_CAPTCHA_VERIFICATION_FAILED", "ALIYUN_CAPTCHA_VERIFICATION_FAILED"], .captcha, .captcha, .captchaFlow, "安全验证未通过，请重新验证"),
    ReasonCatalogCase(400, ["CAPTCHA_PROVIDER_MISMATCH"], .captcha, .captcha, .captchaFlow, "站点验证方式已变更，请重新验证"),
    ReasonCatalogCase(503, ["CAPTCHA_PROVIDER_CONFLICT"], .captcha, .captcha, .noRetry, "站点同时开启了多个验证码服务，请在 Web 后台修正"),
    ReasonCatalogCase(429, ["RATE_LIMITED"], .rateLimited, .rateLimited, .waitRetryAfter, "请求过于频繁，请 30 秒后再试"),
    ReasonCatalogCase(429, ["ACCOUNT_TEST_BUSY"], .rateLimited, .rateLimited, .waitRetryAfter, "站点同时运行的测试已满，请稍后再试"),
    ReasonCatalogCase(503, ["SERVICE_UNAVAILABLE"], .temporary, .temporary, .retryLater, "站点暂时不可用，请稍后重试"),
    ReasonCatalogCase(409, ["IDEMPOTENCY_IN_PROGRESS", "IDEMPOTENCY_RETRY_BACKOFF"], .idempotency, .idempotency, .idempotency, unconfirmed),
    ReasonCatalogCase(503, ["IDEMPOTENCY_STORE_UNAVAILABLE"], .idempotency, .idempotency, .idempotency, unconfirmed),
    ReasonCatalogCase(409, ["IDEMPOTENCY_KEY_CONFLICT"], .idempotency, .idempotency, .idempotency, "请求已变化，请重新提交"),
    ReasonCatalogCase(400, ["IDEMPOTENCY_KEY_INVALID", "IDEMPOTENCY_PAYLOAD_INVALID", "IDEMPOTENCY_KEY_REQUIRED"], .idempotency, .idempotency, .idempotency, "请求无效，请重试"),
    ReasonCatalogCase(404, ["OPS_DISABLED"], .featureDisabled, .featureDisabled, .showDisabled, "运维监控未开启"),
    ReasonCatalogCase(409, ["OPS_CONFIG_DISABLED"], .featureDisabled, .featureDisabled, .noRetry, "需要在服务器配置中启用运维监控"),
    ReasonCatalogCase(503, ["PUSH_NOT_CONFIGURED"], .featureDisabled, .featureDisabled, .showDisabled, "站点未配置 APNs"),
    ReasonCatalogCase(400, ["INVALID_SORT_BY", "OPS_TIME_RANGE_TOO_LARGE", "INVALID_MAX_POINTS", "INVALID_REQUEST_ID", "INVALID_AROUND", "INVALID_TIMEZONE",
                      "INVALID_INCLUDE", "INVALID_GROUP_FILTER", "INVALID_GROUP_ID", "INVALID_ACCOUNT_STATUS_FILTER", "INVALID_READ_STATUS_FILTER",
                      "INVALID_USER_ID", "INVALID_PLATFORM", "INVALID_QUOTA_LIMIT", "VALIDATION_ERROR", "INVALID_IF_MATCH", "INVALID_PATCH",
                      "USER_BALANCE_NOT_EDITABLE", "REDEEM_CODE_TYPE_INVALID", "REDEEM_BATCH_ID_INVALID"], .invalidParameter, .validation, .noRetry),
    ReasonCatalogCase(400, ["INVALID_SINCE_ID", "SINCE_ID_WITH_PAGE"], .invalidParameter, .validation, .restartFromFirstPage),
    ReasonCatalogCase(400, ["TOO_MANY_IDS"], .batchLimit, .validation, .splitBatch),
    ReasonCatalogCase(412, ["ACCOUNT_VERSION_CONFLICT"], .versionConflict, .conflict, .refetch, "账号已被他人修改，已刷新，请重新编辑"),
    ReasonCatalogCase(409, ["MIXED_CHANNEL_WARNING", "ACCOUNT_TEST_RUNNING", "REDEEM_CODE_USED", "REDEEM_BATCH_CONFLICT", "REDEEM_CODE_CONFLICT",
                      "USER_PLATFORM_QUOTA_ACTIVE_EXISTS", "GROUP_EXISTS", "EMAIL_EXISTS", "PUSH_TARGET_IN_USE", "OPS_REQUEST_AMBIGUOUS"],
                .conflict, .conflict, .refreshObject, "操作与当前状态冲突，已刷新，请确认后重试"),
    ReasonCatalogCase(409, ["PUSH_DEVICE_LIMIT_REACHED"], .conflict, .conflict, .noRetry, "推送设备已达上限，请在 Web 删除不用的设备"),
    ReasonCatalogCase(404, ["USER_NOT_FOUND", "ACCOUNT_NOT_FOUND", "GROUP_NOT_FOUND", "RESOURCE_NOT_FOUND", "PROXY_NOT_FOUND", "ANNOUNCEMENT_NOT_FOUND",
                      "REDEEM_CODE_NOT_FOUND", "USER_PLATFORM_QUOTA_NOT_FOUND", "ACCOUNT_TEST_RUN_NOT_FOUND", "PUSH_DEVICE_NOT_FOUND",
                      "SESSION_NOT_FOUND", "ACCESS_TOKEN_NOT_FOUND", "OPS_REQUEST_NOT_FOUND"], .notFound, .notFound, .removeObject, "对象不存在或已删除"),
    ReasonCatalogCase(500, ["ACCOUNT_RECOVERED_SCHEDULABLE_FAILED"], .partialSuccess, .response, .readBack, "已恢复 · 仍暂停调度"),
    ReasonCatalogCase(500, ["REAUTH_PERSIST_FAILED"], .partialSuccess, .response, .readBack, "令牌已换到，但没保存成功"),
    ReasonCatalogCase(503, ["ACCOUNT_STATS_UNAVAILABLE"], .statsUnavailable, .temporary, .showUnavailable, "站点暂时不可用"),
    ReasonCatalogCase(400, ["NOT_OAUTH", "REAUTH_UNSUPPORTED"], .oauth, .validation, .handledByPage, "这个账号不能在手机上重新授权"),
    ReasonCatalogCase(403, ["GROK_OAUTH_ENTITLEMENT_DENIED"], .oauth, .permission, .handledByPage, "这个 xAI 账号没有授权"),
    ReasonCatalogCase(502, ["OAUTH_EXCHANGE_FAILED"], .oauth, .temporary, .retryLater, "站点暂时不可用"),
    ReasonCatalogCase(400, ["INVALID_PUSH_TOKEN", "INVALID_PUSH_TARGET", "INVALID_PUSH_SUBSCRIPTION", "INVALID_APNS_CONFIG", "SECRET_ENCRYPTION_KEY_NOT_CONFIGURED"],
                .push, .validation, .handledByPage),
    ReasonCatalogCase(502, ["PUSH_DELIVERY_FAILED"], .push, .response, .handledByPage, "推送服务拒绝了这台设备，请重新开启推送")
]

@Test(arguments: businessRows)
func catalogRowsMatchSpec(_ row: ReasonCatalogCase) throws {
    for reason in row.reasons {
        let entry = try #require(ReasonCatalog.lookup(status: row.status, reason: reason), "\(row.status) \(reason)")
        #expect(entry.category == row.category, "\(reason)")
        #expect(entry.kind == row.kind, "\(reason)")
        #expect(entry.action == row.action, "\(reason)")
        #expect(entry.message == (row.message ?? "请求参数有误（错误码 \(reason)）"), "\(reason)")
        #expect(!entry.message.hasSuffix("。"), "\(reason)")
    }
}

@Test func userNotFoundDependsOnStatus() throws {
    let session = try #require(ReasonCatalog.lookup(status: 401, reason: "USER_NOT_FOUND"))
    #expect(session.category == .sessionExpired); #expect(session.kind == .authentication); #expect(session.action == .clearSession)
    let object = try #require(ReasonCatalog.lookup(status: 404, reason: "USER_NOT_FOUND"))
    #expect(object.category == .notFound); #expect(object.kind == .notFound); #expect(object.action == .removeObject)
    #expect(object.message == "对象不存在或已删除")
}

@Test(arguments: [ReasonCatalog.Context.login, .twoFactor, .refresh])
func userNotActiveClearsSessionWhileAuthenticating(_ context: ReasonCatalog.Context) throws {
    let entry = try #require(ReasonCatalog.lookup(status: 403, reason: "USER_NOT_ACTIVE", context: context))
    #expect(entry.kind == .authentication); #expect(entry.action == .clearSession); #expect(entry.message == "该账号已被禁用")
    #expect(context.isAuthentication)
    #expect(!ReasonCatalog.Context.business.isAuthentication)
}

@Test func contextualTextsForLoginAndBusiness() {
    #expect(ReasonCatalog.entry(status: 429, reason: "RATE_LIMITED", context: .login, retryAfter: 12).message == "登录过于频繁，请 12 秒后再试")
    #expect(ReasonCatalog.entry(status: 429, reason: "RATE_LIMITED", context: .twoFactor, retryAfter: 12).message == "登录过于频繁，请 12 秒后再试")
    #expect(ReasonCatalog.entry(status: 429, reason: "RATE_LIMITED", retryAfter: 12).message == "请求过于频繁，请 12 秒后再试")
    #expect(ReasonCatalog.entry(status: 429, reason: "RATE_LIMITED", context: .login).message == "登录过于频繁，请 30 秒后再试")
    #expect(ReasonCatalog.entry(status: 429, reason: "TOTP_TOO_MANY_ATTEMPTS", context: .twoFactor).message == "尝试次数过多，请 15 分钟后再试")
    #expect(ReasonCatalog.entry(status: 401, reason: "INVALID_ADMIN_KEY", context: .login).message == "令牌或 Admin Key 无效（已吊销、已删除，或站点不支持管理访问令牌）")
    let backendLogin = ReasonCatalog.entry(status: 403, reason: "BACKEND_MODE_ADMIN_ONLY", context: .login)
    #expect(backendLogin.action == .noRetry); #expect(backendLogin.message == "站点处于后端模式，仅管理员可登录")
    let inactiveOwner = ReasonCatalog.entry(status: 401, reason: "USER_INACTIVE", context: .login)
    #expect(inactiveOwner.message == "该账号已被禁用"); #expect(inactiveOwner.action == .noRetry)
    let vendor = ReasonCatalog.entry(status: 403, reason: "FORBIDDEN", context: .login)
    #expect(vendor.message == "当前版本仅支持管理员账号"); #expect(vendor.action == .noRetry)
}

@Test func refreshContextEndsSessionOnlyForSessionOutcomes() {
    for reason in ["REFRESH_TOKEN_INVALID", "REFRESH_TOKEN_EXPIRED", "REFRESH_TOKEN_REUSED", "TOKEN_REVOKED", "INVALID_TOKEN", "TOKEN_EXPIRED", "NEW_REASON", ""] {
        let entry = ReasonCatalog.entry(status: 401, reason: reason, context: .refresh)
        #expect(entry.category == .sessionExpired, "\(reason)"); #expect(entry.action == .clearSession, "\(reason)")
        #expect(entry.message == sessionLost, "\(reason)")
    }
    #expect(ReasonCatalog.entry(status: 401, reason: nil, context: .refresh).action == .clearSession)
    let missingBody = ReasonCatalog.entry(status: 400, reason: nil, context: .refresh)
    #expect(missingBody.category == .sessionExpired); #expect(missingBody.action == .clearSession)
    let binding = ReasonCatalog.entry(status: 401, reason: "SESSION_BINDING_MISMATCH", context: .refresh)
    #expect(binding.category == .sessionBinding); #expect(binding.action == .clearSession)
    #expect(binding.message == "网络或设备信息变化导致会话失效，请重新登录")
    let disabled = ReasonCatalog.entry(status: 403, reason: "USER_NOT_ACTIVE", context: .refresh)
    #expect(disabled.action == .clearSession); #expect(disabled.message == "该账号已被禁用")
    let backend = ReasonCatalog.entry(status: 403, reason: "BACKEND_MODE_ADMIN_ONLY", context: .refresh)
    #expect(backend.action == .clearSession); #expect(backend.message == "站点处于后端模式，仅管理员可登录")
    let kept: [(Int, String?)] = [(403, "FORBIDDEN"), (403, "WORKSPACE_DISABLED"), (403, nil), (404, nil), (408, nil), (429, "RATE_LIMITED"),
                                  (500, nil), (502, nil), (503, "SERVICE_UNAVAILABLE"), (504, nil)]
    for (status, reason) in kept {
        let entry = ReasonCatalog.entry(status: status, reason: reason, context: .refresh)
        #expect(entry.action != .clearSession, "\(status) \(reason ?? "-")"); #expect(entry.action != .clearCredential, "\(status)")
    }
}

@Test func businessSessionActions() {
    #expect(ReasonCatalog.entry(status: 401, reason: nil).action == .clearSession)
    #expect(ReasonCatalog.entry(status: 401, reason: "SOMETHING_NEW").action == .clearSession)
    #expect(ReasonCatalog.entry(status: 401, reason: "INVALID_ADMIN_KEY").action == .clearCredential)
    #expect(ReasonCatalog.entry(status: 401, reason: "ACCESS_TOKEN_EXPIRED").action == .clearCredential)
    #expect(ReasonCatalog.entry(status: 403, reason: "WORKSPACE_DISABLED").action == .clearSession)
}

@Test func unknownCombinationsFallBackByHTTPStatus() {
    func check(_ status: Int, _ reason: String?, json: Bool = true, _ category: ReasonCatalog.Category, _ kind: APIError.Kind, _ action: ReasonCatalog.Action, _ message: String) {
        let entry = ReasonCatalog.entry(status: status, reason: reason, bodyIsJSON: json)
        #expect(entry == ReasonCatalog.Entry(category: category, kind: kind, action: action, message: message), "\(status) \(reason ?? "-")")
    }
    check(400, "X_NEW", .badRequest, .response, .noRetry, "请求无效（错误码 X_NEW）")
    check(400, nil, .badRequest, .response, .noRetry, "请求无效（错误码 HTTP 400）")
    check(422, nil, .badRequest, .response, .noRetry, "请求无效（错误码 HTTP 422）")
    check(400, "<b>bad</b>", .badRequest, .response, .noRetry, "请求无效（错误码 HTTP 400）")
    check(401, nil, .sessionExpired, .authentication, .clearSession, sessionLost)
    check(403, nil, .permission, .permission, .noRetry, "当前身份没有执行此操作的权限")
    check(404, nil, json: false, .unsupported, .unsupported, .hideFeature, "站点版本较旧，暂不支持此功能")
    check(404, nil, .notFound, .notFound, .removeObject, "对象不存在或已删除")
    check(409, "X_NEW", .conflict, .conflict, .refreshObject, "操作冲突，请刷新后重试")
    check(412, nil, .versionConflict, .conflict, .refetch, "数据已被修改，已刷新")
    check(423, "ANYTHING", .compliance, .compliance, .complianceFlow, "需要先完成管理员合规确认")
    check(429, nil, .rateLimited, .rateLimited, .waitRetryAfter, "请求过于频繁，请 30 秒后再试")
    for status in [500, 502, 503, 504] { check(status, nil, .temporary, .temporary, .retryLater, "站点暂时不可用") }
    check(302, nil, .server, .response, .noRetry, "服务器未能完成请求（HTTP 302）")
    #expect(ReasonCatalog.entry(status: 429, reason: "NEW", retryAfter: 9).message == "请求过于频繁，请 9 秒后再试")
}

@Test func knownReasonUnderOtherStatusUsesFallback() {
    #expect(ReasonCatalog.lookup(status: 500, reason: "TOKEN_EXPIRED") == nil)
    #expect(ReasonCatalog.lookup(status: 403, reason: "INVALID_TOKEN") == nil)
    #expect(ReasonCatalog.lookup(status: 401, reason: "STEP_UP_REQUIRED") == nil)
    #expect(ReasonCatalog.entry(status: 500, reason: "TOKEN_EXPIRED").kind == .temporary)
    #expect(ReasonCatalog.entry(status: 403, reason: "INVALID_TOKEN").category == .permission)
    #expect(ReasonCatalog.entry(status: 401, reason: "STEP_UP_REQUIRED").category == .sessionExpired)
}

@Test func noSubstringMatching() {
    #expect(ReasonCatalog.entry(status: 423, reason: "TOTP_STEP_UP_REQUIRED").kind == .compliance)
    #expect(ReasonCatalog.entry(status: 403, reason: "TOTP_STEP_UP_REQUIRED").kind == .permission)
    #expect(ReasonCatalog.entry(status: 400, reason: "CAPTCHA_REQUIRED").category == .badRequest)
    #expect(ReasonCatalog.entry(status: 403, reason: "LOGIN_AGREEMENT_REQUIRED").kind == .permission)
    #expect(ReasonCatalog.entry(status: 401, reason: "SESSION_BINDING_EXPIRED").category == .sessionExpired)
    #expect(ReasonCatalog.entry(status: 403, reason: "step_up_required").action == .noRetry)
}

@Test func oauthReasonsAreRecognisedBySuffixOnlyOn400() {
    #expect(ReasonCatalog.entry(status: 400, reason: "GEMINI_OAUTH_SESSION_NOT_FOUND") == ReasonCatalog.Entry(category: .oauth, kind: .validation, action: .handledByPage, message: "授权链接已过期"))
    #expect(ReasonCatalog.entry(status: 400, reason: "GROK_OAUTH_INVALID_STATE").message == "授权码不是这次链接换来的")
    #expect(ReasonCatalog.entry(status: 400, reason: "CLAUDE_OAUTH_CODE_REJECTED").message == "授权码无效或已被使用")
    #expect(ReasonCatalog.entry(status: 500, reason: "CLAUDE_OAUTH_SESSION_NOT_FOUND").kind == .temporary)
    #expect(ReasonCatalog.entry(status: 400, reason: "OAUTH_SESSION_NOT_FOUND_X").category == .badRequest)
    #expect(ReasonCatalog.entry(status: 400, reason: "_OAUTH_CODE_REJECTED").category == .badRequest)
    #expect(ReasonCatalog.entry(status: 403, reason: "GROK_OAUTH_ENTITLEMENT_DENIED").message == "这个 xAI 账号没有授权")
}

@Test func lookupDistinguishesKnownFromUnknown() {
    #expect(ReasonCatalog.lookup(status: 401, reason: "TOKEN_EXPIRED") != nil)
    #expect(ReasonCatalog.lookup(status: 401, reason: "NEW_REASON") == nil)
    #expect(ReasonCatalog.lookup(status: 401, reason: nil) == nil)
    #expect(ReasonCatalog.lookup(status: 401, reason: "") == nil)
    #expect(ReasonCatalog.lookup(status: 404, reason: "OPS_DISABLED") != nil)
    for status in [100, 204, 304, 400, 418, 451, 500, 599, 700] { #expect(!ReasonCatalog.entry(status: status, reason: nil).message.isEmpty) }
}
