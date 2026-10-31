import Foundation

/// 00 §3.2 reason table, looked up by the exact (HTTP status, reason) pair, with the 00 §3.3 status fallback.
/// No substring matching; the only suffix rule is the OAuth one that 00 §3.2 spells out.
public enum ReasonCatalog {
    public enum Context: Sendable, Equatable {
        case login, twoFactor, refresh, business
        /// Sign-in, second factor and token refresh: account-state reasons end the session here.
        public var isAuthentication: Bool { self != .business }
        fileprivate var isSigningIn: Bool { self == .login || self == .twoFactor }
    }
    public enum Category: String, Sendable {
        case renewal, sessionExpired, sessionBinding, invalidCredential, stepUp, readOnly, permission, compliance, captcha
        case rateLimited, temporary, idempotency, featureDisabled, invalidParameter, batchLimit, versionConflict, conflict
        case notFound, partialSuccess, statsUnavailable, oauth, push, badRequest, unsupported, server
    }
    public enum Action: String, Sendable {
        case refreshAndResend, clearSession, clearCredential, stepUp, explainStepUpSetup, complianceFlow, captchaFlow
        case twoFactorFlow, waitRetryAfter, retryLater, idempotency, showDisabled, splitBatch, restartFromFirstPage
        case refetch, refreshObject, removeObject, readBack, showUnavailable, hideFeature, noRetry, handledByPage
    }
    public struct Entry: Sendable, Equatable {
        public let category: Category
        public let kind: APIError.Kind
        public let action: Action
        public let message: String
        public init(category: Category, kind: APIError.Kind, action: Action, message: String) {
            self.category = category; self.kind = kind; self.action = action; self.message = message
        }
    }

    /// Only combinations listed in 00 §3.2 (plus the context rules) return a value; nil means unknown.
    public static func lookup(status: Int, reason: String?, context: Context = .business, retryAfter: Int? = nil) -> Entry? {
        let reason = reason.flatMap { $0.isEmpty ? nil : $0 }
        if context == .refresh, let entry = refreshOutcome(status: status, reason: reason) { return entry }
        guard let reason else { return nil }
        if let entry = contextual(status: status, reason: reason, context: context, retryAfter: retryAfter) { return entry }
        return table[Key(status: status, reason: reason)] ?? oauthSuffix(status: status, reason: reason)
    }
    public static func entry(status: Int, reason: String?, context: Context = .business, bodyIsJSON: Bool = true, retryAfter: Int? = nil) -> Entry {
        lookup(status: status, reason: reason, context: context, retryAfter: retryAfter)
            ?? fallback(status: status, reason: reason, bodyIsJSON: bodyIsJSON, retryAfter: retryAfter)
    }
}

private enum Text {
    static let sessionExpired = "登录已失效，请重新登录"
    static let sessionBinding = "网络或设备信息变化导致会话失效，请重新登录"
    static let accountDisabled = "该账号已被禁用"
    static let permission = "当前身份没有执行此操作的权限"
    static let backendMode = "站点处于后端模式，仅管理员可用"
    static let backendModeSignIn = "站点处于后端模式，仅管理员可登录"
    static let compliance = "需要先完成管理员合规确认"
    static let notFound = "对象不存在或已删除"
    static let temporary = "站点暂时不可用"
    static let unconfirmed = "结果未确认：服务器可能已执行。可以核对，或用同一编号重试，不会重复执行"
    static let conflict = "操作与当前状态冲突，已刷新，请确认后重试"
    static func parameter(_ reason: String) -> String { "请求参数有误（错误码 \(reason)）" }
    static func tooFrequent(_ seconds: Int?) -> String { "请求过于频繁，请 \(seconds ?? RetryAfter.rateLimitDefault) 秒后再试" }
}

private extension ReasonCatalog {
    struct Key: Hashable, Sendable { let status: Int; let reason: String }

