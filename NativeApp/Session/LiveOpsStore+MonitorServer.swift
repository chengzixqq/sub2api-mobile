import Foundation
import Sub2Core

// S1-14, 10 §0.1, §0.2, §4.2, §4.5: the monitor overview's 服务器 section — who sees it, its four reads and what it shows. The
// timers, backoff and reentry wait are S1-13's (LiveOpsStore+Monitor.swift); each read goes through `controlled(_:)`, so a 404
// OPS_DISABLED turns the whole segment off, while `enabled: false` from ops/concurrency is only realtime monitoring (appendix A S7).

/// What the section may read on this site.
struct MonitorServerCapabilities: Equatable, Sendable {
    /// 10 §0.1: the site owner (an admin outside any workspace); first-version vendors cannot sign in (U01), so this only guards.
    var isAdministrator: Bool
    var history: Bool
    var ingressTotals: Bool
    var heartbeatStatus: Bool

    init(isAdministrator: Bool, history: Bool, ingressTotals: Bool, heartbeatStatus: Bool) {
        self.isAdministrator = isAdministrator; self.history = history; self.ingressTotals = ingressTotals; self.heartbeatStatus = heartbeatStatus
    }
    init(site: SiteSession?) {
        self.init(isAdministrator: site?.me.isAdministrator == true, history: site?.has(.opsSystemMetricsHistory) == true,
                  ingressTotals: site?.has(.opsIngressRejectTotals) == true, heartbeatStatus: site?.has(.opsJobHeartbeatStatus) == true)
    }
}

/// A read's failure as BlockFailureRow shows it, whatever its value type.
struct MonitorBlockFailure: Sendable, Equatable {
    let error: APIError?
    let occurredAt: Date?
    let refresh: BlockRefresh

    @MainActor init<Value: Sendable>(_ load: LoadState<Value>) {
        error = load.lastError; occurredAt = load.lastErrorAt; refresh = load.refresh
    }
}

/// The reads themselves, capturing nothing of the store, so they fit `controlled(_:)`'s closure.
enum MonitorServerLoads {
    static let timeRange = "1h"
    static let historyMaxPoints = 60
    static let historyRetryReasons: Set<String> = ["INVALID_MAX_POINTS", "OPS_TIME_RANGE_TOO_LARGE"]

    static func isHistoryParameterError(_ error: any Error) -> Bool {
        guard let error = error as? APIError, error.statusCode == 400, let reason = error.reason else { return false }
        return historyRetryReasons.contains(reason)
    }
    /// 10 §4.5: a 400 about the window or the point count is asked once more with 1h / 60; a second failure is the block's.
    static func history(using source: any LiveOpsSource) async throws -> SystemMetricsHistory {
        do {
            return try await source.systemMetricsHistory(timeRange: timeRange, maxPoints: historyMaxPoints)
        } catch let error where isHistoryParameterError(error) {
            return try await source.systemMetricsHistory(timeRange: timeRange, maxPoints: historyMaxPoints)
        }
    }
    /// With `ops.ingress_reject_totals` one row's page carries the total. Without it, or when the reply has none, up to three pages
    /// of 200 rows are added up (“≥ N” while rows remain, 10 §0.2).
    static func ingressTally(using source: any LiveOpsSource, totalsSupported: Bool) async throws -> MonitorPresentation.IngressRejectTally {
        if totalsSupported {
            let page = try await source.ingressRejections(timeRange: timeRange, page: 1, pageSize: 1)
            if page.requestCountTotal != nil, let tally = MonitorPresentation.ingressRejectTally([page]) { return tally }
        }
        var pages: [IngressRejectList] = []
        repeat {
            try Task.checkCancellation()
            let next = try await source.ingressRejections(timeRange: timeRange, page: pages.count + 1, pageSize: MonitorPresentation.ingressFallbackPageSize)
            pages.append(next)
        } while MonitorPresentation.needsMoreIngressPages(pages)
        return MonitorPresentation.ingressRejectTally(pages) ?? .exact(0)
    }
}

extension MonitorOverviewBlock {
    static let serverBlocks: [MonitorOverviewBlock] = [.systemMetrics, .concurrency, .logHealth, .ingress]

