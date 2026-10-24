import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// D06: SessionInvalidation reads only the catalog's action; cause and wording come from the error itself.

private let expiredReasons = ["INVALID_TOKEN", "TOKEN_REVOKED", "USER_NOT_FOUND", "USER_INACTIVE", "REFRESH_TOKEN_INVALID",
                              "REFRESH_TOKEN_EXPIRED", "REFRESH_TOKEN_REUSED", "UNAUTHORIZED", "INVALID_AUTH_HEADER", "EMPTY_TOKEN"]

@Test(arguments: expiredReasons)
func sessionExpiredReasonsInvalidateOnlyAt401(reason: String) throws {
    let invalidation = try #require(SessionInvalidation(error: APIError.server(status: 401, reason: reason)))
    #expect(invalidation.cause == .expired); #expect(invalidation.message == "登录已失效，请重新登录")
    #expect(invalidation.statusCode == 401); #expect(invalidation.reason == reason)
    #expect(SessionInvalidation(error: APIError.server(status: 403, reason: reason)) == nil)
    #expect(SessionInvalidation(error: APIError.server(status: 400, reason: reason)) == nil)
}

@Test func userNotFoundInvalidatesOnlyAt401() {
    #expect(SessionInvalidation(error: APIError.server(status: 401, reason: "USER_NOT_FOUND"))?.cause == .expired)
    // A 404 is the edited user, never the signed-in administrator.
    #expect(SessionInvalidation(error: APIError.server(status: 404, reason: "USER_NOT_FOUND")) == nil)
}

@Test func bindingAndCredentialCausesKeepCatalogWording() throws {
    let binding = try #require(SessionInvalidation(error: APIError.server(status: 401, reason: "SESSION_BINDING_MISMATCH")))
    #expect(binding.cause == .bindingMismatch); #expect(binding.message == "网络或设备信息变化导致会话失效，请重新登录")
    let key = try #require(SessionInvalidation(error: APIError.server(status: 401, reason: "INVALID_ADMIN_KEY")))
    #expect(key.cause == .invalidCredential); #expect(key.message == "令牌或 Admin Key 无效，请重新输入")
    let token = try #require(SessionInvalidation(error: APIError.server(status: 401, reason: "ACCESS_TOKEN_EXPIRED")))
    #expect(token.cause == .accessTokenExpired); #expect(token.message == "管理访问令牌已过期，请重新签发")
}

@Test func accountAndBackendModeEndSessionsOnlyDuringRefresh() throws {
    let disabled = try #require(SessionInvalidation(error: APIError.server(status: 403, reason: "USER_NOT_ACTIVE", context: .refresh)))
    #expect(disabled.cause == .accountDisabled); #expect(disabled.message == "该账号已被禁用")
    let backend = try #require(SessionInvalidation(error: APIError.server(status: 403, reason: "BACKEND_MODE_ADMIN_ONLY", context: .refresh)))
    #expect(backend.cause == .backendModeAdminOnly); #expect(backend.message == "站点处于后端模式，仅管理员可登录")
    #expect(SessionInvalidation(error: APIError.server(status: 403, reason: "USER_NOT_ACTIVE")) == nil)
    #expect(SessionInvalidation(error: APIError.server(status: 403, reason: "BACKEND_MODE_ADMIN_ONLY")) == nil)
}

@Test func workspaceDisabledEndsTheSession() throws {
    let workspace = try #require(SessionInvalidation(error: APIError.server(status: 403, reason: "WORKSPACE_DISABLED")))
    #expect(workspace.cause == .workspaceDisabled); #expect(workspace.message == "你的工作区已被停用")
}

@Test func unknown401FallsBackToExpired() throws {
    for error in [APIError.server(status: 401, reason: nil), .server(status: 401, reason: "SOMETHING_NEW"),
                  .from(HTTPResponse(statusCode: 401, data: Data("<html>unauthorized</html>".utf8))), .authenticationRequired] {
        let invalidation = try #require(SessionInvalidation(error: error))
        #expect(invalidation.cause == .expired); #expect(invalidation.message == "登录已失效，请重新登录")
    }
}

@Test func errorsThatKeepTheSessionAreNotInvalidations() {
    let kept: [any Error] = [
        APIError.server(status: 401, reason: "TOKEN_EXPIRED"), APIError.server(status: 401, reason: "INVALID_CREDENTIALS", context: .login),
        APIError.server(status: 403, reason: "FORBIDDEN"), APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"),
        APIError.server(status: 403, reason: "STEP_UP_REQUIRED"), APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED"),
        APIError.server(status: 429, reason: "RATE_LIMITED"), APIError.server(status: 503, reason: nil), APIError.server(status: 502, reason: nil),
        APIError.refreshDeferred, APIError.transport(URLError(.timedOut)), CancellationError(), URLError(.notConnectedToInternet),
        KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil,
                          lastError: APIError.server(status: 401, reason: "TOKEN_REVOKED"))
    ]
    for error in kept { #expect(SessionInvalidation(error: error) == nil, "\(error)") }
}

@Test func explicitInvalidationKeepsItsFields() {
    let value = SessionInvalidation(cause: .expired, statusCode: 401, reason: "TOKEN_REVOKED", message: "登录已失效，请重新登录")
    #expect(value == SessionInvalidation(error: APIError.server(status: 401, reason: "TOKEN_REVOKED")))
}
