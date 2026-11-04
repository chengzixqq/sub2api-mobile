import Foundation

public struct AccountTestEvent: Decodable, Sendable, Equatable {
    public let type: String
    public let content: String?
    public let message: String?
    public let success: Bool?
    /// test_start's model.
    public let model: String?
    public let status: String?
    /// test_result's payload (C07); nil on other events and when the payload cannot be read.
    public let data: AccountTestResult?
    public var isSuccess: Bool { type == "test_complete" && success == true }
    public var isTestResult: Bool { type == "test_result" }
    /// What an old server (no accounts.test_result) concludes with.
    public var isLegacyConclusion: Bool { type == "test_complete" || type == "error" }
    /// Upstream output: the first one is the local first-token mark.
    public var producesOutput: Bool { ["content", "image", "audio", "video"].contains(type) }
    public init(type: String, content: String? = nil, message: String? = nil, success: Bool? = nil, model: String? = nil,
                status: String? = nil, data: AccountTestResult? = nil) {
        self.type = type; self.content = content; self.message = message; self.success = success
        self.model = model; self.status = status; self.data = data
    }
    enum CodingKeys: String, CodingKey { case type, text, content, error, message, success, model, status, data }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        content = try c.decodeIfPresent(String.self, forKey: .text) ?? c.decodeIfPresent(String.self, forKey: .content)
        message = try c.decodeIfPresent(String.self, forKey: .error) ?? c.decodeIfPresent(String.self, forKey: .message)
        success = try c.decodeIfPresent(Bool.self, forKey: .success)
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        data = type == "test_result" ? try? c.decodeIfPresent(AccountTestResult.self, forKey: .data) : nil
    }
}

/// `test_result.data` (backend `service.AccountTestResult`). Only `success` is required; every other field may be missing,
/// null or malformed and then reads as nil.
public struct AccountTestResult: Decodable, Sendable, Equatable {
    public struct Usage: Decodable, Sendable, Equatable {
        public let inputTokens: Int
        public let outputTokens: Int
        public init(inputTokens: Int, outputTokens: Int) { self.inputTokens = inputTokens; self.outputTokens = outputTokens }
        enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens", outputTokens = "output_tokens" }
    }
    /// The account after the test and its recovery.
    public struct AccountState: Decodable, Sendable, Equatable {
        public let status: String
        public let schedulable: Bool
        public let rateLimitResetAt: Date?
        public let tempUnschedulableUntil: Date?
        public let errorSummary: String?
        public let errorKind: String?
        public init(status: String, schedulable: Bool, rateLimitResetAt: Date? = nil, tempUnschedulableUntil: Date? = nil,
                    errorSummary: String? = nil, errorKind: String? = nil) {
            self.status = status; self.schedulable = schedulable; self.rateLimitResetAt = rateLimitResetAt
            self.tempUnschedulableUntil = tempUnschedulableUntil
            self.errorSummary = AccountTestOutput.nonBlank(errorSummary); self.errorKind = AccountTestOutput.nonBlank(errorKind)
        }
        enum CodingKeys: String, CodingKey {
            case status, schedulable, rateLimitResetAt = "rate_limit_reset_at", tempUnschedulableUntil = "temp_unschedulable_until"
            case errorSummary = "error_summary", errorKind = "error_kind"
        }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(status: try c.decode(String.self, forKey: .status), schedulable: try c.decode(Bool.self, forKey: .schedulable),
                      rateLimitResetAt: try c.optionalTimestamp(.rateLimitResetAt),
                      tempUnschedulableUntil: try c.optionalTimestamp(.tempUnschedulableUntil),
                      errorSummary: try? c.decodeIfPresent(String.self, forKey: .errorSummary),
                      errorKind: try? c.decodeIfPresent(String.self, forKey: .errorKind))
        }
    }
    public struct Recovery: Decodable, Sendable, Equatable {
        public let clearedError: Bool
        public let clearedRateLimit: Bool
        public init(clearedError: Bool, clearedRateLimit: Bool) { self.clearedError = clearedError; self.clearedRateLimit = clearedRateLimit }
        enum CodingKeys: String, CodingKey { case clearedError = "cleared_error", clearedRateLimit = "cleared_rate_limit" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            clearedError = (try? c.decodeIfPresent(Bool.self, forKey: .clearedError)) ?? false
            clearedRateLimit = (try? c.decodeIfPresent(Bool.self, forKey: .clearedRateLimit)) ?? false
        }
    }
    /// What the test itself wrote, from comparing the account before and after (best effort on the server).
    public struct Marked: Decodable, Sendable, Equatable {
        public let error: Bool
        public let rateLimited: Bool
        public let tempUnschedulable: Bool
        public init(error: Bool, rateLimited: Bool, tempUnschedulable: Bool) {
            self.error = error; self.rateLimited = rateLimited; self.tempUnschedulable = tempUnschedulable
        }
        enum CodingKeys: String, CodingKey { case error, rateLimited = "rate_limited", tempUnschedulable = "temp_unschedulable" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            error = (try? c.decodeIfPresent(Bool.self, forKey: .error)) ?? false
            rateLimited = (try? c.decodeIfPresent(Bool.self, forKey: .rateLimited)) ?? false
            tempUnschedulable = (try? c.decodeIfPresent(Bool.self, forKey: .tempUnschedulable)) ?? false
        }
    }
    /// The verdict: the event's top-level `success` drops false, so only this one counts.
    public let success: Bool
    public let startedAt: Date?
    public let firstTokenMs: Int?
    public let totalMs: Int?
    public let upstreamStatus: Int?
    public let usage: Usage?
    public let account: AccountState?
    public let recovery: Recovery?
    public let marked: Marked?
    public init(success: Bool, startedAt: Date? = nil, firstTokenMs: Int? = nil, totalMs: Int? = nil, upstreamStatus: Int? = nil,
                usage: Usage? = nil, account: AccountState? = nil, recovery: Recovery? = nil, marked: Marked? = nil) {
        self.success = success; self.startedAt = startedAt; self.firstTokenMs = firstTokenMs; self.totalMs = totalMs
        self.upstreamStatus = upstreamStatus; self.usage = usage; self.account = account; self.recovery = recovery; self.marked = marked
    }
    enum CodingKeys: String, CodingKey {
        case success, startedAt = "started_at", firstTokenMs = "first_token_ms", totalMs = "total_ms", upstreamStatus = "upstream_status"
        case usage, account, recovery, marked
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decode(Bool.self, forKey: .success)
        startedAt = try c.optionalTimestamp(.startedAt)
        firstTokenMs = try? c.decodeIfPresent(Int.self, forKey: .firstTokenMs)
        totalMs = try? c.decodeIfPresent(Int.self, forKey: .totalMs)
        upstreamStatus = try? c.decodeIfPresent(Int.self, forKey: .upstreamStatus)
        usage = try? c.decodeIfPresent(Usage.self, forKey: .usage)
        account = try? c.decodeIfPresent(AccountState.self, forKey: .account)
        recovery = try? c.decodeIfPresent(Recovery.self, forKey: .recovery)
        marked = try? c.decodeIfPresent(Marked.self, forKey: .marked)
    }
}