    init(serverPart: MonitorServerPart) {
        switch serverPart {
        case .systemMetrics: self = .systemMetrics
        case .concurrency: self = .concurrency
        case .logHealth: self = .logHealth
        case .ingress: self = .ingress
        }
    }
    /// nil for the run section's blocks.
    var serverPart: MonitorServerPart? {
        switch self {
        case .run, .errorTrend: nil
        case .systemMetrics: .systemMetrics
        case .concurrency: .concurrency
        case .logHealth: .logHealth
        case .ingress: .ingress
        }
    }
}

extension LiveOpsStore {
    var monitorServerCapabilities: MonitorServerCapabilities { MonitorServerCapabilities(site: site()) }
    /// 10 §0.1, §4.2: shown and read only for the site owner.
    var showsMonitorServer: Bool { monitorServerCapabilities.isAdministrator }

    /// The run section's blocks always; a server block for the owner while the site has its route, the history only with its
    /// capability.
    func monitorBlockApplies(_ block: MonitorOverviewBlock) -> Bool {
        guard block.serverPart != nil else { return true }
        let capabilities = monitorServerCapabilities
        guard capabilities.isAdministrator, !monitor.unsupportedBlocks.contains(block) else { return false }
        return block != .systemMetrics || capabilities.history
    }

    /// One server read (S1-13's `refreshMonitorBlock` decides when). A non-JSON 404 marks the route missing for the session.
    func refreshMonitorServerBlock(_ block: MonitorOverviewBlock) async {
        guard monitorBlockApplies(block) else { return }
        switch block {
        case .run, .errorTrend:
            return
        case .systemMetrics:
            await monitor.systemMetrics.load(isCurrent: isCurrent, operation: controlled { try await MonitorServerLoads.history(using: $0) })
        case .concurrency:
            await monitor.concurrency.load(isCurrent: isCurrent, operation: controlled { try await $0.opsConcurrency() })
        case .logHealth:
            await monitor.logHealth.load(isCurrent: isCurrent, operation: controlled { try await $0.systemLogsHealth() })
        case .ingress:
            let totals = monitorServerCapabilities.ingressTotals
            await monitor.ingress.load(isCurrent: isCurrent,
                                       operation: controlled { try await MonitorServerLoads.ingressTally(using: $0, totalsSupported: totals) })
        }
        if isCurrent(), monitor.load(block).lastError?.kind == .unsupported { monitor.markUnsupported(block) }
    }
    /// The failure row's 重试 or the title's 更新失败: these reads at once, even one in flight.
    func refreshMonitorServerParts(_ parts: [MonitorServerPart]) async {
        await withDiscardingTaskGroup { group in
            for part in parts {
                let block = MonitorOverviewBlock(serverPart: part)
                group.addTask { await self.refreshMonitorBlock(block, force: true) }
            }
        }
    }
    /// After each overview read, for the owner of a site whose history is not read: its snapshot as one more point (10 §4.3).
    func recordMonitorLocalSample() {
        guard isCurrent(), showsMonitorServer, !monitorBlockApplies(.systemMetrics), case .loaded(let overview, _) = monitor.overview.state else { return }
        monitor.recordLocalSample(overview.systemMetrics)
    }
    func monitorBlockFailure(_ part: MonitorServerPart) -> MonitorBlockFailure {
        switch part {
        case .systemMetrics: MonitorBlockFailure(monitor.systemMetrics)
        case .concurrency: MonitorBlockFailure(monitor.concurrency)
        case .logHealth: MonitorBlockFailure(monitor.logHealth)
        case .ingress: MonitorBlockFailure(monitor.ingress)
        }
    }
    /// `now` is the server's clock; job times read in the server's zone.
    func monitorServerDisplay(now: Date) -> MonitorServerDisplay {
        let unavailable = Set(MonitorOverviewBlock.serverBlocks.filter { !monitorBlockApplies($0) }.compactMap(\.serverPart))
        let input = MonitorServerInput(overview: monitor.overview.state.display, history: monitor.systemMetrics.state.display,
                                       localSamples: monitor.localSamples, concurrency: monitor.concurrency.state.display,
                                       logHealth: monitor.logHealth.state.display, ingress: monitor.ingress.state.display, unavailable: unavailable,
                                       heartbeatStatusSupported: monitorServerCapabilities.heartbeatStatus, now: now,
                                       timeZone: site()?.serverTimeZone.timeZone ?? ServerTimeZone.device.timeZone)
        return MonitorServerPresentation.display(input)
    }
}
