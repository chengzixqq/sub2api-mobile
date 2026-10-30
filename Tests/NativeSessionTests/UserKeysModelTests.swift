import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 30 §7.4–§7.6 (S3-12): the key segment's reads and writes against a stub site.

/// Holds a call until opened.
private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    var waiting: Int { waiters.count }
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; waiters.forEach { $0.resume() }; waiters = [] }
}

private let generation = UUID()
private let zone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let checked = Date(timeIntervalSince1970: 1_800_000_000)
private let directory = [
    AdminGroup(id: 1, name: "高级组", platform: "anthropic", rateMultiplier: 1, sortOrder: 1),
    AdminGroup(id: 2, name: "标准组", platform: "openai", rateMultiplier: 1, sortOrder: 2),
    AdminGroup(id: 5, name: "Claude Code 组", platform: "anthropic", rateMultiplier: 1, isExclusive: true, sortOrder: 5),
]
private let lost = APIError(kind: .transport, message: "无法连接站点")

private func key(_ id: Int = 7, name: String = "脚本", group: Int? = 2, status: String = "active", effective: String? = "active",
                 usage: Decimal = 0, expires: Date? = nil, concurrency: Int? = 0) -> AdminAPIKey {
    AdminAPIKey(id: id, userID: 10, keyMasked: "sk-…\(id)", name: name, groupID: group, status: status, effectiveStatus: effective, expiresAt: expires,
                currentConcurrency: concurrency, rateLimit5h: 5, usage5h: usage)
}
private func context(_ id: UUID = generation, readOnly: Bool = false, writes: Bool = true, concurrency: Bool = true) -> UserKeysContext {
    UserKeysContext(generation: id, isReadOnlyToken: readOnly, simpleMode: false, adminKeyWrites: writes, refreshesConcurrency: concurrency,
                    serverTimeZone: zone, now: { checked })
}
private func body(_ request: AdminAPIKeyUpdateRequest) -> String { String(decoding: (try? request.requestBody()) ?? Data(), as: UTF8.self) }

@MainActor private final class StubKeys: UserKeysSource {
    var userKeysContext: UserKeysContext? = context()
    var listed: [AdminAPIKey] = [key(7), key(8, name: "默认", group: 1)]
    var listError: (any Error)?
    var usage: [Int: Decimal] = [7: 2]
    var usageError: (any Error)?
    var subscriptionList: [AdminUserSubscription] = []
    var subscriptionsError: (any Error)?
    /// The reply to the n-th write (from 1); without one the key comes back as changed, its concurrency 0 like the server's.
    var onWrite: ((_ id: Int, _ request: AdminAPIKeyUpdateRequest, _ call: Int) throws -> AdminAPIKeyWriteResult)?
    /// Without one a read answers the key as last written, with its concurrency.
    var onRead: ((_ id: Int) throws -> AdminAPIKey)?
    var profile = AdminUser(id: 10, email: "ops@studio-k.example", username: "Studio-K 团队")
    var userWriteError: (any Error)?
    var hold: Gate?
    private(set) var listCalls = 0, usageCalls = 0, subscriptionCalls = 0, userReads = 0
    private(set) var reads: [Int] = []
    private(set) var writes: [String] = []
    private(set) var userWrites: [[Int]] = []
    private var latest: [Int: AdminAPIKey] = [:]

