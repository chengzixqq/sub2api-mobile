import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let open = AccountListRefresh.Gate(isForeground: true, isVisible: true)

private func account(_ id: Int, extra fields: [String: Any] = [:]) throws -> UpstreamAccount {
    var json: [String: Any] = ["id": id, "name": "账号-\(id)", "platform": "anthropic", "type": "oauth", "status": "active", "schedulable": true]
    json.merge(fields) { _, new in new }
    return try JSONDecoder().decode(UpstreamAccount.self, from: JSONSerialization.data(withJSONObject: json))
}

private func runtime(status: String = "active", schedulable: Bool = true, concurrency: Int? = 0, available: Bool? = true, overload: Date? = nil,
                     rateLimit: Date? = nil, temporary: Date? = nil) -> AccountRuntime {
    AccountRuntime(status: status, schedulable: schedulable, currentConcurrency: concurrency, concurrencyAvailable: available,
                   rateLimitResetAt: rateLimit, overloadUntil: overload, tempUnschedulableUntil: temporary)
}

/// Seconds before t0; nil = never.
private func marks(light: TimeInterval? = nil, full: TimeInterval? = nil, countdown: TimeInterval? = nil) -> AccountListRefresh.Marks {
    AccountListRefresh.Marks(lastLight: light.map { t0.addingTimeInterval(-$0) }, lastFull: full.map { t0.addingTimeInterval(-$0) },
                             lastCountdown: countdown.map { t0.addingTimeInterval(-$0) })
}

private func due(_ marks: AccountListRefresh.Marks, runtime: Bool = true, throttle: BlockRefresh = BlockRefresh()) -> AccountListRefresh.Kind? {
    AccountListRefresh.due(at: t0, gate: open, marks: marks, supportsRuntime: runtime, throttle: throttle)
}

private func rateLimited(after seconds: Int) -> BlockRefresh {
    BlockRefresh().recordingFailure(APIError.server(status: 429, envelope: ErrorEnvelope(reason: "RATE_LIMITED", retryAfter: seconds), retryAfter: seconds), at: t0)
}

// MARK: - Runtime merge (20 §1.6)

@Test func mergeOverwritesOnlyRuntimeFields() throws {
    let first = try account(1, extra: ["concurrency": 8, "current_concurrency": 1, "concurrency_available": true, "group_ids": [1, 5],
                                       "error_summary": "上游返回异常", "rate_limit_reset_at": ServerTime.utcTimestamp(t0.addingTimeInterval(300)),
                                       "extra": ["model_rate_limits": ["claude-opus-4": ["rate_limit_reset_at": "2027-01-15T08:00:00Z"]]]])
    let second = try account(2, extra: ["current_concurrency": 2, "overload_until": ServerTime.utcTimestamp(t0.addingTimeInterval(60))])
    let merged = AccountListRefresh.merging([first, second], runtime: [
        1: runtime(schedulable: false, concurrency: nil, available: false, overload: t0.addingTimeInterval(120)),
        9: runtime(status: "error")
    ])
    #expect(merged.map(\.id) == [1, 2])
    #expect(merged[0].currentConcurrency == nil && merged[0].concurrencyAvailable == false && !merged[0].schedulable && merged[0].status == "active")
    #expect(merged[0].rateLimitResetAt == nil && merged[0].tempUnschedulableUntil == nil)
    #expect(ServerTime.parseTimestamp(merged[0].overloadUntil) == t0.addingTimeInterval(120))
    #expect(merged[0].name == "账号-1" && merged[0].groupIDs == [1, 5] && merged[0].errorSummary == "上游返回异常" && merged[0].concurrency == 8)
    #expect(merged[0].extra?.modelRateLimits.map(\.model) == ["claude-opus-4"])
    #expect(merged[1].currentConcurrency == 2 && merged[1].overloadUntil == second.overloadUntil && merged[1].concurrencyAvailable == nil)
}

@Test func fullRefreshNeededWhenStatusOrSchedulableChangesOrRowMissing() throws {
    let rows = [try account(1), try account(2)]
    #expect(AccountListRefresh.needsFullRefresh(rows, runtime: [1: runtime(status: "error"), 2: runtime()]))
    #expect(AccountListRefresh.needsFullRefresh(rows, runtime: [1: runtime(schedulable: false), 2: runtime()]))
    #expect(AccountListRefresh.needsFullRefresh(rows, runtime: [1: runtime()]))
    #expect(!AccountListRefresh.needsFullRefresh(rows, runtime: [1: runtime(concurrency: 3, overload: t0.addingTimeInterval(60)), 2: runtime()]))
    #expect(!AccountListRefresh.needsFullRefresh(rows, runtime: [1: runtime(), 2: runtime(), 3: runtime(status: "error")]))
    #expect(!AccountListRefresh.needsFullRefresh([], runtime: [:]))
}

// MARK: - Timer (20 §1.6)

