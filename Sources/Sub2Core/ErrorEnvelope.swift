import Foundation

/// 00 §3.1 error body. Handler errors carry an integer `code`, middleware errors a string `code`.
/// `message` is deliberately not decoded so it can never reach the UI or logs (00 §3.4).
public struct ErrorEnvelope: Decodable, Sendable, Equatable {
    public enum Code: Sendable, Equatable { case int(Int), string(String) }
    public let code: Code?
    public let reason: String?
    /// Server metadata values are always strings; numbers and booleans are converted, nested values dropped.
    public let metadata: [String: String]?
    public let retryAfter: Int?

    public init(code: Code? = nil, reason: String? = nil, metadata: [String: String]? = nil, retryAfter: Int? = nil) {
        self.code = code; self.reason = reason; self.metadata = metadata; self.retryAfter = retryAfter
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Every field is tolerant on its own, so one unexpected type never drops the reason.
        if let value = try? c.decodeIfPresent(Int.self, forKey: .code) { code = .int(value) }
        else if let value = try? c.decodeIfPresent(String.self, forKey: .code) { code = .string(value) }
        else { code = nil }
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        metadata = Self.stringValues(c, forKey: .metadata)
        if let seconds = try? c.decodeIfPresent(Int.self, forKey: .retryAfter) { retryAfter = seconds >= 0 ? seconds : nil }
        else { retryAfter = RetryAfter.seconds(try? c.decodeIfPresent(String.self, forKey: .retryAfter)) }
    }

    /// Non-empty reason, otherwise a middleware string code.
    public var marker: String? {
        if let reason = Self.nonEmpty(reason) { return reason }
        if case .string(let value) = code { return Self.nonEmpty(value) }
        return nil
    }
    public var isSuccess: Bool { code == .int(0) }

    /// nil means the body is not a JSON object: gateway text 404, proxy HTML, an empty body or an array.
    public static func decode(_ data: Data) -> ErrorEnvelope? { try? JSONDecoder().decode(ErrorEnvelope.self, from: data) }

    private enum CodingKeys: String, CodingKey { case code, reason, metadata, retryAfter = "retry_after" }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    private static func stringValues(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> [String: String]? {
        guard let nested = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: key) else { return nil }
        var values = [String: String]()
        for item in nested.allKeys {
            if let value = try? nested.decode(String.self, forKey: item) { values[item.stringValue] = value }
            else if let value = try? nested.decode(Int.self, forKey: item) { values[item.stringValue] = String(value) }
            else if let value = try? nested.decode(Double.self, forKey: item) { values[item.stringValue] = String(value) }
            else if let value = try? nested.decode(Bool.self, forKey: item) { values[item.stringValue] = String(value) }
        }
        return values
    }
}

/// 00 §2.7.2: `Retry-After` header, then top-level `retry_after`, then `metadata.retry_after`.
public enum RetryAfter {
    /// Used only for wording and scheduling when none of the sources is present.
    public static let rateLimitDefault = 30

    public static func seconds(_ raw: String?) -> Int? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(text)
    }
    public static func resolve(headers: [String: String], envelope: ErrorEnvelope?) -> Int? {
        seconds(headers.headerValue("Retry-After")) ?? envelope?.retryAfter ?? seconds(envelope?.metadata?["retry_after"])
    }
}
