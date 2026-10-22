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
    enum CodingKeys: String, CodingKey {
        case required, version, acknowledgement
        case documentPathZH = "document_path_zh", documentPathEN = "document_path_en"
        case documentURLZH = "document_url_zh", documentURLEN = "document_url_en"
        case ackPhraseZH = "ack_phrase_zh", ackPhraseEN = "ack_phrase_en"
    }
}

extension APIClient {
    /// Exempt from the compliance guard, which also makes it the Admin Key permission probe on old servers (00 §1.9).
    public func complianceStatus() async throws -> AdminComplianceStatus {
        try await request("admin/compliance", timeout: Self.probeTimeout)
    }
}