    func userAPIKeys(userID: Int) async throws -> [AdminAPIKey] {
        listCalls += 1
        if let listError { throw listError }
        return listed
    }
    func apiKey(id: Int) async throws -> AdminAPIKey {
        reads.append(id)
        if let onRead { return try onRead(id) }
        let base = current(id)
        return key(id, name: base.name, group: base.groupID, status: base.status, effective: base.effectiveStatus, usage: base.usage5h, concurrency: 3)
    }
    func apiKeysTodayUsage(ids: [Int]) async throws -> [Int: Decimal] {
        usageCalls += 1
        if let usageError { throw usageError }
        return usage.filter { ids.contains($0.key) }
    }
    func userSubscriptions(userID: Int) async throws -> [AdminUserSubscription] {
        subscriptionCalls += 1
        if let subscriptionsError { throw subscriptionsError }
        return subscriptionList
    }
    func updateAPIKey(id: Int, _ change: AdminAPIKeyUpdateRequest) async throws -> AdminAPIKeyWriteResult {
        writes.append(body(change))
        if let hold { await hold.wait() }
        let result = try onWrite?(id, change, writes.count) ?? changed(id, change)
        if let written = result.apiKey { latest[id] = written }
        return result
    }
    func user(id: Int) async throws -> AdminUser { userReads += 1; return profile }
    func updateUserGroups(userID: Int, allowedGroups: [Int], restrictPublicGroups: Bool) async throws -> AdminUser {
        userWrites.append(allowedGroups)
        if let userWriteError { throw userWriteError }
        return profile
    }
    private func current(_ id: Int) -> AdminAPIKey { latest[id] ?? listed.first { $0.id == id } ?? key(id) }
    private func changed(_ id: Int, _ request: AdminAPIKeyUpdateRequest) -> AdminAPIKeyWriteResult {
        let base = current(id), status = request.status?.rawValue ?? base.status
        let group = request.groupID.map { $0 == 0 ? nil : $0 } ?? base.groupID
        return AdminAPIKeyWriteResult(apiKey: key(id, name: base.name, group: group, status: status, effective: status,
                                                  usage: request.resetRateLimitUsage ? 0 : base.usage5h))
    }
}

@MainActor private final class Hooks {
    var access = UserKeyAccess(allowedGroups: [1, 2])
    var allows = true
    private(set) var events: [UserKeyImmediateEvent] = []
    private(set) var userChanges = 0, staleGroups = 0, begins = 0, ends = 0

    var hooks: UserKeysHooks {
        UserKeysHooks(access: { [self] in access }, groups: { directory }, onImmediate: { [self] in events.append($0) },
                      onUserChanged: { [self] in userChanges += 1 }, onGroupsStale: { [self] in staleGroups += 1 })
    }
    var gate: UserKeysWriteGate {
        UserKeysWriteGate(begin: { [self] in begins += 1; return allows }, end: { [self] in ends += 1 })
    }
}

@MainActor private func quietReceipts() -> ReceiptCenter { ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }) }
@MainActor private func makeModel(_ stub: StubKeys, hooks: Hooks = Hooks(), receipts: ReceiptCenter = quietReceipts()) -> UserKeysModel {
    UserKeysModel(userID: 10, source: stub, receipts: receipts, hooks: hooks.hooks, writeGate: hooks.gate)
}
@MainActor private func loaded(_ stub: StubKeys, hooks: Hooks = Hooks(), receipts: ReceiptCenter = quietReceipts()) async -> UserKeysModel {
    let model = makeModel(stub, hooks: hooks, receipts: receipts)
    await model.enterSegment()
    return model
}
/// The receipt's 撤销 runs in a task of its own.
@MainActor private func settle(until done: @MainActor () -> Bool) async {
    for _ in 0..<500 where !done() { try? await Task.sleep(for: .milliseconds(2)) }
}

@MainActor @Test func enterSegmentLoadsOnceAndPullRefreshesAll() async {
    let stub = StubKeys()
    let model = await loaded(stub)
    await model.enterSegment()
    #expect((stub.listCalls, stub.usageCalls, stub.subscriptionCalls) == (1, 1, 1))
    #expect(model.phase == .loaded && model.count == 2 && model.expandedID == 7)
    #expect(model.todayCost(for: 7) == .value(2) && model.todayCost(for: 8) == .value(0))
    await model.refreshAll()
    #expect((stub.listCalls, stub.usageCalls, stub.subscriptionCalls) == (2, 2, 2))
    // The page's count read first: entering still reads today's spend and the subscriptions.
    let fresh = StubKeys(), counted = makeModel(fresh)
    await counted.ensureListLoaded()
    await counted.ensureListLoaded()
    #expect(counted.count == 2 && (fresh.listCalls, fresh.usageCalls) == (1, 0))
    await counted.enterSegment()
    #expect((fresh.usageCalls, fresh.subscriptionCalls) == (1, 1))
}

@MainActor @Test func readOnlyTokenNeverRequestsKeyUsage() async {
    let stub = StubKeys()
    stub.userKeysContext = context(readOnly: true)
    let model = await loaded(stub)
    #expect(stub.usageCalls == 0 && model.todayCost(for: 7) == .unavailable)
    await model.changeGroup(model.keys[0], to: 1)
    await model.setStatus(model.keys[0], to: .inactive)
    #expect(stub.writes.isEmpty)
}

