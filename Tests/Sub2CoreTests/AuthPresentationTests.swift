import Foundation
import Testing
@testable import Sub2Core

@Test func methodLabelFollowsReportedAuthMethodAndTokenScope() {
    let label = { (method: AdminAuthMethod?, scope: String?) in AuthPresentation.methodLabel(authMethod: method, fallback: .password, accessTokenScope: scope) }
    #expect(label(.jwt, nil) == "邮箱和密码")
    #expect(label(.adminAPIKey, nil) == "Admin Key · 以第一个管理员身份操作")
    #expect(label(.adminAccessToken, "read") == "访问令牌 · 只读")
    #expect(label(.adminAccessToken, "write") == "访问令牌 · 读写")
    // Backend ReadOnly() is anything but "write"; an unknown scope is written without either word.
    #expect(label(.adminAccessToken, "admin") == "访问令牌 · 只读")
    #expect(label(.adminAccessToken, nil) == "访问令牌")
}

@Test func methodLabelFallsBackToSavedLoginKind() {
    let fallback = { (kind: AuthenticationKind, method: AdminAuthMethod?) in AuthPresentation.methodLabel(authMethod: method, fallback: kind, accessTokenScope: nil) }
    #expect(fallback(.password, nil) == "邮箱和密码")
    #expect(fallback(.adminKey, nil) == "Admin Key · 以第一个管理员身份操作")
    #expect(fallback(.accessToken, nil) == "访问令牌")
    // A method this App does not know yet reads like the saved kind.
    #expect(fallback(.adminKey, .other("passkey")) == "Admin Key · 以第一个管理员身份操作")
}

@Test func operatorNoteOnlyForAdminKeyWithEmail() {
    #expect(AuthPresentation.operatorNote(authMethod: .adminAPIKey, email: "admin@example.invalid") == "以 admin@example.invalid 身份操作（第一个管理员）")
    #expect(AuthPresentation.operatorNote(authMethod: .adminAPIKey, email: nil) == nil)
    #expect(AuthPresentation.operatorNote(authMethod: .adminAPIKey, email: "") == nil)
    #expect(AuthPresentation.operatorNote(authMethod: .jwt, email: "admin@example.invalid") == nil)
    #expect(AuthPresentation.operatorNote(authMethod: .adminAccessToken, email: "admin@example.invalid") == nil)
}

@Test func siteBadgeNamesLoginKind() {
    #expect(AuthPresentation.siteBadge(.password) == "账号")
    #expect(AuthPresentation.siteBadge(.accessToken) == "管理访问令牌")
    #expect(AuthPresentation.siteBadge(.adminKey) == "Admin Key")
}
