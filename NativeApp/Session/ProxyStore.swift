import Foundation
import Observation
import Sub2Core

/// 60 §12.2: the list's two calls. S6-12 and S6-14 add theirs as sub-protocols (S6D1-12); the client and the UI-test fixture
/// are the only sources.
protocol ProxySource: Sendable {
    func proxies(page: Int, query: ProxyListQuery) async throws -> Page<AdminProxy>
    func testProxy(id: Int) async throws -> ProxyTestResult
}

struct ClientProxySource: ProxySource {
    let client: APIClient
    func proxies(page: Int, query: ProxyListQuery) async throws -> Page<AdminProxy> { try await client.proxies(page: page, query: query) }
    func testProxy(id: Int) async throws -> ProxyTestResult { try await client.testProxy(id: id) }
}

/// Every proxy of the site in the server's order (id descending), each id once. The capsules and the banner need all of them
/// (12.2), so a catalog still missing pages is not complete: no banner, no counts, no 全部测试.
struct ProxyCatalog: Sendable, Equatable {
    let proxies: [AdminProxy]
    let total: Int?
    let isComplete: Bool

    /// The subtitle's N: the rows of a complete catalog, otherwise the server's total while pages are missing.
    var count: Int { isComplete ? proxies.count : total ?? proxies.count }
    func proxy(id: Int) -> AdminProxy? { proxies.first { $0.id == id } }
    /// Only a row already there; an unknown id leaves the catalog as it is.
    func replacing(_ proxy: AdminProxy) -> ProxyCatalog {
        guard let index = proxies.firstIndex(where: { $0.id == proxy.id }) else { return self }
        var rows = proxies
        rows[index] = proxy
        return ProxyCatalog(proxies: rows, total: total, isComplete: isComplete)
    }
    func removing(id: Int) -> ProxyCatalog {
        guard proxies.contains(where: { $0.id == id }) else { return self }
        return ProxyCatalog(proxies: proxies.filter { $0.id != id }, total: total.map { max(0, $0 - 1) }, isComplete: isComplete)
    }
    func applying(_ result: ProxyTestResult, to id: Int) -> ProxyCatalog {
        guard let row = proxy(id: id) else { return self }
        return replacing(row.applying(result))
    }
}

/// 12.4's receipt after 全部测试: a probe answered `success: false` and a request that failed both count as failed.
struct ProxyTestSummary: Sendable, Equatable {
    let tested: Int
    let failed: Int
    var text: String { failed > 0 ? "已测试 \(tested) 个代理 · \(failed) 个失败" : "已测试 \(tested) 个代理" }
    var tone: Tone { failed > 0 ? .critical : .ok }
    var receipt: Receipt { Receipt(text: text, systemImage: "waveform", tone: tone) }
}

enum ProxyAccess {
    /// 60 §0.3: 全部测试, + and the empty list's 添加代理 are hidden for a read-only token; a vendor (U01, kept for later) needs
    /// `proxy_manage`. Without `admin/me` the site administrator is assumed.
    static func canManage(me: AdminMe?, isReadOnlyToken: Bool) -> Bool {
        guard !isReadOnlyToken else { return false }
        guard let workspace = me?.workspace else { return true }
        return workspace.permissions?.proxyManage == true
    }
}

/// One probe of 全部测试, answered off the main actor.
private struct ProxyProbeOutcome: Sendable {
    let id: Int
    let result: Result<ProxyTestResult, any Error>
}

/// 60 §12: the session's proxy catalog (X03), read page by page through `GET admin/proxies` because `proxies/all` has only the
/// active ones. The first load shows each page as it lands; a refresh keeps the complete catalog on screen and, when it fails,
/// keeps it (12.5). Replies of an older load or session are dropped (D13). The detail and the editor (S6-12…S6-14) read rows
/// here, write them back with `replace` / `remove` and share `source`.
@MainActor @Observable
final class ProxyStore {
    nonisolated static let maxConcurrentTests = 4
    nonisolated static let freshness: TimeInterval = 60
    /// A server that keeps answering `has_more` is not read forever.
    nonisolated static let maxPages = 50

    let generation: UUID
    let source: any ProxySource
    private(set) var state: BlockState<ProxyCatalog> = .idle
    /// The probes in flight; a row waiting its turn keeps its old value.
    private(set) var testing: Set<Int> = []
    private(set) var isTestingAll = false

    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var ticket = UUID()
    /// Probe results that landed while a load ran; the catalog it brings takes those newer than its own `latency_checked_at`.
    @ObservationIgnored private var landedDuringLoad: [Int: ProxyTestResult] = [:]

    init(generation: UUID, source: any ProxySource, isCurrent: @escaping @MainActor () -> Bool, now: @escaping @MainActor () -> Date = { Date() }) {
        self.generation = generation; self.source = source; self.isCurrent = isCurrent; self.now = now
    }

    var catalog: ProxyCatalog? { state.value }
    var proxies: [AdminProxy] { catalog?.proxies ?? [] }

    /// 12.6: shown again, it reads unless a complete catalog is younger than `maxAge`; nothing while a load runs.
    func ensureFresh(maxAge: TimeInterval = ProxyStore.freshness) async {
        guard !state.isLoading else { return }
        if case .loaded(let catalog, let at) = state, catalog.isComplete, now().timeIntervalSince(at) < maxAge { return }
        await reload()
    }

