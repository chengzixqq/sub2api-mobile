import Foundation

/// The native client declaration of `POST /api/v1/auth/login` (00 §1.2). Only APIClient builds it, from the same string it sends as X-Device-ID.
struct LoginClient: Encodable, Sendable, Equatable {
    let type = "ios"
    let deviceID: String
    let deviceName: String
    enum CodingKeys: String, CodingKey { case type, deviceID = "device_id", deviceName = "device_name" }
}

/// 00 §1.4 step 2. Captcha fields follow the bridge table of 00 §1.5; absent values are left out of the JSON.
struct LoginBody: Encodable {
    let email: String
    let password: String
    let client: LoginClient
    let captchaProvider: String?
    let turnstileToken: String?
    let tencentTicket: String?
    let tencentRandstr: String?
    let aliyunParam: String?
    enum CodingKeys: String, CodingKey {
        case email, password, client, captchaProvider = "captcha_provider", turnstileToken = "turnstile_token"
        case tencentTicket = "tencent_captcha_ticket", tencentRandstr = "tencent_captcha_randstr", aliyunParam = "aliyun_captcha_param"
    }

    /// `declaresCaptchaProvider` is `PublicSettings.hasCaptchaProviderKey`: older servers know neither `captcha_provider`
    /// nor `aliyun_captcha_param` and read Aliyun's verify param from `turnstile_token`.
    init(email: String, password: String, client: LoginClient, proof: CaptchaProof?, declaresCaptchaProvider: Bool) {
        self.email = email; self.password = password; self.client = client
        let isAliyun = proof?.provider == "aliyun"
        let aliyunProof = isAliyun ? proof?.aliyunParam ?? proof?.turnstileToken : nil
        captchaProvider = declaresCaptchaProvider ? proof?.provider : nil
        aliyunParam = declaresCaptchaProvider ? aliyunProof : nil
        turnstileToken = isAliyun ? (declaresCaptchaProvider ? nil : aliyunProof) : proof?.turnstileToken
        tencentTicket = proof?.tencentTicket; tencentRandstr = proof?.tencentRandstr
    }
}

/// Sign-in and second-factor reply (00 §1.4). `refresh_token_unavailable` marks a login that issued no refresh token.
struct LoginReply: Decodable, Sendable {
    let requires2FA: Bool?; let tempToken: String?; let maskedEmail: String?
    let accessToken: String?; let refreshToken: String?; let expiresIn: Int?; let refreshTokenUnavailable: Bool?; let user: AdminUser?
    enum CodingKeys: String, CodingKey {
        case requires2FA = "requires_2fa", tempToken = "temp_token", maskedEmail = "user_email_masked"
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in"
        case refreshTokenUnavailable = "refresh_token_unavailable", user
    }
}
