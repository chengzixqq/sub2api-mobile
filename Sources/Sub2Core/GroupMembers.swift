import Foundation

/// 50 §0.4.1: one account to add. A priority of 0 or less is the server's default 50, so it is not sent.
public struct GroupMemberAdd: Sendable, Equatable, Hashable, Encodable {
    public let accountID: Int
    public let priority: Int?
    public init(accountID: Int, priority: Int? = nil) {
        self.accountID = accountID
        self.priority = priority.flatMap { $0 > 0 ? $0 : nil }
    }
    enum CodingKeys: String, CodingKey { case accountID = "account_id", priority }
}

public enum GroupMemberAction: String, Sendable, Hashable, Codable {
    case add, remove
    var inverse: GroupMemberAction { self == .add ? .remove : .add }
}
public enum GroupMemberStatus: String, Sendable, Hashable, Codable { case added, removed, unchanged, failed }

/// One account and what is asked of it; a request names each account once.
struct GroupMemberKey: Hashable, Sendable {
    let accountID: Int
    let action: GroupMemberAction
}

/// 50 §0.4.1 `POST admin/groups/:id/accounts/batch`. No Idempotency-Key: an add already in the group and a removal already out
/// both answer `unchanged`, so the same body can go out again.
public struct GroupMemberBatchRequest: Sendable, Equatable, Encodable {
    /// The backend's maxGroupMemberChange.
    public static let maxPerRequest = 200
    public let add: [GroupMemberAdd]
    public let remove: [Int]
    public let confirmMixedChannelRisk: Bool

    /// Each side keeps the first of a repeated account (an add with its priority), as the server does. INVALID_ACCOUNT_ID,
    /// ACCOUNT_IN_BOTH_LISTS and EMPTY_MEMBER_CHANGE are refused here and never sent.
    public init(add: [GroupMemberAdd] = [], remove: [Int] = [], confirmMixedChannelRisk: Bool = false) throws {
        var adding = Set<Int>(), removing = Set<Int>()
        let add = add.filter { adding.insert($0.accountID).inserted }
        let remove = remove.filter { removing.insert($0).inserted }
        guard adding.union(removing).allSatisfy({ $0 > 0 }) else { throw Self.invalid("无效的对象编号。") }
        guard adding.isDisjoint(with: removing) else { throw Self.invalid("同一个账号不能同时加入和移出。") }
        guard !add.isEmpty || !remove.isEmpty else { throw Self.invalid("请选择要加入或移出的账号。") }
        self.init(checkedAdd: add, remove: remove, confirm: confirmMixedChannelRisk)
    }
    private init(checkedAdd add: [GroupMemberAdd], remove: [Int], confirm: Bool) {
        self.add = add; self.remove = remove; confirmMixedChannelRisk = confirm
    }
    enum CodingKeys: String, CodingKey { case add, remove, confirmMixedChannelRisk = "confirm_mixed_channel_risk" }

    /// Adds first, then removals.
    public var accountIDs: [Int] { add.map(\.accountID) + remove }
    public var count: Int { add.count + remove.count }
    var keys: [GroupMemberKey] {
        add.map { GroupMemberKey(accountID: $0.accountID, action: .add) } + remove.map { GroupMemberKey(accountID: $0, action: .remove) }
    }
    /// `limit` accounts a batch in `accountIDs` order (one batch can hold both kinds), each with the same confirmation.
    public func batches(limit: Int = GroupMemberBatchRequest.maxPerRequest) -> [GroupMemberBatchRequest] {
        let size = max(limit, 1)
        guard count > size else { return [self] }
        return stride(from: 0, to: count, by: size).map { start in
            let end = min(start + size, count)
            return GroupMemberBatchRequest(checkedAdd: Array(add[min(start, add.count)..<min(end, add.count)]),
                                           remove: Array(remove[max(start - add.count, 0)..<max(end - add.count, 0)]), confirm: confirmMixedChannelRisk)
        }
    }
    /// Sorted keys; the three keys are always there.
    public func requestBody() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(self)
    }
    /// 5.4: the same accounts after the mixed-channel confirmation.
    public func confirmingMixedChannel() -> GroupMemberBatchRequest { GroupMemberBatchRequest(checkedAdd: add, remove: remove, confirm: true) }
    /// 0.4.3 undo: added → remove, removed → add with the priority the answer brought back; unchanged and failed stay. Never
    /// confirmed: a group that became mixed meanwhile is asked about again. nil when nothing changed.
    public static func inverse(of result: GroupMemberBatchResult) -> GroupMemberBatchRequest? {
        let removed = result.results.filter { $0.action == .remove && $0.status == .removed }
        return nonEmpty(add: removed.map { GroupMemberAdd(accountID: $0.accountID, priority: $0.priority) },
                        remove: result.results.filter { $0.action == .add && $0.status == .added }.map(\.accountID), confirm: false)
    }
    /// nil when both sides are empty.
    static func nonEmpty(add: [GroupMemberAdd], remove: [Int], confirm: Bool) -> GroupMemberBatchRequest? {
        guard !add.isEmpty || !remove.isEmpty else { return nil }
        return try? GroupMemberBatchRequest(add: add, remove: remove, confirmMixedChannelRisk: confirm)
    }
    private static func invalid(_ message: String) -> APIError { APIError(kind: .validation, message: message) }
}

