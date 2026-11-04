import Foundation
import Testing
@testable import Sub2Core

// S5-11: 50 §3.3 成员账号 N, the member half of §3.4 新建 1 / 3 and 编辑 2 / 3, and §0.7's members area.

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(now.addingTimeInterval(seconds)) }
private func account(_ id: Int, _ name: String? = nil, platform: String = "anthropic", rateLimit: String? = nil) -> UpstreamAccount {
    UpstreamAccount(id: id, name: name ?? "Claude-官方-0\(id)", platform: platform, type: "oauth", rateLimitResetAt: rateLimit)
}
private let one = account(1), two = account(2), three = account(3, rateLimit: at(600))
private let four = account(4, "Claude-备用-04"), five = account(5, "Claude-备用-05")
private let premium = AdminGroup(id: 1, name: "高级组", description: "", platform: "anthropic", rateMultiplier: Decimal(string: "0.8")!, rpmLimit: 0,
                                 accountCount: 3, activeAccountCount: 2)
private let admin = AdminMe(user: .init(id: 1, role: "admin"))
private let simple = AdminMe(user: .init(id: 1, role: "admin"), server: .init(runMode: "simple"))
private let vendor = AdminMe(user: .init(id: 2, role: "admin"), workspace: .init(id: 9, name: "代运营", permissions: .init(groupOps: true, groupBilling: true)))

private func ids(_ draft: GroupMemberDraft) -> [Int] { draft.rows.map(\.id) }
private func loaded(_ members: [UpstreamAccount]) -> GroupMemberDraft { GroupMemberDraft(platform: "anthropic", original: members) }

@Test func newDraftIsEmptyLoadedAndHasNoChanges() throws {
    let draft = GroupMemberDraft.new(platform: "anthropic")
    #expect(draft.rows.isEmpty && draft.isLoaded && !draft.hasChanges && draft.count == 0)
    #expect(try draft.commitPlan() == nil && draft.availableAfter(now: now) == 0)
    let pending = GroupMemberDraft.pending(platform: "anthropic")
    #expect(!pending.isLoaded && pending.availableAfter(now: now) == nil && pending.availableNow(now: now) == nil)
    #expect(ids(pending.loaded([three, one])) == [3, 1] && pending.loaded([three]).isLoaded)
    #expect(ids(loaded([one]).loaded([two, three])) == [1])
}

@Test func loadedEditDraftKeepsServerOrderAndAddsInPickOrder() {
    let draft = loaded([three, one, two])
    #expect(ids(draft) == [3, 1, 2] && draft.rows.allSatisfy { !$0.isNew })
    let added = draft.adding([five, one, four])
    #expect(ids(added) == [3, 1, 2, 5, 4] && added.added.map(\.id) == [5, 4] && added.addedCount == 2)
    #expect(ids(added.adding([five])) == [3, 1, 2, 5, 4])
    #expect(added.rows.filter(\.isNew).map(\.id) == [5, 4] && added.count == 5)
}

@Test func removingAddedDropsItAndRemovingOriginalListsItInOriginalOrder() {
    let draft = loaded([one, two, three]).adding([five])
    let dropped = draft.removing(5)
    #expect(ids(dropped) == [1, 2, 3] && dropped.removedNames.isEmpty && !dropped.hasChanges)
    let both = dropped.removing(2).removing(1)
    #expect(both.removedIDs == [1, 2] && both.removedNames == ["Claude-官方-01", "Claude-官方-02"] && both.removedCount == 2)
    #expect(GroupMemberDraftCopy.removedLine(both.removedNames) == "将移出：Claude-官方-01、Claude-官方-02")
    #expect(both.removing(42) == both && ids(both) == [3])
}

@Test func reAddingRemovedOriginalRestoresItWithoutAChange() throws {
    let removed = loaded([one, two]).removing(1)
    #expect(removed.excludedIDs == [2])
    let back = removed.adding([one])
    #expect(ids(back) == [1, 2] && back.rows.allSatisfy { !$0.isNew })
    #expect(back.removedIDs.isEmpty && back.added.isEmpty && !back.hasChanges && back.excludedIDs == [1, 2])
    #expect(try back.commitPlan() == nil)
}

