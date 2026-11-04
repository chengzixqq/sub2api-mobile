import Foundation
import Sub2Core

/// 50 §0.7 `-ui-testing` (S5-13, X44): the fixture server on a simple-mode site (DemoData.simpleModeArgument), answering as the
/// backend does there — groups cut to simpleModeGroupResponse's keys and no composite group listed, 403
/// SIMPLE_MODE_OPERATION_UNSUPPORTED for copies and the advanced reads, 409 GROUP_NOT_EMPTY for deleting a group that still has
/// accounts (DeleteGroupIfEmpty), 400 SIMPLE_MODE_GROUP_NOT_BINDABLE for a composite group, and writes sanitised to the name and the
/// description (a new group also its platform). The fixtures have no composite group, so `simpleUnbindableArgument` makes every
/// member batch answer that 400 and `simpleCompositeArgument` every group's own read (U-15). GroupStore, the action and edit
/// sources and AppModel's member writes call these under `site.me.isSimpleRunMode`; subscriptions are not refused (the backend's
/// ListByGroup does not check run_mode).
extension GroupFixtures {
    enum SimpleModeCall: Sendable, Equatable {
        case stats, usageSummary, capacity, duplicate, apiKeys
        case read(platform: String)
        case delete(accountCount: Int, platform: String)
        case memberBatch(platform: String)
    }
    /// Simple mode only: every member batch answers 400 SIMPLE_MODE_GROUP_NOT_BINDABLE, as for a composite group.
    nonisolated static let simpleUnbindableArgument = "-ui-group-simple-unbindable"
    /// Simple mode only: every `GET admin/groups/:id` answers 400 SIMPLE_MODE_GROUP_NOT_BINDABLE, as for a composite group.
    nonisolated static let simpleCompositeArgument = "-ui-group-simple-composite"
    private nonisolated static let compositePlatform = "composite"

    /// The reply's keys only: the billing fields are gone and account / active / rate-limited counts of 0 are left out (omitempty).
    nonisolated static func simpleModeReply(_ group: AdminGroup) -> AdminGroup {
        AdminGroup(id: group.id, name: group.name, description: group.description, platform: group.platform, status: group.status,
                   rateMultiplier: nil, isExclusive: nil, subscriptionType: nil, rpmLimit: nil, accountCount: positive(group.accountCount),
                   activeAccountCount: positive(group.activeAccountCount), rateLimitedAccountCount: positive(group.rateLimitedAccountCount),
                   createdAt: group.createdAt, updatedAt: group.updatedAt, sortOrder: group.sortOrder ?? 0,
                   errorAccountCount: group.errorAccountCount, idleAccountCount: group.idleAccountCount)
    }
    /// What simple mode answers instead of the call; nil lets it through.
    nonisolated static func simpleModeRefusal(_ call: SimpleModeCall, arguments: [String] = ProcessInfo.processInfo.arguments) -> APIError? {
        let notBindable = APIError.server(status: 400, reason: "SIMPLE_MODE_GROUP_NOT_BINDABLE")
        switch call {
        case .stats, .usageSummary, .capacity, .duplicate, .apiKeys:
            return APIError.server(status: 403, reason: "SIMPLE_MODE_OPERATION_UNSUPPORTED")
        case .read(let platform):
            return platform == compositePlatform || arguments.contains(simpleCompositeArgument) ? notBindable : nil
        case .delete(let accountCount, let platform):
            if platform == compositePlatform { return notBindable }
            return accountCount > 0 ? APIError.server(status: 409, reason: "GROUP_NOT_EMPTY") : nil
        case .memberBatch(let platform):
            return platform == compositePlatform || arguments.contains(simpleUnbindableArgument) ? notBindable : nil
        }
    }

    /// `GET admin/groups`, with the list's failure arguments.
    func simpleModeList(accounts: [UpstreamAccount], now: Date) throws -> [AdminGroup] {
        try readList(accounts: accounts, now: now).filter { $0.platform != Self.compositePlatform }.map(Self.simpleModeReply)
    }
    /// `GET admin/groups/:id`.
    func simpleModeGroup(id: Int, accounts: [UpstreamAccount], now: Date) throws -> AdminGroup {
        let read = try group(id: id, accounts: accounts, now: now)
        if let refusal = Self.simpleModeRefusal(.read(platform: read.platform)) { throw refusal }
        return Self.simpleModeReply(read)
    }
    /// `POST admin/groups` (sanitizeCreateGroupRequestForSimpleMode): ×1, standard billing and public whatever was sent.
    func simpleModeCreate(_ request: GroupCreateRequest, accounts: [UpstreamAccount], now: Date) throws -> AdminGroup {
        let kept = GroupCreateRequest(name: request.name, description: request.description, platform: request.platform)
        return Self.simpleModeReply(try createGroup(kept, accounts: accounts, now: now))
    }
    /// `PUT admin/groups/:id` (sanitizeUpdateGroupRequestForSimpleMode): status, 专属 and billing are dropped without a word, so a
    /// request with neither name nor description changes nothing.
    func simpleModeUpdate(id: Int, _ request: GroupUpdateRequest, accounts: [UpstreamAccount], now: Date) throws -> AdminGroup {
        let kept = GroupUpdateRequest(name: request.name, description: request.description)
        let written = try kept.name == nil && kept.description == nil
            ? group(id: id, accounts: accounts, now: now) : updateGroup(id: id, kept, accounts: accounts, now: now)
        return Self.simpleModeReply(written)
    }
    /// `DELETE admin/groups/:id`: refused while any account, whatever its state, is in the group.
    func simpleModeDeleteRefusal(id: Int, accounts: [UpstreamAccount], now: Date) -> APIError? {
        guard let target = try? group(id: id, accounts: accounts, now: now) else { return nil }
        return Self.simpleModeRefusal(.delete(accountCount: target.accountCount ?? 0, platform: target.platform))
    }
    /// `POST admin/groups/:id/accounts/batch`: ValidateAccountGroupBindings before any change.
    func simpleModeMemberRefusal(groupID: Int) -> APIError? {
        Self.simpleModeRefusal(.memberBatch(platform: groups.first { $0.id == groupID }?.platform ?? ""))
    }

    private nonisolated static func positive(_ count: Int?) -> Int? { (count ?? 0) > 0 ? count : nil }
}
