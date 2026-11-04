import Foundation
import Observation
import Sub2Core

/// One segment's count in the segmented control (40 §6.3): still asked, a number, or “—” when it could not be had.
enum LogCount: Equatable, Sendable {
    case pending, value(Int), unavailable

    /// From here a count is written compactly (12.3K): the three segments share one row (00 §6.2).
    static let compactThreshold = 10_000

    /// “用量明细 1,284”; the name alone while it is asked, “用量明细 —” when it could not be had.
    func segmentTitle(_ name: String) -> String {
        switch self {
        case .pending: name
        case .value(let count): name + " " + (count < Self.compactThreshold ? DisplayFormat.grouped(count) : DisplayFormat.compact(count))
        case .unavailable: name + " " + DisplayFormat.missing
        }
    }
}

/// How a segment is counted (40 §6.2): `usage/stats` → `total_requests`, or an error list's `total` at `page_size=1`.
enum LogCountRequest: Hashable, Sendable {
    case usage(AnalyticsQuery)
    case errors(RequestLogFilter, ErrorLogKind)

    func run(_ source: LogCountSource) async throws -> Int {
        switch self {
        case .usage(let query): try await source.usage(query)
        case .errors(let filter, let kind): try await source.errors(filter, kind)
        }
    }
}

/// R19's two methods, or the UI-test fixtures (LogFixtures).
struct LogCountSource: Sendable {
    let usage: @Sendable (AnalyticsQuery) async throws -> Int
    let errors: @Sendable (RequestLogFilter, ErrorLogKind) async throws -> Int

    static func client(_ client: APIClient) -> LogCountSource {
        LogCountSource(usage: { try await client.usageAnalysis($0).requests }, errors: { try await client.errorCount(filter: $0, kind: $1) })
    }
    /// Nothing is asked: every count reads “—”.
    static let unavailable = LogCountSource(usage: { _ in throw LogCountSource.notCounted },
                                            errors: { _, _ in throw LogCountSource.notCounted })
    private static let notCounted = APIError(kind: .unsupported, message: "这里不取计数。")
}

/// One round of counts (40 §6.2): usage asks `usage/stats` when the window is a fixed range; the shown error segment takes its
/// page 1's `total` and the other one asks its list at `page_size=1`; with ops monitoring off both error segments read “—”.
struct LogCountPlan: Equatable, Sendable {
    let requests: [LogScope: LogCountRequest]
    /// The error segment counted by its own page 1.
    let listScope: LogScope?
    /// Asked instead when the page leaves `listScope` before its page 1 came back.
    let listFallback: LogCountRequest?
    let unavailable: Set<LogScope>

    init(usage: AnalyticsQuery?, errors: RequestLogFilter, upstream: RequestLogFilter, current: LogScope, opsAvailable: Bool) {
        let errorRequests: [LogScope: LogCountRequest] = [.errors: .errors(errors, .request), .upstream: .errors(upstream, .upstream)]
        let asked = opsAvailable ? errorRequests.filter { $0.key != current } : [:]
        let usageRequest: [LogScope: LogCountRequest] = usage.map { [.usage: .usage($0)] } ?? [:]
        let requests = asked.merging(usageRequest) { first, _ in first }
        let fallback = opsAvailable ? errorRequests[current] : nil
        let listed = fallback == nil ? nil : current
        self.requests = requests; listFallback = fallback; listScope = listed
        unavailable = Set(LogScope.allCases.filter { $0 != listed && requests[$0] == nil })
    }
}

/// 40 §6.2–§6.6: the segments' counts, asked in rounds. The page starts a round on entering, on a condition or time change, on
/// pull and when ops monitoring is on again; switching segments asks nothing, except the shown error segment's count when it is
/// left before its page 1 came back. A reply of an older round is dropped; one stopped by the background is asked again when
/// the page is shown again (D18). Failures read “—” and are not retried; during the page's 429 wait nothing is asked and what
/// would be reads “—” (00 §2.7.2).
@MainActor @Observable
final class LogSegmentCounter {
    private(set) var counts: [LogScope: LogCount] = [:]

