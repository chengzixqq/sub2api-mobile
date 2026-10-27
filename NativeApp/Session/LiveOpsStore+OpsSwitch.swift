import Foundation
import Sub2Core

// S1-08, 10 §7.2, U10: turning ops monitoring on (OpsDisabledNotice) and off (the monitor's ··· menu, S1-13). Both are unkeyed
// writes (00 §2.4): no Idempotency-Key, no step-up, never sent twice by themselves; without an answer `monitoring-status` is read
// back. Which endpoint writes is only OpsMonitoringWriteRoute's choice (S1D1-07). A result that lands after the session ended
// changes nothing and shows nothing.

private typealias ToggleOutcome = OpsDisabledPresentation.ToggleOutcome

/// What LiveOpsStore knows about the switch. The newest server signal wins over `/admin/me`'s snapshot (S1D1-02).
struct OpsSwitchState: Sendable, Equatable {
    enum Phase: Sendable, Equatable { case idle, enabling, disabling, verifying }
    /// Other instances read the switch every 30 seconds (ops_service.go:27): after turning it on the blocks are read once more after
    /// this while they still say off, and once they say on, “off” is ignored until this has passed since the write; after turning it
    /// off their “on” is ignored for as long.
    static let recheckDelay: TimeInterval = 30

    private(set) var phase: Phase = .idle
    /// true for off: a home block, a gated read or a switch reply said so last; nil until one did.
    private(set) var latestDisabled: Bool?
    /// The latest `monitoring-status` reply, for the reason.
    private(set) var status: OpsMonitoringStatus?
    /// D09: the settings PUT went through yet monitoring stayed off, so the server configuration holds it.
    private(set) var legacyConfigOff = false
    /// This off period's reason was read, or is being read.
    private(set) var reasonRead = false
    /// Each switch that took effect and each recheck; the monitor, the alert detail and statistics reload on it.
    private(set) var revision = 0
    private(set) var disabledAt: Date?
    private(set) var enabledAt: Date?

    func isDisabled(snapshot: Bool) -> Bool { legacyConfigOff || (latestDisabled ?? snapshot) }

    mutating func note(disabled: Bool, at now: Date) {
        if disabled {
            if let enabledAt, now.timeIntervalSince(enabledAt) < Self.recheckDelay { return }
            if latestDisabled != true { reasonRead = false }
            latestDisabled = true; enabledAt = nil
            return
        }
        if let disabledAt, now.timeIntervalSince(disabledAt) < Self.recheckDelay { return }
        latestDisabled = false; legacyConfigOff = false; disabledAt = nil
        if status?.effective != true { status = nil }
    }
    /// A switch write's reply or its read-back: it says on or off.
    mutating func record(_ reply: OpsMonitoringStatus) {
        status = reply; reasonRead = true
        latestDisabled = reply.effective != true
        if reply.effective == true { legacyConfigOff = false; disabledAt = nil }
    }
    /// A read for the reason only: an instance that has not switched yet may still say otherwise, so the blocks decide on or off.
    mutating func recordReason(_ reply: OpsMonitoringStatus) { status = reply; reasonRead = true }
    mutating func claimReasonRead() -> Bool {
        guard !reasonRead else { return false }
        reasonRead = true
        return true
    }
    mutating func releaseReasonRead() { reasonRead = false }
    /// Only one switch write at a time.
    mutating func begin(_ next: Phase) -> Bool {
        guard phase == .idle else { return false }
        phase = next
        return true
    }
    mutating func enterVerifying() { phase = .verifying }
    mutating func markDisabledByApp(at now: Date) { disabledAt = now; enabledAt = nil }
    /// The blocks said on after the App's write at `writtenAt`.
    mutating func markEnabledByApp(at writtenAt: Date) { enabledAt = writtenAt }
    mutating func markLegacyConfigOff() { legacyConfigOff = true; latestDisabled = true }
    mutating func bumpRevision() { revision += 1 }
    mutating func finish() { phase = .idle }
}

