import Foundation
import Observation
import os
import Sub2Core

/// 00 §7, 60 §7.4 (X03, app-level): this phone's APNs token (in memory only), the switch “在本机接收推送” and device of each
/// site, and the page a tapped notification opens. A device is registered when the switch is turned on, on every connection
/// of a site where it is on (after that site's pending deletions) and when the system hands out a new token. Signing out and
/// deleting a site delete the device through SiteTeardown; here only the session's state ends.
@MainActor @Observable
final class PushCoordinator {
    nonisolated static let tokenTimeout: Duration = .seconds(20)
    /// 60 §7.4 ② when the system never answers (offline, APNs unreachable); the spec has no text for it (S6-23).
    nonisolated static let tokenTimeoutMessage = "没有拿到推送令牌，请检查网络后再试"
    /// How long signing out or deleting the connected site waits for a registration already sent (siteWillEnd).
    nonisolated static let endWait: Duration = .seconds(10)
    private(set) var authorization: PushAuthorization = .notDetermined
    /// The switch is being turned on or off.
    private(set) var isUpdating = false
    private(set) var pendingTarget: PushPendingTarget?
    /// Bumped after every write of the records, which are not observable (S6D2b-05).
    private(set) var revision = 0

    @ObservationIgnored private let records: PushDeviceRecords
    @ObservationIgnored private let authorizer: any NotificationAuthorizing
    @ObservationIgnored private let registrar: any RemoteNotificationRegistering
    @ObservationIgnored private let device: PushDeviceInfo
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    /// Lowercase hex; never stored and never logged.
    @ObservationIgnored private var apnsToken: String?
    @ObservationIgnored private var site: PushSite?
    /// Connect steps and automatic registrations run one at a time; the switch waits for them (S6D2b-05).
    @ObservationIgnored private var queue: Task<Void, Never>?
    /// The automatic registration already sent: once per session and token.
    @ObservationIgnored private var lastAttempt: RegistrationKey?
    @ObservationIgnored private var endedGenerations: [UUID] = []
    @ObservationIgnored private var tokenWaiters: [UUID: CheckedContinuation<TokenReply, Never>] = [:]
    @ObservationIgnored private var lastRefresh: [PushForegroundRefresh: Date] = [:]
    /// The pending target whose site was opened: a login page closed meanwhile is not brought back by the tabs.
    @ObservationIgnored private var openedTarget: UUID?
    /// Registration POSTs out now, and who waits for them to end.
    @ObservationIgnored private var posts = 0
    @ObservationIgnored private var postWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    private static let log = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "push")
    private struct RegistrationKey: Equatable { let generation: UUID; let token: String }
    private enum TokenReply: Sendable { case token(String), failed, timedOut }

    init(records: PushDeviceRecords, authorizer: any NotificationAuthorizing, registrar: any RemoteNotificationRegistering, device: PushDeviceInfo,
         now: @escaping @MainActor () -> Date = { Date() },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.records = records; self.authorizer = authorizer; self.registrar = registrar; self.device = device
        self.now = now; self.sleep = sleep
    }

    // MARK: - Reads

    func registeredDeviceID(serverID: UUID) -> Int? { records.registeredDeviceID(serverID: serverID) }
    func pendingDeletions(serverID: UUID) -> [Int] { records.pendingDeletions(serverID: serverID) }
    func isLocalPushOn(serverID: UUID) -> Bool { records.isLocalPushOn(serverID: serverID) }
    func refreshAuthorization() async { authorization = await authorizer.authorizationStatus() }

    // MARK: - 本机开关（60 §7.4）

    /// Permission, token, then the POST. `config.ready == false` starts nothing (00 §7.1); an unread config does not block.
    func enableLocal(config: PushAPNsConfig?) async -> PushEnableOutcome {
        guard let site, site.supportsPush, !isUpdating else { return .cancelled }
        guard PushPresentation.canEnableLocal(config) else { return .notReady }
        isUpdating = true
        defer { isUpdating = false }
        guard await authorize() else { return .permissionDenied }
        let token: String
        switch await requestToken() {
        case .token(let value): token = value
        case .failed: return .failed(PushPresentation.buildWithoutPush)
        case .timedOut: return .failed(Self.tokenTimeoutMessage)
        }
        await settle()
        guard isCurrent(site) else { return .cancelled }
        switch await register(site, token: token) {
        case .success(let id): return .enabled(deviceID: id)
        case .failure(let error) where error is CancellationError: return .cancelled
        case .failure(let error): return .failed(PushPresentation.failureMessage(error))
        }
    }

    /// A failed DELETE keeps the switch on, so it can be tried again; a device already gone counts as deleted.
    func disableLocal() async -> PushDisableOutcome {
        guard let site, !isUpdating else { return .cancelled }
        isUpdating = true
        defer { isUpdating = false }
        await settle()
        if let id = records.registeredDeviceID(serverID: site.serverID) {
            do { try await delete(id, using: site.api) }
            catch is CancellationError { return .cancelled }
            catch {
                Self.record(error, step: "DELETE admin/push/devices/:id")
                return .failed(PushPresentation.failureMessage(error))
            }
        }
        forget(site.serverID)
        return .disabled
    }

    /// The test push answered 404 PUSH_DEVICE_NOT_FOUND: the switch shows off and stays off until turned on (S6D2b-05).
    func forgetLocalDevice() {
        guard let site else { return }
        forget(site.serverID)
    }

    // MARK: - 会话（AppModel）

    /// After AppModel publishes a session: the address's teardowns, the pending deletions, then the device again when the
    /// switch is on (00 §7.2, §7.6), whether or not the site's APNs is ready (S6D2b-14).
    func siteDidConnect(_ site: PushSite) {
        self.site = site
        lastAttempt = nil
        lastRefresh = [:]
        enqueue { [weak self] in await self?.prepare(site) }
    }

    /// The session ended (signed out, deleted, invalidated). The token and the permission stay; a registration still running
    /// queues its device for deletion. The site's tapped target is dropped, and so is another site's still waiting for these
    /// tabs' sheet.
    func siteDidEnd(serverID: UUID) {
        guard let site, site.serverID == serverID else { return }
        endedGenerations = Array((endedGenerations + [site.generation]).suffix(8))
        self.site = nil
        lastAttempt = nil
        if let pending = pendingTarget, pending.serverID == serverID || pending.id != openedTarget { pendingTarget = nil }
    }

    /// Before signing out or deleting the connected site cancels its client: the session ends here, so nothing new is sent,
    /// and a registration already sent gets up to `endWait` to answer. Cancelled, it may still have created the device, whose
    /// id the teardown would then miss; answered, the id is queued for deletion and the teardown deletes it.
    func siteWillEnd(serverID: UUID) async {
        siteDidEnd(serverID: serverID)
        guard posts > 0 else { return }
        let id = UUID()
        let timer = Task { [weak self, sleep] in
            do { try await sleep(Self.endWait) } catch { return }
            self?.postWaiters.removeValue(forKey: id)?.resume()
        }
        defer { timer.cancel() }
        await withCheckedContinuation { postWaiters[id] = $0 }
    }

    /// Revoking this App's token deleted its device first while the session goes on (BACKLOG “吊销本机令牌失败后的推送设备”).
    func registerAgain() {
        guard let site else { return }
        lastAttempt = nil
        enqueue { [weak self] in await self?.registerIfOn(site) }
    }

    /// Returns once the connect steps and automatic registrations queued so far have run.
    func settle() async {
        while let task = queue {
            await task.value
            if queue == task { return }
        }
    }

    // MARK: - 系统回调

    /// A new token registers the connected site at once; other sites register on their next connection (S6-23).
    func didReceiveDeviceToken(_ deviceToken: Data) {
        let token = PushDeviceRegistration.apnsTokenHex(deviceToken)
        apnsToken = token
        answer(.token(token))
        // Turning the switch on or off sends its own request.
        guard !isUpdating, let site else { return }
        enqueue { [weak self] in await self?.registerIfOn(site) }
    }

    /// 60 §7.5: a build without the push entitlement.
    func didFailToRegister(_ error: any Error) {
        Self.log.notice("registerForRemoteNotifications failed: \(String(describing: type(of: error)), privacy: .public)")
        answer(.failed)
    }

    // MARK: - 通知点按（00 §7.5）

    /// The target waits here for its site's tabs; another site is switched to first, by the connected site's tabs once no
    /// sheet is in use, at once without a connected site.
    func openTap(_ tap: PushTap, navigator: any PushSiteNavigating) async {
        switch PushDeepLink.decision(for: tap, activeServerID: navigator.activeServerID, profiles: navigator.profiles) {
        case .openOnly: pendingTarget = nil
        case .current(let serverID, let target): pendingTarget = PushPendingTarget(serverID: serverID, target: target)
        case .otherSite(let profile, let target):
            pendingTarget = PushPendingTarget(serverID: profile.id, target: target)
            if navigator.activeServerID == nil { await openPendingSite(from: nil, navigator: navigator) }
        }
    }

    /// Another site's target waits for the sheet like this site's (S6D2b-07): switching rebuilds the tabs and cancels the
    /// connected site's requests, a write in the sheet included. Its site is opened once; one that cannot be opened, or is
    /// gone, drops it.
    func openPendingSite(from router: AppRouter?, navigator: any PushSiteNavigating) async {
        guard router?.presentedSheet == nil, let pending = pendingTarget, pending.id != openedTarget,
              pending.serverID != navigator.activeServerID else { return }
        openedTarget = pending.id
        guard let profile = navigator.profiles.first(where: { $0.id == pending.serverID }) else { pendingTarget = nil; return }
        if await navigator.openSite(profile) == .failed, pendingTarget == pending { pendingTarget = nil }
    }

    func takeTarget(for serverID: UUID) -> PushTarget? {
        guard let pending = pendingTarget, pending.serverID == serverID else { return nil }
        pendingTarget = nil
        return pending.target
    }

    /// One refresh of each kind per interval (S6D2b-08): an upstream outage can push many account errors in one round.
    func foregroundRefresh(for tap: PushTap, activeServerID: UUID?) -> PushForegroundRefresh? {
        guard let kind = PushDeepLink.foregroundRefresh(for: tap, activeServerID: activeServerID) else { return nil }
        let time = now()
        if let last = lastRefresh[kind], time.timeIntervalSince(last) < kind.interval { return nil }
        lastRefresh[kind] = time
        return kind
    }

    // MARK: - Private

    private func isCurrent(_ site: PushSite) -> Bool { self.site?.generation == site.generation }
    private func hasEnded(_ site: PushSite) -> Bool { endedGenerations.contains(site.generation) }
    /// A device id without the switch is a registration from before the switch was stored.
    private func isOn(_ serverID: UUID) -> Bool { records.isLocalPushOn(serverID: serverID) || records.registeredDeviceID(serverID: serverID) != nil }

    private func enqueue(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let previous = queue
        queue = Task { await previous?.value; await work() }
    }

    private func prepare(_ site: PushSite) async {
        await site.waitForTeardowns()
        guard isCurrent(site) else { return }
        await deletePending(of: site)
        await registerIfOn(site)
    }

    /// The device registered again stays pending until that registration resolves it (S6D2b-05).
    private func deletePending(of site: PushSite) async {
        var deleted: [Int] = []
        for id in records.pendingDeletions(serverID: site.serverID) where isCurrent(site) && id != records.registeredDeviceID(serverID: site.serverID) {
            do { try await delete(id, using: site.api); deleted.append(id) }
            catch { Self.record(error, step: "DELETE admin/push/devices/:id") }
        }
        guard !deleted.isEmpty else { return }
        records.resolvePendingDeletions(deleted, serverID: site.serverID)
        revision += 1
    }

    /// With the token in memory, or by asking the system for one without asking the user (00 §7.1).
    private func registerIfOn(_ site: PushSite) async {
        guard isCurrent(site), site.supportsPush, isOn(site.serverID) else { return }
        if let apnsToken {
            guard lastAttempt != RegistrationKey(generation: site.generation, token: apnsToken) else { return }
            _ = await register(site, token: apnsToken)
            return
        }
        await refreshAuthorization()
        guard isCurrent(site), authorization == .authorized else { return }
        registrar.registerForRemoteNotifications(reportingTo: self)
    }

    /// One POST (00 §7.2, sent once, R06). The id is kept for the site, or queued for deletion when its session ended
    /// meanwhile; a switch to another site keeps it, since switching deletes nothing.
    private func register(_ site: PushSite, token: String) async -> Result<Int, any Error> {
        let key = RegistrationKey(generation: site.generation, token: token)
        lastAttempt = key
        await site.waitForTeardowns()
        guard !hasEnded(site) else { return .failure(CancellationError()) }
        let registration = PushDeviceRegistration.ios(apnsToken: token, bundleID: device.bundleID, deviceName: device.deviceName(),
                                                      timezone: device.timeZone(), siteID: site.serverID, sandbox: device.sandbox)
        posts += 1
        defer { posts -= 1; if posts == 0 { endPostWaits() } }
        do {
            let id = try await site.api.registerPushDevice(registration).device.id
            keep(id, of: site)
            return hasEnded(site) ? .failure(CancellationError()) : .success(id)
        } catch {
            if lastAttempt == key { lastAttempt = nil }
            Self.record(error, step: "POST admin/push/devices")
            return .failure(error)
        }
    }

    private func keep(_ id: Int, of site: PushSite) {
        if hasEnded(site) {
            records.apply(TeardownReport(failedPushDeviceIDs: [id]), serverID: site.serverID)
        } else {
            records.setRegisteredDeviceID(id, serverID: site.serverID)
            records.setLocalPushOn(true, serverID: site.serverID)
            records.resolvePendingDeletions([id], serverID: site.serverID)
        }
        revision += 1
    }

    private func endPostWaits() {
        let waiting = Array(postWaiters.values)
        postWaiters.removeAll()
        for continuation in waiting { continuation.resume() }
    }

    private func forget(_ serverID: UUID) {
        records.setRegisteredDeviceID(nil, serverID: serverID)
        records.setLocalPushOn(false, serverID: serverID)
        lastAttempt = nil
        revision += 1
    }

    /// A device the server no longer has counts as deleted (00 §3.2), as in SiteTeardown.
    private func delete(_ id: Int, using api: any PushDeviceAPI) async throws {
        do { try await api.deletePushDevice(id: id) }
        catch let error as APIError where error.category == .notFound || error.category == .unsupported {}
    }

    /// Asked only from the switch, and only before the system has an answer (00 §7.1).
    private func authorize() async -> Bool {
        await refreshAuthorization()
        guard authorization == .notDetermined else { return authorization == .authorized }
        do {
            let granted = try await authorizer.requestAuthorization()
            authorization = granted ? .authorized : .denied
            return granted
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    private func requestToken() async -> TokenReply {
        if let apnsToken { return .token(apnsToken) }
        let id = UUID()
        let timer = Task { [weak self, sleep] in
            do { try await sleep(Self.tokenTimeout) } catch { return }
            self?.answer(.timedOut, waiter: id)
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { continuation in
            tokenWaiters[id] = continuation
            registrar.registerForRemoteNotifications(reportingTo: self)
        }
    }
    /// Every waiter, or only `id`'s; a late answer finds none.
    private func answer(_ reply: TokenReply, waiter id: UUID? = nil) {
        let waiting = id.map { tokenWaiters.removeValue(forKey: $0).map { [$0] } ?? [] } ?? Array(tokenWaiters.values)
        if id == nil { tokenWaiters.removeAll() }
        for continuation in waiting { continuation.resume(returning: reply) }
    }

    /// Path template, status, reason and request ID only (00 §3.4).
    private static func record(_ error: any Error, step: String) {
        guard let error = error as? APIError else {
            log.notice("\(step, privacy: .public) failed: \(String(describing: type(of: error)), privacy: .public)")
            return
        }
        log.notice("\(step, privacy: .public) failed: \(error.statusCode ?? 0, privacy: .public) \(error.reason ?? "-", privacy: .public) \(error.requestID ?? "-", privacy: .public)")
    }
}
