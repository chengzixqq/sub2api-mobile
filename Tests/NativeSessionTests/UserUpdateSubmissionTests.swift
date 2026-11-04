import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S3-11: one save of the edit user page (30 §6.4, §6.5, R04, R05, S3D1-18): the operation made now (or the one kept for the
// same draft), the PUT, the read-back after an unknown result or a 400 / 500 without reason, then the attributes.

private let siteID = UUID(uuidString: "5F000000-0000-4000-8000-000000000001")!
private let identity = UUID(uuidString: "5F000000-0000-4000-8000-000000000002")!

private func saved(concurrency: Int = 4, email: String = "xm.wang@example.com") -> AdminUser {
    AdminUser(id: 3, email: email, username: "王小明", concurrency: concurrency)
}
private let concurrencyChange = UserUpdateRequest(concurrency: 4)
private func unconfirmed() -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
}

/// Every effect, recorded in order.
@MainActor private final class UpdateHarness {
    var keyed = true
    var current = true
    var staleAfter: String?
    var updateResult: Result<WriteOutcome<AdminUser>, any Error> = .success(WriteOutcome(value: saved()))
    var readResult: Result<AdminUser, any Error> = .success(saved())
    var attributesFail = false
    private(set) var log: [String] = []
    private(set) var sent: [PendingUserUpdateOperation] = []
    private(set) var attributeWrites: [(Int, [Int: String])] = []

    private func step(_ name: String) {
        log.append(name)
        if staleAfter == name { current = false }
    }
    var effects: UserUpdateSubmission.Effects {
        UserUpdateSubmission.Effects(
            target: { [self] in step("target"); return UserUpdateSubmission.Target(serverID: siteID, identity: identity) },
            sendsIdempotencyKey: { [self] in keyed },
            update: { [self] operation in step("update"); sent.append(operation); return try updateResult.get() },
            readUser: { [self] _ in step("read"); return try readResult.get() },
            writeAttributes: { [self] id, values in
                step("attributes"); attributeWrites.append((id, values))
                if attributesFail { throw APIError.server(status: 400, reason: "ATTRIBUTE_VALIDATION_FAILED") }
            },
            isCurrent: { [self] in current })
    }
    func run(_ request: UserUpdateRequest? = concurrencyChange, attributes: [Int: String] = [:], reusing: PendingUserUpdateOperation? = nil,
             readsBackFirst: Bool = false) async -> UserUpdateSubmission.Outcome {
        await UserUpdateSubmission(effects: effects).run(userID: 3, request: request, attributes: attributes, reusing: reusing,
                                                         readsBackFirst: readsBackFirst)
    }
}

private func name(_ outcome: UserUpdateSubmission.Outcome) -> String {
    switch outcome {
    case .saved(let user, let attributes): "saved \(user.map { String($0.id) } ?? "-") \(attributes)"
    case .differs(let user, let failure): "differs \(user.id) \(failure == nil ? "-" : "failure")"
    case .undetermined: "undetermined"
    case .unconfirmed: "unconfirmed"
    case .failed(let failure, let operation): "failed \(failure) \(operation == nil ? "drop" : "keep")"
    case .stale: "stale"
    }
}

/// R05 / D24: the number is made at the moment of saving; with admin.idempotent_writes it is the key, without it only a
/// concurrency change carries one; the bytes are the request's.
@MainActor @Test func operationIsBuiltAtSaveWithCapabilityKey() async throws {
    let harness = UpdateHarness()
    #expect(name(await harness.run()) == "saved 3 true")
    let keyed = try #require(harness.sent.first)
    #expect(keyed.supportsSafeRetry && keyed.serverID == siteID && keyed.identity == identity && keyed.userID == 3)
    #expect(keyed.body == (try concurrencyChange.requestBody()))
    #expect(harness.log == ["target", "update"])

    let unkeyed = UpdateHarness()
    unkeyed.keyed = false
    _ = await unkeyed.run(UserUpdateRequest(notes: "新备注"))
    #expect(unkeyed.sent.first?.supportsSafeRetry == false)
    _ = await unkeyed.run(concurrencyChange)
    #expect(unkeyed.sent.last?.supportsSafeRetry == true)
}

/// The same draft sends the same number and bytes again (a cleared security prompt, a store that was unavailable).
@MainActor @Test func reusedUpdateKeepsNumberAndBytes() async throws {
    let first = UpdateHarness()
    first.updateResult = .failure(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed))
    guard case .failed(.reconfirm, let kept?) = await first.run(UserUpdateRequest(role: .admin)) else {
        Issue.record("expected a kept operation"); return
    }
    let again = UpdateHarness()
    _ = await again.run(UserUpdateRequest(role: .admin), reusing: kept)
    let resent = try #require(again.sent.first)
    #expect(resent.id == kept.id && resent.body == kept.body)
    #expect(!again.log.contains("target"))
}

