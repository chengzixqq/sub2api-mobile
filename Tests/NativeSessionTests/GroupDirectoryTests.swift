import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Answers in order and counts calls; with a gate, each call waits until it opens.
private actor GroupLoader {
    private var replies: [Result<[AdminGroup], any Error>]
    private let gate: SessionGate?
    private(set) var calls = 0
    init(_ replies: [Result<[AdminGroup], any Error>], gate: SessionGate? = nil) { self.replies = replies; self.gate = gate }
    func load() async throws -> [AdminGroup] {
        calls += 1
        let reply = replies.isEmpty ? .success([]) : replies.removeFirst()
        if let gate { await gate.wait() }
        return try reply.get()
    }
}

@MainActor private final class TestClock {
    var now = t0
}

private func group(_ id: Int, _ name: String, sort: Int?) -> AdminGroup { AdminGroup(id: id, name: name, sortOrder: sort) }

@MainActor private func directory(_ loader: GroupLoader, clock: TestClock? = nil) -> GroupDirectory {
    GroupDirectory(load: { try await loader.load() }, now: { clock?.now ?? t0 })
}

private func waitForArrival(_ gate: SessionGate) async {
    while !(await gate.arrived) { await Task.yield() }
    for _ in 0..<5 { await Task.yield() }
}

/// sort_order ascending with a missing one as 0 (AdminGroup.displayOrder, the backend's order), then id.
@MainActor @Test func ensureLoadedLoadsOnceAndSortsBySortOrderThenID() async {
    let loader = GroupLoader([.success([group(3, "c", sort: 2), group(2, "b", sort: 1), group(1, "a", sort: 2), group(4, "d", sort: nil)])])
    let groups = directory(loader)
    #expect(groups.groups.isEmpty && groups.state == .idle)
    await groups.ensureLoaded()
    #expect(groups.groups.map(\.id) == [4, 2, 1, 3])
    await groups.ensureLoaded()
    #expect(await loader.calls == 1)
    #expect(groups.state.updatedAt == t0 && !groups.state.isLoading)
}

@MainActor @Test func concurrentEnsureLoadedSharesOneRequest() async {
    let gate = SessionGate()
    let loader = GroupLoader([.success([group(1, "高级组", sort: 1)]), .success([])], gate: gate)
    let groups = directory(loader)
    async let first: Void = groups.ensureLoaded()
    async let second: Void = groups.ensureLoaded()
    await waitForArrival(gate)
    #expect(groups.state.isLoading)
    await gate.open()
    _ = await (first, second)
    #expect(await loader.calls == 1)
    #expect(groups.groups.map(\.name) == ["高级组"])
}

@MainActor @Test func refreshForcesAnotherRequest() async {
    let loader = GroupLoader([.success([group(1, "旧名", sort: 1)]), .success([group(1, "新名", sort: 1), group(2, "标准组", sort: 2)])])
    let groups = directory(loader)
    await groups.ensureLoaded()
    await groups.refresh()
    #expect(await loader.calls == 2)
    #expect(groups.groups.map(\.name) == ["新名", "标准组"])
}

@MainActor @Test func failedRefreshKeepsGroupsAndReason() async {
    let failure = APIError.server(status: 502, reason: nil)
    let loader = GroupLoader([.success([group(1, "高级组", sort: 1)]), .failure(failure)])
    let groups = directory(loader)
    await groups.ensureLoaded()
    await groups.refresh()
    #expect(groups.state.failureReason == failure.localizedDescription)
    #expect(groups.groups.map(\.id) == [1] && groups.state.updatedAt == t0)
    #expect(groups.refreshState.consecutiveFailures == 1)
}

@MainActor @Test func failureWithoutGroupsIsRetriedByEnsureLoaded() async {
    let loader = GroupLoader([.failure(APIError.server(status: 502, reason: nil)), .success([group(1, "高级组", sort: 1)])])
    let groups = directory(loader)
    await groups.ensureLoaded()
    #expect(groups.groups.isEmpty && groups.state.failureReason != nil)
    await groups.ensureLoaded()
    #expect(await loader.calls == 2)
    #expect(groups.groups.map(\.id) == [1] && groups.refreshState.consecutiveFailures == 0)
}

@MainActor @Test func nameAndGroupLookups() async {
    let groups = directory(GroupLoader([.success([group(1, "高级组", sort: 1), group(2, "标准组", sort: 2)])]))
    #expect(groups.name(for: 1) == nil)
    await groups.ensureLoaded()
    #expect(groups.name(for: 1) == "高级组" && groups.name(for: 99) == nil)
    #expect(groups.group(id: 2)?.name == "标准组" && groups.group(id: 99) == nil)
    #expect(GroupDirectory.sorted([group(2, "b", sort: 1), group(1, "a", sort: 1)]).map(\.id) == [1, 2])
}

@MainActor @Test func upsertAndRemoveUpdateInPlace() async {
    let groups = directory(GroupLoader([.success([group(1, "高级组", sort: 1), group(2, "标准组", sort: 2)])]))
    await groups.ensureLoaded()
    groups.upsert(group(1, "改名", sort: 1))
    groups.upsert(group(3, "复制", sort: 0))
    #expect(groups.groups.map(\.name) == ["复制", "改名", "标准组"])
    groups.upsert(group(1, "改名", sort: 9))
    groups.remove(id: 2)
    #expect(groups.groups.map(\.id) == [3, 1])
    #expect(groups.state.updatedAt == t0 && !groups.state.isLoading)
}

@MainActor @Test func editsDuringLoadSurviveTheLoadResult() async {
    let gate = SessionGate()
    let loader = GroupLoader([.success([group(1, "旧名", sort: 1), group(2, "标准组", sort: 2)])], gate: gate)
    let groups = directory(loader)
    async let load: Void = groups.refresh()
    await waitForArrival(gate)
    groups.upsert(group(1, "新名", sort: 1))
    groups.remove(id: 2)
    groups.upsert(group(5, "Claude Code 组", sort: 5))
    await gate.open()
    await load
    #expect(groups.groups.map(\.name) == ["新名", "Claude Code 组"])
}

@MainActor @Test func rateLimitedLoadWaitsForRetryAfter() async {
    let limited = APIError.server(status: 429, envelope: ErrorEnvelope(reason: "RATE_LIMITED", retryAfter: 30), retryAfter: 30)
    let loader = GroupLoader([.failure(limited), .success([group(1, "高级组", sort: 1)])])
    let clock = TestClock()
    let groups = directory(loader, clock: clock)
    await groups.ensureLoaded()
    #expect(groups.refreshState.notBefore == t0.addingTimeInterval(30))
    clock.now = t0.addingTimeInterval(10)
    await groups.refresh()
    await groups.ensureLoaded()
    #expect(await loader.calls == 1)
    clock.now = t0.addingTimeInterval(30)
    await groups.refresh()
    #expect(await loader.calls == 2)
    #expect(groups.groups.map(\.id) == [1] && groups.state.updatedAt == t0.addingTimeInterval(30))
}
