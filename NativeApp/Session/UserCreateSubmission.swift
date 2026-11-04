import Foundation
import Sub2Core

/// One confirmed “创建用户” (30 §5.4, R04, R05): Face ID for a positive initial balance (60 §3.4), the operation made now (or
/// the one kept for the same draft), the send, the answer classified by 30 §5.5, a read-back by email when it is unknown, then
/// the attributes. After a result nobody could confirm, the next press for the same draft reads back before it sends
/// (00 §2.4, §2.5.4). Each await is followed by a check of the session and the page; a stale run does nothing more. The
/// request holds the password, so nothing here is logged or saved.
@MainActor
struct UserCreateSubmission {
    /// The site and the client's write identity of the session that opened the page.
    struct Target: Sendable, Equatable {
        let serverID: UUID
        let identity: UUID
    }
    struct Effects: Sendable {
        let authorize: @MainActor @Sendable (GatedAction) async -> Bool
        /// nil once the session is gone.
        let target: @MainActor @Sendable () async -> Target?
        /// admin.idempotent_writes: the number is also the Idempotency-Key (D24).
        let sendsIdempotencyKey: @MainActor @Sendable () -> Bool
        /// AppModel.createUser: with a key, the executor's retries and waits run inside (R04).
        let create: @MainActor @Sendable (PendingUserCreateOperation) async throws -> WriteOutcome<AdminUser>
        let findByEmail: @MainActor @Sendable (String) async throws -> AdminUser?
        let writeAttributes: @MainActor @Sendable (Int, [Int: String]) async throws -> Void
        /// The session is the same and the page is still shown.
        let isCurrent: @MainActor @Sendable () -> Bool
    }
    enum Outcome: Sendable {
        case created(AdminUser, attributesSaved: Bool, replayed: Bool)
        /// The result was unknown and the address is on the server now: taken as created, so the attributes go on it too.
        case foundOnServer(AdminUser, attributesSaved: Bool)
        /// The result was unknown and the address is not on the server; the number stays for the same draft.
        case notCreated(PendingUserCreateOperation)
        /// The result was unknown and the read-back failed as well: still unknown, the number stays for the same draft.
        case unconfirmed(PendingUserCreateOperation)
        /// The number to keep for the same draft, nil when the next send needs a new one.
        case failed(UserCreateFailure, operation: PendingUserCreateOperation?)
        case notAuthorized
        case stale
    }

    let effects: Effects

    /// `reusing` is the number kept from an earlier press for this same draft (a cleared security prompt, a refusal, an
    /// unknown result); the request is then not built again. `readsBackFirst` looks the address up before anything else.
    func run(request: UserCreateRequest, attributes: [Int: String], reusing: PendingUserCreateOperation?,
             readsBackFirst: Bool = false) async -> Outcome {
        if readsBackFirst, let reusing, let settled = await readBack(reusing, attributes: attributes) { return settled }
        if let amount = request.balance, amount > 0 {
            guard await effects.authorize(.initialBalance(amount)) else { return effects.isCurrent() ? .notAuthorized : .stale }
            guard effects.isCurrent() else { return .stale }
        }
        let operation: PendingUserCreateOperation
        if let reusing { operation = reusing } else {
            guard let target = await effects.target(), effects.isCurrent() else { return .stale }
            do {
                operation = try PendingUserCreateOperation(serverID: target.serverID, identity: target.identity, request: request,
                                                           sendsIdempotencyKey: effects.sendsIdempotencyKey())
            } catch { return .failed(UserCreateFailure.classify(error), operation: nil) }
        }
        let outcome: WriteOutcome<AdminUser>
        do { outcome = try await effects.create(operation) } catch { return await settle(error, operation: operation, attributes: attributes) }
        guard effects.isCurrent() else { return .stale }
        let saved = await writeAttributes(attributes, of: outcome.value)
        guard effects.isCurrent() else { return .stale }
        return .created(outcome.value, attributesSaved: saved, replayed: outcome.replayed)
    }

    private func settle(_ error: any Error, operation: PendingUserCreateOperation, attributes: [Int: String]) async -> Outcome {
        guard effects.isCurrent() else { return .stale }
        let failure = UserCreateFailure.classify(error)
        guard failure.next == .readBack else {
            return .failed(failure, operation: failure.next == .unfreezeWithNewKey ? nil : operation)
        }
        return await readBack(operation, attributes: attributes) ?? .notCreated(operation)
    }
    /// 30 §5.4 step 7: the address found is taken as created (attributes as after a 2xx); nil when it is not there. A
    /// failed lookup cannot tell, so it stays unknown and never reads as not created (00 §2.4).
    private func readBack(_ operation: PendingUserCreateOperation, attributes: [Int: String]) async -> Outcome? {
        let found: AdminUser?
        do { found = try await effects.findByEmail(operation.email) } catch {
            return effects.isCurrent() ? .unconfirmed(operation) : .stale
        }
        guard effects.isCurrent() else { return .stale }
        guard let found else { return nil }
        let saved = await writeAttributes(attributes, of: found)
        guard effects.isCurrent() else { return .stale }
        return .foundOnServer(found, attributesSaved: saved)
    }
    /// 30 §5.4 step 6: only after the user exists; a failure keeps the user and only changes the receipt.
    private func writeAttributes(_ values: [Int: String], of user: AdminUser) async -> Bool {
        guard !values.isEmpty else { return true }
        do { try await effects.writeAttributes(user.id, values); return true } catch { return false }
    }
}