/// 30 §6.4 step 5: attributes alone are their own PUT; with user fields they follow a successful user PUT.
@MainActor @Test func attributesFollowTheUserWrite() async {
    let alone = UpdateHarness()
    #expect(name(await alone.run(nil, attributes: [11: "Studio-K"])) == "saved - true")
    #expect(alone.log == ["attributes"])
    #expect(alone.attributeWrites.first?.0 == 3 && alone.attributeWrites.first?.1 == [11: "Studio-K"])

    let after = UpdateHarness()
    #expect(name(await after.run(attributes: [12: "渠道商"])) == "saved 3 true")
    #expect(after.log == ["target", "update", "attributes"])

    let failing = UpdateHarness()
    failing.attributesFail = true
    #expect(name(await failing.run(attributes: [12: "渠道商"])) == "saved 3 false")
    let refused = UpdateHarness()
    refused.updateResult = .failure(APIError.server(status: 409, reason: "EMAIL_EXISTS"))
    _ = await refused.run(attributes: [12: "渠道商"])
    #expect(refused.attributeWrites.isEmpty)
}

/// 30 §6.5 结果不明 after the executor's own retries (R04): a GET compares only what was sent (S3D1-18).
@MainActor @Test func unknownResultReadsBack() async throws {
    let matches = UpdateHarness()
    matches.updateResult = .failure(unconfirmed())
    #expect(name(await matches.run(attributes: [11: "Studio-K"])) == "saved 3 true")
    #expect(matches.log == ["target", "update", "read", "attributes"])

    let drift = UpdateHarness()
    drift.updateResult = .failure(unconfirmed())
    drift.readResult = .success(saved(concurrency: 2))
    #expect(name(await drift.run(attributes: [11: "Studio-K"])) == "differs 3 -")
    #expect(drift.attributeWrites.isEmpty)

    let password = UpdateHarness()
    password.updateResult = .failure(APIError(kind: .transport, message: "网络"))
    #expect(name(await password.run(UserUpdateRequest(password: "Qm7v-Tr2p-Hx9k"))) == "undetermined")

    let unreadable = UpdateHarness()
    unreadable.updateResult = .failure(unconfirmed())
    unreadable.readResult = .failure(APIError(kind: .transport, message: "网络"))
    guard case .unconfirmed(let kept) = await unreadable.run() else { Issue.record("expected unconfirmed"); return }
    #expect(kept.id == unreadable.sent.first?.id)
}

/// A kept unknown result reads back before anything is sent again; still unreadable sends nothing.
@MainActor @Test func keptUnknownResultReadsBackFirst() async throws {
    let first = UpdateHarness()
    first.updateResult = .failure(unconfirmed())
    first.readResult = .failure(APIError(kind: .transport, message: "网络"))
    guard case .unconfirmed(let kept) = await first.run() else { Issue.record("expected unconfirmed"); return }

    let still = UpdateHarness()
    still.readResult = .failure(APIError(kind: .transport, message: "网络"))
    #expect(name(await still.run(reusing: kept, readsBackFirst: true)) == "unconfirmed")
    #expect(still.log == ["read"])

    let found = UpdateHarness()
    #expect(name(await found.run(reusing: kept, readsBackFirst: true)) == "saved 3 true")
    #expect(found.log == ["read"])
}

/// 30 §6.5: a 400 or 500 without a reason reads the user again; what matches was saved, anything else rebuilds the base.
@MainActor @Test func refusalWithoutReasonReadsTheUserAgain() async {
    let matches = UpdateHarness()
    matches.updateResult = .failure(APIError.server(status: 500, reason: nil))
    #expect(name(await matches.run()) == "saved 3 true")

    let other = UpdateHarness()
    other.updateResult = .failure(APIError.server(status: 500, reason: nil))
    other.readResult = .success(saved(concurrency: 2))
    #expect(name(await other.run()) == "differs 3 failure")

    let unreadable = UpdateHarness()
    unreadable.updateResult = .failure(APIError.server(status: 400, reason: nil))
    unreadable.readResult = .failure(APIError(kind: .transport, message: "网络"))
    guard case .failed(.rejected(_, reload: true), .none) = await unreadable.run() else { Issue.record("expected a refusal"); return }
}

/// Which refusals keep the number for the same draft.
@MainActor @Test func refusalsKeepOrDropTheNumber() async {
    func outcome(_ error: any Error) async -> String {
        let harness = UpdateHarness()
        harness.updateResult = .failure(error)
        return name(await harness.run())
    }
    #expect(await outcome(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled)).hasSuffix("keep"))
    #expect(await outcome(KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: nil), key: "k", actionID: nil,
                                            lastError: nil)).hasSuffix("keep"))
    #expect(await outcome(KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil)).hasSuffix("drop"))
    #expect(await outcome(APIError.server(status: 409, reason: "EMAIL_EXISTS")) == "failed emailTaken drop")
    #expect(await outcome(APIError.server(status: 404, reason: "USER_NOT_FOUND")) == "failed notFound drop")
    #expect(await outcome(APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")) == "failed readOnly drop")
}

/// A session switch or the page going away while waiting: nothing more happens.
@MainActor @Test func staleRunDoesNothingMore() async {
    let harness = UpdateHarness()
    harness.staleAfter = "update"
    #expect(name(await harness.run(attributes: [11: "Studio-K"])) == "stale")
    #expect(harness.attributeWrites.isEmpty)

    let reading = UpdateHarness()
    reading.updateResult = .failure(unconfirmed())
    reading.staleAfter = "read"
    #expect(name(await reading.run()) == "stale")
}
