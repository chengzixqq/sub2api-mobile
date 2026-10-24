import Foundation
import Observation
import Sub2Core

/// The one global security sheet (00 §2.7.1, §9.5): a single prompt at a time; requests of the same kind share it, other
/// kinds wait in order. Every waiter is resumed exactly once — by `complete`, by its own cancellation or by `reset`.
@MainActor @Observable
final class SecurityPromptCenter {
    struct Prompt: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable { case compliance, stepUpVerify, stepUpNoTOTP }
        let id: UUID
        let kind: Kind
        /// The session it belongs to; `reset` drops it when that session ends.
        let generation: UUID
        /// For example “把「Alice」设为管理员”; nil uses the general sentence.
        let purpose: String?
        /// Only reads wait: verification continues them on its own; a write returns to its confirmation.
        let isRead: Bool
    }
    /// A late refusal of a request sent before the prompt was answered is let through instead of asking again.
    static let compliancePassWindow: TimeInterval = 10
    static let stepUpGrantWindow: TimeInterval = 5

    private(set) var active: Prompt?
    /// Bumped when compliance is accepted, so read blocks reload (00 §1.10).
    private(set) var complianceRevision = 0
    @ObservationIgnored private var queue: [Prompt] = []
    @ObservationIgnored private var waiters: [UUID: [UUID: CheckedContinuation<SecurityPromptOutcome, Never>]] = [:]
    @ObservationIgnored private var compliancePassed: (generation: UUID, at: Date)?
    /// Sessions whose administrator chose “稍后”: background reads stop asking (writes still ask).
    @ObservationIgnored private var complianceDeclined: Set<UUID> = []
    @ObservationIgnored private var grants: [UUID: (expiresAt: Date, recordedAt: Date)] = [:]
    private let now: @MainActor () -> Date

    init(now: @escaping @MainActor () -> Date = { Date() }) { self.now = now }

    /// Waits for the administrator's answer; a cancelled caller gets `.cancelled` without closing a prompt others share.
    func present(_ kind: Prompt.Kind, purpose: String?, isRead: Bool, generation: UUID) async -> SecurityPromptOutcome {
        guard !Task.isCancelled else { return .cancelled }
        if let shortcut = shortcut(kind, isRead: isRead, generation: generation) { return shortcut }
        let promptID = enqueue(kind, purpose: purpose, isRead: isRead, generation: generation)
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, isPending(promptID) else { continuation.resume(returning: .cancelled); return }
                waiters[promptID, default: [:]][waiterID] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resume(waiterID, of: promptID, with: .cancelled) }
        }
    }
    /// The sheet's answer; it resumes everybody waiting on the prompt and shows the next one.
    func complete(_ promptID: UUID, outcome: SecurityPromptOutcome) {
        guard let prompt = active, prompt.id == promptID else { return }
        if prompt.kind == .compliance {
            switch outcome {
            case .passed:
                complianceRevision += 1
                compliancePassed = (prompt.generation, now()); complianceDeclined.remove(prompt.generation)
            case .cancelled: complianceDeclined.insert(prompt.generation)
            case .blocked: break
            }
        }
        active = queue.isEmpty ? nil : queue.removeFirst()
        for continuation in (waiters.removeValue(forKey: promptID) ?? [:]).values { continuation.resume(returning: outcome) }
    }
    /// 00 §2.6.2 step 3: now plus `expires_in`, kept per session; an unknown remainder records nothing.
    func recordStepUpGrant(expiresIn: Int?, generation: UUID) {
        let recordedAt = now()
        guard let expiresAt = StepUpGrant(verified: true, expiresIn: expiresIn).expiresAt(from: recordedAt) else { return }
        grants[generation] = (expiresAt, recordedAt)
    }
    func localGrantExpiry(generation: UUID) -> Date? { grants[generation]?.expiresAt }
    /// Callers still waiting on any prompt.
    var waitingCount: Int { waiters.values.reduce(0) { $0 + $1.count } }
    /// Switching sites, signing out and an ended session: every waiter is cancelled and nothing of the old session is kept.
    func reset() {
        let pending = waiters.values.flatMap(\.values)
        waiters = [:]; queue = []; active = nil
        compliancePassed = nil; complianceDeclined = []; grants = [:]
        for continuation in pending { continuation.resume(returning: .cancelled) }
    }

    private func shortcut(_ kind: Prompt.Kind, isRead: Bool, generation: UUID) -> SecurityPromptOutcome? {
        switch kind {
        case .compliance:
            if let passed = compliancePassed, passed.generation == generation, now().timeIntervalSince(passed.at) < Self.compliancePassWindow {
                return .passed
            }
            return isRead && complianceDeclined.contains(generation) ? .cancelled : nil
        case .stepUpVerify:
            guard let grant = grants[generation] else { return nil }
            if now().timeIntervalSince(grant.recordedAt) < Self.stepUpGrantWindow { return .passed }
            // The server no longer honours it (expired, or the session moved), so it is asked again.
            grants[generation] = nil
            return nil
        case .stepUpNoTOTP: return nil
        }
    }
    /// Joins the shown or queued prompt of the same kind and session; a write joining makes it a write prompt.
    private func enqueue(_ kind: Prompt.Kind, purpose: String?, isRead: Bool, generation: UUID) -> UUID {
        func joined(_ prompt: Prompt) -> Prompt {
            Prompt(id: prompt.id, kind: kind, generation: generation, purpose: prompt.purpose == purpose ? purpose : nil,
                   isRead: prompt.isRead && isRead)
        }
        if let shown = active, shown.kind == kind, shown.generation == generation {
            let merged = joined(shown)
            if merged != shown { active = merged }
            return shown.id
        }
        if let index = queue.firstIndex(where: { $0.kind == kind && $0.generation == generation }) {
            queue[index] = joined(queue[index])
            return queue[index].id
        }
        let prompt = Prompt(id: UUID(), kind: kind, generation: generation, purpose: purpose, isRead: isRead)
        if active == nil { active = prompt } else { queue.append(prompt) }
        return prompt.id
    }
    private func isPending(_ promptID: UUID) -> Bool { active?.id == promptID || queue.contains { $0.id == promptID } }
    private func resume(_ waiterID: UUID, of promptID: UUID, with outcome: SecurityPromptOutcome) {
        waiters[promptID]?.removeValue(forKey: waiterID)?.resume(returning: outcome)
    }
}
