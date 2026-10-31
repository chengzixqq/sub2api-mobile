import Foundation
import Observation
import Sub2Core

/// What the platform quota section needs from the session (S3-14). The server clock travels here, as for the key segment (S3D1-06).
struct PlatformQuotaContext: Sendable {
    let generation: UUID
    /// `users.platform_quota_item`: single-platform PUT / DELETE / restore; without it the whole-table fallback (30 §8.4).
    let supportsItemWrites: Bool
    let isReadOnlyToken: Bool
    let serverTimeZone: ServerTimeZone
    let now: @Sendable () -> Date
}

/// The section's calls: AppModel (with its -ui-testing branches) in the App, stubs in tests.
@MainActor protocol PlatformQuotaSource: AnyObject {
    var platformQuotaContext: PlatformQuotaContext? { get }
    /// X25: the session's catalog wrapper, the built-in list without `meta.catalog`.
    func metaCatalog() async -> MetaCatalog
    func platformQuotas(userID: Int) async throws -> [UserPlatformQuota]
    func upsertPlatformQuota(userID: Int, platform: String, limits: PlatformQuotaLimits) async throws -> PlatformQuotaUpsertResult
    func deletePlatformQuota(userID: Int, platform: String) async throws -> PlatformQuotaDeleteResult
    func restorePlatformQuota(userID: Int, platform: String) async throws -> PlatformQuotaRestoreResult
    func resetPlatformQuotaWindow(userID: Int, platform: String, window: PlatformQuotaWindowKind) async throws -> [UserPlatformQuota]
    func replaceUserPlatformQuotas(userID: Int, quotas: [PlatformQuotaEntry]) async throws -> [UserPlatformQuota]
}

/// The edit page around the section: a write took effect or was undone (its leave confirmation names it), the user is gone.
struct PlatformQuotaHooks {
    let onApplied: @MainActor (String) -> Void
    let onUndone: @MainActor (String) -> Void
    let onUserGone: @MainActor () -> Void
    static let none = PlatformQuotaHooks(onApplied: { _ in }, onUndone: { _ in }, onUserGone: {})
}

/// 30 §8 平台限额 (S3-14, S3D1-17): the user's platform quotas and the writes. Nothing changes before the server answers; every
/// write goes out once and a lost reply is read back. With `users.platform_quota_item` a save touches one platform and its 撤销
/// follows PlatformQuotaUndo; without it the whole table is read fresh, only the target changed, and put back. A receipt's
/// 撤销 keeps the store alive after the page has gone; a session change drops every late reply.
@MainActor @Observable
final class PlatformQuotaStore {
    let userID: Int
    private(set) var quotas: BlockState<[UserPlatformQuota]> = .idle
    private(set) var catalog = MetaCatalog.builtin
    /// Platforms with a write out: their sheet's buttons turn into progress.
    private(set) var busyPlatforms: Set<String> = []
    /// INVALID_QUOTA_LIMIT and other refusals, at the bottom of the sheet.
    private(set) var sheetError: String?

    @ObservationIgnored private weak var source: (any PlatformQuotaSource)?
    @ObservationIgnored let receipts: ReceiptCenter
    @ObservationIgnored let hooks: PlatformQuotaHooks
    @ObservationIgnored private var entryTask: Task<Void, Never>?
    @ObservationIgnored private var readTask: Task<Void, Never>?

    init(userID: Int, source: any PlatformQuotaSource, receipts: ReceiptCenter, hooks: PlatformQuotaHooks = .none) {
        self.userID = userID; self.source = source; self.receipts = receipts; self.hooks = hooks
    }

    var context: PlatformQuotaContext? { source?.platformQuotaContext }
    var rows: [UserPlatformQuota] { PlatformQuotaPresentation.ordered(quotas.value ?? [], catalog: catalog) }
    func row(_ platform: String) -> UserPlatformQuota? { quotas.value?.first { $0.platform == platform } }
    var addablePlatforms: [String] { PlatformQuotaPresentation.addablePlatforms(catalog: catalog, existing: quotas.value ?? []) }
    func name(_ platform: String) -> String { PlatformQuotaPresentation.platformName(platform, catalog: catalog) }
    var canWrite: Bool { context.map { !$0.isReadOnlyToken } ?? false }
    func clearSheetError() { sheetError = nil }

    // MARK: - 读取（30 §8.6）

