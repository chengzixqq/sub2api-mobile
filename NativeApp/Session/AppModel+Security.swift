import Foundation
import Sub2Core

/// What an operation that needs step-up may do now (00 §2.6.2).
enum SecurityResolution: Equatable {
    case passed, cancelled
    case blocked(String)
}

/// The global compliance and step-up sheets (00 §1.10, §2.6, §2.7.1, §9.5; D09, D11, D13). The client's interceptor lands in
/// `interceptSecurity`; the sheets call the wrappers below, which carry the UI-test fixtures.
extension AppModel {
    /// The active client's hook (D13); it answers only for the session it was made for.
    func makeSecurityInterceptor(generation: UUID) -> SecurityInterceptor {
        { [weak self] error, isRead in
            guard let self else { return .cancelled }
            return await self.interceptSecurity(error, isRead: isRead, generation: generation)
        }
    }
    /// A read-only token is only marked (the usage batches keep their block at “—”, 00 §2.6.3); machine credentials and an
    /// unavailable step-up service have nothing to ask. One sheet at a time (SecurityPromptCenter).
    func interceptSecurity(_ error: APIError, isRead: Bool, generation: UUID) async -> SecurityPromptOutcome {
        guard generation == sessionGeneration, let interruption = SecurityInterruption(error) else { return .cancelled }
        switch interruption {
        case .readOnlyToken:
            markAccessTokenReadOnly(generation: generation)
            return .blocked
        case .stepUpMachineCredential, .stepUpUnavailable: return .blocked
        case .stepUpTOTPNotEnabled: return await securityPrompts.present(.stepUpNoTOTP, purpose: nil, isRead: isRead, generation: generation)
        case .stepUpRequired: return await securityPrompts.present(.stepUpVerify, purpose: nil, isRead: isRead, generation: generation)
        case .complianceRequired: return await securityPrompts.present(.compliance, purpose: nil, isRead: isRead, generation: generation)
        }
    }
    /// For a caller that got the refusal some other way: what the prompt decided; nil when the error is not a security one.
    func resolveSecurity(_ error: any Error, purpose: String? = nil) async -> SecurityResolution? {
        guard let refusal = error as? APIError, SecurityInterruption(refusal) != nil else { return nil }
        let outcome: SecurityPromptOutcome
        if let known = refusal.securityOutcome { outcome = known }
        else { outcome = await interceptSecurity(refusal, isRead: false, generation: sessionGeneration) }
        switch outcome {
        case .passed: return .passed
        case .cancelled: return .cancelled
        case .blocked: return .blocked(refusal.localizedDescription)
        }
    }

    /// 00 §2.6.1: the check before an operation marked “needs step-up”.
    func stepUpRequirement(now: Date = Date()) -> StepUpRequirement {
        guard let site = siteSession else { return .notRequired }
        let expiry = StepUpPolicy.grantExpiry(security: site.me.security, fetchedAt: site.probedAt,
                                              localGrant: securityPrompts.localGrantExpiry(generation: sessionGeneration))
        return StepUpPolicy.requirement(security: site.me.security, authMethod: site.authMethod, grantExpiresAt: expiry, now: now)
    }
    /// The active entry (reveal a key, issue a token, push configuration, new administrators — stages 3 and 6).
    func ensureStepUp(purpose: String?, isRead: Bool = false) async -> SecurityResolution {
        let generation = sessionGeneration
        switch stepUpRequirement() {
        case .notRequired: return .passed
        case .machineCredential: return .blocked(StepUpPolicy.machineCredentialNotice)
        case .totpNotEnabled:
            _ = await securityPrompts.present(.stepUpNoTOTP, purpose: purpose, isRead: isRead, generation: generation)
            return .blocked(StepUpPolicy.totpNotEnabledTitle)
        case .verify:
            let outcome = await securityPrompts.present(.stepUpVerify, purpose: purpose, isRead: isRead, generation: generation)
            return outcome == .passed && generation == sessionGeneration ? .passed : .cancelled
        }
    }

    /// After connecting (and reloading) a site that still needs the acknowledgement; connect does not wait for it (S0-16).
    func presentComplianceIfRequired() async {
        guard siteSession?.me.compliance.required == true else { return }
        _ = await presentCompliance()
    }
    /// Also the entry of a block's “完成合规确认” button (stage 1): asked by the administrator, so it shows after “稍后”.
    func presentCompliance() async -> SecurityPromptOutcome {
        await securityPrompts.present(.compliance, purpose: nil, isRead: false, generation: sessionGeneration)
    }

    func loadComplianceStatus() async throws -> AdminComplianceStatus {
        if isUITesting { return DemoData.complianceStatus }
        return try await requireClient().complianceStatus()
    }
    /// 00 §1.10: accept, read `/admin/me` again (a failed reload keeps the acceptance), then release what waited on the prompt.
    func submitCompliance(phrase: String, prompt: SecurityPromptCenter.Prompt) async throws {
        guard prompt.generation == sessionGeneration else { throw CancellationError() }
        if isUITesting {
            guard DemoData.complianceStatus.phraseMatches(phrase) else { throw APIError.server(status: 400, reason: "ADMIN_COMPLIANCE_INVALID_PHRASE") }
        } else {
            _ = try await requireClient().acceptCompliance(phrase: phrase)
            try? await reloadSiteSession()
        }
        guard prompt.generation == sessionGeneration else { throw CancellationError() }
        securityPrompts.complete(prompt.id, outcome: .passed)
    }
    /// 00 §2.6.2 step 3: the local expiry is recorded before the waiting requests continue; `/admin/me` is read again in the background.
    func verifyStepUp(code: String, prompt: SecurityPromptCenter.Prompt) async throws {
        guard prompt.generation == sessionGeneration else { throw CancellationError() }
        let grant: StepUpGrant
        if isUITesting {
            guard OneTimeCode.isComplete(code), code != "000000" else { throw APIError.server(status: 400, reason: "TOTP_INVALID_CODE") }
            grant = StepUpGrant(verified: true, expiresIn: 900)
        } else {
            grant = try await requireClient().stepUp(code: code)
        }
        guard prompt.generation == sessionGeneration else { throw CancellationError() }
        securityPrompts.recordStepUpGrant(expiresIn: grant.expiresIn, generation: prompt.generation)
        securityPrompts.complete(prompt.id, outcome: .passed)
        if !isUITesting { Task { try? await reloadSiteSession() } }
    }

    /// UI fixture for user writes: `-ui-step-up-required` refuses making or creating an administrator until verified,
    /// `-ui-step-up-no-totp` always refuses it; both go through the same interception as a real refusal.
    func fixtureSecurityRefusal(body: Data) async -> APIError? {
        let arguments = ProcessInfo.processInfo.arguments
        let fields = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        guard fields?["role"] as? String == AdminUserRole.admin.rawValue else { return nil }
        let refusal: APIError
        if arguments.contains("-ui-step-up-no-totp") { refusal = .server(status: 403, reason: "STEP_UP_TOTP_NOT_ENABLED") }
        else if arguments.contains("-ui-step-up-required"), stepUpRequirement() == .verify { refusal = .server(status: 403, reason: "STEP_UP_REQUIRED") }
        else { return nil }
        return refusal.withSecurityOutcome(await interceptSecurity(refusal, isRead: false, generation: sessionGeneration))
    }
}