    /// 00 §1.7.2 plus the rules that keep refresh outcomes in one place: any 401 or 400 ends the session.
    static func refreshOutcome(status: Int, reason: String?) -> Entry? {
        switch (status, reason) {
        case (401, "SESSION_BINDING_MISMATCH"?): Entry(category: .sessionBinding, kind: .sessionBinding, action: .clearSession, message: Text.sessionBinding)
        case (401, _), (400, _): Entry(category: .sessionExpired, kind: .authentication, action: .clearSession, message: Text.sessionExpired)
        default: nil
        }
    }

    /// Combinations whose action or wording depends on the request context or on Retry-After.
    static func contextual(status: Int, reason: String, context: Context, retryAfter: Int?) -> Entry? {
        switch (status, reason) {
        case (401, "USER_INACTIVE") where context == .login:
            Entry(category: .invalidCredential, kind: .authentication, action: .noRetry, message: Text.accountDisabled)
        case (401, "INVALID_ADMIN_KEY") where context == .login:
            Entry(category: .invalidCredential, kind: .authentication, action: .clearCredential, message: "令牌或 Admin Key 无效（已吊销、已删除，或站点不支持管理访问令牌）")
        case (403, "FORBIDDEN") where context == .login:
            Entry(category: .permission, kind: .permission, action: .noRetry, message: "当前版本仅支持管理员账号")
        case (403, "USER_NOT_ACTIVE"):
            context.isAuthentication
                ? Entry(category: .sessionExpired, kind: .authentication, action: .clearSession, message: Text.accountDisabled)
                : Entry(category: .permission, kind: .permission, action: .noRetry, message: Text.permission)
        case (403, "BACKEND_MODE_ADMIN_ONLY"):
            context.isAuthentication
                ? Entry(category: .permission, kind: .permission, action: context == .refresh ? .clearSession : .noRetry, message: Text.backendModeSignIn)
                : Entry(category: .permission, kind: .permission, action: .noRetry, message: Text.backendMode)
        case (403, "WORKSPACE_DISABLED"):
            Entry(category: .permission, kind: .permission, action: context == .refresh ? .noRetry : .clearSession, message: "你的工作区已被停用")
        case (429, "RATE_LIMITED"):
            Entry(category: .rateLimited, kind: .rateLimited, action: .waitRetryAfter, message: context.isSigningIn
                ? "登录过于频繁，请 \(retryAfter ?? RetryAfter.rateLimitDefault) 秒后再试" : Text.tooFrequent(retryAfter))
        case (429, "TOTP_TOO_MANY_ATTEMPTS"):
            Entry(category: .stepUp, kind: .twoFactor, action: .twoFactorFlow, message: context.isSigningIn ? "尝试次数过多，请 15 分钟后再试" : "尝试次数过多，请稍后再试")
        default: nil
        }
    }

    static let oauthSuffixes = [("_OAUTH_SESSION_NOT_FOUND", "授权链接已过期"), ("_OAUTH_INVALID_STATE", "授权码不是这次链接换来的"),
                                ("_OAUTH_CODE_REJECTED", "授权码无效或已被使用")]
    static func oauthSuffix(status: Int, reason: String) -> Entry? {
        guard status == 400, let match = oauthSuffixes.first(where: { reason.hasSuffix($0.0) && reason.count > $0.0.count }) else { return nil }
        return Entry(category: .oauth, kind: .validation, action: .handledByPage, message: match.1)
    }