/// Incremental byte parser: UTF-8 characters, CRLF and SSE frames can straddle arbitrary network chunks.
/// With accounts.test_result (C07) only test_result ends the stream: an error is followed by one. An old server is read to
/// EOF, because it recovers the account after test_complete on the request's context; test_complete / error give the verdict.
public struct AccountSSEParser: Sendable {
    private let expectsTestResult: Bool
    private var buffer = Data()
    private var dataLines = [String]()
    private var frameBytes = 0
    /// Stop reading now: only test_result, and only when it is expected.
    public private(set) var receivedTerminal = false
    /// A verdict arrived: test_result, or on an old server test_complete / error.
    public private(set) var receivedConclusion = false
    public init(expectsTestResult: Bool = false) { self.expectsTestResult = expectsTestResult }
    public mutating func append(_ chunk: Data) throws -> [AccountTestEvent] {
        guard !receivedTerminal else { return [] }
        buffer.append(chunk)
        var events = [AccountTestEvent]()
        while let end = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            if line.last == 0x0D { line.removeLast() }
            if let event = try consume(line) { events.append(event); if receivedTerminal { buffer.removeAll(); break } }
        }
        guard buffer.count + frameBytes <= 1_048_576 else { throw APIError.malformedStream }
        return events
    }
    public mutating func finish() throws -> [AccountTestEvent] {
        // An unterminated frame is not proof of completion. Only a complete SSE frame commits a test result.
        guard receivedConclusion else { throw APIError.incompleteStream }
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
            note(event)
            return event
        }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            dataLines.append(value)
        }
        return nil // Comments, event, retry and id fields are not application data.
    }
    private mutating func note(_ event: AccountTestEvent) {
        if expectsTestResult {
            if event.isTestResult { receivedTerminal = true; receivedConclusion = true }
        } else if event.isLegacyConclusion {
            receivedConclusion = true
        }
    }
}
