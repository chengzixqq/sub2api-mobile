import Foundation

/// The security answers a request gets before its handler runs (00 §0 rules 5–6, §2.6, §2.7.1), by the exact (status,
/// reason) pair. Any 423 is the compliance guard, JSON body or not (00 §3.3).
public enum SecurityInterruption: Equatable, Sendable {
    case complianceRequired, stepUpRequired, stepUpTOTPNotEnabled, stepUpMachineCredential, stepUpUnavailable, readOnlyToken

    public init?(_ error: APIError) {
        guard let status = error.statusCode else { return nil }
        switch (status, error.reason) {
        case (423, _): self = .complianceRequired
        case (403, "STEP_UP_REQUIRED"?): self = .stepUpRequired
        case (403, "STEP_UP_TOTP_NOT_ENABLED"?): self = .stepUpTOTPNotEnabled
        case (403, "STEP_UP_ADMIN_API_KEY_FORBIDDEN"?): self = .stepUpMachineCredential
        case (503, "STEP_UP_UNAVAILABLE"?): self = .stepUpUnavailable
        case (403, "ACCESS_TOKEN_READ_ONLY"?): self = .readOnlyToken
        default: return nil
        }
    }
    /// Only these open a sheet; the others are answered with the catalog text (00 §2.6.2 step 1, §2.6.3).
    public var presentsPrompt: Bool {
        switch self {
        case .complianceRequired, .stepUpRequired, .stepUpTOTPNotEnabled: true
        case .stepUpMachineCredential, .stepUpUnavailable, .readOnlyToken: false
        }
    }
    /// What a write cleared by the prompt says while it waits for the second confirmation (00 §2.6.2 step 4).
    var passedNotice: String? {
        switch self {
        case .complianceRequired: "合规确认已完成，请重新确认后发送"
        case .stepUpRequired: "二次验证已通过，请重新确认后发送"
        case .stepUpTOTPNotEnabled, .stepUpMachineCredential, .stepUpUnavailable, .readOnlyToken: nil
        }
    }
}

public enum SecurityPromptOutcome: String, Equatable, Sendable {
    /// Verified or accepted: a read is sent again, a write goes back to its confirmation.
    case passed
    /// The administrator closed the sheet, or the session ended while it was open.
    case cancelled
    /// Nothing to ask (machine credential, read-only token, TOTP off, service unavailable).
    case blocked
}

/// The session owner's answer to a security refusal; `isRead` is `RequestClass.isRead` of the refused request.
public typealias SecurityInterceptor = @Sendable (_ error: APIError, _ isRead: Bool) async -> SecurityPromptOutcome

extension APIClient {
    /// D01 ④, between `failure` and `surfaced`: asked at most once per call; nil without an interceptor or for any other
    /// error. A changed generation after the wait cancels, so a switch or sign-out meanwhile never resends.
    func securityOutcome(for error: APIError, isRead: Bool, generation snapshot: UUID) async throws -> SecurityPromptOutcome? {
        guard let securityInterceptor, SecurityInterruption(error) != nil else { return nil }
        let outcome = await securityInterceptor(error, isRead)
        try check(snapshot)
        return outcome
    }
    /// A write is refused before its handler and never resent (00 §0 rule 5): the caller gets the refusal with the outcome
    /// and returns to its confirmation with the same key and bytes. The refusal is final even when the caller was cancelled
    /// or the session ended meanwhile (counted as cancelled), so a money record can still be resolved as not executed.
    func refusedWrite(_ refusal: APIError, generation snapshot: UUID) async -> APIError {
        do {
            guard let outcome = try await securityOutcome(for: refusal, isRead: false, generation: snapshot) else { return refusal }
            return refusal.withSecurityOutcome(outcome)
        } catch { return refusal.withSecurityOutcome(.cancelled) }
    }
}