/// The per-item reasons of 50 §0.4.2 and §0.8.
public enum GroupMemberReason {
    public static let accountNotFound = AccountWriteReason.notFound
    public static let mixedChannelRisk = "MIXED_CHANNEL_RISK"
    public static let repositoryUnsupported = "GROUP_REPOSITORY_UNSUPPORTED"
    /// The App's own marks, never sent by the server (as AccountWriteReason.legacyCredentialsPut). Not delivered: a later batch
    /// that never went out, or an account the fallback did not reach after it stopped (5.3 “请求没有送达，账号没有改动”).
    public static let notDelivered = "REQUEST_NOT_DELIVERED"
    /// Sent, but nothing says whether it ran: a later batch lost after its one resend, an account a 2xx answer left out, or a
    /// fallback PUT without a definite answer (S5D2a-17).
    public static let notConfirmed = "REQUEST_UNCONFIRMED"
}

/// MIXED_CHANNEL_RISK `details`: display names (Anthropic / Antigravity), not platform ids.
public struct GroupMemberMixedChannel: Sendable, Equatable, Hashable, Decodable {
    public let currentPlatform: String
    public let otherPlatform: String
    public init(currentPlatform: String, otherPlatform: String) { self.currentPlatform = currentPlatform; self.otherPlatform = otherPlatform }
    /// The fallback's 409 metadata or check-mixed-channel details.
    public init(_ warning: MixedChannelWarning) { self.init(currentPlatform: warning.currentPlatform, otherPlatform: warning.otherPlatform) }
    enum CodingKeys: String, CodingKey { case currentPlatform = "current_platform", otherPlatform = "other_platform" }
    /// Both names, trimmed and not empty; anything else fails and the item keeps no details.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let names = try [CodingKeys.currentPlatform, .otherPlatform].map { try c.decode(String.self, forKey: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !names.contains(where: \.isEmpty) else {
            throw DecodingError.dataCorruptedError(forKey: .otherPlatform, in: c, debugDescription: "empty platform name")
        }
        self.init(currentPlatform: names[0], otherPlatform: names[1])
    }
}

/// One `results[]` entry. `message` is never read (R11, 00 §3.4).
public struct GroupMemberResultItem: Sendable, Equatable, Decodable {
    public let accountID: Int
    public let action: GroupMemberAction
    public let status: GroupMemberStatus
    /// added / removed; a removed one's is the priority an undo brings back.
    public let priority: Int?
    /// failed only; "" reads as nil.
    public let reason: String?
    public let details: GroupMemberMixedChannel?
    public init(accountID: Int, action: GroupMemberAction, status: GroupMemberStatus, priority: Int? = nil, reason: String? = nil,
                details: GroupMemberMixedChannel? = nil) {
        self.accountID = accountID; self.action = action; self.status = status; self.priority = priority; self.reason = reason; self.details = details
    }
    enum CodingKeys: String, CodingKey { case accountID = "account_id", action, status, priority, reason, details }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let reason = (try? c.decodeIfPresent(String.self, forKey: .reason))?.trimmingCharacters(in: .whitespacesAndNewlines)
        try self.init(accountID: c.decode(Int.self, forKey: .accountID), action: c.decode(GroupMemberAction.self, forKey: .action),
                      status: c.decode(GroupMemberStatus.self, forKey: .status), priority: try? c.decodeIfPresent(Int.self, forKey: .priority),
                      reason: reason?.isEmpty == false ? reason : nil, details: try? c.decodeIfPresent(GroupMemberMixedChannel.self, forKey: .details))
    }
    /// unchanged counts as a success (0.4.3).
    public var isSuccess: Bool { status != .failed }
    public var changedMembership: Bool { status == .added || status == .removed }
    var key: GroupMemberKey { GroupMemberKey(accountID: accountID, action: action) }
    static func failed(_ key: GroupMemberKey, reason: String, details: GroupMemberMixedChannel? = nil) -> GroupMemberResultItem {
        GroupMemberResultItem(accountID: key.accountID, action: key.action, status: .failed, reason: reason, details: details)
    }
}

