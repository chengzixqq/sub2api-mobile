import Foundation

/// One row of the “上游尝试” section (40 §7.3); `id` is the attempt's index. Tapping opens `accountID`.
public struct AttemptRow: Identifiable, Sendable, Equatable {
    public let id: Int
    /// `account_name` ?? “#<account_id>” ?? “未知账号”.
    public let title: String
    public let accountID: Int?
    /// “429 · 0.4s”; an estimate reads “约 0.4s”, a missing part “—”.
    public let trailing: String
    public let subtitle: String
    /// The index circle: 2xx ok, 429 caution, other codes critical, no code neutral.
    public let tone: Tone
}

extension RequestDetailPresentation {
    /// The failed looks show the section from one attempt, the success from two.
    public static func showsAttempts(style: RequestDetailStyle, count: Int) -> Bool { count >= (style == .success ? 2 : 1) }
    /// “2 次 · 返回客户端 200”.
    public static func attemptsMeta(count: Int, clientStatusCode: Int?) -> String {
        "\(count) 次" + (clientStatusCode.map { " · 返回客户端 \($0)" } ?? "")
    }
    public static func droppedNote(_ count: Int) -> String? { count > 0 ? "更早的 \(count) 次尝试因队列上限没有记录" : nil }
    /// The failed looks' “上游请求 ID”: the last attempt's.
    public static func lastUpstreamRequestID(_ chain: RequestAttempts) -> String? { chain.attempts.last?.upstreamRequestID }
    /// The server's client_request_id, else the request ID; nil when neither can be a path segment (the fallback then).
    public static func attemptsID(forError record: RequestErrorRecord) -> String? {
        [record.clientRequestID, record.requestID].compactMap { $0 }.first(where: RequestAttemptsLookup.isQueryable)
    }
    /// Usage rows send `client:<uuid>`, which the backend accepts; an id it cannot take hides the section.
    public static func attemptsID(forUsage usage: UsageRequestRecord) -> String? {
        RequestAttemptsLookup.isQueryable(usage.requestID) ? usage.requestID : nil
    }
    public static func attemptRows(_ chain: RequestAttempts) -> [AttemptRow] {
        rows(chain.attempts.map {
            AttemptStep(index: $0.index, accountID: $0.accountID, accountName: $0.accountName, statusCode: $0.upstreamStatusCode,
                        durationMs: $0.durationMs, isEstimated: false, outcome: $0.outcome)
        })
    }

    // MARK: Fallback (40 §7.2): no `ops.request_attempts`, or the chain could not be read.

    /// The failed tries of `upstream_errors`, then the client's success when there was one (read with `fallbackSuccessFilter`).
    /// A duration is `duration_ms`, else at − started, else the gap since the previous event (an estimate); the first event
    /// without either shows “—”.
    public static func fallbackRows(events: [UpstreamErrorEvent], success: UsageRequestRecord?) -> [AttemptRow] {
        var steps = events.indices.map { offset in
            let event = events[offset]
            let duration = fallbackDuration(event, previous: offset > 0 ? events[offset - 1] : nil)
            return AttemptStep(index: offset + 1, accountID: event.accountID, accountName: event.accountName, statusCode: event.upstreamStatusCode,
                               durationMs: duration.ms, isEstimated: duration.isEstimated, outcome: .failed)
        }
        if let success {
            steps.append(AttemptStep(index: steps.count + 1, accountID: success.accountID, accountName: success.accountName, statusCode: 200,
                                     durationMs: success.durationMs, isEstimated: false, outcome: .success))
        }
        return rows(steps)
    }
    public static func fallbackDropped(_ events: [UpstreamErrorEvent]) -> Int { events.map(\.droppedEarlierAttempts).max() ?? 0 }
    /// The client's successful try by `client:<client_request_id>`. RequestLogFilter carries no key view: S4-08 passes
    /// `maskedView: session.has(.apiKeysMaskedView)` to `requestRecords(page: 1, filter:maskedView:)` (S4D1-06).
    public static func fallbackSuccessFilter(clientRequestID: String?) -> RequestLogFilter? {
        guard let id = trimmed(clientRequestID) else { return nil }
        return RequestLogFilter(time: .none, requestID: "client:" + id, pageSize: 1)
    }
}

/// An attempt from the chain or rebuilt from `upstream_errors`.
private struct AttemptStep {
    let index: Int
    let accountID: Int?
    let accountName: String?
    let statusCode: Int?
    let durationMs: Int?
    let isEstimated: Bool
    let outcome: RequestAttempt.Outcome

    var title: String {
        if let name = RequestDetailPresentation.trimmed(accountName) { return name }
        if let accountID, accountID > 0 { return "#\(accountID)" }
        return "未知账号"
    }
    /// Ids when both have one, otherwise non-empty names; nothing to compare counts as another account.
    func isSameAccount(as other: AttemptStep) -> Bool {
        if let mine = accountID, let theirs = other.accountID, mine > 0, theirs > 0 { return mine == theirs }
        guard let mine = RequestDetailPresentation.trimmed(accountName), let theirs = RequestDetailPresentation.trimmed(other.accountName) else { return false }
        return mine == theirs
    }
}

private extension RequestDetailPresentation {
    static func rows(_ steps: [AttemptStep]) -> [AttemptRow] {
        steps.indices.map { offset in
            let step = steps[offset], next = offset + 1 < steps.count ? steps[offset + 1] : nil
            let duration = (step.isEstimated && step.durationMs != nil ? "约 " : "") + DisplayFormat.duration(step.durationMs, style: .list)
            return AttemptRow(id: step.index, title: step.title, accountID: step.accountID.flatMap { $0 > 0 ? $0 : nil },
                              trailing: (step.statusCode.map(String.init) ?? DisplayFormat.missing) + " · " + duration,
                              subtitle: subtitle(step, next: next), tone: Tone.httpStatus(step.statusCode))
        }
    }
    static func subtitle(_ step: AttemptStep, next: AttemptStep?) -> String {
        switch step.outcome {
        case .success: return "成功，结果返回客户端"
        case .partial: return "已计费，但请求最终失败"
        case .failed, .unknown:
            guard let next else { return "失败，错误返回客户端" }
            return step.isSameAccount(as: next) ? "失败，同一账号重试" : "失败，切换到 \(next.title) 重试"
        }
    }
    static func fallbackDuration(_ event: UpstreamErrorEvent, previous: UpstreamErrorEvent?) -> (ms: Int?, isEstimated: Bool) {
        if let duration = event.durationMs { return (duration, false) }
        guard let at = event.atUnixMs else { return (nil, false) }
        if let started = event.startedAtUnixMs, at >= started { return (Int(at - started), false) }
        guard let before = previous?.atUnixMs, at >= before else { return (nil, false) }
        return (Int(at - before), true)
    }
}