@Test func dueFollowsSixtySecondAndFiveMinuteRules() {
    #expect(due(marks()) == .full)
    #expect(due(marks(light: 59, full: 100)) == nil)
    #expect(due(marks(light: 60, full: 100)) == .light)
    #expect(due(marks(light: 10, full: 300)) == .full)
    #expect(due(marks(full: 70)) == .light)
    #expect(due(marks(full: 59)) == nil)
    #expect(due(marks(light: 60, full: 100), runtime: false) == .full)
    // The device clock moved back: refresh now instead of waiting it out.
    #expect(due(marks(light: -30, full: 100)) == .light)
    #expect(due(marks(full: -30)) == .full)
}

@Test func failuresStretchTheLightInterval() {
    let failed = BlockRefresh().recordingFailure(APIError.server(status: 502, reason: nil), at: t0)
    #expect(due(marks(light: 60, full: 100), throttle: failed) == nil)
    #expect(due(marks(light: 120, full: 200), throttle: failed) == .light)
    #expect(due(marks(light: 200, full: 200), throttle: rateLimited(after: 30)) == nil)
}

@Test(arguments: [
    AccountListRefresh.Gate(isForeground: false, isVisible: true),
    AccountListRefresh.Gate(isForeground: true, isVisible: false),
    AccountListRefresh.Gate(isForeground: true, isVisible: true, isSelecting: true),
    AccountListRefresh.Gate(isForeground: true, isVisible: true, hasSheet: true)
])
func closedGatePausesEveryTimerRefresh(_ gate: AccountListRefresh.Gate) {
    #expect(!gate.isOpen)
    #expect(AccountListRefresh.due(at: t0, gate: gate, marks: marks(), supportsRuntime: true, throttle: BlockRefresh()) == nil)
    #expect(AccountListRefresh.nextCheck(at: t0, gate: gate, marks: marks(), throttle: BlockRefresh()) == nil)
    #expect(AccountListRefresh.countdownRefresh(at: t0, gate: gate, marks: marks(), supportsRuntime: true, throttle: BlockRefresh()) == nil)
}

@Test func defaultGateWaitsForTheTabToShow() {
    #expect(!AccountListRefresh.Gate().isOpen)
    #expect(open.isOpen)
}

@Test func nextCheckWaitsForEarliestDueAndRateLimit() {
    func next(_ marks: AccountListRefresh.Marks, _ throttle: BlockRefresh = BlockRefresh()) -> TimeInterval? {
        AccountListRefresh.nextCheck(at: t0, gate: open, marks: marks, throttle: throttle)
    }
    #expect(next(marks(light: 20, full: 100)) == 40)
    #expect(next(marks(light: 20, full: 290)) == 10)
    #expect(next(marks()) == 0)
    #expect(next(marks(light: 90, full: 100)) == 0)
    #expect(next(marks(light: 20, full: 100), BlockRefresh().recordingFailure(APIError.server(status: 502, reason: nil), at: t0)) == 100)
    #expect(next(marks(light: 20, full: 100), rateLimited(after: 150)) == 150)
}

@Test func countdownRefreshAtMostOncePerTenSeconds() {
    func countdown(_ marks: AccountListRefresh.Marks, runtime: Bool = true, throttle: BlockRefresh = BlockRefresh()) -> AccountListRefresh.Kind? {
        AccountListRefresh.countdownRefresh(at: t0, gate: open, marks: marks, supportsRuntime: runtime, throttle: throttle)
    }
    #expect(countdown(marks(full: 5)) == .light)
    #expect(countdown(marks(full: 5, countdown: 9)) == nil)
    #expect(countdown(marks(full: 5, countdown: 10)) == .light)
    #expect(countdown(marks(full: 5), runtime: false) == .full)
    #expect(countdown(marks(full: 5), throttle: rateLimited(after: 30)) == nil)
}

@Test func marksRecordEachKind() {
    let recorded = AccountListRefresh.Marks().recording(.full, at: t0).recording(.light, at: t0.addingTimeInterval(1))
        .recordingCountdown(at: t0.addingTimeInterval(2))
    #expect(recorded == AccountListRefresh.Marks(lastLight: t0.addingTimeInterval(1), lastFull: t0, lastCountdown: t0.addingTimeInterval(2)))
}

@Test func forgettingFullRunsOneAtTheNextCheck() {
    let cut = marks(light: 20, full: 20).forgettingFull()
    #expect(cut.lastFull == nil && cut.lastLight == t0.addingTimeInterval(-20))
    #expect(due(cut) == .full)
    #expect(AccountListRefresh.nextCheck(at: t0, gate: open, marks: cut, throttle: BlockRefresh()) == 0)
    #expect(due(cut, throttle: rateLimited(after: 30)) == nil)
}

// MARK: - Light blocks (00 §2.3, §2.7.2, §4.6)

