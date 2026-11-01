import Foundation
import Observation
import OSLog
import SwiftUI
import Sub2Core

/// 50 §2.2: the reads of the alert banner, 贰 and 叁's counts, so `-ui-testing` swaps them as a whole (GroupFixtures+DetailSections).
/// The banner and the two 24-hour counts go through the session's LiveOpsStore, the ops switch's one entry (S1D1-02); OPS_DISABLED
/// comes back as no banner and as `.opsDisabled`.
struct GroupDetailSectionsSource: Sendable {
    var capacity: @MainActor @Sendable (_ groupID: Int) async throws -> GroupCapacitySummary?
    var usageSummary: @MainActor @Sendable () async throws -> [GroupUsageSummary]
    var todayUsage: @MainActor @Sendable (_ groupID: Int) async throws -> GroupTodayUsage
    var firingAlert: @MainActor @Sendable (_ groupID: Int) async throws -> AlertEvent?
    var errorCount: @MainActor @Sendable (_ groupID: Int, _ kind: ErrorLogKind) async throws -> GroupLogCount

    @MainActor static func make(_ app: AppModel) -> GroupDetailSectionsSource { app.isUITesting ? GroupFixtures.detailSectionsSource(app) : live(app) }

    @MainActor static func live(_ app: AppModel) -> GroupDetailSectionsSource {
        GroupDetailSectionsSource(
            capacity: { [weak app] id in
                let session = try session(app)
                return try await session.client.groupCapacities(groupIDs: [id], serverFiltered: session.has(.groupsCapacityFilter)).first { $0.groupID == id }
            },
            usageSummary: { [weak app] in
                let session = try session(app)
                let isVendor = GroupPermissions(me: session.site.me, isReadOnlyToken: session.isReadOnlyToken).isVendor
                return try await session.client.groupUsageSummary(timezone: GroupStoreRules.usageTimeZone(isVendor: isVendor, siteZone: session.site.serverTimeZone))
            },
            todayUsage: { [weak app] id in
                let session = try session(app)
                return try await session.client.groupTodayUsage(id: id, serverTimeZone: session.site.serverTimeZone)
            },
            firingAlert: { [weak app] id in
                guard let liveOps = app?.liveOps else { throw CancellationError() }
                do { return try await liveOps.groupFiringAlert(groupID: id) } catch let error where GroupLogCount.isOpsDisabled(error) { return nil }
            },
            errorCount: { [weak app] id, kind in
                guard let liveOps = app?.liveOps else { throw CancellationError() }
                do {
                    return .count(try await liveOps.alertErrorCount(AlertErrorCountQuery(kind: kind, groupID: id)))
                } catch let error where GroupLogCount.isOpsDisabled(error) {
                    return .opsDisabled
                }
            })
    }
    @MainActor private static func session(_ app: AppModel?) throws -> SessionContext {
        guard let session = app?.sessionContext else { throw CancellationError() }
        return session
    }
}

/// 50 §2 (S5-07): the banner, 贰 and 叁's counts of one group detail, read with each of GroupDetailModel's refreshes (2.6). Each block
/// reads and fails on its own and keeps its last value through a failed refresh (S5D2a-15); a reply for an older session or after
/// the group was found deleted is dropped.
@MainActor @Observable
final class GroupDetailSectionsModel {
    let groupID: Int
    /// nil: the reply had no row for the group (a stopped group's empty reply).
    let capacity = LoadState<GroupCapacitySummary?>()
    /// nil: usage-summary had no row for the group.
    let usage = LoadState<GroupUsageSummary?>()
    let todayUsage = LoadState<GroupTodayUsage>()
    /// The newest firing event; nil when there is none or ops monitoring is off.
    let alert = LoadState<AlertEvent?>()
    let requestErrors = LoadState<GroupLogCount>()
    let upstreamErrors = LoadState<GroupLogCount>()

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let source: GroupDetailSectionsSource
    @ObservationIgnored private let generation: UUID
    @ObservationIgnored private var isCancelled = false
    /// Device time before which the 60-second refresh skips a block still backing off after failures (00 §4.6).
    @ObservationIgnored private var blockDue: [GroupDetailBlock: Date] = [:]

    init(app: AppModel, groupID: Int, generation: UUID, source: GroupDetailSectionsSource? = nil) {
        self.app = app
        self.groupID = groupID
        self.generation = generation
        self.source = source ?? .make(app)
    }