@MainActor @Test func partialFailuresStayInTheirBlocks() async {
    let stub = StubKeys()
    stub.usageError = APIError.server(status: 500, reason: nil)
    stub.subscriptionsError = APIError.server(status: 500, reason: nil)
    stub.subscriptionList = [AdminUserSubscription(id: 1, groupID: 4, status: "active")]
    let model = await loaded(stub)
    #expect(model.phase == .loaded && model.todayCost(for: 7) == .unavailable && model.subscriptions.isEmpty)
    let failing = StubKeys()
    failing.listError = APIError.server(status: 500, reason: nil)
    let broken = await loaded(failing)
    #expect(broken.phase == .failed && broken.count == nil && failing.usageCalls == 0)
    failing.listError = nil
    await broken.retryList()
    #expect(broken.phase == .loaded && broken.count == 2 && failing.usageCalls == 1)
    // A pull that fails keeps what was read.
    failing.listError = APIError.server(status: 500, reason: nil)
    await broken.refreshAll()
    #expect(broken.phase == .loaded && broken.keys.count == 2)
}

@MainActor @Test func toggleExpandedKeepsOnlyOneOpen() async {
    let stub = StubKeys()
    let model = await loaded(stub)
    #expect(model.toggleExpanded(8) && model.expandedID == 8)
    #expect(!model.toggleExpanded(8) && model.expandedID == nil)
    #expect(model.toggleExpanded(7) && model.expandedID == 7)
}

@MainActor @Test func changeGroupWaitsForServerAndReplacesCard() async {
    let stub = StubKeys(), hooks = Hooks(), receipts = quietReceipts(), gate = Gate()
    let model = await loaded(stub, hooks: hooks, receipts: receipts)
    stub.hold = gate
    let change = Task { await model.changeGroup(model.keys[0], to: 1) }
    while await gate.waiting == 0 { await Task.yield() }
    #expect(model.keys[0].groupID == 2 && model.inFlight == [7])
    await gate.open()
    await change.value
    #expect(stub.writes == [#"{"group_id":1}"#])
    #expect(model.inFlight.isEmpty && model.keys[0].groupID == 1)
    // api_keys.current_concurrency: one read of the card after the write.
    #expect(stub.reads == [7] && model.keys[0].currentConcurrency == 3)
    #expect(hooks.events == [.applied(name: "Key「脚本」换分组", grantedGroupID: nil)] && hooks.userChanges == 0)
    #expect(receipts.current?.text == "「脚本」已改到「高级组」" && receipts.current?.action != nil)
    // The current group sends nothing.
    await model.changeGroup(model.keys[0], to: 1)
    #expect(stub.writes.count == 1)
    let other = StubKeys(), unbind = await loaded(other, receipts: receipts)
    await unbind.changeGroup(unbind.keys[0], to: nil)
    #expect(other.writes == [#"{"group_id":0}"#])
    #expect(receipts.current?.text == "「脚本」已不绑定分组")
}

@MainActor @Test func newlyGrantedChangeUpdatesBaselineAndBumpsUser() async {
    let stub = StubKeys(), hooks = Hooks(), receipts = quietReceipts()
    stub.onWrite = { id, _, _ in AdminAPIKeyWriteResult(apiKey: key(id, group: 5), autoGrantedGroupAccess: true, grantedGroupID: 5) }
    let model = await loaded(stub, hooks: hooks, receipts: receipts)
    await model.changeGroup(model.keys[0], to: 5)
    #expect(hooks.events == [.applied(name: "Key「脚本」换分组", grantedGroupID: 5)] && hooks.userChanges == 1)
    #expect(receipts.current?.text == "已改到「Claude Code 组」，并为用户添加了这个分组")
    // The base already has it: no grant, whatever auto_granted_group_access says.
    let had = Hooks()
    had.access = UserKeyAccess(allowedGroups: [1, 2, 5])
    let other = await loaded(stub, hooks: had, receipts: receipts)
    await other.changeGroup(other.keys[0], to: 5)
    #expect(had.events == [.applied(name: "Key「脚本」换分组", grantedGroupID: nil)] && had.userChanges == 0)
    #expect(receipts.current?.text == "「脚本」已改到「Claude Code 组」")
}

