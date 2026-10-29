import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S3-10: one press of the confirmed “创建用户” (30 §5.4, R04, R05, 60 §3.4): Face ID, the operation made now, the send, the
// classified answer, the read-back by email and the attribute write.

private let siteID = UUID(uuidString: "5E000000-0000-4000-8000-000000000001")!
private let identity = UUID(uuidString: "5E000000-0000-4000-8000-000000000002")!

private func newUser(balance: Decimal? = nil, role: AdminUserRole = .user) -> UserCreateRequest {
    UserCreateRequest(email: "qi.he@example.invalid", password: "Qm7v-Tr2p-Hx9k", username: "何琪", role: role, balance: balance, allowedGroups: [5])
}
private func created(id: Int = 27) -> AdminUser { AdminUser(id: id, email: "qi.he@example.invalid", username: "何琪", balance: 20) }
private func unconfirmed() -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
}

/// Every effect, recorded in order.
@MainActor private final class CreateHarness {
    var authorizes = true
    var keyed = true
    var hasTarget = true
    var current = true
    /// Turns false right after this effect ran (“authorize”, “target”, “create”, “find”, “attributes”).
    var staleAfter: String?
    var createResult: Result<WriteOutcome<AdminUser>, any Error> = .success(WriteOutcome(value: created()))
    var findResult: Result<AdminUser?, any Error> = .success(nil)
    var attributesFail = false
    private(set) var log: [String] = []
    private(set) var gated: [GatedAction] = []
    private(set) var sent: [PendingUserCreateOperation] = []
    private(set) var searched: [String] = []
    private(set) var attributeWrites: [(Int, [Int: String])] = []

    private func step(_ name: String) {
        log.append(name)
        if staleAfter == name { current = false }
    }
    var effects: UserCreateSubmission.Effects {
        UserCreateSubmission.Effects(
            authorize: { [self] action in step("authorize"); gated.append(action); return authorizes },
            target: { [self] in step("target"); return hasTarget ? UserCreateSubmission.Target(serverID: siteID, identity: identity) : nil },
            sendsIdempotencyKey: { [self] in keyed },
            create: { [self] operation in step("create"); sent.append(operation); return try createResult.get() },
            findByEmail: { [self] email in step("find"); searched.append(email); return try findResult.get() },
            writeAttributes: { [self] id, values in
                step("attributes"); attributeWrites.append((id, values))
                if attributesFail { throw APIError.server(status: 400, reason: "ATTRIBUTE_VALIDATION_FAILED") }
            },
            isCurrent: { [self] in current })
    }
    func run(_ request: UserCreateRequest = newUser(), attributes: [Int: String] = [:],
             reusing: PendingUserCreateOperation? = nil) async -> UserCreateSubmission.Outcome {
        await UserCreateSubmission(effects: effects).run(request: request, attributes: attributes, reusing: reusing)
    }
}

private func name(_ outcome: UserCreateSubmission.Outcome) -> String {
    switch outcome {
    case .created(let user, let saved, let replayed): "created \(user.id) \(saved) \(replayed)"
    case .foundOnServer(let user): "found \(user.id)"
    case .notCreated: "notCreated"
    case .failed(let failure, let operation): "failed \(failure.next) \(operation == nil ? "drop" : "keep")"
    case .notAuthorized: "notAuthorized"
    case .stale: "stale"
    }
}

/// 60 §3.4: a positive initial balance is verified before anything is made or sent; a failed check sends nothing.
@MainActor @Test func faceIDRunsFirstAndFailureSendsNothing() async {
    let harness = CreateHarness()
    harness.authorizes = false
    #expect(name(await harness.run(newUser(balance: 150))) == "notAuthorized")
    #expect(harness.gated == [.initialBalance(150)])
    #expect(harness.sent.isEmpty)
    #expect(harness.log == ["authorize"])

    let free = CreateHarness()
    free.authorizes = false
    #expect(name(await free.run(newUser(balance: nil))) == "created 27 true false")
    #expect(name(await free.run(newUser(balance: 0))) == "created 27 true false")
    #expect(free.gated.isEmpty)
}

/// R05 / D24: the number is made when the administrator confirms; with admin.idempotent_writes it is also the key; the
/// bytes are the request's.
@MainActor @Test func operationIsBuiltAtConfirmationWithCapabilityKey() async throws {
    let harness = CreateHarness()
    _ = await harness.run(newUser(balance: 20))
    let keyed = try #require(harness.sent.first)
    #expect(keyed.sendsIdempotencyKey)
    #expect(keyed.serverID == siteID && keyed.identity == identity)
    #expect(keyed.body == (try newUser(balance: 20).requestBody()))
    #expect(harness.log == ["authorize", "target", "create"])

    let unkeyed = CreateHarness()
    unkeyed.keyed = false
    _ = await unkeyed.run()
    #expect(unkeyed.sent.first?.sendsIdempotencyKey == false)

    let gone = CreateHarness()
    gone.hasTarget = false
    #expect(name(await gone.run()) == "stale")
    #expect(gone.sent.isEmpty)
}