@Test func changingPlatformOfANewGroupClearsPickedAccounts() {
    let reset = GroupMemberDraft.new(platform: "anthropic").adding([one, two]).resetting(platform: "openai")
    #expect(reset.rows.isEmpty && reset.platform == "openai" && !reset.hasChanges && reset.isLoaded)

    var draft = GroupEditDraft.creating()
    draft.members = draft.members.adding([one])
    #expect(draft.hasUnsavedChanges)
    draft.platform = "openai"
    #expect(draft.members.rows.isEmpty && draft.members.platform == "openai")
    draft.platform = "anthropic"
    #expect(!draft.hasUnsavedChanges)
}

@Test func rowTrailingIsNewTagThenSchedulableThenBadge() throws {
    let draft = loaded([one, three]).adding([two])
    let rows = Dictionary(uniqueKeysWithValues: draft.rows.map { ($0.id, $0) })
    #expect(try #require(rows[2]).trailing(now: now) == .newlyAdded)
    #expect(try #require(rows[1]).trailing(now: now) == .schedulable)
    guard case .badge(let display) = try #require(rows[3]).trailing(now: now) else { Issue.record("限流成员应显示徽章"); return }
    #expect(display.state == .rateLimited && display.countdownTarget != nil)
    #expect(draft.hasCountdown(now: now) && !draft.hasCountdown(now: now.addingTimeInterval(601)))
    #expect(!GroupMemberDraft.new(platform: "anthropic").adding([three]).hasCountdown(now: now))
}

@Test func availabilityCountsSchedulableMembersOfTheGroupPlatform() {
    let openai = account(9, "OpenAI-主力", platform: "openai")
    let draft = loaded([one, three, openai])
    #expect(draft.availableNow(now: now) == 1 && draft.availableAfter(now: now) == 1)
    #expect(draft.removing(1).availableAfter(now: now) == 0 && draft.removing(1).availableNow(now: now) == 1)
    let composite = GroupMemberDraft(platform: "composite", original: [one, three, openai])
    #expect(composite.availableAfter(now: now) == 2)
    #expect(draft.availableAfter(now: now) == GroupPresentation.availableAfter(members: [one, three, openai], platform: "anthropic", now: now))
}

@Test func commitPlanAddsInPickOrderWithoutPriorityAndRemovesInOriginalOrder() throws {
    let draft = loaded([three, one, two]).removing(2).removing(3).adding([five, four])
    let plan = try #require(try draft.commitPlan())
    #expect(plan.request.add.map(\.accountID) == [5, 4] && plan.request.add.allSatisfy { $0.priority == nil })
    #expect(plan.request.remove == [3, 2] && !plan.request.confirmMixedChannelRisk)
    #expect(plan.accounts.map(\.id) == [5, 4, 3, 2] && plan.snapshots[3]?.name == "Claude-官方-03" && plan.snapshots.count == 4)
}

@Test func footnoteRowsOfTheMembersTable() {
    func note(isNew: Bool = false, isPublic: Bool = true, isActive: Bool = true, count: Int, after: Int, now: Int? = nil) -> GroupMemberFootnote {
        GroupMemberDraftCopy.footnote(isNew: isNew, isPublic: isPublic, isActiveAfterSave: isActive, count: count, availableAfter: after, availableNow: now)
    }
    #expect(note(isNew: true, count: 0, after: 0) == GroupMemberFootnote(text: "公开分组没有可用账号时，选它的请求会失败。可以现在添加，也可以创建后在详情里添加。", isCritical: false))
    #expect(note(isNew: true, isPublic: false, count: 0, after: 0) == GroupMemberFootnote(text: "可以现在添加，也可以创建后在详情里添加。", isCritical: false))
    #expect(note(isNew: true, count: 3, after: 2) == GroupMemberFootnote(text: "创建后可用 2 / 3", isCritical: false))
    #expect(note(isNew: true, count: 1, after: 0).isCritical)
    #expect(note(count: 3, after: 2, now: 2) == GroupMemberFootnote(text: "保存后可用 2 / 3", isCritical: false))
    #expect(note(count: 1, after: 1, now: 2) == GroupMemberFootnote(text: "保存后可用 1 / 1（现在 2）", isCritical: false))
    #expect(note(count: 1, after: 0, now: 2) == GroupMemberFootnote(text: "保存后可用 0 / 1（现在 2）", isCritical: true))
    #expect(!note(isActive: false, count: 1, after: 0, now: 2).isCritical)
}

