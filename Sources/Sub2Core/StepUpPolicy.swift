import Foundation

/// What an operation marked “needs step-up” must do before it is sent (00 §2.6.1–§2.6.2).
public enum StepUpRequirement: Equatable, Sendable {
    case notRequired, verify, machineCredential, totpNotEnabled
}

public enum StepUpPolicy {
    /// 00 §2.6.2 step 1, for the check before sending; a server refusal uses the catalog text instead.
    public static let machineCredentialNotice = "Admin Key 与管理访问令牌不能做二次验证，请改用账号登录"
    public static let totpNotEnabledTitle = "需要先在 Web 端开启二次验证"

    /// The backend's guard order (middleware/step_up.go): the site switch, then machine credentials, then TOTP, then the
    /// grant. An unknown switch (old server) sends without asking and leaves it to a STEP_UP_REQUIRED refusal.
    public static func requirement(security: AdminMe.Security, authMethod: AdminAuthMethod?, grantExpiresAt: Date?, now: Date) -> StepUpRequirement {
        guard security.stepUpEnabled == true else { return .notRequired }
        if authMethod?.isMachineCredential == true { return .machineCredential }
        if security.totpEnabled == false { return .totpNotEnabled }
        if let grantExpiresAt, grantExpiresAt > now { return .notRequired }
        return .verify
    }
    /// The later of `/admin/me`'s grant (read time plus `step_up_expires_in`, only while granted) and the local record. A
    /// missing or non-positive remainder is unknown, not granted.
    public static func grantExpiry(security: AdminMe.Security, fetchedAt: Date?, localGrant: Date?) -> Date? {
        var reported: Date?
        if security.stepUpGranted == true, let seconds = security.stepUpExpiresIn, seconds > 0, let fetchedAt {
            reported = fetchedAt.addingTimeInterval(TimeInterval(seconds))
        }
        return [reported, localGrant].compactMap { $0 }.max()
    }
}

/// `POST /api/v1/user/totp/step-up` → `{verified, expires_in}`; an unreadable `expires_in` is unknown.
public struct StepUpGrant: Decodable, Sendable, Equatable {
    public let verified: Bool
    public let expiresIn: Int?
    public init(verified: Bool, expiresIn: Int?) { self.verified = verified; self.expiresIn = expiresIn }
    enum CodingKeys: String, CodingKey { case verified, expiresIn = "expires_in" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verified = try c.decode(Bool.self, forKey: .verified)
        expiresIn = try? c.decodeIfPresent(Int.self, forKey: .expiresIn)
    }
    /// The local expiry to record: now plus `expires_in` (00 §2.6.2 step 3); nil when the server did not say.
    public func expiresAt(from now: Date) -> Date? {
        guard let expiresIn, expiresIn > 0 else { return nil }
        return now.addingTimeInterval(TimeInterval(expiresIn))
    }
}

/// What the verification sheet does with a failed `stepUp` (00 §2.6.2 table).
public enum StepUpFailure: Equatable, Sendable {
    /// Clear the code and type again.
    case retype(String)
    /// Close the sheet; the operation stays unverified.
    case close(String)
    /// Keep the sheet and the session; try again later.
    case keep(String)
    /// Show the “turn on TOTP in Web” notice (TOTP_NOT_SETUP: TOTP was turned off after `/admin/me` was read).
    case totpNotEnabled
    /// The session ended or the request was cancelled: close without a message, the session layer explains.
    case sessionEnded

    static let unavailable = "二次验证服务暂时不可用，请稍后重试"

    public init(_ error: any Error) {
        guard let error = error as? APIError else {
            self = error is CancellationError ? .sessionEnded : .keep(APIError.transport(error).localizedDescription)
            return
        }
        if error.action == .clearSession || error.action == .clearCredential { self = .sessionEnded; return }
        switch (error.statusCode, error.reason) {
        case (_, "TOTP_INVALID_CODE"?): self = .retype(error.localizedDescription)
        case (_, "TOTP_TOO_MANY_ATTEMPTS"?): self = .close(error.localizedDescription)
        case (_, "TOTP_NOT_SETUP"?), (_, "STEP_UP_TOTP_NOT_ENABLED"?): self = .totpNotEnabled
        case (let status?, _) where (500..<600).contains(status): self = .keep(Self.unavailable)
        case (nil, _) where error.kind == .twoFactor: self = .retype(error.localizedDescription)
        default: self = .keep(error.localizedDescription)
        }
    }
}

/// The 6-digit code of 00 §2.6.2 step 3 and the login's second factor (S0-16).
public enum OneTimeCode {
    public static let length = 6
    /// ASCII digits only (full-width digits and letters are dropped), at most six.
    public static func sanitize(_ raw: String) -> String {
        String(String.UnicodeScalarView(raw.unicodeScalars.filter { ("0"..."9").contains($0) }.prefix(length)))
    }
    public static func isComplete(_ code: String) -> Bool { code.utf8.count == length && code.utf8.allSatisfy { (48...57).contains($0) } }
}

extension APIClient {
    /// 00 §2.6.2 step 3 (JWT only). A malformed code is refused locally and never sent; the caller records the expiry.
    public func stepUp(code: String) async throws -> StepUpGrant {
        guard OneTimeCode.isComplete(code) else { throw APIError(kind: .twoFactor, message: "请输入六位双因素验证码。") }
        let grant: StepUpGrant = try await request("user/totp/step-up", method: "POST", body: encode(["code": code]))
        guard grant.verified else { throw APIError(kind: .twoFactor, message: "二次验证未通过。") }
        return grant
    }
}