/// A refusal cleared by the security prompt is confirmed again: the same number and bytes, and Face ID once more.
@MainActor @Test func reusedOperationKeepsNumberAndBytes() async throws {
    let first = CreateHarness()
    first.createResult = .failure(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed))
    guard case .failed(let failure, let kept?) = await first.run(newUser(balance: 150)) else { Issue.record("expected a kept operation"); return }
    #expect(failure.next == .reconfirm)

    let again = CreateHarness()
    _ = await again.run(newUser(balance: 150), reusing: kept)
    let resent = try #require(again.sent.first)
    #expect(resent.id == kept.id && resent.body == kept.body)
    #expect(again.gated == [.initialBalance(150)])
    #expect(!again.log.contains("target"))

    let fresh = CreateHarness()
    _ = await fresh.run(newUser(balance: 150))
    #expect(fresh.sent.first?.id != kept.id)
}

/// 30 §5.4 step 6: attributes only after the user exists, never when empty; their failure keeps the user.
@MainActor @Test func createdWritesAttributesAfterUser() async {
    let harness = CreateHarness()
    #expect(name(await harness.run(attributes: [11: "Studio-K"])) == "created 27 true false")
    #expect(harness.log == ["target", "create", "attributes"])
    #expect(harness.attributeWrites.first?.0 == 27 && harness.attributeWrites.first?.1 == [11: "Studio-K"])

    let none = CreateHarness()
    _ = await none.run(attributes: [:])
    #expect(none.attributeWrites.isEmpty)

    let failing = CreateHarness()
    failing.attributesFail = true
    failing.createResult = .success(WriteOutcome(value: created(), replayed: true))
    #expect(name(await failing.run(attributes: [11: "Studio-K"])) == "created 27 false true")
}

/// 30 §5.4 step 7: an unknown result is looked up by email; nothing found, or the lookup failing, means not created.
@MainActor @Test func uncertainResultReadsBackByEmail() async {
    let found = CreateHarness()
    found.createResult = .failure(unconfirmed())
    found.findResult = .success(created(id: 31))
    #expect(name(await found.run()) == "found 31")
    #expect(found.searched == ["qi.he@example.invalid"])

    let missing = CreateHarness()
    missing.createResult = .failure(APIError.server(status: 500, reason: nil))
    #expect(name(await missing.run()) == "notCreated")

    let failing = CreateHarness()
    failing.createResult = .failure(unconfirmed())
    failing.findResult = .failure(APIError.server(status: 500, reason: nil))
    #expect(name(await failing.run()) == "notCreated")
}

/// A definite answer is never read back; the number stays for the same draft except after a key problem.
@MainActor @Test func definiteFailuresReturnOperationToKeepOrDrop() async {
    let taken = CreateHarness()
    taken.createResult = .failure(APIError.server(status: 409, reason: "EMAIL_EXISTS"))
    #expect(name(await taken.run()) == "failed unfreeze keep")
    #expect(taken.searched.isEmpty)

    let conflict = CreateHarness()
    conflict.createResult = .failure(KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil))
    #expect(name(await conflict.run()) == "failed unfreezeWithNewKey drop")

    let passed = CreateHarness()
    passed.createResult = .failure(APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_REQUIRED").withSecurityOutcome(.passed))
    #expect(name(await passed.run()) == "failed reconfirm keep")
}

/// Each await is followed by a check of the session and the page: a stale run does nothing more.
@MainActor @Test func staleSessionStopsAfterEveryAwait() async {
    for (step, expected) in [("authorize", ["authorize"]), ("target", ["authorize", "target"]), ("create", ["authorize", "target", "create"])] {
        let harness = CreateHarness()
        harness.staleAfter = step
        #expect(name(await harness.run(newUser(balance: 20), attributes: [11: "Studio-K"])) == "stale")
        #expect(harness.log == expected)
    }
    let readBack = CreateHarness()
    readBack.createResult = .failure(unconfirmed())
    readBack.findResult = .success(created())
    readBack.staleAfter = "find"
    #expect(name(await readBack.run()) == "stale")
    let attributes = CreateHarness()
    attributes.staleAfter = "attributes"
    #expect(name(await attributes.run(attributes: [11: "Studio-K"])) == "stale")
}