/// How one write came back.
private enum SwitchReply { case status(OpsMonitoringStatus), sent, refused(ToggleOutcome), dropped }

extension LiveOpsStore {
    var opsDisabledReason: OpsDisabledReason {
        OpsDisabledPresentation.reason(status: opsSwitch.status, legacyConfigOff: opsSwitch.legacyConfigOff, features: site()?.me.features ?? .init())
    }
    var isTogglingOps: Bool { opsSwitch.phase != .idle }
    var opsRevision: Int { opsSwitch.revision }
    var opsWriteRoute: OpsMonitoringWriteRoute { site().map { OpsMonitoringWriteRoute.resolve(me: $0.me) } ?? .unavailable }
    var canEnableOpsInApp: Bool { opsWriteRoute != .unavailable }
    /// Whether the viewer is the owner is the page's check (OpsDisabledPresentation.offersDisable).
    var canDisableOpsMonitoring: Bool { opsWriteRoute == .monitoringStatus && !opsDisabled }

    /// nil: a switch write is already on its way, or the session ended. On success the blocks are read again at once (nocache) and,
    /// while they still say off, once more after 30 seconds (10 §7.2 step 3); the old route answers only after that (D09).
    @discardableResult func enableOpsMonitoring() async -> OpsDisabledPresentation.ToggleOutcome? {
        guard isCurrent() else { return nil }
        let route = opsWriteRoute
        guard route != .unavailable else { return conclude(.failed(OpsDisabledPresentation.unsupportedMessage)) }
        guard opsSwitch.begin(.enabling) else { return nil }
        let reply = await send(enabled: true, route: route)
        guard isCurrent() else { return dropped() }
        let writtenAt = localNow()
        switch reply {
        case .dropped: return dropped()
        case .refused(let outcome): return await refused(outcome)
        case .sent: return await confirmEnabled(announced: false, writtenAt: writtenAt)
        case .status(let status):
            opsSwitch.record(status)
            let outcome = OpsDisabledPresentation.enableOutcome(status)
            guard outcome == .enabled else { return conclude(outcome) }
            show(outcome)
            return await confirmEnabled(announced: true, writtenAt: writtenAt)
        }
    }
    /// U10: only through `monitoring-status`. The notice shows at once; for 30 seconds other instances' “on” is not believed.
    @discardableResult func disableOpsMonitoring() async -> OpsDisabledPresentation.ToggleOutcome? {
        guard isCurrent() else { return nil }
        guard opsWriteRoute == .monitoringStatus else { return conclude(.failed(OpsDisabledPresentation.unsupportedMessage)) }
        guard opsSwitch.begin(.disabling) else { return nil }
        let reply = await send(enabled: false, route: .monitoringStatus)
        guard isCurrent() else { return dropped() }
        switch reply {
        case .dropped, .sent: return dropped()
        case .refused(let outcome): return await refused(outcome)
        case .status(let status):
            opsSwitch.record(status)
            let outcome = OpsDisabledPresentation.disableOutcome(status)
            guard outcome == .disabled else { return conclude(outcome) }
            opsSwitch.markDisabledByApp(at: localNow())
            show(outcome)
            await refreshAfterSwitch()
            guard isCurrent() else { return dropped() }
            opsSwitch.bumpRevision()
            opsSwitch.finish()
            return outcome
        }
    }
    /// 10 §7.2 判定: once per off period, on a site with `ops.monitoring_status`, outside a switch write. A failed read is tried
    /// again with the next signal.
    func resolveOpsDisabledReasonIfNeeded() async {
        guard isCurrent(), opsDisabled, opsSwitch.phase == .idle, site()?.has(.opsMonitoringStatus) == true, opsSwitch.claimReasonRead() else { return }
        do {
            let status = try await source.opsMonitoringStatus()
            if isCurrent() { opsSwitch.recordReason(status) }
        } catch {
            if isCurrent() { opsSwitch.releaseReasonRead() }
        }
    }