@Test func sectionTitleAddRowAndRemoveLabel() {
    #expect(GroupMemberDraftCopy.sectionTitle(count: 3) == "成员账号 3" && GroupMemberDraftCopy.sectionTitle(count: 0) == "成员账号 0")
    #expect(GroupMemberDraftCopy.addRowTitle(platform: "anthropic") == "添加 Anthropic 账号…")
    #expect(GroupMemberDraftCopy.addRowTitle(platform: "openai") == "添加 OpenAI 账号…")
    #expect(GroupMemberDraftCopy.addRowTitle(platform: "composite") == "添加账号…")
    #expect(GroupMemberDraftCopy.removeLabel(name: "Claude-官方-01") == "移出 Claude-官方-01")
    #expect(GroupMemberDraftCopy.removedLine([]) == nil && GroupMemberDraftCopy.newTag == "新加入")
}

@Test func receiptWordsAfterTheGroupWasSaved() {
    #expect(GroupMemberDraftCopy.unconfirmedAfterSave(.saved(name: "高级组")) == "已保存「高级组」 · 成员改动未确认")
    #expect(GroupMemberDraftCopy.unconfirmedAfterSave(.created(name: "Claude 夜间组")) == "已创建「Claude 夜间组」 · 成员改动未确认")
    #expect(GroupMemberDraftCopy.rejectedAfterSave(.saved(name: "高级组"), reason: "提交的成员有误，请重试。") == "已保存「高级组」 · 成员没有改动：提交的成员有误，请重试。")
    #expect(GroupMemberDraftCopy.rejectedAfterSave(.saved(name: "标准组", droppedFields: true), reason: "x") == "已保存「标准组」 · 部分字段无权修改，未生效 · 成员没有改动：x")
}

@Test func stepsFollowWhatChanged() {
    #expect(GroupEditSteps.resolve(isNew: true, hasFieldChanges: true, hasMemberChanges: true) == .createGroup(thenMembers: true))
    #expect(GroupEditSteps.resolve(isNew: true, hasFieldChanges: false, hasMemberChanges: false) == .createGroup(thenMembers: false))
    #expect(GroupEditSteps.resolve(isNew: false, hasFieldChanges: true, hasMemberChanges: true) == .updateGroup(thenMembers: true))
    #expect(GroupEditSteps.resolve(isNew: false, hasFieldChanges: true, hasMemberChanges: false) == .updateGroup(thenMembers: false))
    let membersOnly = GroupEditSteps.resolve(isNew: false, hasFieldChanges: false, hasMemberChanges: true)
    #expect(membersOnly == .membersOnly && !membersOnly.sendsGroupWrite && membersOnly.sendsMembers)
    #expect(GroupEditSteps.resolve(isNew: false, hasFieldChanges: false, hasMemberChanges: false) == .nothing)
    #expect(GroupEditSteps.updateGroup(thenMembers: false).sendsGroupWrite && !GroupEditSteps.updateGroup(thenMembers: false).sendsMembers)
}

@Test func membersSectionHiddenForVendorAndSimpleModeComposite() {
    let composite = AdminGroup(id: 6, name: "组合", platform: "composite")
    let site = GroupPermissions(me: admin, isReadOnlyToken: false)
    #expect(GroupMemberDraftCopy.membersEntry(site, group: nil) == .enabled && GroupMemberDraftCopy.membersEntry(site, group: premium) == .enabled)
    let agency = GroupPermissions(me: vendor, isReadOnlyToken: false)
    #expect(GroupMemberDraftCopy.membersEntry(agency, group: nil) == .hidden && GroupMemberDraftCopy.membersEntry(agency, group: premium) == .hidden)
    let simpleMode = GroupPermissions(me: simple, isReadOnlyToken: false)
    #expect(GroupMemberDraftCopy.membersEntry(simpleMode, group: composite) == .hidden)
    #expect(GroupMemberDraftCopy.membersEntry(simpleMode, group: premium) == .enabled && GroupMemberDraftCopy.membersEntry(simpleMode, group: nil) == .enabled)
    let readOnly = GroupPermissions(me: admin, isReadOnlyToken: true)
    #expect(GroupMemberDraftCopy.membersEntry(readOnly, group: nil) == .readOnly && GroupMemberDraftCopy.membersEntry(readOnly, group: premium) == .readOnly)
}

