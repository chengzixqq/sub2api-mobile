import Foundation
import Observation
import os
import Sub2Core

/// What AlertActions asks of LiveOpsStore: the local copies of an event, the reads after a write, and the ops switch's one entry
/// (S1D1-02). `isSessionCurrent` turns false once the session ended; nothing is sent or shown after that.
@MainActor protocol AlertActionsHost: AnyObject {
    var isSessionCurrent: Bool { get }
    func markResolved(eventID: Int, at date: Date)
    func applySilence(eventID: Int, _ silence: AlertSilenceRef?)
    func upsertAlert(_ event: AlertEvent) async
    func removeAlert(eventID: Int)
    func refreshAlertsAfterWrite() async
    func noteOpsDisabled() async
    func noteExternalWrite()
}

/// C-6: how a write ended. `ignored`: nothing was sent or shown (a second tap, an action the event does not offer, or the session
/// ended meanwhile).
enum AlertActionOutcome: Equatable, Sendable {
    case succeeded, notApplied, unconfirmed, failed, eventMissing, opsDisabled, ignored
}

/// 10 §7.1, C-6: 手动解决, 静默, 改静默时长 and 结束静默 for the overview, the monitor, the alert detail and the account tab; one per
/// session, held by LiveOpsStore, so all of them show the same result. These are unkeyed writes (00 §2.4): never sent twice by
/// themselves; when no answer came (or a gateway's 502 / 503 / 504) the event read back decides. A failure changes nothing here.
/// Each success reads the event and the lists again, since the server answers even for an event that is gone (BACKLOG D06).
@MainActor @Observable
final class AlertActions {
    /// Events with a write on the way; their buttons wait (C-6 `isRunning`).
    private(set) var inFlight: Set<Int> = []
    /// Receipt buttons tapped while their event was running, in tap order; each takes the event's turn when the write before ends.
    @ObservationIgnored private var queued: [Int: [CheckedContinuation<Void, Never>]] = [:]
    /// Rules the server refused to silence (400 INVALID_RULE_ID), for this session.
    private(set) var silenceRejectedRuleIDs: Set<Int> = []
    @ObservationIgnored weak var host: (any AlertActionsHost)?
    private let source: any AlertActionSource
    private let receipts: ReceiptCenter
    private let timeZone: @MainActor () -> TimeZone
    private let now: @Sendable () -> Date
    private static let log = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "alerts")

    /// `timeZone` is the server's and `now` its corrected clock: an `until` is the server's now plus the duration (10 §7.1).
    init(source: any AlertActionSource, receipts: ReceiptCenter, timeZone: @escaping @MainActor () -> TimeZone, now: @escaping @Sendable () -> Date) {
        self.source = source; self.receipts = receipts; self.timeZone = timeZone; self.now = now
    }

    func availableActions(for event: AlertEvent) -> [AlertActionKind] {
        AlertActionCopy.availableActions(event: event, silenceRejected: event.ruleID.map { silenceRejectedRuleIDs.contains($0) } ?? false)
    }
    func isRunning(_ eventID: Int) -> Bool { inFlight.contains(eventID) }
    func dialog(for kind: AlertActionKind, event: AlertEvent) -> AlertActionDialog {
        AlertActionCopy.dialog(kind, event: event, now: now(), timeZone: timeZone())
    }

    /// A dialog's choice: a duration on a silenced event changes its silence.
    @discardableResult func perform(_ choice: AlertActionDialog.Choice, on event: AlertEvent) async -> AlertActionOutcome {
        switch choice {
        case .resolve: return await resolve(event)
        case .silence(let duration) where event.silence == nil: return await silence(event, for: duration)
        case .silence(let duration): return await changeSilence(event, to: duration)
        case .endSilence: return await endSilence(event)
        }
    }

    @discardableResult func resolve(_ event: AlertEvent) async -> AlertActionOutcome {
        guard availableActions(for: event).contains(.resolve) else { return .ignored }
        let source = source, now = now, id = event.id
        return await execute(event, Step(intent: .resolve, route: "PUT ops/alert-events/:id/status") {
            try await source.setAlertEventStatus(id: id, status: AlertEvent.manualResolved)
            return .resolved(at: now())
        })
    }
    @discardableResult func silence(_ event: AlertEvent, for duration: AlertSilenceDuration) async -> AlertActionOutcome {
        guard availableActions(for: event).contains(.silence), let ruleID = event.ruleID else { return .ignored }
        let source = source, until = duration.until(from: now()), platform = event.platform, groupID = event.groupID
        return await execute(event, Step(intent: .silence(duration), route: "POST ops/alert-silences") {
            let created = try await source.createAlertSilence(ruleID: ruleID, platform: platform, groupID: groupID, until: until)
            return .silence(AlertSilenceRef(id: created.id, until: created.until ?? until))
        })
    }
    @discardableResult func changeSilence(_ event: AlertEvent, to duration: AlertSilenceDuration) async -> AlertActionOutcome {
        guard availableActions(for: event).contains(.changeSilence), let current = event.silence else { return .ignored }
        return await execute(event, change(current.id, to: duration.until(from: now()), isUndo: false))
    }
    @discardableResult func endSilence(_ event: AlertEvent) async -> AlertActionOutcome {
        guard availableActions(for: event).contains(.changeSilence), let current = event.silence else { return .ignored }
        return await execute(event, end(current.id, isUndo: false))
    }

    // MARK: 写入、读回与回执

    private enum Applied: Sendable { case resolved(at: Date), silence(AlertSilenceRef?) }
    /// One request: what a read-back must show, its route template for the log, and whether it undoes an earlier write (an undo
    /// shows no receipt when it works, and says 撤销没有成功 when it does not).
    private struct Step: Sendable {
        let intent: AlertWriteIntent
        let route: String
        var isUndo = false
        let send: @Sendable () async throws -> Applied
    }

    private func change(_ silenceID: Int, to until: Date, isUndo: Bool) -> Step {
        let source = source
        return Step(intent: .changeSilence(until: until), route: "PUT ops/alert-silences/:id", isUndo: isUndo) {
            let updated = try await source.updateAlertSilence(id: silenceID, until: until)
            return .silence(AlertSilenceRef(id: updated.id, until: updated.until ?? until))
        }
    }
    private func end(_ silenceID: Int, isUndo: Bool) -> Step {
        let source = source
        return Step(intent: .endSilence, route: "DELETE ops/alert-silences/:id", isUndo: isUndo) {
            try await source.deleteAlertSilence(id: silenceID)
            return .silence(nil)
        }
    }

    private var liveHost: (any AlertActionsHost)? { host?.isSessionCurrent == true ? host : nil }

    private func execute(_ event: AlertEvent, _ step: Step) async -> AlertActionOutcome {
        guard liveHost != nil, inFlight.insert(event.id).inserted else { return .ignored }
        return await run(event, step)
    }
    /// From a receipt's button: an undo or a retry. The receipt shows before its write reads back, so a tap may come while the
    /// event is still running: it then waits for that write to end and is sent after it, never dropped.
    private func start(_ event: AlertEvent, _ step: Step) {
        Task { [weak self] in
            guard let self else { return }
            if !inFlight.insert(event.id).inserted { await withCheckedContinuation { queued[event.id, default: []].append($0) } }
            _ = await run(event, step)
        }
    }
    /// Holds the event's turn until it returns, then hands it to the next waiting receipt button, or frees it.
    private func run(_ event: AlertEvent, _ step: Step) async -> AlertActionOutcome {
        defer { passTurn(event.id) }
        guard liveHost != nil else { return .ignored }
        do {
            let applied = try await step.send()
            return await complete(event, step, applied, readBack: nil)
        } catch {
            return await recover(event, step, error)
        }
    }
    private func passTurn(_ eventID: Int) {
        guard var waiting = queued.removeValue(forKey: eventID), !waiting.isEmpty else { inFlight.remove(eventID); return }
        let next = waiting.removeFirst()
        if !waiting.isEmpty { queued[eventID] = waiting }
        next.resume()
    }

    /// The write landed: the local copies change and the receipt shows, then the event and the lists are read again.
    private func complete(_ event: AlertEvent, _ step: Step, _ applied: Applied, readBack: AlertEvent?) async -> AlertActionOutcome {
        guard let host = liveHost else { return .ignored }
        switch applied {
        case .resolved(let at): host.markResolved(eventID: event.id, at: at)
        case .silence(let silence): host.applySilence(eventID: event.id, silence)
        }
        if !step.isUndo { receipts.show(successReceipt(event, step.intent, applied)) }
        guard let readBack else { return await reread(event.id) }
        await host.upsertAlert(readBack)
        await host.refreshAlertsAfterWrite()
        return .succeeded
    }
    /// The event as the server now has it, then the firing list and the counts; a gone event leaves every list.
    private func reread(_ eventID: Int) async -> AlertActionOutcome {
        do {
            let fresh = try await source.alertEvent(id: eventID)
            guard let host = liveHost else { return .ignored }
            await host.upsertAlert(fresh)
            await host.refreshAlertsAfterWrite()
            return .succeeded
        } catch {
            let failure = Self.apiError(error)
            if AlertWriteFailure(failure) == .eventMissing { return await eventMissing(eventID, failure) }
            guard !(error is CancellationError), let host = liveHost else { return .ignored }
            await host.refreshAlertsAfterWrite()
            return .succeeded
        }
    }
    private func eventMissing(_ eventID: Int, _ error: APIError) async -> AlertActionOutcome {
        guard let host = liveHost else { return .ignored }
        host.removeAlert(eventID: eventID)
        receipts.show(Self.failureReceipt(AlertActionCopy.message(for: error)))
        await host.refreshAlertsAfterWrite()
        return .eventMissing
    }

    /// 10 §7.1 error table; nothing local changes.
    private func recover(_ event: AlertEvent, _ step: Step, _ error: any Error) async -> AlertActionOutcome {
        guard !(error is CancellationError), let host = liveHost else { return .ignored }
        let failure = Self.apiError(error)
        let text = AlertActionCopy.message(for: failure)
        let receipt = Self.failureReceipt(step.isUndo ? AlertActionCopy.undoFailedReceipt(text) : text)
        switch AlertWriteFailure(failure) {
        case .resultUnknown:
            return await verify(event, step)
        case .eventMissing:
            return await eventMissing(event.id, failure)
        case .opsDisabled:
            await host.noteOpsDisabled()
            host.noteExternalWrite()
            receipts.show(receipt)
            return .opsDisabled
        case .silenceMissing:
            receipts.show(receipt)
            _ = await reread(event.id)
            return .failed
        case .ruleRejected:
            if let ruleID = event.ruleID { silenceRejectedRuleIDs.insert(ruleID) }
        case .programError:
            let status = failure.statusCode ?? 0, reason = failure.reason ?? "-", requestID = failure.requestID ?? "-"
            Self.log.error("\(step.route, privacy: .public) \(status, privacy: .public) \(reason, privacy: .public) X-Request-ID \(requestID, privacy: .public)")
        case .invalidUntil, .readOnly, .other:
            break
        }
        receipts.show(receipt)
        return .failed
    }
    /// 00 §2.4: no answer came. The event read now decides; when that read fails too, the result stays unconfirmed.
    private func verify(_ event: AlertEvent, _ step: Step) async -> AlertActionOutcome {
        let fresh: AlertEvent
        do {
            fresh = try await source.alertEvent(id: event.id)
        } catch {
            let failure = Self.apiError(error)
            if [.eventMissing, .opsDisabled].contains(AlertWriteFailure(failure)) { return await recover(event, step, failure) }
            guard !(error is CancellationError), liveHost != nil else { return .ignored }
            receipts.show(Self.failureReceipt(AlertActionCopy.unconfirmedReceipt))
            return .unconfirmed
        }
        guard liveHost != nil else { return .ignored }
        guard AlertActionCopy.readBackConfirms(step.intent, event: fresh) else {
            let retry = ReceiptAction(title: AlertActionCopy.retryTitle, perform: rerun(event, step))
            receipts.show(Receipt(text: AlertActionCopy.notAppliedReceipt, systemImage: "exclamationmark.triangle", tone: .caution, action: retry))
            return .notApplied
        }
        let applied: Applied = step.intent == .resolve ? .resolved(at: fresh.resolvedAt ?? now()) : .silence(fresh.silence)
        return await complete(event, step, applied, readBack: fresh)
    }

    /// 10 §7.1 step 3: a new silence is undone by ending it; a changed one by changing it back, unless that time has passed.
    private func successReceipt(_ event: AlertEvent, _ intent: AlertWriteIntent, _ applied: Applied) -> Receipt {
        let silence: AlertSilenceRef? = if case .silence(let ref) = applied { ref } else { nil }
        switch intent {
        case .resolve:
            return Receipt(text: AlertActionCopy.resolvedReceipt)
        case .silence(let duration):
            let undo = silence.map { rerun(event, end($0.id, isUndo: true)) }
            return Self.silenceReceipt(AlertActionCopy.silencedReceipt(duration), undo: undo)
        case .changeSilence(let until):
            let text = AlertActionCopy.changedReceipt(until: silence?.until ?? until, now: now(), timeZone: timeZone())
            guard let previous = event.silence, let previousUntil = previous.until, previousUntil > now() else { return Self.silenceReceipt(text, undo: nil) }
            return Self.silenceReceipt(text, undo: rerun(event, change(silence?.id ?? previous.id, to: previousUntil, isUndo: true)))
        case .endSilence:
            return Self.silenceReceipt(AlertActionCopy.endedReceipt, undo: nil)
        }
    }

    private func rerun(_ event: AlertEvent, _ step: Step) -> @MainActor @Sendable () -> Void {
        { [weak self] in self?.start(event, step) }
    }
    private static func silenceReceipt(_ text: String, undo: (@MainActor @Sendable () -> Void)?) -> Receipt {
        Receipt(text: text, systemImage: "hourglass", tone: .neutral, undo: undo)
    }
    private static func failureReceipt(_ text: String) -> Receipt { Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .caution) }
    /// Every request goes through APIClient, which only throws APIError (or cancellation); anything else had no answer either.
    private static func apiError(_ error: any Error) -> APIError { error as? APIError ?? APIError(kind: .transport, message: "无法连接站点") }
}
