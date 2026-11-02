import Foundation
import Sub2Core

/// 50 §3.4–§3.5's source for the group sheet: the session, identity, stats and one group as the group actions read them
/// (AppGroupActionSource); the write through the session's client, or under `-ui-testing` the session's GroupFixtures after the
/// checks APIClient makes, a read-only token's 403, `-ui-group-write-timeout` and the strict PUT. S5-13 wraps `sendGroupWrite`
/// for the home refresh (X17) and adds simple mode's sanitising to its fixture branch.
@MainActor final class AppGroupEditSource: GroupEditSource {
    private weak var model: AppModel?
    private let actions: AppGroupActionSource

    init(model: AppModel) {
        self.model = model
        actions = AppGroupActionSource(model: model)
    }

    var groupWriteSession: GroupWriteSession? { actions.groupWriteSession }
    func groupWriteIdentity() async throws -> UUID { try await actions.groupWriteIdentity() }
    func fetchGroupStats(id: Int) async throws -> GroupStats? { try await actions.fetchGroupStats(id: id) }
    func fetchGroup(id: Int) async throws -> AdminGroup { try await actions.fetchGroup(id: id) }

    func sendGroupWrite(_ intent: GroupWriteDraft.Intent, operation: GroupWriteOperation, onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<AdminGroup> {
        if let fixture = try await fixtureWrite(operation) { return WriteOutcome(value: try Self.written(intent, in: fixture)) }
        let client = try client()
        switch intent {
        case .create: return try await client.createGroup(operation, onEvent: onEvent)
        case .update: return try await client.updateGroup(operation, onEvent: onEvent)
        }
    }
    func searchGroups(name: String, platform: String) async throws -> [AdminGroup] {
        if model?.isUITesting == true {
            guard let fixture = model?.groupStore?.fixtureContext else { throw CancellationError() }
            return fixture.fixtures.searchGroups(name: name, platform: platform, accounts: fixture.accounts, now: fixture.now)
        }
        return try await client().groups(page: 1, pageSize: GroupEditFlow.reconcilePageSize, search: name, platform: platform).items
    }

    private func client() throws -> APIClient {
        guard let client = model?.sessionContext?.client else { throw CancellationError() }
        return client
    }
    /// nil on a real site; under `-ui-testing` the session's fixtures once the operation passes APIClient's checks.
    private func fixtureWrite(_ operation: GroupWriteOperation) async throws -> GroupFixtureContext? {
        guard let model, model.isUITesting else { return nil }
        guard let session = model.sessionContext, operation.serverID == session.serverID else { throw APIError.stationMismatch }
        let identity = await session.client.userWriteIdentity()
        guard operation.identity == identity, session.generation == model.sessionGeneration, let context = model.groupStore?.fixtureContext else {
            throw CancellationError()
        }
        if session.isReadOnlyToken { throw APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY") }
        try context.fixtures.interruptFirstWrite(operation)
        return context
    }
    private static func written(_ intent: GroupWriteDraft.Intent, in fixture: GroupFixtureContext) throws -> AdminGroup {
        switch intent {
        case .create(let request):
            return try fixture.fixtures.createGroup(request, accounts: fixture.accounts, now: fixture.now)
        case .update(let id, let request):
            if let current = fixture.fixtures.groups.first(where: { $0.id == id }), !GroupFixtures.sendsOnlyChanges(request, current: current) {
                throw APIError.server(status: 400, reason: "VALIDATION_ERROR")
            }
            return try fixture.fixtures.updateGroup(id: id, request, accounts: fixture.accounts, now: fixture.now)
        }
    }
}