    /// Every page from 1, the newest load winning. reason is the error's catalog text, never the server's message.
    func reload() async {
        guard isCurrent() else { return }
        let ticket = UUID()
        self.ticket = ticket
        landedDuringLoad = [:]
        let keepsCatalog = catalog?.isComplete == true
        state = state.withLoading()
        do {
            let fetched = try await fetchAll(ticket: ticket, showsPages: !keepsCatalog)
            guard let fetched else { return }
            state = .loaded(merged(fetched), at: now())
        } catch {
            guard ticket == self.ticket, isCurrent() else { return }
            if error is CancellationError { return cancelLoad() }
            state = state.withFailure(error.localizedDescription)
        }
    }

    func proxy(id: Int) -> AdminProxy? { catalog?.proxy(id: id) }
    /// A backup proxy's name; nil when it is not in the catalog or has none.
    func name(for id: Int) -> String? {
        guard let name = proxy(id: id)?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }
    /// A write's answer for a row already listed; the state's kind and time stay. A load running now may still bring the
    /// server's older copy, which then stands.
    func replace(_ proxy: AdminProxy) { state = state.updatingValue { $0.replacing(proxy) } }
    func remove(id: Int) { state = state.updatingValue { $0.removing(id: id) } }

    /// 12.4: every proxy of the catalog whatever the capsule, at most four at a time; each answer updates its row at once.
    /// nil, with nothing sent, without a complete catalog or while one runs; nil too when the session ends or the caller's
    /// task is cancelled midway, and then no further probe goes out.
    func testAll() async -> ProxyTestSummary? {
        guard !isTestingAll, isCurrent(), let catalog, catalog.isComplete, !catalog.proxies.isEmpty else { return nil }
        isTestingAll = true
        defer { isTestingAll = false; testing = [] }
        var queue = catalog.proxies.map(\.id)[...]
        var tested = 0, failed = 0
        let source = self.source
        return await withTaskGroup(of: ProxyProbeOutcome.self, returning: ProxyTestSummary?.self) { group in
            while true {
                while testing.count < Self.maxConcurrentTests, let id = queue.popFirst() {
                    testing.insert(id)
                    group.addTask { await Self.probe(source, id: id) }
                }
                guard let outcome = await group.next() else { break }
                testing.remove(outcome.id)
                guard isCurrent(), !Task.isCancelled else {
                    group.cancelAll()
                    return nil
                }
                switch outcome.result {
                case .success(let result):
                    land(result, for: outcome.id)
                    if !result.success { failed += 1 }
                case .failure(let error) where error is CancellationError:
                    group.cancelAll()
                    return nil
                case .failure:
                    failed += 1
                }
                tested += 1
            }
            return ProxyTestSummary(tested: tested, failed: failed)
        }
    }

    // MARK: - Internals

    /// The pages in order until one says there is no more, comes back empty or the cap is hit. nil: superseded or the session
    /// ended. Without a complete catalog to keep, each page shows at once.
    private func fetchAll(ticket: UUID, showsPages: Bool) async throws -> ProxyCatalog? {
        var rows: [AdminProxy] = [], seen = Set<Int>(), total: Int?
        for page in 1...Self.maxPages {
            let reply = try await source.proxies(page: page, query: ProxyListQuery())
            guard ticket == self.ticket, isCurrent() else { return nil }
            for row in reply.items where seen.insert(row.id).inserted { rows.append(row) }
            total = reply.total
            guard reply.hasMore, !reply.items.isEmpty, page < Self.maxPages else { break }
            if showsPages { state = .loading(previous: merged(ProxyCatalog(proxies: rows, total: total, isComplete: false)), at: now()) }
        }
        return ProxyCatalog(proxies: rows, total: total, isComplete: true)
    }
    /// A cancelled refresh goes back to the complete catalog it kept; a cancelled first load to nothing.
    private func cancelLoad() {
        if let catalog, catalog.isComplete, let at = state.updatedAt { state = .loaded(catalog, at: at) } else { state = .idle }
    }
    private func land(_ result: ProxyTestResult, for id: Int) {
        if state.isLoading { landedDuringLoad[id] = result }
        state = state.updatingValue { $0.applying(result, to: id) }
    }
    /// A result stays over the server's row unless the server's own probe is newer.
    private func merged(_ catalog: ProxyCatalog) -> ProxyCatalog {
        landedDuringLoad.reduce(catalog) { partial, landed in
            guard let row = partial.proxy(id: landed.key) else { return partial }
            let isNewer = switch (landed.value.checkedAt, row.latencyCheckedAt) {
            case (_, nil): true
            case (let ours?, let theirs?): ours > theirs
            case (nil, _?): false
            }
            return isNewer ? partial.applying(landed.value, to: landed.key) : partial
        }
    }
    private nonisolated static func probe(_ source: any ProxySource, id: Int) async -> ProxyProbeOutcome {
        do { return ProxyProbeOutcome(id: id, result: .success(try await source.testProxy(id: id))) }
        catch { return ProxyProbeOutcome(id: id, result: .failure(error)) }
    }
}
