import Testing
import Sub2Core
@testable import NativeSessionSupport

// S5-05: a deleted group's pages leave the current tab's stack first; 查看 opens a copy once (50 §0.5).

@Test func leavingGroupDropsItsDetailAndWhatIsAbove() {
    #expect(GroupNavigation.leavingGroup([.groups(), .group(id: 1)], groupID: 1) == [.groups()])
    #expect(GroupNavigation.leavingGroup([.groups(), .group(id: 1), .groupKeys(groupID: 1)], groupID: 1) == [.groups()])
    #expect(GroupNavigation.leavingGroup([.group(id: 2), .group(id: 1)], groupID: 1) == [.group(id: 2)])
    #expect(GroupNavigation.leavingGroup([.groups(), .group(id: 2)], groupID: 1) == [.groups(), .group(id: 2)])
    #expect(GroupNavigation.leavingGroup([], groupID: 1) == [])
}

@MainActor @Test func leaveGroupChangesOnlyTheCurrentTab() {
    let router = AppRouter(selectedTab: .search)
    router.setPath([.groups(), .group(id: 1)], for: .search)
    router.setPath([.group(id: 1)], for: .accounts)
    #expect(router.leaveGroup(id: 1))
    #expect(router.path(for: .search) == [.groups()])
    #expect(router.path(for: .accounts) == [.group(id: 1)])
    #expect(!router.leaveGroup(id: 3))
    #expect(router.path(for: .search) == [.groups()])
}

@MainActor @Test func showGroupPushesUnlessAlreadyOnTop() {
    let router = AppRouter(selectedTab: .search)
    router.setPath([.groups()], for: .search)
    router.showGroup(id: 12)
    #expect(router.path(for: .search) == [.groups(), .group(id: 12)])
    router.showGroup(id: 12)
    #expect(router.path(for: .search) == [.groups(), .group(id: 12)])
    #expect(router.path(for: .today).isEmpty)
}

/// S5-08: 0.4.3 查看 opens the member write's per-item results on the current tab; S5-09: the route carries the outcome.
@MainActor @Test func showGroupBatchPushesTheResultPageOnTheCurrentTab() throws {
    let router = AppRouter(selectedTab: .search)
    router.setPath([.groups(), .group(id: 4)], for: .search)
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 7)])
    let outcome = GroupBatchOutcome(groupID: 4, groupName: "企业专线", request: request,
                                    result: GroupMemberBatchResult(groupID: 4, results: [], counts: nil))
    router.showGroupBatch(outcome)
    let path = router.path(for: .search)
    #expect(path.count == 3)
    #expect(Array(path.prefix(2)) == [.groups(), .group(id: 4)])
    guard case .groupBatch(let groupID, let name, let pushed)? = path.last else { Issue.record("no batch route"); return }
    #expect(groupID == 4 && name == "企业专线")
    #expect(pushed.value == outcome)
    #expect(pushed.value.items.map(\.result) == [.failed(.unconfirmed)])
    #expect(router.path(for: .accounts).isEmpty)
}
