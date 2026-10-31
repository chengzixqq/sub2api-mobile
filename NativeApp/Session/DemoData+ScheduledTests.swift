import Foundation
import Sub2Core

// S2-21 fixtures: the design's VD_TESTS (v-detail.jsx) as the backend's bare plan and result arrays (20 §9.2), decoded from the
// wire keys. Claude-官方-03, OpenAI-备用-A and GLM-直连-01 failed last (GLM's code only in error_message), Gemini-测试-B's plans
// are both off, DeepSeek-01's plan is a raw cron on the default model with no results yet; Kimi-01 and Grok-旧-01 have none.
extension DemoData.AccountFixture {
    /// The plans read answers 502: the detail's row reads “读取失败” and the small page offers 重试 (S2-21).
    static let scheduledTestsError = "-ui-scheduled-tests-error"
}

/// One result: minutes before the session's base, latency, then the failure's code, kind and message (nil kind = success).
private typealias ScheduledResultFixture = (minutesAgo: Double, latency: Int, code: Int?, kind: String?, message: String?)

private struct ScheduledPlanFixture {
    let id: Int
    let cron: String
    let model: String
    var enabled = true
    var results: [ScheduledResultFixture] = []
}

private func passed(_ minutesAgo: Double, _ latency: Int) -> ScheduledResultFixture { (minutesAgo, latency, nil, nil, nil) }

private let scheduledPlanFixtures: [Int: [ScheduledPlanFixture]] = [
    1: [ScheduledPlanFixture(id: 11, cron: "*/30 * * * *", model: "claude-haiku-4-5", results: [passed(10, 900), passed(40, 1_000), passed(70, 1_200)])],
    2: [ScheduledPlanFixture(id: 21, cron: "*/30 * * * *", model: "claude-haiku-4-5", results: [passed(10, 1_000), passed(40, 900), passed(70, 1_100)])],
    3: [ScheduledPlanFixture(id: 31, cron: "*/10 * * * *", model: "claude-sonnet-4-5", results: [
        (5, 400, 429, "rate_limit", "API returned 429: rate_limit_error"), passed(15, 1_300), passed(25, 1_100)])],
    4: [ScheduledPlanFixture(id: 41, cron: "0 */2 * * *", model: "gpt-4.1-mini", results: [passed(30, 700), passed(150, 800), passed(270, 700)])],
    5: [ScheduledPlanFixture(id: 51, cron: "*/30 * * * *", model: "gemini-2.5-flash", enabled: false, results: [passed(1_440, 1_000)]),
        ScheduledPlanFixture(id: 52, cron: "0 */6 * * *", model: "gemini-2.5-pro", enabled: false)],
    7: [ScheduledPlanFixture(id: 71, cron: "*/10 * * * *", model: "gpt-4.1-mini", results: [
        (5, 200, 401, "auth", "API returned 401: invalid_api_key"), passed(15, 800), passed(25, 900)])],
    8: [ScheduledPlanFixture(id: 81, cron: "15 9 * * 1-5", model: "")],
    // No upstream_status_code: the 529 comes from error_message (20 §0.1).
    11: [ScheduledPlanFixture(id: 111, cron: "*/15 * * * *", model: "glm-4.6", results: [
        (15, 1_200, nil, "other", "upstream returned 529 overloaded"), passed(30, 2_100), passed(45, 1_900)])],
    12: [ScheduledPlanFixture(id: 121, cron: "*/15 * * * *", model: "MiniMax-M2", results: [
        (15, 1_400, 529, "other", "(529) overloaded"), (30, 1_300, 529, "other", "(529) overloaded"), passed(45, 2_400)])]
]

extension AccountDemoStore {
    /// `scheduled-test-plans` and the primary plan's newest results; an account the store lacks is the server's 404. Result ids
    /// are the plan id × 100 + the row number (OpenAI-备用-A's newest is 7101).
    func scheduledTests(accountID: Int, resultLimit: Int, arguments: [String]) throws -> AccountScheduledTestsSnapshot {
        if arguments.contains(DemoData.AccountFixture.scheduledTestsError) { throw APIError.server(status: 502, reason: nil) }
        guard account(id: accountID) != nil else { throw APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND") }
        let fixtures = scheduledPlanFixtures[accountID] ?? []
        let plans = try Self.decoded([ScheduledTestPlan].self, fixtures.map { plan -> [String: Any] in
            ["id": plan.id, "account_id": accountID, "model_id": plan.model, "cron_expression": plan.cron, "enabled": plan.enabled,
             "max_results": 50, "auto_recover": false, "last_run_at": NSNull(), "next_run_at": NSNull()]
        })
        guard let primary = ScheduledTestsPresentation.primaryPlan(plans), let fixture = fixtures.first(where: { $0.id == primary.id }) else {
            return AccountScheduledTestsSnapshot(plans: plans, results: .notRequested)
        }
        let rows = fixture.results.prefix(max(resultLimit, 1)).enumerated().map { index, row in
            resultWire(row, id: fixture.id * 100 + index + 1, planID: fixture.id)
        }
        return AccountScheduledTestsSnapshot(plans: plans, results: .loaded(try Self.decoded([ScheduledTestResult].self, rows)))
    }

    private func resultWire(_ row: ScheduledResultFixture, id: Int, planID: Int) -> [String: Any] {
        let started = base.addingTimeInterval(-row.minutesAgo * 60)
        var wire: [String: Any] = [
            "id": id, "plan_id": planID, "status": row.kind == nil ? "success" : "failed", "latency_ms": row.latency, "response_text": "",
            "error_message": row.message ?? "", "started_at": ServerTime.utcTimestamp(started),
            "finished_at": ServerTime.utcTimestamp(started.addingTimeInterval(Double(row.latency) / 1_000)), "error_kind": row.kind ?? NSNull()
        ]
        // A failure whose code the server did not record leaves the key out, as an older server does.
        if let code = row.code { wire["upstream_status_code"] = code } else if row.kind == nil { wire["upstream_status_code"] = 200 }
        return wire
    }
    private static func decoded<Value: Decodable>(_ type: Value.Type, _ rows: [[String: Any]]) throws -> Value {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: rows))
    }
}