/// 50 §0.4.2. The counts are taken from `results`, never from the reply's top-level numbers (00 §4.5).
public struct GroupMemberBatchResult: Sendable, Equatable, Decodable {
    /// 0 when missing; the client's results carry the requested group.
    public let groupID: Int
    /// An entry that cannot be read is dropped.
    public let results: [GroupMemberResultItem]
    /// Missing when the server could not read the group back: keep the old counts and reload the detail.
    public let counts: GroupAccountCounts?
    public init(groupID: Int, results: [GroupMemberResultItem], counts: GroupAccountCounts?) {
        self.groupID = groupID; self.results = results; self.counts = counts
    }
    enum CodingKeys: String, CodingKey { case groupID = "group_id", results, counts }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(groupID: (try? c.decodeIfPresent(Int.self, forKey: .groupID)) ?? 0,
                  results: (try? c.decodeIfPresent(LossyList<GroupMemberResultItem>.self, forKey: .results))?.items ?? [],
                  counts: try? c.decodeIfPresent(GroupAccountCounts.self, forKey: .counts))
    }
    public var added: Int { count(.added) }
    public var removed: Int { count(.removed) }
    public var unchanged: Int { count(.unchanged) }
    public var failed: Int { count(.failed) }
    private func count(_ status: GroupMemberStatus) -> Int { results.filter { $0.status == status }.count }
    /// Successes (unchanged included) of one kind.
    func succeeded(_ action: GroupMemberAction) -> Int { results.filter { $0.isSuccess && $0.action == action }.count }
    public func item(for accountID: Int, action: GroupMemberAction) -> GroupMemberResultItem? {
        results.first { $0.accountID == accountID && $0.action == action }
    }
    /// The first answer for each account and action.
    var answers: [GroupMemberKey: GroupMemberResultItem] { Dictionary(results.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }) }
    /// The next batch after this one; its counts are the latest (nil when it has none).
    public func merging(_ later: GroupMemberBatchResult) -> GroupMemberBatchResult {
        GroupMemberBatchResult(groupID: groupID, results: results + later.results, counts: later.counts)
    }
    /// Only the first answer for each account and action `request` asked for, in its order; one it asked for and did not get is
    /// unconfirmed (S5D2a-17).
    func scoped(to request: GroupMemberBatchRequest, groupID: Int) -> GroupMemberBatchResult {
        let firstAnswers = answers
        return GroupMemberBatchResult(groupID: groupID, results: request.keys.map { firstAnswers[$0] ?? .failed($0, reason: GroupMemberReason.notConfirmed) },
                                      counts: counts)
    }
    /// A batch that never went out.
    static func undelivered(_ request: GroupMemberBatchRequest, groupID: Int) -> GroupMemberBatchResult {
        failing(request, reason: GroupMemberReason.notDelivered, groupID: groupID)
    }
    static func failing(_ request: GroupMemberBatchRequest, reason: String, groupID: Int) -> GroupMemberBatchResult {
        GroupMemberBatchResult(groupID: groupID, results: request.keys.map { .failed($0, reason: reason) }, counts: nil)
    }
}