@MainActor @Test func groupUndoExactThenStillInUseFallback() async {
    let stub = StubKeys(), hooks = Hooks(), receipts = quietReceipts()
    stub.onWrite = { id, request, _ in
        AdminAPIKeyWriteResult(apiKey: key(id, group: request.groupID ?? 2), autoGrantedGroupAccess: request.groupID == 5,
                               revokedGroupAccess: request.revokeGroupAccessID != nil)
    }
    let model = await loaded(stub, hooks: hooks, receipts: receipts)
    await model.changeGroup(model.keys[0], to: 5)
    receipts.performAction(id: receipts.current!.id)
    await settle { hooks.events.count == 2 }
    #expect(stub.writes == [#"{"group_id":5}"#, #"{"group_id":2,"revoke_group_access_id":5}"#])
    #expect(hooks.events.last == .withdrawn(name: "Key「脚本」换分组", revokedGroupID: 5) && hooks.userChanges == 2)
    #expect(receipts.current == nil && model.keys[0].groupID == 2)
    // 409 GROUP_STILL_IN_USE rolled the whole undo back: the key goes back alone and the grant stays.
    let busy = StubKeys(), kept = Hooks()
    busy.onWrite = { id, request, _ in
        if request.revokeGroupAccessID != nil { throw APIError.server(status: 409, reason: "GROUP_STILL_IN_USE") }
        return AdminAPIKeyWriteResult(apiKey: key(id, group: request.groupID ?? 2))
    }
    let other = await loaded(busy, hooks: kept, receipts: receipts)
    await other.changeGroup(other.keys[0], to: 5)
    receipts.performAction(id: receipts.current!.id)
    await settle { busy.writes.count == 3 && receipts.current != nil }
    #expect(busy.writes == [#"{"group_id":5}"#, #"{"group_id":2,"revoke_group_access_id":5}"#, #"{"group_id":2}"#])
    #expect(receipts.current?.text == "Key 已还原；该分组还有其他 Key 在用，授权保留" && receipts.current?.action == nil)
    #expect(kept.events == [.applied(name: "Key「脚本」换分组", grantedGroupID: 5)])
}

@MainActor @Test func groupUndoTwoStepWhenExactUndoUnavailable() async {
    let stub = StubKeys(), hooks = Hooks(), receipts = quietReceipts()
    stub.userKeysContext = context(writes: false)
    stub.profile.allowedGroups = [5, 1, 2]
    stub.profile.restrictPublicGroups = true
    let model = await loaded(stub, hooks: hooks, receipts: receipts)
    await model.changeGroup(model.keys[0], to: 5)
    receipts.performAction(id: receipts.current!.id)
    await settle { hooks.events.count == 2 }
    #expect(stub.writes == [#"{"group_id":5}"#, #"{"group_id":2}"#])
    #expect(stub.userReads == 1 && stub.userWrites == [[1, 2]])
    #expect(hooks.events.last == .withdrawn(name: "Key「脚本」换分组", revokedGroupID: 5))
    // The second step fails: the key is back, the grant is not.
    let failing = StubKeys(), kept = Hooks()
    failing.userKeysContext = context(writes: false)
    failing.profile.allowedGroups = [1, 2, 5]
    failing.userWriteError = APIError.server(status: 500, reason: nil)
    let other = await loaded(failing, hooks: kept, receipts: receipts)
    await other.changeGroup(other.keys[0], to: 5)
    receipts.performAction(id: receipts.current!.id)
    await settle { receipts.current != nil }
    #expect(receipts.current?.text == "Key 已还原，但分组授权没收回，请在权限与并发里手动移除")
    #expect(kept.events == [.applied(name: "Key「脚本」换分组", grantedGroupID: 5)])
}

