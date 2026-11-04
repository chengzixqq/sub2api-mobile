import Foundation

/// `GET /api/v1/admin/compliance` (00 §1.10). The only compliance model; acceptance is added here as well.
public struct AdminComplianceStatus: Decodable, Sendable, Equatable {
    public struct Acknowledgement: Decodable, Sendable, Equatable {
        public let version: String?
        public let acceptedAt: String?
        enum CodingKeys: String, CodingKey { case version, acceptedAt = "accepted_at" }
    }
    public let required: Bool?
    public let version: String?
    public let documentPathZH: String?
    public let documentPathEN: String?
    public let documentURLZH: String?
    public let documentURLEN: String?
    public let ackPhraseZH: String?
    public let ackPhraseEN: String?
    public let acknowledgement: Acknowledgement?
    public init(required: Bool? = nil, version: String? = nil, documentPathZH: String? = nil, documentPathEN: String? = nil,
                documentURLZH: String? = nil, documentURLEN: String? = nil, ackPhraseZH: String? = nil, ackPhraseEN: String? = nil,
                acknowledgement: Acknowledgement? = nil) {
        self.required = required; self.version = version; self.documentPathZH = documentPathZH; self.documentPathEN = documentPathEN
        self.documentURLZH = documentURLZH; self.documentURLEN = documentURLEN; self.ackPhraseZH = ackPhraseZH; self.ackPhraseEN = ackPhraseEN
        self.acknowledgement = acknowledgement
    }
    enum CodingKeys: String, CodingKey {
        case required, version, acknowledgement
        case documentPathZH = "document_path_zh", documentPathEN = "document_path_en"
        case documentURLZH = "document_url_zh", documentURLEN = "document_url_en"
        case ackPhraseZH = "ack_phrase_zh", ackPhraseEN = "ack_phrase_en"
    }
}

extension AdminComplianceStatus {
    /// Compared like the backend: both sides trimmed, then byte for byte (no Unicode normalisation). An empty phrase never matches.
    public func phraseMatches(_ input: String) -> Bool {
        guard let expected = ackPhraseZH?.trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty else { return false }
        return input.trimmingCharacters(in: .whitespacesAndNewlines).utf8.elementsEqual(expected.utf8)
    }
    /// `document_url_zh` when it is HTTPS, otherwise the site plus `document_path_zh`; nil when neither opens in Safari.
    public func documentURL(site: URL) -> URL? {
        if let url = Self.httpsURL(documentURLZH) { return url }
        guard let path = documentPathZH?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
              var components = URLComponents(url: site, resolvingAgainstBaseURL: false) else { return nil }
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.query = nil; components.fragment = nil
        return Self.httpsURL(components.url?.absoluteString)
    }
    /// 00 §1.10: a read-only `sat_` cannot accept; a mismatched phrase keeps the input. Never the server's message.
    public static func acceptFailureMessage(for error: any Error) -> String {
        guard let error = error as? APIError else { return APIError.transport(error).localizedDescription }
        switch (error.statusCode, error.reason) {
        case (403, "ACCESS_TOKEN_READ_ONLY"?): return "只读令牌不能完成合规确认，请用账号登录或在 Web 完成"
        case (400, "ADMIN_COMPLIANCE_INVALID_PHRASE"?): return "确认语句不一致，请逐字输入"
        default: return error.localizedDescription
        }
    }
    private static func httpsURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: raw),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}

extension APIClient {
    /// Exempt from the compliance guard, which also makes it the Admin Key permission probe on old servers (00 §1.9).
    public func complianceStatus() async throws -> AdminComplianceStatus {
        try await request("admin/compliance", timeout: RequestTimeout.probe)
    }
    /// 00 §1.10: sent once, without a key; a successful answer has `required=false`.
    public func acceptCompliance(phrase: String) async throws -> AdminComplianceStatus {
        try await request("admin/compliance/accept", method: "POST", body: encode(["language": "zh", "phrase": phrase]))
    }
}
