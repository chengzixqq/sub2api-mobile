import Foundation
import Sub2Core

/// One press of “保存” on the edit user page (30 §6.4, §6.5, R04, R05, S3D1-18): the operation made now (or the one kept for
/// the same draft), the PUT, a read-back after an unknown result or a refusal without a reason, then the attributes (only after
/// the user PUT went through). Each await is followed by a check of the session and the page; a stale run does nothing more.
/// The request may hold a password, so nothing here is logged or saved.
@MainActor
struct UserUpdateSubmission {
    /// The site and the client's write identity of the session that opened the page.
    struct Target: Sendable, Equatable {
        let serverID: UUID
        let identity: UUID
    }
    struct Effects: Sendable {
        /// nil once the session is gone.
        let target: @MainActor @Sendable () async -> Target?
        /// admin.idempotent_writes: every edit carries the number as its key (otherwise only a concurrency change, D24).
        let sendsIdempotencyKey: @MainActor @Sendable () -> Bool
        /// AppModel.updateUser: with a key, the executor's retries and waits run inside (R04).
        let update: @MainActor @Sendable (PendingUserUpdateOperation) async throws -> WriteOutcome<AdminUser>
        /// `GET admin/users/:id`: the PUT's reply has no group rates, so a read-back always reads this.
        let readUser: @MainActor @Sendable (Int) async throws -> AdminUser
        let writeAttributes: @MainActor @Sendable (Int, [Int: String]) async throws -> Void
        /// The session is the same and the page is still shown.
        let isCurrent: @MainActor @Sendable () -> Bool
    }
    enum Outcome: Sendable {
        /// The user as the server has it (nil when only attributes were written).
        case saved(AdminUser?, attributesSaved: Bool)
        /// The read-back found other values: after an unknown result (`failure` nil) or a refusal without a reason.
        case differs(AdminUser, failure: UserSaveFailure?)
        /// The result is unknown and only a password went, which cannot be read back.
        case undetermined
        /// The result is unknown and the read-back failed too; the number stays for the same draft, read back first next time.
        case unconfirmed(PendingUserUpdateOperation)
        /// The number to keep for the same draft, nil when the next save needs a new one.
        case failed(UserSaveFailure, operation: PendingUserUpdateOperation?)
        case stale
    }

    let effects: Effects

    /// `request` is nil when only attributes changed (their own PUT). `reusing` is the number kept from an earlier press for
    /// the same draft; `readsBackFirst` settles a kept unknown result by a read before anything is sent.
    func run(userID: Int, request: UserUpdateRequest?, attributes: [Int: String], reusing: PendingUserUpdateOperation?,
             readsBackFirst: Bool = false) async -> Outcome {
        guard let request else { return await attributesOnly(userID: userID, attributes: attributes) }
        if readsBackFirst, let reusing { return await readBack(reusing, attributes: attributes, failure: nil) }
        let operation: PendingUserUpdateOperation
        if let reusing { operation = reusing } else {
            guard let target = await effects.target(), effects.isCurrent() else { return .stale }
            do {
                operation = try PendingUserUpdateOperation(serverID: target.serverID, identity: target.identity, userID: userID, request: request,
                                                           serverSupportsIdempotentWrites: effects.sendsIdempotencyKey())
            } catch { return .failed(UserSaveFailure(error), operation: nil) }
        }
        let outcome: WriteOutcome<AdminUser>
        do { outcome = try await effects.update(operation) } catch { return await settle(error, operation: operation, attributes: attributes) }
        guard effects.isCurrent() else { return .stale }
        let saved = await writeAttributes(attributes, userID: userID)
        guard effects.isCurrent() else { return .stale }
        return .saved(outcome.value, attributesSaved: saved)
    }

    private func settle(_ error: any Error, operation: PendingUserUpdateOperation, attributes: [Int: String]) async -> Outcome {
        guard effects.isCurrent() else { return .stale }
        let failure = UserSaveFailure(error)
        switch failure {
        case .unconfirmed: return await readBack(operation, attributes: attributes, failure: nil)
        case .rejected(_, reload: true): return await readBack(operation, attributes: attributes, failure: failure)
        default: return .failed(failure, operation: failure.keepsOperation ? operation : nil)
        }
    }
    /// 30 §6.5: only what was sent is compared. Matching is taken as saved, so the attributes follow.
    private func readBack(_ operation: PendingUserUpdateOperation, attributes: [Int: String], failure: UserSaveFailure?) async -> Outcome {
        let user: AdminUser
        do { user = try await effects.readUser(operation.userID) } catch {
            guard effects.isCurrent() else { return .stale }
            return failure.map { .failed($0, operation: nil) } ?? .unconfirmed(operation)
        }
        guard effects.isCurrent() else { return .stale }
        switch UserAccessDraft.readback(sent: operation.request, server: user) {
        case .matches:
            let saved = await writeAttributes(attributes, userID: operation.userID)
            guard effects.isCurrent() else { return .stale }
            return .saved(user, attributesSaved: saved)
        case .differs: return .differs(user, failure: failure)
        case .undetermined: return failure.map { .failed($0, operation: nil) } ?? .undetermined
        }
    }
    private func attributesOnly(userID: Int, attributes: [Int: String]) async -> Outcome {
        let saved = await writeAttributes(attributes, userID: userID)
        return effects.isCurrent() ? .saved(nil, attributesSaved: saved) : .stale
    }
    /// 30 §6.4 step 5: only the changed values; a failure keeps what the user PUT saved and only changes the receipt.
    private func writeAttributes(_ values: [Int: String], userID: Int) async -> Bool {
        guard !values.isEmpty else { return true }
        do { try await effects.writeAttributes(userID, values); return true } catch { return false }
    }
}
