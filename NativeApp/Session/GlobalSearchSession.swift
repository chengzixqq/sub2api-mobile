import Foundation
import Observation
import Sub2Core

/// 60 §2.2: the global search's one call. The client and S6-21's UI-test fixture are the sources; the “查看全部” page reads
/// through it too.
protocol GlobalSearchSource: Sendable {
    func hits(for request: GlobalSearchRequest) async throws -> SearchHits
}

struct ClientGlobalSearchSource: GlobalSearchSource {
    let client: APIClient
    func hits(for request: GlobalSearchRequest) async throws -> SearchHits { try await client.searchHits(request) }
}

/// A section still in its 429 wait (00 §2.7.2): not sent, shown as failed with the countdown, so its round is not cached.
struct GlobalSearchThrottled: LocalizedError {
    let message: String?
    var errorDescription: String? { message }
}

private struct CachedSearch {
    let results: GlobalSearchResults
    let storedAt: Date
}

private struct SearchOutcome: Sendable {
    let section: SearchSection
    let result: Result<SearchHits, any Error>
}

/// 60 §2.2 / §2.6: the search box's fan-out for one session. Each input waits 300 ms, then every planned section goes out at
/// once and lands on its own; new input cancels the round before. A round that ended without a failure is reused for 30
/// seconds while this object lives. Answers of a superseded round or of an ended session are dropped. A section that got
/// 429 is not sent until its wait ends, then once for the query shown at that time (S6D2b-03). A read the suspend cut off
/// keeps its section searching and goes out again on `foregroundResumed()` (00 §4.6, D18).
@MainActor @Observable
final class GlobalSearchSession {
    nonisolated static let debounce: Duration = .milliseconds(300)
    nonisolated static let cacheLifetime: TimeInterval = 30
    nonisolated static let cacheLimit = 20

    let generation: UUID
    let source: any GlobalSearchSource
    /// nil: blank or under two characters, nothing sent.
    private(set) var plan: GlobalSearchPlan?
    private(set) var results: GlobalSearchResults?
    private(set) var throttles: [SearchSection: BlockRefresh] = [:]
    var query: GlobalSearchQuery? { plan?.query }

    @ObservationIgnored private let me: @MainActor () -> AdminMe?
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var ticket = UUID()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var resends: [SearchSection: Task<Void, Never>] = [:]
    /// Sections of the current round whose read was cancelled by the suspend.
    @ObservationIgnored private var cutOff: Set<SearchSection> = []
    @ObservationIgnored private var cache: [GlobalSearchPlan: CachedSearch] = [:]

    init(generation: UUID, source: any GlobalSearchSource, me: @escaping @MainActor () -> AdminMe?, isCurrent: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date = { Date() }, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.generation = generation; self.source = source; self.me = me; self.isCurrent = isCurrent; self.now = now; self.sleep = sleep
    }

    /// Every change of the search text, clearing included. The same trimmed text for the same identity changes nothing.
    func update(text: String) {
        let next = GlobalSearchQuery(text)?.plan(me: me())
        guard next != plan else { return }
        ticket = UUID()
        cutOff = []
        tasks.forEach { $0.cancel() }
        tasks = []
        plan = next
        guard let next, isCurrent() else { results = nil; return }
        if let cached = cached(next) { results = cached; return }
        results = GlobalSearchResults(plan: next)
        start(next.sections, of: next, debounced: true)
    }
    /// “重试” of a block: only those of these sections that failed and are not waiting out a 429, without the debounce.
    func retry(_ sections: Set<SearchSection>) {
        guard let plan, let results, isCurrent() else { return }
        let failed = results.failedSections
        let resend = plan.sections.filter { sections.contains($0) && failed.contains($0) && throttle(for: $0).allowsRequest(at: now()) }
        guard !resend.isEmpty else { return }
        self.results = results.reloading(Set(resend))
        start(resend, of: plan, debounced: false)
    }
    /// FailureView's “重试”.
    func retryFailed() { retry(results?.failedSections ?? []) }
    func throttle(for section: SearchSection) -> BlockRefresh { throttles[section] ?? BlockRefresh() }
    /// On `foregroundRevision`: the sections the suspend cut off go out again for the round shown, without the debounce.
    func foregroundResumed() {
        let resumed = cutOff
        cutOff = []
        guard let plan, let results, isCurrent() else { return }
        let resend = plan.sections.filter { resumed.contains($0) && results.status(of: $0) == .searching }
        guard !resend.isEmpty else { return }
        start(resend, of: plan, debounced: false)
    }

