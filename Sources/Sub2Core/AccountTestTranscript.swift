import Foundation

/// Redaction of everything the account test shows (20 §4.3): bearer tokens, `sk-…` keys and URLs read “[已隐藏]”.
public enum AccountTestOutput {
    public static let hidden = "[已隐藏]"
    public static let maxLineLength = 8_192
    public static let maxLines = 500
    /// Redacted, then cut to `maxLineLength` characters.
    public static func sanitize(_ text: String) -> String { String(redact(text).prefix(maxLineLength)) }
    static func redact(_ text: String) -> String {
        patterns.reduce(text) { $0.replacingOccurrences(of: $1, with: hidden, options: .regularExpression) }
    }
    /// Trimmed, or nil when blank.
    static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
    private static let patterns = [#"(?i)Bearer\s+[^\s]+"#, #"(?i)sk-[A-Za-z0-9_-]{6,}"#, #"(?i)https?://[^\s]+"#]
}

/// “首字 · 总耗时”: the server's trace (C07, C08), or this phone's monotonic clock when the server reports none.
public struct AccountTestTiming: Sendable, Equatable {
    public let firstTokenMs: Int?
    public let totalMs: Int
    public let isLocal: Bool
    public init(firstTokenMs: Int?, totalMs: Int, isLocal: Bool) { self.firstTokenMs = firstTokenMs; self.totalMs = totalMs; self.isLocal = isLocal }
    /// Whole milliseconds, rounded down.
    public static func local(started: ContinuousClock.Instant, firstOutput: ContinuousClock.Instant?,
                             finished: ContinuousClock.Instant) -> AccountTestTiming {
        AccountTestTiming(firstTokenMs: firstOutput.map { milliseconds($0 - started) }, totalMs: milliseconds(finished - started), isLocal: true)
    }
    private static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return max(0, Int(parts.seconds) * 1_000 + Int(parts.attoseconds / 1_000_000_000_000_000))
    }
}

/// The events of one test folded into output lines and a verdict (S2D1-01). Content chunks are joined into whole lines before
/// redaction, so a key split across chunks is still hidden; status, error (“✕ …”) and media (“← 收到图片”) are lines of their own.
/// Only the latest `maxLines` lines are kept.
public struct AccountTestTranscript: Sendable, Equatable {
    public private(set) var lines = [String]()
    /// Every line ever added, including the ones dropped from `lines`.
    public private(set) var lineCount = 0
    /// test_start's model, redacted.
    public private(set) var model: String?
    /// test_complete's `success`; a missing one is false.
    public private(set) var completion: Bool?
    /// The last error event's text, redacted.
    public private(set) var errorText: String?
    public private(set) var result: AccountTestResult?
    public private(set) var receivedTestResult = false
    private var sawError = false
    private var pending = ""
    private let startedAt: ContinuousClock.Instant
    private var firstOutputAt: ContinuousClock.Instant?
    private var concludedAt: ContinuousClock.Instant?
    private var finishedAt: ContinuousClock.Instant?

    public init(startedAt: ContinuousClock.Instant) { self.startedAt = startedAt }

    public mutating func apply(_ event: AccountTestEvent, at instant: ContinuousClock.Instant) {
        if event.producesOutput, firstOutputAt == nil { firstOutputAt = instant }
        switch event.type {
        case "test_start": model = AccountTestOutput.nonBlank(event.model).map(AccountTestOutput.sanitize)
        case "content": appendContent(event.content ?? "")
        case "status": addSeparateLine(AccountTestOutput.nonBlank(event.content ?? event.status).map(AccountTestOutput.sanitize))
        case "image", "audio", "video": addSeparateLine("← 收到" + Self.mediaNames[event.type, default: ""])
        case "error":
            let text = AccountTestOutput.nonBlank(event.message ?? event.content).map(AccountTestOutput.sanitize)
            sawError = true; errorText = text ?? errorText
            addSeparateLine(text.map { "✕ " + $0 } ?? "✕")
            conclude(at: instant)
        case "test_complete": completion = event.success ?? false; conclude(at: instant)
        case "test_result": result = event.data; receivedTestResult = true; conclude(at: instant)
        default: break
        }
    }
    /// The stream ended: an unfinished content line becomes a line.
    public mutating func finish(at instant: ContinuousClock.Instant) {
        flush()
        if finishedAt == nil { finishedAt = instant }
    }
    /// `lines` plus the unfinished content line, redacted.
    public var displayLines: [String] {
        guard !pending.isEmpty else { return lines }
        return Array((lines + [AccountTestOutput.sanitize(pending)]).suffix(AccountTestOutput.maxLines))
    }
    /// Up to the first verdict (test_complete, error or test_result), else to `finish`; nil before either.
    public var localTiming: AccountTestTiming? {
        (concludedAt ?? finishedAt).map { AccountTestTiming.local(started: startedAt, firstOutput: firstOutputAt, finished: $0) }
    }
    /// C07: present once test_result carried a readable payload.
    public var serverOutcome: AccountTestOutcome? { result.map { AccountTestOutcome(result: $0, errorText: errorText) } }
    /// Old servers: an error event fails the test, otherwise test_complete decides; nil without either.
    public var legacyPassed: Bool? { sawError ? false : completion }

    private static let mediaNames = ["image": "图片", "audio": "音频", "video": "视频"]

    private mutating func conclude(at instant: ContinuousClock.Instant) { if concludedAt == nil { concludedAt = instant } }
    private mutating func appendContent(_ text: String) {
        pending += text
        // "\r\n" is one Character; a "\r" ending the chunk waits, since the next chunk may start with its "\n".
        while let newline = pending.firstIndex(where: \.isNewline),
              !(pending[newline] == "\r" && pending.index(after: newline) == pending.endIndex) {
            let line = String(pending[..<newline])
            pending = String(pending[pending.index(after: newline)...])
            addLine(AccountTestOutput.sanitize(line))
        }
        guard pending.count > AccountTestOutput.maxLineLength else { return }
        // A line with no end in sight is cut into whole-length lines; the rest keeps waiting for its newline.
        var rest = AccountTestOutput.redact(pending)
        while rest.count > AccountTestOutput.maxLineLength {
            addLine(String(rest.prefix(AccountTestOutput.maxLineLength)))
            rest = String(rest.dropFirst(AccountTestOutput.maxLineLength))
        }
        pending = rest
    }
    private mutating func flush() {
        guard !pending.isEmpty else { return }
        var line = pending; pending = ""
        if line.last == "\r" { line.removeLast() }
        addLine(AccountTestOutput.sanitize(line))
    }
    /// Status, error and media lines end the content line in progress.
    private mutating func addSeparateLine(_ line: String?) {
        flush()
        if let line { addLine(line) }
    }
    private mutating func addLine(_ line: String) {
        lines.append(line); lineCount += 1
        if lines.count > AccountTestOutput.maxLines { lines.removeFirst(lines.count - AccountTestOutput.maxLines) }
    }
}
