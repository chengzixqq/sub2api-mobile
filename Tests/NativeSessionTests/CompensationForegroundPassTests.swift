import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S6-08 (60 §19.4 step 9; 30 §3.6; X34): back in the foreground each compensation of the address is checked once, read-only;
// only one the server shows as redeemed for its user is settled. Records going out are skipped.

private let siteID = UUID(uuidString: "5C000000-0000-4000-8000-000000000001")!

private func grant(_ suffix: Int) -> PendingCompensation {
    PendingCompensation(id: UUID(uuidString: String(format: "5C000000-0000-4000-8000-%012ld", suffix))!, serverID: siteID, actorUserID: 1,
                        createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(suffix)), userID: suffix, userDisplayName: "用户 \(suffix)",
                        userEmail: "user\(suffix)@example.com", code: "FIXTURE-GRANT-\(suffix)", type: .balance, value: 10)
}
private func code(for grant: PendingCompensation, usedBy: Int?, status: String = "used") -> AdminRedeemCode {
    AdminRedeemCode(id: 900 + grant.userID, code: grant.code, type: "balance", value: grant.value, status: status, usedBy: usedBy)
}

/// Every effect of one pass, recorded in order.
@MainActor private final class CompensationPassHarness {
    var records: [PendingCompensation]
    /// What the pass gets on its first read, when that differs from `records`.
    var firstRead: [PendingCompensation]?
    var outcomes: [UUID: Result<CompensationReconcileOutcome?, any Error>] = [:]
    var inFlight: Set<UUID> = []
    var continues = true
    /// Runs inside a check, after it is counted (another session takes over, the record is settled by hand…).
    var duringCheck: (@MainActor (PendingCompensation) -> Void)?
    private(set) var checked: [UUID] = []
    private(set) var settled: [(UUID, Int)] = []
    init(_ records: [PendingCompensation]) { self.records = records }
    var effects: CompensationForegroundPass.Effects {
        CompensationForegroundPass.Effects(
            records: { [self] in
                defer { firstRead = nil }
                return firstRead ?? records
            },
            isInFlight: { [self] in inFlight.contains($0) },
            reconcile: { [self] grant in
                checked.append(grant.id)
                duringCheck?(grant)
                guard let outcome = outcomes[grant.id] else { throw APIError.server(status: 500, reason: nil) }
                return try outcome.get()
            },
            settle: { [self] grant, code in
                settled.append((grant.id, code.id))
                records.removeAll { $0.id == grant.id }
            },
            shouldContinue: { [self] in continues })
    }
    func run() async -> [UUID] { await CompensationForegroundPass(effects: effects).run() }
}

@MainActor @Test func onlyIssuedRecordsAreSettled() async {
    let issued = grant(1), unused = grant(2), absent = grant(3), other = grant(4), unverifiable = grant(5), skipped = grant(6), failing = grant(7)
    let harness = CompensationPassHarness([issued, unused, absent, other, unverifiable, skipped, failing])
    harness.outcomes = [issued.id: .success(.issued(code(for: issued, usedBy: 1))),
                        unused.id: .success(.createdNotRedeemed(code(for: unused, usedBy: nil, status: "unused"))),
                        absent.id: .success(.notFound), other.id: .success(.redeemedByOther(code(for: other, usedBy: 99))),
                        unverifiable.id: .success(.unverifiable(code(for: unverifiable, usedBy: nil))), skipped.id: .success(nil)]
    let settled = await harness.run()
    #expect(settled == [issued.id])
    #expect(harness.settled.map { $0.0 } == [issued.id] && harness.settled.map { $0.1 } == [901])
    #expect(harness.checked == [issued, unused, absent, other, unverifiable, skipped, failing].map(\.id))
    #expect(harness.records.count == 6)
}

@MainActor @Test func recordsBeingSentAreSkipped() async {
    let sending = grant(1), settledByHand = grant(2), due = grant(3), startsSending = grant(4)
    let harness = CompensationPassHarness([sending, due, startsSending])
    // The pass starts with all four; `settledByHand` is gone by its turn, and `startsSending` goes out while `due` is checked.
    harness.firstRead = [sending, settledByHand, due, startsSending]
    harness.inFlight = [sending.id]
    for record in [sending, settledByHand, due, startsSending] { harness.outcomes[record.id] = .success(.issued(code(for: record, usedBy: record.userID))) }
    harness.duringCheck = { [harness] grant in if grant.id == due.id { harness.inFlight.insert(startsSending.id) } }
    #expect(await harness.run() == [due.id])
    #expect(harness.checked == [due.id])
}

@MainActor @Test func failuresKeepRecordsAndStopsEndThePass() async {
    let failing = grant(1), issued = grant(2), cancelled = grant(3), after = grant(4)
    let harness = CompensationPassHarness([failing, issued, cancelled, after])
    harness.outcomes = [issued.id: .success(.issued(code(for: issued, usedBy: 2))), cancelled.id: .failure(CancellationError()),
                        after.id: .success(.issued(code(for: after, usedBy: 4)))]
    #expect(await harness.run() == [issued.id])
    #expect(harness.checked == [failing.id, issued.id, cancelled.id])
    #expect(harness.records.map(\.id) == [failing.id, cancelled.id, after.id])

    let stopping = CompensationPassHarness([grant(5), grant(6)])
    for record in stopping.records { stopping.outcomes[record.id] = .success(.issued(code(for: record, usedBy: record.userID))) }
    // Another session or the background arrives while the first answer is out: nothing is settled for it, nothing more is read.
    stopping.duringCheck = { [stopping] _ in stopping.continues = false }
    #expect(await stopping.run().isEmpty)
    #expect(stopping.checked == [grant(5).id] && stopping.settled.isEmpty)

    let idle = CompensationPassHarness([grant(7)])
    idle.continues = false
    #expect(await idle.run().isEmpty && idle.checked.isEmpty)
}
