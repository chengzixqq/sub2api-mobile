import Foundation

public struct AccountTestEvent: Decodable, Sendable, Equatable {
    public let type: String
    public let content: String?
    public let message: String?
    public let success: Bool?
    public var isTerminal: Bool { type == "test_complete" || type == "error" }
    public var isSuccess: Bool { type == "test_complete" && success == true }
    public init(type: String, content: String? = nil, message: String? = nil, success: Bool? = nil) {
        self.type = type; self.content = content; self.message = message; self.success = success
    }
    enum CodingKeys: String, CodingKey { case type, text, content, error, message, success }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        content = try c.decodeIfPresent(String.self, forKey: .text) ?? c.decodeIfPresent(String.self, forKey: .content)
        message = try c.decodeIfPresent(String.self, forKey: .error) ?? c.decodeIfPresent(String.self, forKey: .message)
        success = try c.decodeIfPresent(Bool.self, forKey: .success)
    }
}

/// Incremental byte parser: UTF-8 characters, CRLF and SSE frames can straddle arbitrary network chunks.
public struct AccountSSEParser: Sendable {
    private var buffer = Data()
    private var dataLines = [String]()
    private var frameBytes = 0
    public private(set) var receivedTerminal = false
    public init() {}
    public mutating func append(_ chunk: Data) throws -> [AccountTestEvent] {
        guard !receivedTerminal else { return [] }
        buffer.append(chunk)
        var events = [AccountTestEvent]()
        while let end = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            if line.last == 0x0D { line.removeLast() }
            if let event = try consume(line) { events.append(event); if event.isTerminal { buffer.removeAll(); break } }
        }
        guard buffer.count + frameBytes <= 1_048_576 else { throw APIError.malformedStream }
        return events
    }
    public mutating func finish() throws -> [AccountTestEvent] {
        // An unterminated frame is not proof of completion. Only a complete SSE frame commits a test result.
        guard receivedTerminal else { throw APIError.incompleteStream }
        return []
    }
    private mutating func consume(_ bytes: Data) throws -> AccountTestEvent? {
        guard let line = String(data: bytes, encoding: .utf8) else { throw APIError.malformedStream }
        frameBytes += bytes.count
        guard frameBytes <= 1_048_576 else { throw APIError.malformedStream }
        if line.isEmpty {
            defer { dataLines.removeAll(keepingCapacity: true); frameBytes = 0 }
            guard !dataLines.isEmpty else { return nil }
            let data = Data(dataLines.joined(separator: "\n").utf8)
            let event: AccountTestEvent
            do { event = try JSONDecoder().decode(AccountTestEvent.self, from: data) }
            catch { throw APIError.malformedStream }
            receivedTerminal = event.isTerminal
            return event
        }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            dataLines.append(value)
        }
        return nil // Comments, event, retry and id fields are not application data.
    }
}
