import Foundation

/// How a site is signed in, in words (D10): settings, site rows and the site session read these. The login page keeps its own titles.
public enum AuthPresentation {
    /// 60 §3.3 认证方式: what `/admin/me` reported, otherwise the saved login kind; a token scope that is not known yet is left out.
    public static func methodLabel(authMethod: AdminAuthMethod?, fallback: AuthenticationKind, accessTokenScope: String?) -> String {
        switch kind(of: authMethod) ?? fallback {
        case .password: return "邮箱和密码"
        case .adminKey: return "Admin Key · 以第一个管理员身份操作"
        case .accessToken:
            guard let accessTokenScope else { return "访问令牌" }
            return AdminAccessToken.isReadOnly(scope: accessTokenScope) ? "访问令牌 · 只读" : "访问令牌 · 读写"
        }
    }
    /// 00 §1.1: an Admin Key acts as the site's first administrator.
    public static func operatorNote(authMethod: AdminAuthMethod?, email: String?) -> String? {
        guard authMethod == .adminAPIKey, let email, !email.isEmpty else { return nil }
        return "以 \(email) 身份操作（第一个管理员）"
    }
    /// 00 §1.1 site row badge.
    public static func siteBadge(_ kind: AuthenticationKind) -> String {
        switch kind {
        case .password: "账号"
        case .accessToken: "管理访问令牌"
        case .adminKey: "Admin Key"
        }
    }
    /// nil for a method this App does not know yet.
    private static func kind(of method: AdminAuthMethod?) -> AuthenticationKind? {
        switch method {
        case .jwt: .password
        case .adminAPIKey: .adminKey
        case .adminAccessToken: .accessToken
        case .other, nil: nil
        }
    }
}