    /// Switching to the segment reads once per page; the read is the store's, so a view scrolled away does not cancel it.
    func enterSegment() async {
        if entryTask == nil { entryTask = Task { await self.refresh() } }
        await entryTask?.value
    }
    /// The pull, and every read after a write that nobody saw.
    func refresh() async {
        if let readTask { return await readTask.value }
        let task = Task { await self.read() }
        readTask = task
        await task.value
        readTask = nil
    }
    private func read() async {
        guard let source, let context else { return }
        if quotas.value == nil { quotas = quotas.withLoading() }
        async let names = readCatalog()
        do {
            let loaded = try await source.platformQuotas(userID: userID)
            let fresh = await names
            guard isCurrent(context.generation) else { return }
            catalog = fresh
            quotas = .loaded(loaded, at: context.now())
        } catch {
            _ = await names
            guard isCurrent(context.generation) else { return }
            guard let failure = PlatformQuotaFailure(error) else { quotas = quotas.withCancelledLoad(); return }
            settleRead(failure)
        }
    }
    private func readCatalog() async -> MetaCatalog { await source?.metaCatalog() ?? catalog }
    private func settleRead(_ failure: PlatformQuotaFailure) {
        switch failure {
        case .unavailable: quotas = .disabled(reason: "SERVICE_UNAVAILABLE")
        case .userGone: hooks.onUserGone()
        default:
            if quotas.value != nil {
                receipts.show(Receipt(text: PlatformQuotaPresentation.refreshFailed, systemImage: "exclamationmark.triangle", tone: .caution))
            }
            quotas = quotas.withFailure(failure.message)
        }
    }

    // MARK: - 保存（30 §8.4）

    /// The sheet's “保存”: true when the sheet may close. Empty limits on a platform with a quota cancel it.
    @discardableResult func save(platform: String, limits: PlatformQuotaLimits) async -> Bool {
        guard let context, canWrite, !busyPlatforms.contains(platform) else { return false }
        sheetError = nil
        do { try limits.validate() } catch { sheetError = PlatformQuotaFailure.invalidLimit.message; return false }
        busyPlatforms.insert(platform)
        defer { busyPlatforms.remove(platform) }
        if context.supportsItemWrites { return await saveItem(platform, limits: limits, context: context) }
        return await saveWhole(platform, limits: limits, context: context)
    }
    private func saveItem(_ platform: String, limits: PlatformQuotaLimits, context: PlatformQuotaContext) async -> Bool {
        guard let source else { return false }
        guard !limits.isEmpty || row(platform) != nil else { return true }
        do {
            let previous: PlatformQuotaLimits?, readable: Bool, current: UserPlatformQuota?
            if limits.isEmpty {
                let result = try await source.deletePlatformQuota(userID: userID, platform: platform)
                (previous, readable, current) = (result.previous, result.previousReadable, nil)
            } else {
                let result = try await source.upsertPlatformQuota(userID: userID, platform: platform, limits: limits)
                (previous, readable, current) = (result.previous, result.previousReadable, result.platformQuota)
            }
            guard isCurrent(context.generation) else { return false }
            put(current, for: platform, at: context)
            var undo: (@MainActor @Sendable () -> Void)?
            if readable, let plan = PlatformQuotaUndo.plan(previous: previous, current: current?.limits) {
                undo = { [self] in Task { await self.undo(platform: platform, plan: plan) } }
            }
            finishWrite(platform, cancelled: current == nil, undo: undo)
            return true
        } catch {
            return await settleWrite(error, context: context)
        }
    }
    /// S3D1-17: GET, change only the target in what came back, PUT that — never the page's copy. An unreadable row stops it.
    private func saveWhole(_ platform: String, limits: PlatformQuotaLimits, context: PlatformQuotaContext) async -> Bool {
        guard let source else { return false }
        do {
            let latest = try await source.platformQuotas(userID: userID)
            guard isCurrent(context.generation) else { return false }
            quotas = .loaded(latest, at: context.now())
            let before = latest.first { $0.platform == platform }?.limits
            guard !limits.isEmpty || before != nil else { return true }
            guard let entries = try? PlatformQuotaFallback.entries(latest: latest, setting: platform, to: limits) else {
                receipts.show(Receipt(text: PlatformQuotaPresentation.unreadable, systemImage: "exclamationmark.triangle", tone: .critical))
                return true
            }
            let fresh = try await source.replaceUserPlatformQuotas(userID: userID, quotas: entries)
            guard isCurrent(context.generation) else { return false }
            quotas = .loaded(fresh, at: context.now())
            let cancelled = !fresh.contains { $0.platform == platform }
            finishWrite(platform, cancelled: cancelled, undo: { [self] in Task { await self.undoWhole(platform: platform, before: before) } })
            return true
        } catch {
            return await settleWrite(error, context: context)
        }
    }
    private func finishWrite(_ platform: String, cancelled: Bool, undo: (@MainActor @Sendable () -> Void)?) {
        let display = name(platform)
        hooks.onApplied(PlatformQuotaPresentation.appliedName(display))
        let text = cancelled ? PlatformQuotaPresentation.cancelledReceipt(display) : PlatformQuotaPresentation.updatedReceipt(display)
        receipts.show(Receipt(text: text, systemImage: "gauge.with.dots.needle.67percent", undo: undo))
    }

    // MARK: - 重置该窗口

    /// After the confirmation: the reply is the whole list; cannot be undone.
    func confirmReset(platform: String, window: PlatformQuotaWindowKind) async {
        guard let source, let context, canWrite, !busyPlatforms.contains(platform) else { return }
        sheetError = nil
        busyPlatforms.insert(platform)
        defer { busyPlatforms.remove(platform) }
        do {
            let fresh = try await source.resetPlatformQuotaWindow(userID: userID, platform: platform, window: window)
            guard isCurrent(context.generation) else { return }
            quotas = .loaded(fresh, at: context.now())
            let display = name(platform)
            hooks.onApplied(PlatformQuotaPresentation.appliedName(display))
            receipts.show(Receipt(text: PlatformQuotaPresentation.resetReceipt(platform: display, kind: window), systemImage: "arrow.counterclockwise"))
        } catch {
            _ = await settleWrite(error, context: context)
        }
    }

