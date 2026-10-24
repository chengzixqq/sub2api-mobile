import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where a login failed: `settings/public`, `auth/login`, `auth/login/2fa`, or `admin/me` while connecting.
public enum LoginStage: Sendable { case site, password, twoFactor, connect }

/// What the login page does with an error (00 §1.4 table, §1.6 step 2). Only the action is decided here; the text is
/// ReasonCatalog's in the sign-in context, so `admin/me`'s business wording never reaches the login page (D32).
public struct LoginFailure: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case none, clearPassword, reverify, reloadSettings, stop, clearCode, closeTwoFactor, restart, cooldown(seconds: Int)
    }
    public let message: String
    public let action: Action
    public init(message: String, action: Action) { self.message = message; self.action = action }

    public static let notSub2Site = LoginFailure(message: LoginCopy.notSub2Site, action: .stop)

    /// nil for a cancelled attempt, which shows nothing.
    public static func classify(_ error: any Error, stage: LoginStage) -> LoginFailure? {
        if error is CancellationError { return nil }
        if error is URLError { return LoginFailure(message: LoginCopy.unreachable, action: .none) }
        guard let error = error as? APIError else { return LoginFailure(message: error.localizedDescription, action: .none) }
        if error.kind == .transport { return LoginFailure(message: LoginCopy.unreachable, action: .none) }
        if stage == .site && (error.kind == .unsupported || error == .invalidResponse) { return notSub2Site }
        if error == .administratorRequired { return LoginFailure(message: error.localizedDescription, action: .stop) }
        guard let status = error.statusCode, error.category != nil else { return LoginFailure(message: error.localizedDescription, action: .none) }
        let context: ReasonCatalog.Context = stage == .twoFactor ? .twoFactor : .login
        let message = ReasonCatalog.lookup(status: status, reason: error.reason, context: context, retryAfter: error.retryAfter)?.message
            ?? error.localizedDescription
        return LoginFailure(message: message, action: action(status: status, reason: error.reason, retryAfter: error.retryAfter))
    }

    private static func action(status: Int, reason: String?, retryAfter: Int?) -> Action {
        switch (status, reason) {
        case (401, "INVALID_CREDENTIALS"?): .clearPassword
        case (400, "TURNSTILE_VERIFICATION_FAILED"?), (400, "TENCENT_CAPTCHA_VERIFICATION_FAILED"?), (400, "ALIYUN_CAPTCHA_VERIFICATION_FAILED"?):
            .reverify
        case (400, "CAPTCHA_PROVIDER_MISMATCH"?): .reloadSettings
        case (400, "TOTP_INVALID_CODE"?): .clearCode
        case (429, "TOTP_TOO_MANY_ATTEMPTS"?): .closeTwoFactor
        case (400, "TOTP_LOGIN_SESSION_EXPIRED"?): .restart
        case (429, _): .cooldown(seconds: retryAfter ?? RetryAfter.rateLimitDefault)
        case (503, "CAPTCHA_PROVIDER_CONFLICT"?), (403, "BACKEND_MODE_ADMIN_ONLY"?), (403, "USER_NOT_ACTIVE"?), (403, "FORBIDDEN"?),
             (401, "USER_INACTIVE"?), (401, "INVALID_ADMIN_KEY"?), (401, "ACCESS_TOKEN_EXPIRED"?):
            .stop
        default: .none
        }
    }
}
