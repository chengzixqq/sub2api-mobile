import Foundation

public enum CaptchaBridgeResult: Sendable { case proof(CaptchaProof), cancelled }

/// Validates message contents only. Native WebKit must additionally enforce main-frame origin and nonce expiry.
public enum CaptchaBridgeValidator {
    public static func parse(_ data: Data, nonce: UUID, provider: String) throws -> CaptchaBridgeResult {
        do {
            guard data.count <= 65_536, CaptchaBridge.providers.contains(provider),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw invalidMessage }
            // Codable deliberately avoids NSNumber's Bool/Int bridging: true cannot be accepted as version 1.
            let header = try JSONDecoder().decode(Header.self, from: data)
            guard header.version == 1, header.nonce == nonce.uuidString else { throw invalidMessage }
            if Set(object.keys) == Set(["version", "nonce", "cancelled"]) {
                guard header.cancelled == true else { throw invalidMessage }
                return .cancelled
            }
            guard Set(object.keys) == Set(["version", "nonce", "provider", "proof"]),
                  let receivedProvider = object["provider"] as? String, receivedProvider == provider,
                  let proof = object["proof"] as? [String: Any] else { throw invalidMessage }
            if provider == "tencent" {
                guard Set(proof.keys) == Set(["tencent_captcha_ticket", "tencent_captcha_randstr"]) else { throw invalidMessage }
                return .proof(CaptchaProof(provider: provider, tencentTicket: try token(proof["tencent_captcha_ticket"]),
                                           tencentRandstr: try token(proof["tencent_captcha_randstr"])))
            }
            guard Set(proof.keys) == Set(["turnstile_token"]) else { throw invalidMessage }
            // Aliyun's verify param arrives as turnstile_token; old servers read it there, new ones as aliyun_captcha_param (00 §1.5).
            let value = try token(proof["turnstile_token"])
            return .proof(CaptchaProof(provider: provider, turnstileToken: value, aliyunParam: provider == "aliyun" ? value : nil))
        } catch { throw invalidMessage }
    }
    private struct Header: Decodable { let version: Int; let nonce: String; let cancelled: Bool? }
    private static func token(_ value: Any?) throws -> String {
        guard let token = value as? String, token.utf8.count <= 16_384,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalidMessage }
        return token
    }
    private static var invalidMessage: APIError { APIError(kind: .captcha, reason: "INVALID_CAPTCHA_BRIDGE_MESSAGE", message: "验证码返回结果无效，请关闭页面后重新验证。") }
}