@Test func membersEntryStaysGreyedWithoutMemberBatchInSimpleMode() {
    let unsupported = GroupPermissions(me: simple, isReadOnlyToken: false, supportsMemberBatch: false)
    #expect(GroupMemberDraftCopy.membersEntry(unsupported, group: premium) == .readOnly)
    #expect(GroupMemberDraftCopy.membersEntry(unsupported, group: nil) == .readOnly)
    let legacy = GroupPermissions(me: admin, isReadOnlyToken: false, supportsMemberBatch: false)
    #expect(GroupMemberDraftCopy.membersEntry(legacy, group: premium) == .enabled && GroupMemberDraftCopy.membersEntry(legacy, group: nil) == .enabled)
    let agency = GroupPermissions(me: vendor, isReadOnlyToken: false, supportsMemberBatch: false)
    #expect(GroupMemberDraftCopy.membersEntry(agency, group: nil) == .hidden)
}

@Test func editDiffFromDraftAsksBeforeEmptyingTheGroup() throws {
    var draft = GroupEditDraft(editing: premium)
    draft.membersLoaded([one, two, three])
    draft.members = draft.members.removing(1).removing(2)
    #expect(draft.steps(editable: Set(GroupPermissions.Field.allCases)) == .membersOnly)
    let diff = try #require(draft.diff(GroupUpdateRequest(), now: now))
    #expect(diff.membersRemoved == 2 && diff.availableNow == 2 && diff.availableAfter == 0)
    #expect(diff.requiresConfirmation && diff.isDestructive)
    let confirmation = diff.confirmation(siteName: "X", activeAPIKeys: nil)
    #expect(confirmation.lines.contains("成员：移出 2 个") && confirmation.lines.contains("保存后这个分组没有可用的账号，新请求会失败。"))
    #expect(confirmation.confirmTitle == "仍然保存" && confirmation.isDestructive)
    draft.isActive = false
    let disabling = try #require(try draft.updateRequest(editable: Set(GroupPermissions.Field.allCases)))
    #expect(try #require(draft.diff(disabling, now: now)).isDestructive == false)
}

@Test func membersOnlyWithoutEmptyingSavesDirectly() throws {
    var draft = GroupEditDraft(editing: premium)
    draft.membersLoaded([one, two, three])
    #expect(!draft.hasUnsavedChanges && !draft.isSubmittable(takenNames: [], editable: Set(GroupPermissions.Field.allCases)))
    draft.members = draft.members.removing(3)
    #expect(draft.hasUnsavedChanges && draft.isSubmittable(takenNames: [], editable: Set(GroupPermissions.Field.allCases)))
    #expect(try #require(draft.diff(GroupUpdateRequest(), now: now)).requiresConfirmation == false)
    let footnote = try #require(draft.membersFootnote(now: now))
    #expect(footnote == GroupMemberFootnote(text: "保存后可用 2 / 2", isCritical: false))
    #expect(GroupEditDraft(editing: premium).membersFootnote(now: now) == nil)
}

@Test func createConfirmationUsesDraftAvailability() throws {
    var draft = GroupEditDraft.creating()
    draft.name = "Claude 夜间组"
    let request = try draft.createRequest()
    draft.members = draft.members.adding([one])
    #expect(GroupCopy.createConfirmation(request, siteName: "X", availableAfter: try #require(draft.members.availableAfter(now: now))) == nil)
    draft.members = draft.members.removing(1).adding([three])
    let ask = GroupCopy.createConfirmation(request, siteName: "X", availableAfter: try #require(draft.members.availableAfter(now: now)))
    #expect(ask?.title == "创建公开分组「Claude 夜间组」？")
    #expect(draft.steps(editable: []) == .createGroup(thenMembers: true))
    #expect(draft.membersFootnote(now: now) == GroupMemberFootnote(text: "创建后可用 0 / 1", isCritical: true))
}

@Test func equalityComparesMemberIDs() {
    #expect(loaded([one, two]) == loaded([one, two]))
    #expect(loaded([one]).adding([four, five]) != loaded([one]).adding([five, four]))
    #expect(GroupMemberDraft.pending(platform: "anthropic") != loaded([]))
    #expect(GroupMemberDraft.new(platform: "anthropic") != GroupMemberDraft.new(platform: "openai"))
}
