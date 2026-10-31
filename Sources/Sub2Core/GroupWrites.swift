import Foundation

/// One user intent, one number (00 §2.5.2, R05): built at the last confirmation, reused unchanged for every retry, built again
/// when the body changes. Memory only.
public struct GroupWriteOperation: Identifiable, Sendable, Equatable, CustomDebugStringConvertible {
    public enum Kind: Sendable, Equatable { case create, update(groupID: Int), delete(groupID: Int), duplicate(sourceGroupID: Int) }
    public let id: UUID
    public let serverID: UUID
    /// `userWriteIdentity()` when confirmed; a later session refuses to send it.
    public let identity: UUID
    public let kind: Kind
    /// Checked, sorted-key bytes for create and update; empty for delete and duplicate.
    public let body: Data
    /// admin.idempotent_writes; a duplicate always sends one (the server requires it).
    public let sendsIdempotencyKey: Bool
    /// Idempotency-Key and X-Request-ID.
    public var key: String { id.uuidString.lowercased() }
    public var path: String {
        switch kind {
        case .create: "admin/groups"
        case .update(let groupID), .delete(let groupID): "admin/groups/\(groupID)"
        case .duplicate(let groupID): "admin/groups/\(groupID)/duplicate"
        }
    }
    public var method: String {
        switch kind { case .create, .duplicate: "POST"; case .update: "PUT"; case .delete: "DELETE" }
    }
    public var debugDescription: String { "GroupWriteOperation(\(kind), \(key))" }

    private init(id: UUID, serverID: UUID, identity: UUID, kind: Kind, body: Data, sendsIdempotencyKey: Bool) {
        self.id = id; self.serverID = serverID; self.identity = identity; self.kind = kind; self.body = body
        self.sendsIdempotencyKey = sendsIdempotencyKey
    }
    public static func create(_ request: GroupCreateRequest, serverID: UUID, identity: UUID, sendsIdempotencyKey: Bool,
                              id: UUID = UUID()) throws -> GroupWriteOperation {
        try GroupWriteOperation(id: id, serverID: serverID, identity: identity, kind: .create, body: request.requestBody(),
                                sendsIdempotencyKey: sendsIdempotencyKey)
    }
    public static func update(groupID: Int, _ request: GroupUpdateRequest, serverID: UUID, identity: UUID, sendsIdempotencyKey: Bool,
                              id: UUID = UUID()) throws -> GroupWriteOperation {
        try GroupWriteOperation(id: id, serverID: serverID, identity: identity, kind: .update(groupID: validGroupID(groupID)),
                                body: request.requestBody(), sendsIdempotencyKey: sendsIdempotencyKey)
    }
    public static func delete(groupID: Int, serverID: UUID, identity: UUID, sendsIdempotencyKey: Bool, id: UUID = UUID()) throws -> GroupWriteOperation {
        try GroupWriteOperation(id: id, serverID: serverID, identity: identity, kind: .delete(groupID: validGroupID(groupID)), body: Data(),
                                sendsIdempotencyKey: sendsIdempotencyKey)
    }
    public static func duplicate(sourceGroupID: Int, serverID: UUID, identity: UUID, id: UUID = UUID()) throws -> GroupWriteOperation {
        try GroupWriteOperation(id: id, serverID: serverID, identity: identity, kind: .duplicate(sourceGroupID: validGroupID(sourceGroupID)),
                                body: Data(), sendsIdempotencyKey: true)
    }
    /// After KEY_CONFLICT / KEY_INVALID: the same kind and bytes under a new number, to be confirmed again.
    public func renewingKey(_ id: UUID = UUID()) -> GroupWriteOperation {
        GroupWriteOperation(id: id, serverID: serverID, identity: identity, kind: kind, body: body, sendsIdempotencyKey: sendsIdempotencyKey)
    }
    fileprivate static func validGroupID(_ value: Int) throws -> Int {
        guard value > 0 else { throw invalidTarget }; return value
    }
    fileprivate static let invalidTarget = APIError(kind: .validation, message: "无效的对象编号。")
}

/// 50 §0.8: a group that is already gone counts as deleted, for example when a keyed retry finds the first attempt's delete.
public enum GroupDeleteResult: Sendable, Equatable { case deleted, alreadyGone }