/// 0.4.3: the member receipt of the list, the detail and both sheets. The caller turns it into a ReceiptCenter Receipt.
public struct GroupMemberReceipt: Sendable, Equatable {
    public enum Prefix: Sendable, Equatable {
        case none, created(name: String), saved(name: String, droppedFields: Bool = false)
        var text: String? {
            switch self {
            case .none: nil
            case .created(let name): GroupCopy.createdReceipt(name: name)
            case .saved(let name, let droppedFields): GroupCopy.savedReceipt(name: name, droppedFields: droppedFields)
            }
        }
    }
    /// 撤销 / 查看 / 重试.
    public enum Button: Sendable, Equatable { case undo, details, retry }
    public let text: String
    public let systemImage: String
    public let tone: Tone
    public let button: Button?
    public init(text: String, systemImage: String, tone: Tone, button: Button?) {
        self.text = text; self.systemImage = systemImage; self.tone = tone; self.button = button
    }
    /// All succeeded: the summary, “ · 可用 x → y” when both are known and differ, 撤销 when anything changed. Some failed:
    /// “已加入 a 个，n 个失败” with 查看. All failed: “加入失败 · n 个账号没有改动” with 查看.
    public init(result: GroupMemberBatchResult, prefix: Prefix = .none, activeBefore: Int?) {
        let lead = prefix.text.map { $0 + " · " } ?? ""
        let added = result.succeeded(.add), removed = result.succeeded(.remove), failed = result.failed
        if failed == 0 {
            let change = Self.availability(from: activeBefore, to: result.counts?.activeAccountCount) ?? ""
            self.init(text: lead + (Self.summary(added: added, removed: removed) ?? GroupBatchCopy.allDone(nil)) + change, systemImage: "checkmark.circle",
                      tone: .ok, button: GroupMemberBatchRequest.inverse(of: result) == nil ? nil : .undo)
        } else if added + removed > 0 {
            let done = [added > 0 ? "已加入 \(DisplayFormat.grouped(added)) 个" : nil, removed > 0 ? "已移出 \(DisplayFormat.grouped(removed)) 个" : nil]
            self.init(text: lead + done.compactMap { $0 }.joined(separator: "、") + "，\(DisplayFormat.grouped(failed)) 个失败",
                      systemImage: "exclamationmark.triangle", tone: .caution, button: .details)
        } else {
            let actions = Set(result.results.map(\.action))
            let verb = actions.count > 1 ? "成员调整" : actions.first == .remove ? "移出" : "加入"
            self.init(text: lead + "\(verb)失败 · \(DisplayFormat.grouped(failed)) 个账号没有改动", systemImage: "xmark.octagon", tone: .critical, button: .details)
        }
    }
    public static func text(result: GroupMemberBatchResult, prefix: Prefix = .none, activeBefore: Int?) -> String {
        GroupMemberReceipt(result: result, prefix: prefix, activeBefore: activeBefore).text
    }
    /// 50 §2.4, one member swiped out: “已移出「账号」”, with “ · 可用 x → y” when it was available (y from the counts, else x − 1)
    /// and 撤销 when it really left; a failure reads as `init(result:)`.
    public static func removal(accountName: String, result: GroupMemberBatchResult, wasAvailable: Bool, activeBefore: Int?) -> GroupMemberReceipt {
        guard let item = result.results.first(where: { $0.action == .remove }), item.isSuccess else {
            return GroupMemberReceipt(result: result, activeBefore: activeBefore)
        }
        let text = "已移出「\(accountName)」"
        guard item.status == .removed else { return GroupMemberReceipt(text: text, systemImage: "checkmark.circle", tone: .ok, button: nil) }
        let after = result.counts?.activeAccountCount ?? activeBefore.map { max($0 - 1, 0) }
        let change = wasAvailable ? availability(from: activeBefore, to: after) : nil
        return GroupMemberReceipt(text: text + (change ?? ""), systemImage: "checkmark.circle", tone: .ok, button: .undo)
    }
    /// 0.8: still unknown after the one automatic resend; 重试 sends the same change again.
    public static let unconfirmed = GroupMemberReceipt(text: "成员改动未确认", systemImage: "exclamationmark.triangle", tone: .caution, button: .retry)
    /// “已加入 a 个账号” / “已移出 b 个账号” / “已加入 a 个、已移出 b 个账号”; nil when both are 0.
    public static func summary(added: Int, removed: Int) -> String? {
        switch (added > 0, removed > 0) {
        case (true, false): "已加入 \(DisplayFormat.grouped(added)) 个账号"
        case (false, true): "已移出 \(DisplayFormat.grouped(removed)) 个账号"
        case (true, true): "已加入 \(DisplayFormat.grouped(added)) 个、已移出 \(DisplayFormat.grouped(removed)) 个账号"
        case (false, false): nil
        }
    }
    private static func availability(from before: Int?, to after: Int?) -> String? {
        guard let before, let after, before != after else { return nil }
        return " · 可用 \(DisplayFormat.grouped(before)) → \(DisplayFormat.grouped(after))"
    }
}

