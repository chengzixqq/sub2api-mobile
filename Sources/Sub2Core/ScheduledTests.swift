import Foundation

// 20 §9 定时测试（只读, S2-21）: an account's plans, the primary plan's newest results, and how the detail's row and the small
// page word them. Plans are kept in the Web; the App never writes them.

/// S2D1-15: a success body that is the bare value instead of `{code, data}`: both scheduled-test reads answer
/// `c.JSON(200, list)`, and `null` when there is nothing. APIClient.decode reads it before the envelope; a body that is an object
/// with `code` is still read as an envelope, so a server that adds one later keeps working.
protocol UnenvelopedReply: Decodable, Sendable {
    static func decodeUnenveloped(_ data: Data) throws -> Self
}
extension UnenvelopedReply {
    static func decodeUnenveloped(_ data: Data) throws -> Self { try JSONDecoder().decode(Self.self, from: data) }
    /// nil for an envelope after all; anything else that does not decode is `invalidResponse`.
    static func unenveloped(_ data: Data) throws -> Self? {
        let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        if let fields = object as? [String: Any], fields["code"] != nil { return nil }
        do { return try decodeUnenveloped(data) } catch { throw APIError.invalidResponse }
    }
}

/// A bare list read element by element (LenientDecoded): `null` is empty and an element without an id is dropped.
struct UnenvelopedList<Element: Decodable & Sendable>: UnenvelopedReply {
    let items: [Element]
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        items = container.decodeNil() ? [] : try container.decode([LenientDecoded<Element>].self).compactMap(\.value)
    }
}

/// `GET admin/accounts/:id/scheduled-test-plans`, newest first. Only what the App shows is read; every field may be missing.
public struct ScheduledTestPlan: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    /// Blank means the account's default model.
    public let modelID: String?
    public let cronExpression: String?
    /// Missing reads as off.
    public let enabled: Bool

    public init(id: Int, modelID: String? = nil, cronExpression: String? = nil, enabled: Bool = false) {
        self.id = id; self.modelID = modelID; self.cronExpression = cronExpression; self.enabled = enabled
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        modelID = c.lenientValue(.modelID)
        cronExpression = c.lenientValue(.cronExpression)
        enabled = c.lenientValue(.enabled) ?? false
    }
    private enum CodingKeys: String, CodingKey { case id, enabled; case modelID = "model_id", cronExpression = "cron_expression" }
}

/// `GET admin/scheduled-test-plans/:id/results`, newest first. `error_message` is read only for its status code (20 §0.1) and
/// is never kept, so neither the page nor a description can show it; `response_text` is not read at all.
public struct ScheduledTestResult: Decodable, Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable { case success, failed, other(String) }
    public let id: Int
    public let status: Status?
    public let latencyMs: Int?
    public let startedAt: Date?
    /// `scheduled_tests.upstream_status`; null when the test saw no upstream reply.
    public let upstreamStatusCode: Int?
    public let errorKind: String?
    /// The code `error_message` names, by the 20 §0.1 pattern.
    let messageStatusCode: Int?

    public init(id: Int, status: Status? = nil, latencyMs: Int? = nil, startedAt: Date? = nil, upstreamStatusCode: Int? = nil,
                errorKind: String? = nil, errorMessage: String? = nil) {
        self.id = id; self.status = status; self.latencyMs = latencyMs; self.startedAt = startedAt
        self.upstreamStatusCode = upstreamStatusCode; self.errorKind = errorKind
        messageStatusCode = ScheduledTestsPresentation.parsedStatusCode(errorMessage)
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let status: String? = c.lenientValue(.status)
        self.init(id: try c.decode(Int.self, forKey: .id), status: status.map(Self.parseStatus), latencyMs: c.lenientValue(.latencyMs),
                  startedAt: try c.optionalTimestamp(.startedAt), upstreamStatusCode: c.lenientValue(.upstreamStatusCode),
                  errorKind: c.lenientValue(.errorKind), errorMessage: c.lenientValue(.errorMessage))
    }
    private static func parseStatus(_ raw: String) -> Status {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "success": .success
        case "failed": .failed
        default: .other(raw)
        }
    }
    private enum CodingKeys: String, CodingKey {
        case id, status
        case latencyMs = "latency_ms", startedAt = "started_at", upstreamStatusCode = "upstream_status_code", errorKind = "error_kind"
        case errorMessage = "error_message"
    }
}