/// The editor's checked request and identity. The number is made only at the last confirmation (“确认发送”, R05) and kept from
/// then on, so an unconfirmed result is checked or retried under the same number. Memory only.
public struct GroupWriteDraft: Sendable {
    public enum Intent: Sendable { case create(GroupCreateRequest), update(groupID: Int, GroupUpdateRequest) }
    public let intent: Intent
    public let serverID: UUID
    public let identity: UUID
    public let sendsIdempotencyKey: Bool
    public private(set) var operation: GroupWriteOperation?
    public init(_ intent: Intent, serverID: UUID, identity: UUID, sendsIdempotencyKey: Bool) throws {
        switch intent {
        case .create(let request): try request.validate()
        case .update(let groupID, let request): _ = try GroupWriteOperation.validGroupID(groupID); try request.validate()
        }
        self.intent = intent; self.serverID = serverID; self.identity = identity; self.sendsIdempotencyKey = sendsIdempotencyKey
    }
    /// The first call makes and keeps the operation; later calls return it unchanged and ignore `id`.
    public mutating func confirmedOperation(id: UUID = UUID()) throws -> GroupWriteOperation {
        if let operation { return operation }
        let made: GroupWriteOperation
        switch intent {
        case .create(let request):
            made = try .create(request, serverID: serverID, identity: identity, sendsIdempotencyKey: sendsIdempotencyKey, id: id)
        case .update(let groupID, let request):
            made = try .update(groupID: groupID, request, serverID: serverID, identity: identity, sendsIdempotencyKey: sendsIdempotencyKey, id: id)
        }
        operation = made
        return made
    }
}

extension APIClient {
    public func createGroup(_ operation: GroupWriteOperation, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminGroup> {
        try await performGroupWrite(operation, onEvent: onEvent) { $0 == .create }
    }
    public func updateGroup(_ operation: GroupWriteOperation, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminGroup> {
        try await performGroupWrite(operation, onEvent: onEvent) { if case .update = $0 { true } else { false } }
    }
    /// 404 GROUP_NOT_FOUND / RESOURCE_NOT_FOUND reads as already deleted (50 §0.8); a non-JSON 404 (no such endpoint),
    /// 409 GROUP_NOT_EMPTY and unconfirmed keyed results are thrown.
    public func deleteGroup(_ operation: GroupWriteOperation, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<GroupDeleteResult> {
        do {
            let outcome: WriteOutcome<EmptyReply> = try await performGroupWrite(operation, onEvent: onEvent) { if case .delete = $0 { true } else { false } }
            return WriteOutcome(value: .deleted, replayed: outcome.replayed, recovered: outcome.recovered, degraded: outcome.degraded,
                                expiresAt: outcome.expiresAt, actionID: outcome.actionID, batchID: outcome.batchID, requestID: outcome.requestID)
        } catch let error as APIError where error.statusCode == 404 && ["GROUP_NOT_FOUND", "RESOURCE_NOT_FOUND"].contains(error.reason ?? "") {
            return WriteOutcome(value: .alreadyGone, requestID: error.requestID)
        }
    }
    /// The server requires a key (executeAdminIdempotent); `recovered`, a stuck first execution's copy found again, is a success.
    public func duplicateGroup(_ operation: GroupWriteOperation, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminGroup> {
        try await performGroupWrite(operation, onEvent: onEvent) { if case .duplicate = $0 { true } else { false } }
    }
    /// Nothing is sent for another site, an older session or a cancelled task, or a kind the method does not take. With a key the
    /// keyed executor retries transport failures twice with the same key and bytes (R04); without one the write goes out once
    /// with its number as X-Request-ID and is checked by reading back.
    private func performGroupWrite<T: Decodable & Sendable>(_ operation: GroupWriteOperation, onEvent: KeyedWriteEventHandler?,
                                                            accepts: (GroupWriteOperation.Kind) -> Bool) async throws -> WriteOutcome<T> {
        guard operation.serverID == server.id else { throw APIError.stationMismatch }
        try check(operation.identity)
        guard accepts(operation.kind) else { throw GroupWriteOperation.invalidTarget }
        guard operation.sendsIdempotencyKey else {
            return try await performUnkeyedWrite(operation.path, method: operation.method, body: operation.body, requestID: operation.key)
        }
        return try await performKeyedWrite(KeyedWriteRequest(path: operation.path, method: operation.method, body: operation.body, key: operation.id),
                                           onEvent: onEvent)
    }
}