@MainActor @Test func statusToggleUndoOnlyForActiveOrInactivePrevious() async {
    let stub = StubKeys(), hooks = Hooks(), receipts = quietReceipts()
    stub.onWrite = { id, request, _ in
        AdminAPIKeyWriteResult(apiKey: key(id, status: request.status!.rawValue, effective: request.status!.rawValue),
                               previous: AdminAPIKeyPrevious(status: request.status == .inactive ? "active" : "inactive"))
    }
    let model = await loaded(stub, hooks: hooks, receipts: receipts)
    await model.setStatus(model.keys[0], to: .inactive)
    #expect(receipts.current?.text == "已停用「脚本」" && receipts.current?.action != nil && model.keys[0].status == "inactive")
    receipts.performAction(id: receipts.current!.id)
    await settle { hooks.events.count == 2 }
    #expect(stub.writes == [#"{"status":"inactive"}"#, #"{"status":"active"}"#])
    #expect(hooks.events == [.applied(name: "Key「脚本」停用", grantedGroupID: nil), .withdrawn(name: "Key「脚本」停用", revokedGroupID: nil)])
    // previous quota_exhausted cannot be written back.
    stub.onWrite = { id, _, _ in AdminAPIKeyWriteResult(apiKey: key(id, status: "inactive"), previous: AdminAPIKeyPrevious(status: "quota_exhausted")) }
    await model.setStatus(model.keys[1], to: .inactive)
    #expect(receipts.current?.text == "已停用「默认」" && receipts.current?.action == nil)
    // Enabling an expired key leaves it unable to call.
    stub.onWrite = { id, _, _ in
        AdminAPIKeyWriteResult(apiKey: key(id, status: "active", effective: "expired"), previous: AdminAPIKeyPrevious(status: "inactive"))
    }
    await model.setStatus(model.keys[1], to: .active)
    #expect(receipts.current?.text == "已启用，但 Key 已过期，仍不能调用")
}

@MainActor @Test func statusIgnoredByAnOlderServer() async {
    let stub = StubKeys(), hooks = Hooks(), receipts = quietReceipts()
    stub.onWrite = { id, _, _ in AdminAPIKeyWriteResult(apiKey: key(id, status: "active")) }
    let model = await loaded(stub, hooks: hooks, receipts: receipts)
    await model.setStatus(model.keys[0], to: .inactive)
    #expect(receipts.current?.text == "这个站点还不支持停用 Key" && receipts.current?.action == nil && hooks.events.isEmpty)
    // Without E01 the menu is not there, and nothing is sent.
    stub.userKeysContext = context(writes: false)
    await model.setStatus(model.keys[0], to: .inactive)
    #expect(stub.writes.count == 1)
}

@MainActor @Test func resetRateLimitIsNotUndoable() async {
    let stub = StubKeys(), hooks = Hooks(), receipts = quietReceipts()
    stub.listed = [key(7, usage: 2)]
    stub.onWrite = { id, _, _ in AdminAPIKeyWriteResult(apiKey: key(id, usage: 0)) }
    let model = await loaded(stub, hooks: hooks, receipts: receipts)
    await model.resetRateLimit(model.keys[0])
    #expect(stub.writes == [#"{"reset_rate_limit_usage":true}"#] && model.keys[0].usage5h == 0)
    #expect(receipts.current?.text == "速率限制已重置" && receipts.current?.action == nil)
    #expect(hooks.events == [.applied(name: "Key「脚本」重置速率限制", grantedGroupID: nil)])
}

@MainActor @Test func keyGoneRemovesCardOnAnyWrite() async {
    let stub = StubKeys(), receipts = quietReceipts()
    stub.onWrite = { _, _, _ in throw APIError.server(status: 404, reason: "API_KEY_NOT_FOUND") }
    let model = await loaded(stub, receipts: receipts)
    await model.setStatus(model.keys[0], to: .inactive)
    #expect(model.keys.map(\.id) == [8] && model.expandedID == nil && model.count == 1)
    #expect(receipts.current?.text == "这个 Key 已被删除")
}

@MainActor @Test func groupErrorsKeepCardAndRefreshDirectory() async {
    let stub = StubKeys(), hooks = Hooks(), receipts = quietReceipts()
    stub.onWrite = { _, _, _ in throw APIError.server(status: 400, reason: "GROUP_NOT_ACTIVE") }
    let model = await loaded(stub, hooks: hooks, receipts: receipts)
    await model.changeGroup(model.keys[0], to: 1)
    #expect(model.keys[0].groupID == 2 && hooks.staleGroups == 1 && hooks.events.isEmpty)
    #expect(receipts.current?.text == "这个分组已停用")
    stub.onWrite = { _, _, _ in throw APIError.server(status: 400, reason: "SUBSCRIPTION_REQUIRED") }
    await model.changeGroup(model.keys[0], to: 1)
    await settle { stub.subscriptionCalls == 2 }
    #expect(receipts.current?.text == "用户没有这个分组的有效订阅" && stub.subscriptionCalls == 2)
}