/// One read for the detail's row or the small page: the plans and, when there is one, the primary plan's newest results.
public struct AccountScheduledTestsSnapshot: Sendable, Equatable {
    public enum Results: Sendable, Equatable {
        /// No plan, so nothing was asked.
        case notRequested
        case loaded([ScheduledTestResult])
        /// 403 FORBIDDEN: a vendor sees its accounts' plans, but the results route is not on its whitelist.
        case unavailable
    }
    public let plans: [ScheduledTestPlan]
    public let results: Results
    public init(plans: [ScheduledTestPlan], results: Results) { self.plans = plans; self.results = results }
    public var primaryPlan: ScheduledTestPlan? { ScheduledTestsPresentation.primaryPlan(plans) }
}

/// The detail's 记录 row, right side (20 §9.3).
public enum ScheduledTestSummary: Sendable, Equatable {
    public enum LastOutcome: Sendable, Equatable { case success, failed }
    case noPlan, allDisabled, readFailed
    case active(schedule: String, isRawCron: Bool, model: String, last: LastOutcome?)

    public var text: String {
        switch self {
        case .noPlan: "没有计划 · 在 Web 中添加"
        case .allDisabled: "计划已停用"
        case .readFailed: "读取失败"
        case .active(let schedule, _, let model, let last):
            ([schedule, model] + (last.map { [$0 == .success ? "上次成功" : "上次失败"] } ?? [])).joined(separator: " · ")
        }
    }
    public var tone: Tone? {
        if case .active(_, _, _, .failed) = self { .critical } else { nil }
    }
    /// The cron shown as written, set in a monospaced face; `text` starts with it.
    public var monospacedPrefix: String? {
        if case .active(let schedule, true, _, _) = self { schedule } else { nil }
    }
}

/// One line of the small page: HH:MM, then “成功 · 1.3s” or a status badge and a kind word (20 §9.3).
public struct ScheduledTestResultRow: Sendable, Equatable, Identifiable {
    public enum Outcome: Sendable, Equatable {
        case success(latency: String?)
        /// `badge` is the code or “—”, `tone` Tone.httpStatus of it.
        case failure(badge: String, tone: Tone, word: String)
    }
    public let id: Int
    public let time: String
    public let outcome: Outcome

    public var text: String {
        switch outcome {
        case .success(let latency): latency.map { "成功 · \($0)" } ?? "成功"
        case .failure(let badge, _, let word): "\(badge) \(word)"
        }
    }
    public var spokenText: String {
        let detail = if case .failure(DisplayFormat.missing, _, let word) = outcome { word } else { text }
        return "\(DisplayFormat.spoken(time))，\(detail)"
    }
}

public enum ScheduledTestsPresentation {
    public static let defaultModel = "默认模型"
    /// The small page's list (20 §9.2); the server's own default is 50.
    public static let resultLimit = 20
    static let resultLimitRange = 1...50

