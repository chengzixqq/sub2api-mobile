import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let device = stubDeviceID.uuidString.lowercased()
private func loginClient(_ transport: ScriptedTransport, clock: RequestClock = .immediate) -> APIClient {
    APIClient(server: stubServer(), deviceID: stubDeviceID, transport: transport, requestClock: clock)
}
private func issued(role: String = "admin", refresh: String? = "issued-refresh", extra: String = "") -> HTTPResponse {
    let user = stubUserJSON.replacingOccurrences(of: "\"role\":\"admin\"", with: "\"role\":\"\(role)\"")
    let refreshField = refresh.map { ",\"refresh_token\":\"\($0)\"" } ?? ""
    return okReply("{\"access_token\":\"issued-access\"\(refreshField),\"expires_in\":3600,\"token_type\":\"Bearer\"\(extra),\"user\":\(user)}")
}
private func jsonBody(_ request: URLRequest?) throws -> [String: Any] {
    let data = try #require(request?.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
private func isLogout(_ request: URLRequest) -> Bool { request.url?.path == "/api/v1/auth/logout" }

@Test func loginDeclaresNativeClientWithSameDeviceIDAsHeader() async throws {
    let transport = ScriptedTransport { _ in issued() }
    _ = try await loginClient(transport).login(email: "admin@example.invalid", password: "only-test", deviceName: "测试设备", declaresCaptchaProvider: true)
    let request = await transport.requests.first
    let body = try jsonBody(request)
    let declared = try #require(body["client"] as? [String: String])
    #expect(declared == ["type": "ios", "device_id": device, "device_name": "测试设备"])
    #expect(declared["device_id"] == sentHeader(request, "X-Device-ID"))
    #expect(sentHeader(request, "Content-Type") == "application/json")
    #expect(request?.url?.path == "/api/v1/auth/login")
}

@Test func loginWithoutProofSendsNoCaptchaFields() async throws {
    let transport = ScriptedTransport { _ in issued() }
    _ = try await loginClient(transport).login(email: "admin@example.invalid", password: "only-test", deviceName: "iPhone", declaresCaptchaProvider: true)
    #expect(Set(try jsonBody(await transport.requests.first).keys) == ["email", "password", "client"])
}

@Test func twoFactorStepOmitsClientDeclaration() async throws {
    let transport = ScriptedTransport { request in
        request.url?.path.hasSuffix("/login/2fa") == true ? issued() : okReply(#"{"requires_2fa":true,"temp_token":"temporary"}"#)
    }
    let client = loginClient(transport)
    guard case .twoFactor(let challenge) = try await client.login(email: "admin@example.invalid", password: "only-test", deviceName: "iPhone",
                                                                  declaresCaptchaProvider: false) else { Issue.record("Expected TOTP challenge"); return }
    _ = try await client.completeTOTP(tempToken: challenge.tempToken, code: "123456")
    let second = await transport.requests.last
    #expect(Set(try jsonBody(second).keys) == ["temp_token", "totp_code"])
    #expect(sentHeader(second, "X-Device-ID") == device)
}

struct CaptchaRow: Sendable, CustomTestStringConvertible {
    let proof: CaptchaProof
    let declaresProvider: Bool
    let fields: [String: String]
    var testDescription: String { "\(proof.provider ?? "-") \(declaresProvider ? "新服务端" : "旧服务端")" }
}
private let captchaRows: [CaptchaRow] = [
    CaptchaRow(proof: CaptchaProof(provider: "turnstile", turnstileToken: "t-proof"), declaresProvider: true,
               fields: ["captcha_provider": "turnstile", "turnstile_token": "t-proof"]),
    CaptchaRow(proof: CaptchaProof(provider: "turnstile", turnstileToken: "t-proof"), declaresProvider: false, fields: ["turnstile_token": "t-proof"]),
    CaptchaRow(proof: CaptchaProof(provider: "tencent", tencentTicket: "ticket", tencentRandstr: "rand"), declaresProvider: true,
               fields: ["captcha_provider": "tencent", "tencent_captcha_ticket": "ticket", "tencent_captcha_randstr": "rand"]),
    CaptchaRow(proof: CaptchaProof(provider: "tencent", tencentTicket: "ticket", tencentRandstr: "rand"), declaresProvider: false,
               fields: ["tencent_captcha_ticket": "ticket", "tencent_captcha_randstr": "rand"]),
    CaptchaRow(proof: CaptchaProof(provider: "aliyun", turnstileToken: "a-proof", aliyunParam: "a-proof"), declaresProvider: true,
               fields: ["captcha_provider": "aliyun", "aliyun_captcha_param": "a-proof"]),
    CaptchaRow(proof: CaptchaProof(provider: "aliyun", turnstileToken: "a-proof", aliyunParam: "a-proof"), declaresProvider: false,
               fields: ["turnstile_token": "a-proof"])
]

@Test(arguments: captchaRows)
func captchaProofMapsToLoginFieldsPerBridgeTable(row: CaptchaRow) async throws {
    let transport = ScriptedTransport { _ in issued() }
    _ = try await loginClient(transport).login(email: "admin@example.invalid", password: "only-test", proof: row.proof, deviceName: "iPhone",
                                               declaresCaptchaProvider: row.declaresProvider)
    var body = try jsonBody(await transport.requests.first)
    for key in ["email", "password", "client"] { body.removeValue(forKey: key) }
    #expect(body as? [String: String] == row.fields)
}

@Test func refreshTokenUnavailableLoginIsAccepted() async throws {
    let clock = ManualClock()
    let transport = ScriptedTransport { _ in issued(refresh: nil, extra: ",\"refresh_token_unavailable\":true") }
    let result = try await loginClient(transport, clock: clock.requestClock).login(email: "admin@example.invalid", password: "only-test",
                                                                                     deviceName: "iPhone", declaresCaptchaProvider: true)
    guard case .authenticated(let session) = result else { Issue.record("Expected a session"); return }
    #expect(session.refreshTokenUnavailable); #expect(session.tokens.refreshToken.isEmpty)
    #expect(session.tokens.expiresAt == clock.start.addingTimeInterval(3_600))
    let normal = try await loginClient(ScriptedTransport { _ in issued() }).login(email: "admin@example.invalid", password: "only-test",
                                                                                  deviceName: "iPhone", declaresCaptchaProvider: true)
    guard case .authenticated(let regular) = normal else { Issue.record("Expected a session"); return }
    #expect(!regular.refreshTokenUnavailable)
}

@Test(arguments: ["vendor", "user"])
func nonAdministratorLoginRevokesIssuedSessionBeforeFailing(role: String) async throws {
    let transport = ScriptedTransport { request in isLogout(request) ? okReply("null") : issued(role: role) }
    let client = loginClient(transport)
    await #expect(throws: APIError.administratorRequired) {
        _ = try await client.login(email: "user@example.invalid", password: "only-test", deviceName: "iPhone", declaresCaptchaProvider: true)
    }
    let requests = await transport.requests
    #expect(requests.count == 2)
    let logout = requests.last
    #expect(logout?.url?.path == "/api/v1/auth/logout"); #expect(logout?.httpMethod == "POST")
    #expect(sentHeader(logout, "Authorization") == "Bearer issued-access"); #expect(sentHeader(logout, "x-api-key") == nil)
    #expect(sentHeader(logout, "X-Device-ID") == device)
    #expect(try jsonBody(logout) as? [String: String] == ["refresh_token": "issued-refresh"])
    #expect(await client.currentCredential() == nil)
    #expect(APIError.administratorRequired.localizedDescription == "当前版本仅支持管理员账号")
}

@Test func discardWithoutRefreshTokenSendsEmptyBody() async throws {
    let transport = ScriptedTransport { request in isLogout(request) ? okReply("null") : issued(role: "user", refresh: nil) }
    await #expect(throws: APIError.administratorRequired) {
        _ = try await loginClient(transport).login(email: "user@example.invalid", password: "only-test", deviceName: "iPhone", declaresCaptchaProvider: true)
    }
    #expect(String(decoding: try #require(await transport.requests.last?.httpBody), as: UTF8.self) == "{}")
}

@Test(arguments: [ScriptStep.fail(URLError(.notConnectedToInternet)), .reply(errorReply(500)), .reply(errorReply(401, reason: "TOKEN_REVOKED"))])
func discardFailureStillReportsAdministratorRequired(discard: ScriptStep) async throws {
    let transport = ScriptedTransport { request in try isLogout(request) ? discard.resolve() : issued(role: "vendor") }
    await #expect(throws: APIError.administratorRequired) {
        _ = try await loginClient(transport).login(email: "user@example.invalid", password: "only-test", deviceName: "iPhone", declaresCaptchaProvider: true)
    }
    // Sent once: no refresh, no retry.
    #expect(await transport.requests.filter(isLogout).count == 1)
}