@MainActor @Test func unkeyedWriteUncertainReadsBackOnceWithoutResend() async {
    let stub = StubKeys(), receipts = quietReceipts()
    stub.onWrite = { _, _, _ in throw APIError.server(status: 502, reason: nil) }
    stub.onRead = { key($0, group: 1) }
    let model = await loaded(stub, receipts: receipts)
    await model.changeGroup(model.keys[0], to: 1)
    #expect(stub.writes.count == 1 && model.keys[0].groupID == 1 && receipts.current?.text == "「脚本」已改到「高级组」")
    // The read shows the old group: not confirmed.
    stub.onRead = { key($0, group: 1) }
    await model.changeGroup(model.keys[0], to: 2)
    #expect(stub.writes.count == 2 && model.keys[0].groupID == 1 && receipts.current?.text == "结果未确认，请刷新核对后再操作")
    stub.onWrite = { _, _, _ in throw lost }
    stub.onRead = { _ in throw lost }
    await model.setStatus(model.keys[0], to: .inactive)
    #expect(stub.writes.count == 3 && receipts.current?.text == "结果未确认，请刷新核对后再操作")
}

@MainActor @Test func staleGenerationResultsAreDropped() async {
    let stub = StubKeys(), hooks = Hooks(), receipts = quietReceipts(), gate = Gate()
    let model = await loaded(stub, hooks: hooks, receipts: receipts)
    stub.hold = gate
    let change = Task { await model.changeGroup(model.keys[0], to: 1) }
    while await gate.waiting == 0 { await Task.yield() }
    stub.userKeysContext = context(UUID())
    await gate.open()
    await change.value
    #expect(model.keys[0].groupID == 2 && receipts.current == nil && hooks.events.isEmpty && stub.reads.isEmpty)
}

@MainActor @Test func bindingCountAndInsertRemove() async {
    let stub = StubKeys()
    stub.listed = [key(7, group: 4), key(9, group: 4), key(8, group: 1)]
    let model = await loaded(stub)
    #expect(model.bindingCount(groupID: 4) == 2 && model.bindingCount(groupID: 5) == 0)
    model.insert(key(3, group: 5))
    #expect(model.keys.map(\.id) == [3, 7, 8, 9] && model.count == 4)
    model.remove(id: 7)
    #expect(model.keys.map(\.id) == [3, 8, 9] && model.bindingCount(groupID: 4) == 1 && model.expandedID == nil)
    model.replace(key(8, name: "改名", group: 1))
    #expect(model.keys[1].name == "改名")
}

@MainActor @Test func writeGateWrapsGroupWritesAndRefusesWhileSaving() async {
    let stub = StubKeys(), hooks = Hooks(), receipts = quietReceipts()
    hooks.allows = false
    let model = await loaded(stub, hooks: hooks, receipts: receipts)
    await model.changeGroup(model.keys[0], to: 5)
    #expect(stub.writes.isEmpty && hooks.begins == 1 && hooks.ends == 0 && receipts.current?.text == "正在保存，请稍后再试")
    hooks.allows = true
    await model.changeGroup(model.keys[0], to: 5)
    #expect(stub.writes.count == 1 && (hooks.begins, hooks.ends) == (2, 1))
    stub.onWrite = { _, _, _ in throw APIError.server(status: 400, reason: "GROUP_NOT_ACTIVE") }
    await model.changeGroup(model.keys[1], to: 5)
    #expect((hooks.begins, hooks.ends) == (3, 2))
    // A change that grants nothing, a status or a reset never asks.
    stub.onWrite = { id, request, _ in AdminAPIKeyWriteResult(apiKey: key(id, group: request.groupID ?? 1, status: request.status?.rawValue ?? "active")) }
    await model.changeGroup(model.keys[1], to: 2)
    await model.setStatus(model.keys[1], to: .inactive)
    await model.resetRateLimit(model.keys[1])
    #expect((hooks.begins, hooks.ends) == (3, 2))
}