/// R06: the one unkeyed write that resends itself, once, with the same body.
enum GroupMemberRetry {
    static let delay: Duration = .seconds(1)
    /// Not answered (the request left: not a deferred refresh), 408, or a gateway answer (502, 504, a 503 without its own reason).
    /// Business answers and anything a security prompt handled are final.
    static func retriesOnce(after error: APIError) -> Bool {
        guard error.securityOutcome == nil else { return false }
        guard let status = error.statusCode else { return error.kind == .transport && error != .refreshDeferred }
        return status == 408 || RequestPolicy.isRetryableStatus(status, marker: error.reason)
    }
    /// The mark of the account or batch that stopped a run. `mayHaveWritten`: the failed request was the write itself, so no
    /// answer, 408, 5xx, an unreadable reply or an unconfirmed keyed write leave it unconfirmed (S5D2a-17); a refusal keeps its
    /// reason; anything that was never sent is not delivered.
    static func unfinishedReason(_ error: any Error, mayHaveWritten: Bool) -> String {
        if let failure = error as? KeyedWriteFailure {
            guard mayHaveWritten, case .unconfirmed = failure.disposition else { return GroupMemberReason.notDelivered }
            return GroupMemberReason.notConfirmed
        }
        guard let api = error as? APIError else { return mayHaveWritten ? GroupMemberReason.notConfirmed : GroupMemberReason.notDelivered }
        if mayHaveWritten, mayHaveRun(api) { return GroupMemberReason.notConfirmed }
        guard api.statusCode != nil, let reason = api.reason, !reason.isEmpty else { return GroupMemberReason.notDelivered }
        return reason
    }
    private static func mayHaveRun(_ error: APIError) -> Bool {
        guard let status = error.statusCode else { return error != .refreshDeferred && [.transport, .response, .stream].contains(error.kind) }
        return status == 408 || status >= 500
    }
}

extension APIClient {
    /// 50 §0.4, R06. More than 200 accounts go in order, 200 a batch. The first batch's failure is thrown (the caller says
    /// “成员改动未确认”, the group is gone, or it switches to the 0.4.4 fallback); a later batch's failure stops the run and
    /// marks that batch (`GroupMemberRetry.unfinishedReason`) and the ones after it (not delivered), without counts.
    public func groupMemberBatch(groupID: Int, _ request: GroupMemberBatchRequest) async throws -> GroupMemberBatchResult {
        let path = "admin/groups/\(try validID(groupID))/accounts/batch"
        let snapshot = currentGeneration()
        let batches = request.batches()
        var merged = try await memberBatch(path, batches[0], generation: snapshot).scoped(to: batches[0], groupID: groupID)
        for index in batches.indices.dropFirst() {
            do {
                try check(snapshot)
                merged = merged.merging(try await memberBatch(path, batches[index], generation: snapshot).scoped(to: batches[index], groupID: groupID))
            } catch let error where !(error is CancellationError) {
                let stopped = GroupMemberBatchResult.failing(batches[index], reason: GroupMemberRetry.unfinishedReason(error, mayHaveWritten: true), groupID: groupID)
                return batches[(index + 1)...].reduce(merged.merging(stopped)) { $0.merging(.undelivered($1, groupID: groupID)) }
            }
        }
        return merged
    }
    /// One batch under one X-Request-ID; after GroupMemberRetry.retriesOnce it waits a second and sends the same bytes once
    /// more, in the foreground of the same session only: a wait cut short by `suspend` throws the first error, a new session
    /// CancellationError.
    private func memberBatch(_ path: String, _ batch: GroupMemberBatchRequest, generation snapshot: UUID) async throws -> GroupMemberBatchResult {
        let body = try batch.requestBody(), requestID = UUID().uuidString.lowercased()
        do {
            return try await memberBatchPost(path, body: body, requestID: requestID)
        } catch let error as APIError where GroupMemberRetry.retriesOnce(after: error) {
            do { try await pause(GroupMemberRetry.delay, generation: snapshot) }
            catch is CancellationError where currentGeneration() == snapshot && !Task.isCancelled { throw error }
            return try await memberBatchPost(path, body: body, requestID: requestID)
        }
    }
    private func memberBatchPost(_ path: String, body: Data, requestID: String) async throws -> GroupMemberBatchResult {
        let outcome: WriteOutcome<GroupMemberBatchResult> = try await performUnkeyedWrite(path, method: "POST", body: body, requestID: requestID)
        return outcome.value
    }
}