    // MARK: 写入与结论

    private func send(enabled: Bool, route: OpsMonitoringWriteRoute) async -> SwitchReply {
        let source = source
        do {
            guard route == .monitoringStatus else {
                try await source.enableOpsMonitoringLegacy()
                return .sent
            }
            return .status(try await source.setOpsMonitoring(enabled: enabled))
        } catch {
            guard let outcome = OpsDisabledPresentation.failureOutcome(error) else { return .dropped }
            // 00 §2.4: not sent again; the switch as the server now has it decides. The old route has nothing to read back.
            guard outcome == .unconfirmed, route == .monitoringStatus, isCurrent() else { return .refused(outcome) }
            guard let status = try? await source.opsMonitoringStatus() else { return .refused(.unconfirmed) }
            return .status(status)
        }
    }
    /// The blocks say whether it took; when they still say off, they are read once more after the other instances caught up.
    private func confirmEnabled(announced: Bool, writtenAt: Date) async -> ToggleOutcome? {
        await refreshAfterSwitch()
        guard isCurrent() else { return dropped() }
        opsSwitch.bumpRevision()
        guard opsDisabled else { return confirmedOn(announced: announced, writtenAt: writtenAt) }
        opsSwitch.enterVerifying()
        do { try await sleep(.seconds(OpsSwitchState.recheckDelay)) } catch { return announced ? finished(.enabled) : dropped() }
        guard isCurrent() else { return dropped() }
        await refreshAfterSwitch()
        guard isCurrent() else { return dropped() }
        opsSwitch.bumpRevision()
        guard opsDisabled else { return confirmedOn(announced: announced, writtenAt: writtenAt) }
        guard announced else {
            opsSwitch.markLegacyConfigOff()
            return conclude(.configOff)
        }
        // The server accepted it yet the blocks still say off: the reason now shown comes from the switch as read now.
        if let status = try? await source.opsMonitoringStatus(), isCurrent() { opsSwitch.recordReason(status) }
        return finished(.enabled)
    }
    /// Instances that have not read the switch yet still say off; for the rest of 30 seconds from the write that is not believed.
    private func confirmedOn(announced: Bool, writtenAt: Date) -> ToggleOutcome {
        opsSwitch.markEnabledByApp(at: writtenAt)
        return announced ? finished(.enabled) : conclude(.enabled)
    }
    /// 409 OPS_CONFIG_DISABLED is the configuration's word; no answer means the blocks show what the server now has.
    private func refused(_ outcome: ToggleOutcome) async -> ToggleOutcome? {
        switch outcome {
        case .configOff:
            opsSwitch.record(OpsMonitoringStatus(configEnabled: false, effective: false, disabledReason: OpsDisabledReason.configOff.rawValue))
        case .unconfirmed:
            show(outcome)
            await refreshAfterSwitch()
            return isCurrent() ? finished(outcome) : dropped()
        case .enabled, .disabled, .failed:
            break
        }
        return conclude(outcome)
    }
    private func refreshAfterSwitch() async {
        await refreshHome(noCache: true)
        await refreshFiringAlerts(maxAge: 0)
    }
    private func show(_ outcome: ToggleOutcome) {
        receipts.show(Receipt(text: outcome.receiptText, systemImage: outcome.receiptImage, tone: outcome.receiptTone))
    }
    /// Shows the outcome's receipt and ends the write.
    private func conclude(_ outcome: ToggleOutcome) -> ToggleOutcome {
        show(outcome)
        return finished(outcome)
    }
    private func finished(_ outcome: ToggleOutcome) -> ToggleOutcome {
        opsSwitch.finish()
        return outcome
    }
    private func dropped() -> ToggleOutcome? {
        opsSwitch.finish()
        return nil
    }
}