    /// `*/N * * * *` → 每 N 分钟 and `0 */N * * *` → 每 N 小时 while N fits the field; anything else as written (shown monospaced).
    public static func cronText(_ expression: String?) -> (text: String, isRaw: Bool) {
        let trimmed = expression?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return (DisplayFormat.missing, true) }
        let fields = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5, fields[2...] == ["*", "*", "*"] else { return (trimmed, true) }
        if fields[1] == "*", let minutes = step(fields[0], within: 1...59) { return ("每 \(minutes) 分钟", false) }
        if fields[0] == "0", let hours = step(fields[1], within: 1...23) { return ("每 \(hours) 小时", false) }
        return (trimmed, true)
    }
    /// The first enabled plan in the server's order, else the first.
    public static func primaryPlan(_ plans: [ScheduledTestPlan]) -> ScheduledTestPlan? { plans.first(where: \.enabled) ?? plans.first }
    /// The small page's header: “每 10 分钟 · claude-sonnet-4-5”, “ · 已停用” for a plan that is off.
    public static func planText(_ plan: ScheduledTestPlan) -> String {
        ([cronText(plan.cronExpression).text, modelName(plan)] + (plan.enabled ? [] : ["已停用"])).joined(separator: " · ")
    }
    /// The page lists the primary plan only.
    public static func otherPlansNote(_ snapshot: AccountScheduledTestsSnapshot) -> String? {
        snapshot.plans.count > 1 ? "另有 \(snapshot.plans.count - 1) 个计划，在 Web 中查看" : nil
    }
    public static func summary(_ snapshot: AccountScheduledTestsSnapshot) -> ScheduledTestSummary {
        guard !snapshot.plans.isEmpty else { return .noPlan }
        guard let plan = snapshot.primaryPlan, plan.enabled else { return .allDisabled }
        let schedule = cronText(plan.cronExpression)
        var last: ScheduledTestSummary.LastOutcome?
        if case .loaded(let results) = snapshot.results {
            switch results.first?.status {
            case .success: last = .success
            case .failed: last = .failed
            case .other, nil: last = nil
            }
        }
        return .active(schedule: schedule.text, isRawCron: schedule.isRaw, model: modelName(plan), last: last)
    }
    public static func resultRow(_ result: ScheduledTestResult, timeZone: TimeZone) -> ScheduledTestResultRow {
        let time = DisplayFormat.clock(result.startedAt, timeZone: timeZone)
        guard result.status != .success else {
            let latency = result.latencyMs.flatMap { $0 >= 0 ? DisplayFormat.duration($0, style: .list) : nil }
            return ScheduledTestResultRow(id: result.id, time: time, outcome: .success(latency: latency))
        }
        let code = statusCode(of: result)
        let outcome = ScheduledTestResultRow.Outcome.failure(badge: code.map(String.init) ?? DisplayFormat.missing, tone: Tone.httpStatus(code),
                                                             word: kindWord(kind: result.errorKind, code: code))
        return ScheduledTestResultRow(id: result.id, time: time, outcome: outcome)
    }
    /// `upstream_status_code` when it is a real status, else the one `error_message` names.
    public static func statusCode(of result: ScheduledTestResult) -> Int? {
        if let code = result.upstreamStatusCode, (100...599).contains(code) { return code }
        return result.messageStatusCode
    }
    /// 20 §0.1: `\((\d{3})\)|returned (\d{3})`, a real status only.
    static func parsedStatusCode(_ message: String?) -> Int? {
        guard let message, let range = message.range(of: #"\((\d{3})\)|returned (\d{3})"#, options: .regularExpression),
              let code = Int(String(message[range].filter(\.isNumber))), (100...599).contains(code) else { return nil }
        return code
    }
    /// The design's words for `error_kind`; an old server without it is classified by the code as the backend does
    /// (accountTestStatusErrorKinds). Other kinds say “上游 {code}”, or “失败” without one.
    public static func kindWord(kind: String?, code: Int?) -> String {
        let byCode: [Int: String] = [401: "auth", 402: "quota", 403: "forbidden", 429: "rate_limit"]
        let words = ["auth": "凭据无效", "forbidden": "无权限", "quota": "额度不足", "rate_limit": "上游限流"]
        let given = kind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolved = given?.isEmpty == false ? given : code.flatMap { byCode[$0] }
        if let resolved, let word = words[resolved] { return word }
        return code.map { "上游 \($0)" } ?? "失败"
    }

    private static func modelName(_ plan: ScheduledTestPlan) -> String {
        let model = plan.modelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return model.isEmpty ? defaultModel : model
    }
    private static func step(_ field: String, within range: ClosedRange<Int>) -> Int? {
        guard field.hasPrefix("*/"), let value = Int(field.dropFirst(2)), range.contains(value) else { return nil }
        return value
    }
}

extension APIClient {
    public func scheduledTestPlans(accountID: Int) async throws -> [ScheduledTestPlan] {
        let reply: UnenvelopedList<ScheduledTestPlan> = try await request("admin/accounts/\(validID(accountID))/scheduled-test-plans")
        return reply.items
    }
    public func scheduledTestResults(planID: Int, limit: Int = ScheduledTestsPresentation.resultLimit) async throws -> [ScheduledTestResult] {
        let range = ScheduledTestsPresentation.resultLimitRange
        let query = [URLQueryItem(name: "limit", value: String(min(max(limit, range.lowerBound), range.upperBound)))]
        let reply: UnenvelopedList<ScheduledTestResult> = try await request("admin/scheduled-test-plans/\(validID(planID))/results", query: query)
        return reply.items
    }
    /// Plans first; the primary plan's results only when there is one. A vendor's 403 FORBIDDEN on the results is not a failure.
    public func accountScheduledTests(accountID: Int, resultLimit: Int) async throws -> AccountScheduledTestsSnapshot {
        let plans = try await scheduledTestPlans(accountID: accountID)
        guard let primary = ScheduledTestsPresentation.primaryPlan(plans) else { return AccountScheduledTestsSnapshot(plans: plans, results: .notRequested) }
        do {
            return AccountScheduledTestsSnapshot(plans: plans, results: .loaded(try await scheduledTestResults(planID: primary.id, limit: resultLimit)))
        } catch let error as APIError where error.statusCode == 403 && error.reason == "FORBIDDEN" {
            return AccountScheduledTestsSnapshot(plans: plans, results: .unavailable)
        }
    }
}
