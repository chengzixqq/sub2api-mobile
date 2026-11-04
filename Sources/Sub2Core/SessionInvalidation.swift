import Foundation

/// A server answer that ends the site's session or credential (00 §3.2 “会话失效 / 会话绑定 / 凭据无效”, §1.7.2, §1.7.4). The
/// catalog's action is the only source (D06): the cause follows the error's category and the wording is the error's own.
public struct SessionInvalidation: Sendable, Equatable {
    public enum Cause: String, Sendable {
        case expired, bindingMismatch, invalidCredential, accessTokenExpired, accountDisabled, backendModeAdminOnly, workspaceDisabled
    }
    public let cause: Cause
    public let statusCode: Int?
    public let reason: String?
    /// The 3.2 / 1.7.2 wording shown on the site's login page.
    public let message: String

    public init(cause: Cause, statusCode: Int? = nil, reason: String? = nil, message: String) {
        self.cause = cause; self.statusCode = statusCode; self.reason = reason; self.message = message
    }
    /// nil unless the error is a catalog error whose action clears the session or the credential.
    public init?(error: any Error) {
        guard let error = error as? APIError, let action = error.action, action == .clearSession || action == .clearCredential,
              let message = error.errorDescription else { return nil }
        self.init(cause: Self.cause(of: error), statusCode: error.statusCode, reason: error.reason, message: message)
    }

    private static func cause(of error: APIError) -> Cause {
        switch (error.category, error.reason) {
        case (.sessionBinding?, _): .bindingMismatch
        case (.invalidCredential?, "ACCESS_TOKEN_EXPIRED"?): .accessTokenExpired
        case (.invalidCredential?, _): .invalidCredential
        case (_, "USER_NOT_ACTIVE"?): .accountDisabled
        case (.permission?, "BACKEND_MODE_ADMIN_ONLY"?): .backendModeAdminOnly
        case (.permission?, "WORKSPACE_DISABLED"?): .workspaceDisabled
        default: .expired
        }
    }
}
