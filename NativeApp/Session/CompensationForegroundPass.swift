import Foundation
import Sub2Core

/// 60 §19.4 step 9 (30 §3.6, X34): back in the foreground each compensation of the connected address is checked once, read-only,
/// with the current identity. Only one the server shows as redeemed for its user is settled, with its receipt; every other
/// answer and a failed read keep it for the administrator, silently. Records going out are skipped (MoneyWriteInFlight).
@MainActor
struct CompensationForegroundPass {
    struct Effects: Sendable {
        /// The address's compensations, oldest first.
        let records: @MainActor @Sendable () -> [PendingCompensation]
        let isInFlight: @MainActor @Sendable (UUID) -> Bool
        /// nil: not checked (a UI test without a `-ui-reconcile-*` argument).
        let reconcile: @MainActor @Sendable (PendingCompensation) async throws -> CompensationReconcileOutcome?
        let settle: @MainActor @Sendable (PendingCompensation, AdminRedeemCode) -> Void
        /// Same session, still in the foreground.
        let shouldContinue: @MainActor @Sendable () -> Bool
    }

    let effects: Effects

    /// The ids settled because the server showed them redeemed.
    @discardableResult
    func run() async -> [UUID] {
        var settled: [UUID] = []
        for grant in effects.records() {
            guard effects.shouldContinue() else { break }
            guard isDue(grant) else { continue }
            let outcome: CompensationReconcileOutcome?
            do { outcome = try await effects.reconcile(grant) } catch is CancellationError { break } catch { continue }
            guard case .issued(let code)? = outcome, effects.shouldContinue(), isDue(grant) else { continue }
            effects.settle(grant, code)
            settled.append(grant.id)
        }
        return settled
    }

    /// Still saved (not settled by hand meanwhile) and not going out.
    private func isDue(_ grant: PendingCompensation) -> Bool {
        !effects.isInFlight(grant.id) && effects.records().contains { $0.id == grant.id }
    }
}