    @ObservationIgnored private let source: LogCountSource
    @ObservationIgnored private let onOpsDisabled: @MainActor (any Error) async -> Void
    /// Changes with every round; a reply carrying an older one is dropped.
    @ObservationIgnored private var pass = UUID()
    /// What each segment of this round was asked with.
    @ObservationIgnored private var asked: [LogScope: LogCountRequest] = [:]
    @ObservationIgnored private var listScope: LogScope?
    @ObservationIgnored private var listFallback: LogCountRequest?
    /// The background stopped `listScope`'s page 1.
    @ObservationIgnored private var listInterrupted = false
    @ObservationIgnored private var tasks: [LogScope: Task<Void, Never>] = [:]
    @ObservationIgnored private var interrupted: Set<LogScope> = []

    /// `onOpsDisabled` hands a 404 OPS_DISABLED to LiveOpsStore (S1D1-02).
    init(source: LogCountSource, onOpsDisabled: @escaping @MainActor (any Error) async -> Void = { _ in }) {
        self.source = source; self.onOpsDisabled = onOpsDisabled
    }

    func count(for scope: LogScope) -> LogCount { counts[scope] ?? .pending }

    /// `holdingBack`: the page's 429 wait lasts, so the shown error segment waits for its page 1 and the others read “—”.
    func begin(_ plan: LogCountPlan, holdingBack: Bool = false) {
        cancel()
        listScope = plan.listScope; listFallback = plan.listFallback
        counts = Dictionary(uniqueKeysWithValues: LogScope.allCases.map { scope -> (LogScope, LogCount) in
            (scope, plan.unavailable.contains(scope) ? .unavailable : .pending)
        })
        for (scope, request) in plan.requests { ask(scope, request, holdingBack: holdingBack) }
    }
    /// The shown error segment's page 1 of this round: the first one that lands is its count.
    func firstPageLoaded(_ scope: LogScope, total: Int?) {
        guard scope == listScope else { return }
        listScope = nil
        counts[scope] = total.map(LogCount.value) ?? .unavailable
    }
    /// “—” until a retry lands; nil is a read held back or not sent. A cancelled read stays: on return page 1 is read again,
    /// or the count asked (`resumeInterrupted`).
    func firstPageFailed(_ scope: LogScope, error: (any Error)?) {
        guard scope == listScope else { return }
        if error is CancellationError { listInterrupted = true } else { counts[scope] = .unavailable }
    }
    /// Before the page switches away from `scope`.
    func leaving(_ scope: LogScope) {
        guard scope == listScope else { return }
        askListFallback(holdingBack: false)
    }
    /// D18: only the asks the background stopped. With `listReadsAgain` false the page reads no page 1 again, so the shown
    /// error segment whose page 1 the background stopped is asked as on leaving it.
    func resumeInterrupted(listReadsAgain: Bool = true, holdingBack: Bool = false) {
        let resumed = interrupted
        interrupted = []
        for scope in LogScope.allCases where resumed.contains(scope) {
            if let request = asked[scope] { ask(scope, request, holdingBack: holdingBack) }
        }
        guard listInterrupted else { return }
        listInterrupted = false
        if !listReadsAgain { askListFallback(holdingBack: holdingBack) }
    }
    func cancel() {
        for task in tasks.values { task.cancel() }
        tasks = [:]; asked = [:]; interrupted = []; listScope = nil; listFallback = nil; listInterrupted = false
        pass = UUID()
    }
    /// Waits for this round's asks (tests).
    func settled() async {
        while let task = tasks.values.first { await task.value }
    }

    /// `listScope`'s page 1 of this round will not come: its count is asked once instead.
    private func askListFallback(holdingBack: Bool) {
        guard let scope = listScope, count(for: scope) == .pending, let listFallback else { return }
        listScope = nil
        ask(scope, listFallback, holdingBack: holdingBack)
    }
    private func ask(_ scope: LogScope, _ request: LogCountRequest, holdingBack: Bool) {
        guard !holdingBack else { counts[scope] = .unavailable; return }
        let pass = self.pass, source = self.source
        asked[scope] = request
        tasks[scope] = Task { [weak self] in
            let result: Result<Int, any Error>
            do { result = .success(try await request.run(source)) } catch { result = .failure(error) }
            await self?.finish(scope, result, pass: pass)
        }
    }
    private func finish(_ scope: LogScope, _ result: Result<Int, any Error>, pass: UUID) async {
        guard pass == self.pass else { return }
        tasks[scope] = nil
        switch result {
        case .success(let count):
            counts[scope] = .value(count)
        case .failure(let error) where error is CancellationError:
            interrupted.insert(scope)
        case .failure(let error):
            counts[scope] = .unavailable
            if AccountUpstreamErrors.isOpsDisabled(error) { await onOpsDisabled(error) }
        }
    }
}