private func round(_ seconds: TimeInterval, scheduled: Bool = true) -> AccountListRefresh.Round {
    AccountListRefresh.Round(start: t0.addingTimeInterval(seconds), isScheduled: scheduled)
}

@Test func lightBlockSendsNothingDuringItsRateLimitWait() {
    let limited = AccountListRefresh.LightBlock().requesting(in: round(0))
        .recordingFailure(APIError.server(status: 429, envelope: ErrorEnvelope(reason: "RATE_LIMITED", retryAfter: 120), retryAfter: 120), at: t0)
    for scheduled in [true, false] {
        #expect(!limited.allowsRequest(in: round(60, scheduled: scheduled)))
        #expect(!limited.allowsRequest(in: round(119, scheduled: scheduled)))
    }
    #expect(limited.allowsRequest(in: round(120, scheduled: false)))
    #expect(limited.allowsRequest(in: round(240)))
    #expect(AccountListRefresh.LightBlock().allowsRequest(in: round(0)))
}

@Test func failingLightBlockBacksOffOnScheduledRoundsOnly() {
    let server = APIError.server(status: 502, reason: nil)
    let once = AccountListRefresh.LightBlock().requesting(in: round(0)).recordingFailure(server, at: t0.addingTimeInterval(2))
    #expect(!once.allowsRequest(in: round(60)))
    #expect(once.allowsRequest(in: round(120)))
    #expect(once.allowsRequest(in: round(60, scheduled: false)))
    let twice = once.requesting(in: round(120)).recordingFailure(server, at: t0.addingTimeInterval(121))
    #expect(!twice.allowsRequest(in: round(300)))
    #expect(twice.allowsRequest(in: round(360)))
    let many = (0..<6).reduce(twice) { block, _ in block.requesting(in: round(360)).recordingFailure(server, at: t0.addingTimeInterval(361)) }
    #expect(!many.allowsRequest(in: round(659)) && many.allowsRequest(in: round(660)))
    // Success restores the 60-second rhythm; a device clock that moved back is treated as overdue.
    #expect(twice.recordingSuccess().allowsRequest(in: round(180)))
    #expect(twice.allowsRequest(in: round(60)))
}

@Test func resolvedLightBecomesFullWithoutRuntimeBatch() {
    #expect(AccountListRefresh.resolved(.light, supportsRuntime: false) == .full)
    #expect(AccountListRefresh.resolved(.light, supportsRuntime: true) == .light)
    #expect(AccountListRefresh.resolved(.full, supportsRuntime: true) == .full)
    #expect(AccountListRefresh.resolved(.full, supportsRuntime: false) == .full)
}

// MARK: - Pages (20 §1.2, U15)

@Test(arguments: [(2350, 1, 5, 500, Int?.some(2)), (2350, 2, 5, 1000, 3), (2350, 4, 5, 2000, nil), (400, 1, 1, 400, nil), (1500, 3, 3, 1500, nil),
                  (1200, 1, 3, 480, 2)])
func nextPageStopsAtTwoThousandRowsOrLastPage(_ total: Int, _ page: Int, _ pages: Int, _ loaded: Int, _ expected: Int?) {
    let current = AccountListPage(items: [], total: total, page: page, pageSize: 500, pages: pages)
    #expect(AccountListRefresh.nextPage(after: current, loaded: loaded, limit: 2000) == expected)
}

@Test func appendingDropsDuplicateIDsAndCapsAtLimit() throws {
    let existing = [try account(1), try account(2)]
    let page = [try account(2, extra: ["name": "后来的"]), try account(3), try account(4)]
    let merged = AccountListRefresh.appending(page, to: existing, limit: 3)
    #expect(merged.map(\.id) == [1, 2, 3] && merged[1].name == "账号-2")
    #expect(AccountListRefresh.appending(page, to: [], limit: 10).map(\.id) == [2, 3, 4])
}

@Test func updatingValueKeepsStateKindAndTime() {
    let at = t0
    #expect(BlockState<Int>.loaded(1, at: at).updatingValue { $0 + 1 } == .loaded(2, at: at))
    #expect(BlockState<Int>.loading(previous: 1, at: at).updatingValue { $0 + 1 } == .loading(previous: 2, at: at))
    #expect(BlockState<Int>.failed(reason: "失败", previous: 1, at: at).updatingValue { $0 + 1 } == .failed(reason: "失败", previous: 2, at: at))
    #expect(BlockState<Int>.idle.updatingValue { $0 + 1 } == .idle)
    #expect(BlockState<Int>.disabled(reason: "OPS_DISABLED").updatingValue { $0 + 1 } == .disabled(reason: "OPS_DISABLED"))
    #expect(BlockState<Int>.failed(reason: "失败", previous: nil, at: nil).updatingValue { $0 + 1 } == .failed(reason: "失败", previous: nil, at: nil))
    #expect(BlockState<Int>.loading(previous: nil, at: nil).updatingValue { $0 + 1 } == .loading(previous: nil, at: nil))
}