    // MARK: - Internals

    /// Sections in a 429 wait land as failed at once; the rest go out after the debounce, if asked for, under the current ticket.
    private func start(_ sections: [SearchSection], of plan: GlobalSearchPlan, debounced: Bool) {
        let held = sections.filter { !throttle(for: $0).allowsRequest(at: now()) }
        for section in held { land(.failure(GlobalSearchThrottled(message: throttle(for: section).throttleMessage(at: now()))), for: section) }
        let sending = sections.filter { !held.contains($0) }
        guard !sending.isEmpty else { return }
        let ticket = self.ticket, sleep = self.sleep
        tasks.append(Task { [weak self] in
            if debounced {
                guard !Task.isCancelled else { return }
                do { try await sleep(Self.debounce) } catch { return }
            }
            await self?.fanOut(sending, of: plan, ticket: ticket)
        })
    }
    private func fanOut(_ sections: [SearchSection], of plan: GlobalSearchPlan, ticket: UUID) async {
        guard ticket == self.ticket, !Task.isCancelled, isCurrent() else { return }
        let source = self.source, requests = sections.compactMap(plan.request(for:))
        await withTaskGroup(of: SearchOutcome.self) { group in
            for request in requests { group.addTask { await Self.fetch(source, request) } }
            for await outcome in group {
                guard ticket == self.ticket, isCurrent() else {
                    group.cancelAll()
                    return
                }
                if GlobalSearchFailure.isCutOff(outcome.result) { cutOff.insert(outcome.section) }
                else { land(outcome.result, for: outcome.section) }
            }
        }
    }
    private func land(_ result: Result<SearchHits, any Error>, for section: SearchSection) {
        guard let landed = results?.landing(result, for: section, at: now()) else { return }
        results = landed
        record(result, for: section)
        if landed.isSettled, landed.failedSections.isEmpty { store(landed) }
    }
    /// A 429 starts the section's wait and its one resend; any other answer ends a wait.
    private func record(_ result: Result<SearchHits, any Error>, for section: SearchSection) {
        if case .failure(let error) = result {
            if error is GlobalSearchThrottled { return }
            if let api = error as? APIError, api.statusCode == 429 {
                throttles[section] = BlockRefresh().recordingFailure(api, at: now())
                return scheduleResend(section)
            }
        }
        if throttles[section] != nil { throttles[section] = nil }
    }
    /// One per section, a newer wait replacing it. New input does not cancel it: it resends for the plan shown when it ends.
    private func scheduleResend(_ section: SearchSection) {
        resends[section]?.cancel()
        guard let notBefore = throttles[section]?.notBefore else { return }
        let wait = max(0, notBefore.timeIntervalSince(now())), sleep = self.sleep
        resends[section] = Task { [weak self] in
            do { try await sleep(.seconds(wait)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.resendAfterWait(section)
        }
    }
    private func resendAfterWait(_ section: SearchSection) {
        resends[section] = nil
        guard isCurrent() else { return }
        throttles[section] = nil
        guard let plan, plan.sections.contains(section), let results, results.status(of: section) == .failed else { return }
        self.results = results.reloading([section])
        start([section], of: plan, debounced: false)
    }
    private func cached(_ plan: GlobalSearchPlan) -> GlobalSearchResults? {
        guard let entry = cache[plan], now().timeIntervalSince(entry.storedAt) < Self.cacheLifetime else { return nil }
        return entry.results
    }
    /// Expired entries go; past `cacheLimit` the oldest go too.
    private func store(_ results: GlobalSearchResults) {
        let stamp = now()
        let fresh = cache.filter { stamp.timeIntervalSince($0.value.storedAt) < Self.cacheLifetime && $0.key != results.plan }
        let kept = fresh.sorted { $0.value.storedAt > $1.value.storedAt }.prefix(Self.cacheLimit - 1)
        cache = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        cache[results.plan] = CachedSearch(results: results, storedAt: stamp)
    }
    private nonisolated static func fetch(_ source: any GlobalSearchSource, _ request: GlobalSearchRequest) async -> SearchOutcome {
        do { return SearchOutcome(section: request.section, result: .success(try await source.hits(for: request))) }
        catch { return SearchOutcome(section: request.section, result: .failure(error)) }
    }
}