    /// 00 §3.3 for (status, reason) pairs the table does not know.
    static func fallback(status: Int, reason: String?, bodyIsJSON: Bool, retryAfter: Int?) -> Entry {
        switch status {
        case 401: Entry(category: .sessionExpired, kind: .authentication, action: .clearSession, message: Text.sessionExpired)
        case 403: Entry(category: .permission, kind: .permission, action: .noRetry, message: Text.permission)
        case 404 where !bodyIsJSON: Entry(category: .unsupported, kind: .unsupported, action: .hideFeature, message: "站点版本较旧，暂不支持此功能")
        case 404: Entry(category: .notFound, kind: .notFound, action: .removeObject, message: Text.notFound)
        case 409: Entry(category: .conflict, kind: .conflict, action: .refreshObject, message: "操作冲突，请刷新后重试")
        case 412: Entry(category: .versionConflict, kind: .conflict, action: .refetch, message: "数据已被修改，已刷新")
        case 423: Entry(category: .compliance, kind: .compliance, action: .complianceFlow, message: Text.compliance)
        case 429: Entry(category: .rateLimited, kind: .rateLimited, action: .waitRetryAfter, message: Text.tooFrequent(retryAfter))
        case 400..<500: Entry(category: .badRequest, kind: .response, action: .noRetry, message: "请求无效（错误码 \(displayCode(reason) ?? "HTTP \(status)")）")
        case 500..<600: Entry(category: .temporary, kind: .temporary, action: .retryLater, message: Text.temporary)
        default: Entry(category: .server, kind: .response, action: .noRetry, message: "服务器未能完成请求（HTTP \(status)）")
        }
    }
    /// Only stable code-like reasons are shown; anything else from the server is not echoed.
    static func displayCode(_ reason: String?) -> String? {
        guard let reason, (1...64).contains(reason.utf8.count),
              reason.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 95 }) else { return nil }
        return reason
    }

    static let table: [Key: Entry] = Dictionary(uniqueKeysWithValues: [authenticationRows(), securityRows(), availabilityRows(), requestRows(), objectRows()].flatMap { $0 })

    static func rows(_ status: Int, _ reasons: [String], _ category: Category, _ kind: APIError.Kind, _ action: Action, _ message: String) -> [(Key, Entry)] {
        reasons.map { (Key(status: status, reason: $0), Entry(category: category, kind: kind, action: action, message: message)) }
    }
    static func parameterRows(_ reasons: [String], _ category: Category, _ action: Action) -> [(Key, Entry)] {
        reasons.map { (Key(status: 400, reason: $0), Entry(category: category, kind: .validation, action: action, message: Text.parameter($0))) }
    }

    static func authenticationRows() -> [(Key, Entry)] {
        let groups: [[(Key, Entry)]] = [
            rows(401, ["TOKEN_EXPIRED"], .renewal, .authentication, .refreshAndResend, Text.sessionExpired),
            rows(401, ["INVALID_TOKEN", "TOKEN_REVOKED", "USER_NOT_FOUND", "USER_INACTIVE", "REFRESH_TOKEN_INVALID", "REFRESH_TOKEN_EXPIRED",
                "REFRESH_TOKEN_REUSED", "UNAUTHORIZED", "INVALID_AUTH_HEADER", "EMPTY_TOKEN"], .sessionExpired, .authentication, .clearSession, Text.sessionExpired),
            rows(401, ["SESSION_BINDING_MISMATCH"], .sessionBinding, .sessionBinding, .clearSession, Text.sessionBinding),
            rows(401, ["INVALID_ADMIN_KEY"], .invalidCredential, .authentication, .clearCredential, "令牌或 Admin Key 无效，请重新输入"),
            rows(401, ["ACCESS_TOKEN_EXPIRED"], .invalidCredential, .authentication, .clearCredential, "管理访问令牌已过期，请重新签发"),
            rows(401, ["INVALID_CREDENTIALS"], .invalidCredential, .authentication, .noRetry, "邮箱或密码错误"),
            rows(400, ["TURNSTILE_VERIFICATION_FAILED", "TENCENT_CAPTCHA_VERIFICATION_FAILED", "ALIYUN_CAPTCHA_VERIFICATION_FAILED"],
                .captcha, .captcha, .captchaFlow, "安全验证未通过，请重新验证"),
            rows(400, ["CAPTCHA_PROVIDER_MISMATCH"], .captcha, .captcha, .captchaFlow, "站点验证方式已变更，请重新验证"),
            rows(503, ["CAPTCHA_PROVIDER_CONFLICT"], .captcha, .captcha, .noRetry, "站点同时开启了多个验证码服务，请在 Web 后台修正"),
            rows(400, ["TOTP_INVALID_CODE"], .stepUp, .twoFactor, .twoFactorFlow, "验证码不对，请重新输入"),
            rows(400, ["TOTP_LOGIN_SESSION_EXPIRED"], .stepUp, .twoFactor, .twoFactorFlow, "验证超时，请重新登录")
        ]
        return groups.flatMap { $0 }
    }
    static func securityRows() -> [(Key, Entry)] {
        let groups: [[(Key, Entry)]] = [
            rows(403, ["STEP_UP_REQUIRED"], .stepUp, .stepUp, .stepUp, "该操作需要先完成二次验证"),
            rows(403, ["STEP_UP_TOTP_NOT_ENABLED"], .stepUp, .stepUp, .explainStepUpSetup, "需要先在 Web 端开启二次验证"),
            rows(403, ["STEP_UP_ADMIN_API_KEY_FORBIDDEN"], .stepUp, .stepUp, .noRetry, "该操作需要账号登录（Admin Key 与管理访问令牌不能二次验证）"),
            rows(503, ["STEP_UP_UNAVAILABLE"], .stepUp, .temporary, .retryLater, "二次验证服务暂时不可用"),
            rows(403, ["ACCESS_TOKEN_READ_ONLY"], .readOnly, .readOnly, .noRetry, "当前管理访问令牌只读，不能执行此操作"),
            rows(403, ["FORBIDDEN", "WORKSPACE_PERMISSION_DENIED"], .permission, .permission, .noRetry, Text.permission),
            rows(403, ["BACKEND_MODE_SELF_SERVICE_DISABLED"], .permission, .permission, .noRetry, Text.backendMode),
            rows(423, ["ADMIN_COMPLIANCE_ACK_REQUIRED"], .compliance, .compliance, .complianceFlow, Text.compliance)
        ]
        return groups.flatMap { $0 }
    }
    static func availabilityRows() -> [(Key, Entry)] {
        let groups: [[(Key, Entry)]] = [
            rows(503, ["SERVICE_UNAVAILABLE"], .temporary, .temporary, .retryLater, "站点暂时不可用，请稍后重试"),
            rows(429, ["ACCOUNT_TEST_BUSY"], .rateLimited, .rateLimited, .waitRetryAfter, "站点同时运行的测试已满，请稍后再试"),
            rows(404, ["OPS_DISABLED"], .featureDisabled, .featureDisabled, .showDisabled, "运维监控未开启"),
            rows(409, ["OPS_CONFIG_DISABLED"], .featureDisabled, .featureDisabled, .noRetry, "需要在服务器配置中启用运维监控"),
            rows(403, ["CHANNEL_MONITOR_DISABLED"], .featureDisabled, .featureDisabled, .showDisabled, "渠道监控未开启"),
            rows(503, ["PUSH_NOT_CONFIGURED"], .featureDisabled, .featureDisabled, .showDisabled, "站点未配置 APNs"),
            rows(503, ["ACCOUNT_STATS_UNAVAILABLE"], .statsUnavailable, .temporary, .showUnavailable, Text.temporary),
            rows(409, ["IDEMPOTENCY_IN_PROGRESS", "IDEMPOTENCY_RETRY_BACKOFF"], .idempotency, .idempotency, .idempotency, Text.unconfirmed),
            rows(503, ["IDEMPOTENCY_STORE_UNAVAILABLE"], .idempotency, .idempotency, .idempotency, Text.unconfirmed),
            rows(409, ["IDEMPOTENCY_KEY_CONFLICT"], .idempotency, .idempotency, .idempotency, "请求已变化，请重新提交"),
            rows(400, ["IDEMPOTENCY_KEY_INVALID", "IDEMPOTENCY_PAYLOAD_INVALID", "IDEMPOTENCY_KEY_REQUIRED"], .idempotency, .idempotency, .idempotency, "请求无效，请重试")
        ]
        return groups.flatMap { $0 }
    }
    static func requestRows() -> [(Key, Entry)] {
        let groups: [[(Key, Entry)]] = [
            parameterRows(["INVALID_SORT_BY", "OPS_TIME_RANGE_TOO_LARGE", "INVALID_MAX_POINTS", "INVALID_REQUEST_ID", "INVALID_AROUND", "INVALID_TIMEZONE",
                "INVALID_INCLUDE", "INVALID_GROUP_FILTER", "INVALID_GROUP_ID", "INVALID_ACCOUNT_STATUS_FILTER", "INVALID_READ_STATUS_FILTER",
                "INVALID_USER_ID", "INVALID_PLATFORM", "INVALID_QUOTA_LIMIT", "VALIDATION_ERROR", "INVALID_IF_MATCH", "INVALID_PATCH",
                "USER_BALANCE_NOT_EDITABLE", "REDEEM_CODE_TYPE_INVALID", "REDEEM_BATCH_ID_INVALID"], .invalidParameter, .noRetry),
            parameterRows(["INVALID_SINCE_ID", "SINCE_ID_WITH_PAGE"], .invalidParameter, .restartFromFirstPage),
            parameterRows(["TOO_MANY_IDS"], .batchLimit, .splitBatch),
            parameterRows(["INVALID_PUSH_TOKEN", "INVALID_PUSH_TARGET", "INVALID_PUSH_SUBSCRIPTION", "INVALID_APNS_CONFIG",
                "SECRET_ENCRYPTION_KEY_NOT_CONFIGURED"], .push, .handledByPage),
            rows(412, ["ACCOUNT_VERSION_CONFLICT"], .versionConflict, .conflict, .refetch, "账号已被他人修改，已刷新，请重新编辑"),
            rows(409, ["MIXED_CHANNEL_WARNING", "ACCOUNT_TEST_RUNNING", "REDEEM_CODE_USED", "REDEEM_BATCH_CONFLICT", "REDEEM_CODE_CONFLICT",
                "USER_PLATFORM_QUOTA_ACTIVE_EXISTS", "GROUP_EXISTS", "EMAIL_EXISTS", "PUSH_TARGET_IN_USE", "OPS_REQUEST_AMBIGUOUS"],
                .conflict, .conflict, .refreshObject, Text.conflict),
            rows(409, ["PUSH_DEVICE_LIMIT_REACHED"], .conflict, .conflict, .noRetry, "推送设备已达上限，请在 Web 删除不用的设备"),
            rows(502, ["PUSH_DELIVERY_FAILED"], .push, .response, .handledByPage, "推送服务拒绝了这台设备，请重新开启推送")
        ]
        return groups.flatMap { $0 }
    }
    static func objectRows() -> [(Key, Entry)] {
        let groups: [[(Key, Entry)]] = [
            rows(404, ["USER_NOT_FOUND", "ACCOUNT_NOT_FOUND", "GROUP_NOT_FOUND", "RESOURCE_NOT_FOUND", "PROXY_NOT_FOUND", "ANNOUNCEMENT_NOT_FOUND",
                "REDEEM_CODE_NOT_FOUND", "USER_PLATFORM_QUOTA_NOT_FOUND", "ACCOUNT_TEST_RUN_NOT_FOUND", "PUSH_DEVICE_NOT_FOUND",
                "SESSION_NOT_FOUND", "ACCESS_TOKEN_NOT_FOUND", "OPS_REQUEST_NOT_FOUND"], .notFound, .notFound, .removeObject, Text.notFound),
            rows(404, ["OPS_ERROR_NOT_FOUND"], .notFound, .notFound, .removeObject, "记录已不存在"),
            rows(500, ["ACCOUNT_RECOVERED_SCHEDULABLE_FAILED"], .partialSuccess, .response, .readBack, "已恢复 · 仍暂停调度"),
            rows(500, ["REAUTH_PERSIST_FAILED"], .partialSuccess, .response, .readBack, "令牌已换到，但没保存成功"),
            rows(400, ["NOT_OAUTH", "REAUTH_UNSUPPORTED"], .oauth, .validation, .handledByPage, "这个账号不能在手机上重新授权"),
            rows(403, ["GROK_OAUTH_ENTITLEMENT_DENIED"], .oauth, .permission, .handledByPage, "这个 xAI 账号没有授权"),
            rows(502, ["OAUTH_EXCHANGE_FAILED"], .oauth, .temporary, .retryLater, Text.temporary)
        ]
        return groups.flatMap { $0 }
    }
}