    /// The blocks GroupDetailSectionReads picks for `trigger`, side by side.
    func refresh(_ trigger: GroupDetailTrigger, showsUsageAndCapacity: Bool) async {
        guard isCurrent else { return }
        let blocks = GroupDetailSectionReads.reads(for: trigger, showsUsageAndCapacity: showsUsageAndCapacity,
                                                   opsKnownDisabled: app?.liveOps?.opsDisabled ?? false, due: blockDue, unread: unread, now: Date())
        async let capacityDone: Void = loadCapacity(if: blocks.contains(.capacity))
        async let usageDone: Void = loadUsage(if: blocks.contains(.usage), reusingList: GroupDetailSectionReads.reusesListUsage(trigger))
        async let todayDone: Void = loadToday(if: blocks.contains(.todayUsage))
        async let alertDone: Void = loadAlert(if: blocks.contains(.alert))
        async let requestDone: Void = loadCount(requestErrors, kind: .request, if: blocks.contains(.errorCounts))
        await loadCount(upstreamErrors, kind: .upstream, if: blocks.contains(.errorCounts))
        _ = await (capacityDone, usageDone, todayDone, alertDone, requestDone)
    }
    /// The group is gone: nothing read later lands.
    func cancel() {
        isCancelled = true
        capacity.cancel(); usage.cancel(); todayUsage.cancel(); alert.cancel(); requestErrors.cancel(); upstreamErrors.cancel()
    }
    /// 肆's Web row (S2D1-23's way): the system browser keeps the Web login; `-ui-testing` stays in the App with the receipt.
    func openGroupsInWeb(using openURL: OpenURLAction) {
        guard let app, let root = app.activeProfile?.baseURL, let url = GroupWebLink.url(siteRoot: root) else { return }
        let opened = Receipt(text: GroupWebLink.openedReceipt, systemImage: "safari", tone: .neutral)
        guard !app.isUITesting else { app.receipts.show(opened); return }
        let receipts = app.receipts
        openURL(url) { accepted in
            receipts.show(accepted ? opened : Receipt(text: AccountWebLink.openFailedReceipt, systemImage: "exclamationmark.triangle", tone: .caution))
        }
    }

    // MARK: - Blocks

    /// 400 INVALID_GROUP_ID / TOO_MANY_IDS mean the App sent a wrong id list: logged, and the lines show “—”.
    private func loadCapacity(if needed: Bool) async {
        guard needed, isCurrent else { return }
        let source = source, id = groupID, failedBefore = capacity.lastErrorAt
        await capacity.load(isCurrent: { self.isCurrent }) { try await source.capacity(id) }
        noteBackoff(.capacity, capacity.refresh)
        guard capacity.lastErrorAt != failedBefore, let error = capacity.lastError, GroupErrorCopy.resolve(error, context: .capacity).logs else { return }
        Self.log.error("GET admin/groups/capacity-summary \(error.statusCode ?? 0, privacy: .public) \(error.reason ?? "-", privacy: .public) \(error.requestID ?? "-", privacy: .public)")
    }
    /// Entering takes the list's read of the last 60 seconds (only a successful one counts, S5D2a-15); otherwise this group's row.
    private func loadUsage(if needed: Bool, reusingList: Bool) async {
        guard needed, isCurrent else { return }
        let source = source, id = groupID
        if reusingList, let cached = app?.groupStore?.usage(for: id) {
            await usage.load(isCurrent: { self.isCurrent }) { cached }
            return
        }
        await usage.load(isCurrent: { self.isCurrent }) {
            let rows = try await source.usageSummary()
            return GroupStoreRules.usageByGroup(rows)[id]
        }
        noteBackoff(.usage, usage.refresh)
    }
    private func loadToday(if needed: Bool) async {
        guard needed, isCurrent else { return }
        let source = source, id = groupID
        await todayUsage.load(isCurrent: { self.isCurrent }) { try await source.todayUsage(id) }
        noteBackoff(.todayUsage, todayUsage.refresh)
    }
    private func loadAlert(if needed: Bool) async {
        guard needed, isCurrent else { return }
        let source = source, id = groupID
        await alert.load(isCurrent: { self.isCurrent }) { try await source.firingAlert(id) }
        noteBackoff(.alert, alert.refresh)
    }
    private func loadCount(_ count: LoadState<GroupLogCount>, kind: ErrorLogKind, if needed: Bool) async {
        guard needed, isCurrent else { return }
        let source = source, id = groupID
        await count.load(isCurrent: { self.isCurrent }) { try await source.errorCount(id, kind) }
    }

    // MARK: - Internals

    private var isCurrent: Bool { app?.sessionGeneration == generation && !isCancelled }
    /// A block the 60-second refresh leaves out whose first read never went out (the page covered it) goes with the next one.
    private var unread: Set<GroupDetailBlock> {
        let blocks: [(GroupDetailBlock, Bool)] = [(.usage, Self.isIdle(usage.state)), (.todayUsage, Self.isIdle(todayUsage.state)),
                                                  (.errorCounts, Self.isIdle(requestErrors.state))]
        return Set(blocks.filter(\.1).map(\.0))
    }
    private static func isIdle<Value: Sendable>(_ state: BlockState<Value>) -> Bool {
        if case .idle = state { return true }
        return false
    }
    /// 60 → 120 → 240 → 300 seconds after consecutive failures, as GroupDetailModel's blocks.
    private func noteBackoff(_ block: GroupDetailBlock, _ refresh: BlockRefresh) {
        guard refresh.consecutiveFailures > 0 else { blockDue[block] = nil; return }
        blockDue[block] = Date().addingTimeInterval(refresh.nextDelay(base: GroupDetailRefreshPlan.interval, at: Date()) - Self.backoffTolerance)
    }
    private static let backoffTolerance: TimeInterval = 5
    private static let log = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "groups")
}
