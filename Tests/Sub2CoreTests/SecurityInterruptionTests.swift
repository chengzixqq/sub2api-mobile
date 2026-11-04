import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func refusal(_ status: Int, _ reason: String?) -> APIError { APIError.server(status: status, reason: reason) }
private let phrase = "我已阅读、理解并同意 Sub2API 部署与运营合规承诺"

@Test func classifiesComplianceStepUpAndReadOnlyByStatusAndReason() {
    let cases: [(APIError, SecurityInterruption)] = [
        (refusal(423, "ADMIN_COMPLIANCE_ACK_REQUIRED"), .complianceRequired),
        (APIError.server(status: 423, envelope: nil), .complianceRequired),
        (refusal(403, "STEP_UP_REQUIRED"), .stepUpRequired),
        (refusal(403, "STEP_UP_TOTP_NOT_ENABLED"), .stepUpTOTPNotEnabled),
        (refusal(403, "STEP_UP_ADMIN_API_KEY_FORBIDDEN"), .stepUpMachineCredential),
        (refusal(503, "STEP_UP_UNAVAILABLE"), .stepUpUnavailable),
        (refusal(403, "ACCESS_TOKEN_READ_ONLY"), .readOnlyToken)
    ]
    for (error, expected) in cases { #expect(SecurityInterruption(error) == expected) }
    #expect(cases.map(\.1).filter(\.presentsPrompt) == [.complianceRequired, .complianceRequired, .stepUpRequired, .stepUpTOTPNotEnabled])
}

@Test func otherReasonsAreNotSecurityInterruptions() {
    let others = [refusal(403, "FORBIDDEN"), refusal(400, "TOTP_INVALID_CODE"), refusal(401, "TOKEN_EXPIRED"), refusal(404, "USER_NOT_FOUND"),
                  refusal(429, "RATE_LIMITED"), refusal(400, "STEP_UP_REQUIRED"), refusal(403, "STEP_UP_REQUIRED_LATER"), refusal(403, nil),
                  refusal(503, nil), APIError(kind: .stepUp, message: "本地错误")]
    for error in others { #expect(SecurityInterruption(error) == nil) }
}

/// 00 §2.5.4 step 2 across calls: a retry of a write that may have run is not settled by an answer from before the handler,
/// whatever the global sheet ended with.
@Test func refusalsBeforeTheHandlerAreToldApartFromAnswers() {
    let before = [refusal(423, "ADMIN_COMPLIANCE_ACK_REQUIRED"), APIError.server(status: 423, envelope: nil), refusal(403, "STEP_UP_REQUIRED"),
                  refusal(403, "STEP_UP_TOTP_NOT_ENABLED"), refusal(403, "STEP_UP_ADMIN_API_KEY_FORBIDDEN"), refusal(403, "ACCESS_TOKEN_READ_ONLY"),
                  refusal(403, "FORBIDDEN"), refusal(503, "STEP_UP_UNAVAILABLE"), refusal(401, "TOKEN_REVOKED"), refusal(429, "RATE_LIMITED")]
    for error in before {
        #expect(error.isRefusedBeforeHandler)
        for outcome in [SecurityPromptOutcome.passed, .cancelled, .blocked] { #expect(error.withSecurityOutcome(outcome).isRefusedBeforeHandler) }
    }
    let answers = [refusal(400, "INVALID_BALANCE"), refusal(400, "VALIDATION_ERROR"), refusal(404, "USER_NOT_FOUND"), refusal(409, "EMAIL_EXISTS"),
                   refusal(422, nil), refusal(500, nil), refusal(503, nil), refusal(503, "IDEMPOTENCY_STORE_UNAVAILABLE"),
                   APIError.invalidAmount, APIError.stationMismatch, APIError(kind: .stepUp, message: "本地错误")]
    for error in answers { #expect(!error.isRefusedBeforeHandler) }
}

@Test func outcomeKeepsTheAnswerAndOnlyPassedChangesTheText() {
    let stepUp = refusal(403, "STEP_UP_REQUIRED")
    #expect(stepUp.securityOutcome == nil)
    let passed = stepUp.withSecurityOutcome(.passed)
    #expect(passed.statusCode == 403); #expect(passed.reason == "STEP_UP_REQUIRED"); #expect(passed.kind == .stepUp)
    #expect(passed.securityOutcome == .passed); #expect(passed.action == .stepUp)
    #expect(passed.localizedDescription == "二次验证已通过，请重新确认后发送")
    #expect(refusal(423, nil).withSecurityOutcome(.passed).localizedDescription == "合规确认已完成，请重新确认后发送")
    #expect(stepUp.withSecurityOutcome(.cancelled).localizedDescription == "该操作需要先完成二次验证")
    #expect(refusal(403, "ACCESS_TOKEN_READ_ONLY").withSecurityOutcome(.blocked).localizedDescription == "当前管理访问令牌只读，不能执行此操作")
    #expect(stepUp.withSecurityOutcome(.blocked) != stepUp)
}

@Test func stepUpRequirementFollowsSwitchCredentialTOTPAndGrant() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let on = AdminMe.Security(totpEnabled: true, stepUpEnabled: true)
    func requirement(_ security: AdminMe.Security, _ method: AdminAuthMethod? = .jwt, grant: Date? = nil) -> StepUpRequirement {
        StepUpPolicy.requirement(security: security, authMethod: method, grantExpiresAt: grant, now: now)
    }
    #expect(requirement(AdminMe.Security()) == .notRequired)
    #expect(requirement(AdminMe.Security(stepUpEnabled: false), .adminAPIKey) == .notRequired)
    #expect(requirement(on, .adminAPIKey) == .machineCredential)
    #expect(requirement(on, .adminAccessToken) == .machineCredential)
    #expect(requirement(AdminMe.Security(totpEnabled: false, stepUpEnabled: true)) == .totpNotEnabled)
    #expect(requirement(on, grant: now.addingTimeInterval(1)) == .notRequired)
    #expect(requirement(on, grant: now) == .verify)
    #expect(requirement(on, grant: now.addingTimeInterval(-1)) == .verify)
    #expect(requirement(on) == .verify)
    #expect(requirement(on, nil) == .verify)
    #expect(requirement(AdminMe.Security(stepUpEnabled: true)) == .verify)
    #expect(StepUpPolicy.machineCredentialNotice == "Admin Key 与管理访问令牌不能做二次验证，请改用账号登录")
}

@Test func grantExpiryCombinesAdminMeAndLocalGrant() {
    let fetched = Date(timeIntervalSince1970: 1_800_000_000)
    let granted = AdminMe.Security(stepUpEnabled: true, stepUpGranted: true, stepUpExpiresIn: 600)
    #expect(StepUpPolicy.grantExpiry(security: granted, fetchedAt: fetched, localGrant: nil) == fetched.addingTimeInterval(600))
    #expect(StepUpPolicy.grantExpiry(security: granted, fetchedAt: fetched, localGrant: fetched.addingTimeInterval(900)) == fetched.addingTimeInterval(900))
    #expect(StepUpPolicy.grantExpiry(security: granted, fetchedAt: fetched, localGrant: fetched.addingTimeInterval(60)) == fetched.addingTimeInterval(600))
    #expect(StepUpPolicy.grantExpiry(security: granted, fetchedAt: nil, localGrant: nil) == nil)
    let local = fetched.addingTimeInterval(30)
    for unknown in [AdminMe.Security(stepUpGranted: true, stepUpExpiresIn: 0), AdminMe.Security(stepUpGranted: true),
                    AdminMe.Security(stepUpGranted: false, stepUpExpiresIn: 600), AdminMe.Security(stepUpExpiresIn: 600)] {
        #expect(StepUpPolicy.grantExpiry(security: unknown, fetchedAt: fetched, localGrant: local) == local)
        #expect(StepUpPolicy.grantExpiry(security: unknown, fetchedAt: fetched, localGrant: nil) == nil)
    }
}

@Test func stepUpGrantDecodesExpiryAndToleratesItsAbsence() throws {
    let grant = try JSONDecoder().decode(StepUpGrant.self, from: Data(#"{"verified":true,"expires_in":900}"#.utf8))
    #expect(grant == StepUpGrant(verified: true, expiresIn: 900))
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(grant.expiresAt(from: start) == start.addingTimeInterval(900))
    let bare = try JSONDecoder().decode(StepUpGrant.self, from: Data(#"{"verified":true,"expires_in":"soon"}"#.utf8))
    #expect(bare.expiresIn == nil); #expect(bare.expiresAt(from: start) == nil)
    #expect(StepUpGrant(verified: true, expiresIn: 0).expiresAt(from: start) == nil)
}

@Test func stepUpFailureMapsVerificationErrors() {
    #expect(StepUpFailure(refusal(400, "TOTP_INVALID_CODE")) == .retype("验证码不对，请重新输入"))
    #expect(StepUpFailure(refusal(429, "TOTP_TOO_MANY_ATTEMPTS")) == .close("尝试次数过多，请稍后再试"))
    #expect(StepUpFailure(refusal(400, "TOTP_NOT_SETUP")) == .totpNotEnabled)
    #expect(StepUpFailure(refusal(403, "STEP_UP_TOTP_NOT_ENABLED")) == .totpNotEnabled)
    #expect(StepUpFailure(refusal(503, "STEP_UP_UNAVAILABLE")) == .keep("二次验证服务暂时不可用，请稍后重试"))
    #expect(StepUpFailure(refusal(500, nil)) == .keep("二次验证服务暂时不可用，请稍后重试"))
    let limited = APIError.server(status: 429, envelope: ErrorEnvelope(reason: "RATE_LIMITED"), retryAfter: 12)
    guard case .keep(let text) = StepUpFailure(limited) else { Issue.record("限流应保留 sheet"); return }
    #expect(text.contains("12 秒"))
    #expect(StepUpFailure(APIError.transport(URLError(.notConnectedToInternet))) == .keep("无法连接站点"))
    guard case .keep = StepUpFailure(URLError(.timedOut)) else { Issue.record("网络错误应保留 sheet"); return }
    #expect(StepUpFailure(refusal(401, "INVALID_TOKEN")) == .sessionEnded)
    #expect(StepUpFailure(APIError.authenticationRequired) == .sessionEnded)
    #expect(StepUpFailure(CancellationError()) == .sessionEnded)
    #expect(StepUpFailure(APIError(kind: .twoFactor, message: "请输入六位双因素验证码。")) == .retype("请输入六位双因素验证码。"))
}

@Test func oneTimeCodeKeepsSixDigitsOnly() {
    #expect(OneTimeCode.sanitize("12 34a5678") == "123456")
    #expect(OneTimeCode.sanitize("１２3４5x6") == "356")
    #expect(OneTimeCode.sanitize("") == "")
    #expect(OneTimeCode.isComplete("123456")); #expect(!OneTimeCode.isComplete("12345"))
    #expect(!OneTimeCode.isComplete("12a456")); #expect(!OneTimeCode.isComplete("１２３４５６")); #expect(!OneTimeCode.isComplete("1234567"))
}

@Test func compliancePhraseRequiresExactTextIgnoringOuterWhitespace() {
    let status = AdminComplianceStatus(required: true, ackPhraseZH: phrase)
    #expect(status.phraseMatches(phrase)); #expect(status.phraseMatches("  \(phrase)\n"))
    #expect(!status.phraseMatches("我已阅读、理解并同意  Sub2API 部署与运营合规承诺"))
    #expect(!status.phraseMatches("我已阅读,理解并同意 Sub2API 部署与运营合规承诺"))
    #expect(!status.phraseMatches(String(phrase.dropLast())))
    #expect(!status.phraseMatches(""))
    #expect(!AdminComplianceStatus(ackPhraseZH: "caf\u{E9}").phraseMatches("cafe\u{301}"))
    #expect(!AdminComplianceStatus(ackPhraseZH: "  ").phraseMatches("  "))
    #expect(!AdminComplianceStatus().phraseMatches("x"))
}

@Test func complianceDocumentURLPrefersHTTPSURLThenSitePath() {
    let site = URL(string: "https://sub2.example.invalid")!
    let fallback = URL(string: "https://sub2.example.invalid/docs/legal/admin-compliance.zh.md")
    let document = "https://docs.example.invalid/admin-compliance.zh.md"
    #expect(AdminComplianceStatus(documentPathZH: "docs/legal/admin-compliance.zh.md", documentURLZH: document).documentURL(site: site)
            == URL(string: document))
    for path in ["docs/legal/admin-compliance.zh.md", "/docs/legal/admin-compliance.zh.md"] {
        #expect(AdminComplianceStatus(documentPathZH: path, documentURLZH: "").documentURL(site: site) == fallback)
        #expect(AdminComplianceStatus(documentPathZH: path).documentURL(site: site) == fallback)
    }
    for unsafe in ["http://docs.example.invalid/zh.md", "javascript:alert(1)", "https://"] {
        #expect(AdminComplianceStatus(documentPathZH: "docs/legal/admin-compliance.zh.md", documentURLZH: unsafe).documentURL(site: site) == fallback)
        #expect(AdminComplianceStatus(documentURLZH: unsafe).documentURL(site: site) == nil)
    }
    #expect(AdminComplianceStatus().documentURL(site: site) == nil)
    #expect(AdminComplianceStatus(documentPathZH: " ").documentURL(site: site) == nil)
}

@Test func complianceAcceptFailureMessages() {
    #expect(AdminComplianceStatus.acceptFailureMessage(for: refusal(403, "ACCESS_TOKEN_READ_ONLY")) == "只读令牌不能完成合规确认，请用账号登录或在 Web 完成")
    #expect(AdminComplianceStatus.acceptFailureMessage(for: refusal(403, "ACCESS_TOKEN_READ_ONLY").withSecurityOutcome(.blocked))
            == "只读令牌不能完成合规确认，请用账号登录或在 Web 完成")
    #expect(AdminComplianceStatus.acceptFailureMessage(for: refusal(400, "ADMIN_COMPLIANCE_INVALID_PHRASE")) == "确认语句不一致，请逐字输入")
    let other = APIError.from(HTTPResponse(statusCode: 500, data: Data(#"{"code":500,"message":"https://upstream.example.invalid?token=x"}"#.utf8)))
    #expect(AdminComplianceStatus.acceptFailureMessage(for: other) == "站点暂时不可用")
    #expect(AdminComplianceStatus.acceptFailureMessage(for: APIError.transport(URLError(.cannotConnectToHost))) == "无法连接站点")
}