    // MARK: - 撤销（30 §8.4）

    /// Runs after the page has gone too. Success shows nothing more; the page stops naming the write.
    func undo(platform: String, plan: PlatformQuotaUndo) async {
        guard let source, let context, canWrite, !busyPlatforms.contains(platform) else { return }
        busyPlatforms.insert(platform)
        defer { busyPlatforms.remove(platform) }
        do {
            let current: UserPlatformQuota?
            switch plan {
            case .delete:
                _ = try await source.deletePlatformQuota(userID: userID, platform: platform)
                current = nil
            case .put(let previous):
                current = try await source.upsertPlatformQuota(userID: userID, platform: platform, limits: previous).platformQuota
            case .restore:
                current = try await source.restorePlatformQuota(userID: userID, platform: platform).platformQuota
            }
            guard isCurrent(context.generation) else { return }
            put(current, for: platform, at: context)
            hooks.onUndone(PlatformQuotaPresentation.appliedName(name(platform)))
        } catch {
            await settleUndo(error, context: context)
        }
    }
    /// The fallback's 撤销: GET again, put the target back, PUT; a row inserted again starts its use from 0, and the receipt says so.
    func undoWhole(platform: String, before: PlatformQuotaLimits?) async {
        guard let source, let context, canWrite, !busyPlatforms.contains(platform) else { return }
        busyPlatforms.insert(platform)
        defer { busyPlatforms.remove(platform) }
        do {
            let latest = try await source.platformQuotas(userID: userID)
            guard isCurrent(context.generation) else { return }
            let after = latest.first { $0.platform == platform }?.limits
            guard let entries = try? PlatformQuotaFallback.undoEntries(latest: latest, platform: platform, before: before) else {
                quotas = .loaded(latest, at: context.now())
                receipts.show(Receipt(text: PlatformQuotaPresentation.undoFailed(PlatformQuotaPresentation.unreadable), systemImage: "exclamationmark.triangle",
                                      tone: .critical))
                return
            }
            let fresh = try await source.replaceUserPlatformQuotas(userID: userID, quotas: entries)
            guard isCurrent(context.generation) else { return }
            quotas = .loaded(fresh, at: context.now())
            let display = name(platform)
            hooks.onUndone(PlatformQuotaPresentation.appliedName(display))
            if PlatformQuotaFallback.undoResetsUsage(before: before, after: after) {
                receipts.show(Receipt(text: PlatformQuotaPresentation.undoResetsUsageReceipt(display), systemImage: "info.circle", tone: .caution))
            }
        } catch {
            await settleUndo(error, context: context)
        }
    }

    // MARK: - 失败（30 §8.5）

    /// true when the sheet may close: the section shows the outcome, or a receipt does.
    private func settleWrite(_ error: any Error, context: PlatformQuotaContext) async -> Bool {
        guard isCurrent(context.generation), let failure = PlatformQuotaFailure(error) else { return false }
        switch failure {
        case .unavailable:
            quotas = .disabled(reason: "SERVICE_UNAVAILABLE")
            return true
        case .userGone:
            hooks.onUserGone()
            return true
        case .quotaGone:
            await refresh()
            return true
        case .unconfirmed:
            await refresh()
            receipts.show(Receipt(text: failure.message, systemImage: "exclamationmark.triangle", tone: .caution))
            return true
        case .invalidLimit, .activeExists, .rejected:
            sheetError = failure.message
            return false
        }
    }
    private func settleUndo(_ error: any Error, context: PlatformQuotaContext) async {
        guard isCurrent(context.generation), let failure = PlatformQuotaFailure(error) else { return }
        switch failure {
        case .unavailable: quotas = .disabled(reason: "SERVICE_UNAVAILABLE")
        case .userGone: hooks.onUserGone()
        case .quotaGone: await refresh()
        case .activeExists:
            await refresh()
            receipts.show(Receipt(text: failure.message, systemImage: "exclamationmark.triangle", tone: .caution))
        case .unconfirmed:
            await refresh()
            receipts.show(Receipt(text: PlatformQuotaPresentation.undoFailed(failure.message), systemImage: "exclamationmark.triangle", tone: .caution))
        case .invalidLimit, .rejected:
            receipts.show(Receipt(text: PlatformQuotaPresentation.undoFailed(failure.message), systemImage: "exclamationmark.triangle", tone: .critical))
        }
    }

    // MARK: - 私有

    private func isCurrent(_ generation: UUID) -> Bool { source?.platformQuotaContext?.generation == generation }
    /// The reply's row replaces the platform's; nil removes it.
    private func put(_ row: UserPlatformQuota?, for platform: String, at context: PlatformQuotaContext) {
        let others = (quotas.value ?? []).filter { $0.platform != platform }
        quotas = .loaded(others + (row.map { [$0] } ?? []), at: context.now())
    }
}
