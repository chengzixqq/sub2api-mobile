import Foundation
import Testing
@testable import Sub2Core

// S5-02: 50 §0.7 and 00 §2.6.3 — entries, fields, menu, swipes and the button row. Vendor rows are kept for later (U01).

private let admin = AdminMe(user: .init(id: 1, role: "admin"))
private let simple = AdminMe(user: .init(id: 1, role: "admin"), server: .init(runMode: " Simple "))
private func vendor(ops: Bool? = nil, billing: Bool? = nil) -> AdminMe {
    AdminMe(user: .init(id: 2, role: "admin"), workspace: .init(id: 9, name: "代运营", permissions: .init(groupOps: ops, groupBilling: billing)))
}
private func group(status: String = "active", platform: String = "anthropic", billingLocked: Bool? = nil) -> AdminGroup {
    AdminGroup(id: 3, name: "高级组", platform: platform, status: status, billingLocked: billingLocked)
}
private func writes(_ p: GroupPermissions) -> [GroupPermissions.Entry] { [p.canCreate, p.canEdit, p.canToggleStatus, p.canDuplicate, p.canDelete] }

@Test func administratorSeesEveryEntry() {
    let permissions = GroupPermissions(me: admin, isReadOnlyToken: false)
    #expect(writes(permissions).allSatisfy { $0 == .enabled } && permissions.canEditMembers(group()) == .enabled)
    #expect(permissions.showsStats && permissions.showsKeysAndSubscriptions && permissions.showsUsageAndCapacity && permissions.showsBillingRow)
    #expect(permissions.membersFootnote == nil && permissions.billingNote(for: group()) == nil && permissions.billingNote(for: nil) == nil)
    #expect(!permissions.isVendor && !permissions.isSimpleMode && !permissions.isReadOnlyToken)
    #expect(GroupPermissions.Entry.enabled.isShown && GroupPermissions.Entry.enabled.isEnabled)
    #expect(!GroupPermissions.Entry.hidden.isShown && !GroupPermissions.Entry.hidden.isEnabled)
}

@Test func unknownIdentityIsTreatedAsTheAdministrator() {
    let reference = GroupPermissions(me: admin, isReadOnlyToken: false)
    #expect(GroupPermissions(me: nil, isReadOnlyToken: false) == reference)
    #expect(GroupPermissions(me: AdminMe(), isReadOnlyToken: false) == reference)
    #expect(GroupPermissions(me: nil, isReadOnlyToken: false).menu(for: group()).map(\.action) == reference.menu(for: group()).map(\.action))
}

@Test func readOnlyTokenGreysWritesAndOffersNoSwipes() {
    let permissions = GroupPermissions(me: admin, isReadOnlyToken: true)
    #expect(writes(permissions).allSatisfy { $0 == .readOnly } && permissions.canEditMembers(group()) == .readOnly)
    #expect(GroupPermissions.Entry.readOnly.isShown && !GroupPermissions.Entry.readOnly.isEnabled)
    let menu = permissions.menu(for: group())
    #expect(menu.map(\.action) == [.edit, .addAccounts, .disable, .duplicate, .delete] && menu.allSatisfy { $0.entry == .readOnly })
    #expect(permissions.leadingSwipe(for: group()).isEmpty && permissions.trailingSwipe(for: group()).isEmpty)
    #expect(GroupPermissions.Field.allCases.allSatisfy { permissions.access($0, in: group()) == .readOnly })
    #expect(GroupPermissions.Field.allCases.allSatisfy { permissions.access($0, in: nil) == .readOnly })
    #expect(permissions.editableFields(in: group()).isEmpty)
    #expect(permissions.showsStats && permissions.showsKeysAndSubscriptions && permissions.showsUsageAndCapacity && permissions.showsBillingRow)
    let simpleReadOnly = GroupPermissions(me: simple, isReadOnlyToken: true)
    #expect(simpleReadOnly.access(.name, in: group()) == .readOnly && simpleReadOnly.access(.rateMultiplier, in: group()) == .hidden)
    #expect(simpleReadOnly.canDuplicate == .hidden)
}

@Test func simpleModeHidesAdvancedEntriesAndFields() {
    let permissions = GroupPermissions(me: simple, isReadOnlyToken: false)
    #expect(permissions.isSimpleMode && permissions.canDuplicate == .hidden && permissions.canToggleStatus == .hidden)
    #expect(permissions.canCreate == .enabled && permissions.canEdit == .enabled && permissions.canDelete == .enabled)
    #expect(!permissions.showsStats && !permissions.showsKeysAndSubscriptions && !permissions.showsUsageAndCapacity && !permissions.showsBillingRow)
    #expect(permissions.access(.name, in: group()) == .editable && permissions.access(.description, in: group()) == .editable)
    #expect(permissions.access(.platform, in: group()) == .readOnly && permissions.access(.platform, in: nil) == .editable)
    let hidden: [GroupPermissions.Field] = [.status, .exclusive, .rateMultiplier, .billingType, .rpmLimit, .limits]
    #expect(hidden.allSatisfy { permissions.access($0, in: group()) == .hidden && permissions.access($0, in: nil) == .hidden })
    #expect(permissions.editableFields(in: group()) == [.name, .description] && permissions.editableFields(in: nil) == [.name, .description, .platform])
    #expect(permissions.menu(for: group()).map(\.action) == [.edit, .addAccounts, .delete])
    #expect(permissions.menu(for: group(status: "inactive")).map(\.action) == [.edit, .addAccounts, .delete])
    #expect(permissions.billingNote(for: group()) == nil)
}

@Test func simpleModeHidesMembersOfACompositeGroup() {
    #expect(GroupPermissions(me: simple, isReadOnlyToken: false).canEditMembers(group(platform: "composite")) == .hidden)
    #expect(GroupPermissions(me: simple, isReadOnlyToken: false).canEditMembers(group()) == .enabled)
    #expect(GroupPermissions(me: admin, isReadOnlyToken: false).canEditMembers(group(platform: "composite")) == .enabled)
    #expect(!GroupPermissions(me: simple, isReadOnlyToken: false).menu(for: group(platform: "composite")).contains { $0.action == .addAccounts })
}

@Test func vendorCannotCreateDuplicateDeleteOrChangeMembers() {
    let both = GroupPermissions(me: vendor(ops: true, billing: true), isReadOnlyToken: false)
    #expect(both.isVendor && both.canCreate == .hidden && both.canDuplicate == .hidden && both.canDelete == .hidden)
    #expect(both.canEditMembers(group()) == .hidden && both.membersFootnote == "调整成员请在账号详情里修改分组")
    #expect(!both.showsStats && !both.showsKeysAndSubscriptions && both.showsUsageAndCapacity && both.showsBillingRow)
    #expect(both.canEdit == .enabled && both.canToggleStatus == .enabled)
    #expect(both.menu(for: group()).map(\.action) == [.edit, .disable])
    let neither = GroupPermissions(me: vendor(), isReadOnlyToken: false)
    #expect(neither.canEdit == .hidden && neither.canToggleStatus == .hidden && neither.menu(for: group()).isEmpty)
    #expect(GroupPermissions(me: vendor(ops: false, billing: false), isReadOnlyToken: false).canEdit == .hidden)
}

@Test func vendorWithOnlyGroupOpsEditsBasicsButNotBilling() {
    let permissions = GroupPermissions(me: vendor(ops: true), isReadOnlyToken: false)
    #expect(permissions.canEdit == .enabled && permissions.canToggleStatus == .enabled)
    let basics: [GroupPermissions.Field] = [.name, .description, .status, .exclusive, .rpmLimit]
    #expect(basics.allSatisfy { permissions.access($0, in: group()) == .editable })
    #expect(permissions.access(.rateMultiplier, in: group()) == .readOnly && permissions.access(.limits, in: group()) == .readOnly)
    #expect(permissions.access(.billingType, in: group()) == .readOnly && permissions.access(.platform, in: group()) == .readOnly)
    #expect(permissions.billingNote(for: group()) == "计费由站长管理。" && GroupPermissions.billingManagedNote == "计费由站长管理。")
}

@Test func vendorWithOnlyGroupBillingAndBillingLocked() {
    let permissions = GroupPermissions(me: vendor(billing: true), isReadOnlyToken: false)
    #expect(permissions.canEdit == .enabled && permissions.canToggleStatus == .hidden)
    #expect(permissions.access(.rateMultiplier, in: group()) == .editable && permissions.access(.limits, in: group()) == .editable)
    let basics: [GroupPermissions.Field] = [.name, .description, .status, .exclusive, .rpmLimit]
    #expect(basics.allSatisfy { permissions.access($0, in: group()) == .readOnly })
    #expect(permissions.billingNote(for: group()) == nil && permissions.billingNote(for: group(billingLocked: false)) == nil)
    let locked = group(billingLocked: true)
    #expect(permissions.access(.rateMultiplier, in: locked) == .readOnly && permissions.access(.limits, in: locked) == .readOnly)
    #expect(permissions.billingNote(for: locked) == "计费由站长管理。")
    #expect(GroupPermissions(me: admin, isReadOnlyToken: false).access(.rateMultiplier, in: locked) == .editable)
    #expect(permissions.menu(for: group()).map(\.action) == [.edit])
}

@Test func menuOrderTitlesAndDestructiveDelete() {
    let permissions = GroupPermissions(me: admin, isReadOnlyToken: false)
    let menu = permissions.menu(for: group())
    #expect(menu.map(\.action) == [.edit, .addAccounts, .disable, .duplicate, .delete] && menu.allSatisfy { $0.entry == .enabled })
    #expect(menu.map(\.action.menuTitle) == ["编辑分组", "添加账号", "停用分组…", "复制分组", "删除分组…"] && menu[0].id == .edit)
    #expect(GroupAction.allCases.filter(\.isDestructive) == [.delete])
    #expect(permissions.menu(for: group(status: "inactive")).map(\.action) == [.edit, .addAccounts, .enable, .duplicate, .delete])
    #expect(GroupAction.enable.menuTitle == "启用分组")
    #expect(GroupAction.allCases.map(\.swipeTitle) == ["编辑", "添加账号", "停用", "启用", "复制", "删除"])
    #expect(GroupAction.allCases.map(\.rawValue) == ["edit", "addAccounts", "disable", "enable", "duplicate", "delete"])
}

@Test func swipesFollowStatusAndPermissions() {
    let permissions = GroupPermissions(me: admin, isReadOnlyToken: false)
    #expect(permissions.leadingSwipe(for: group()) == [.addAccounts] && permissions.leadingSwipe(for: group(status: "inactive")).isEmpty)
    #expect(permissions.trailingSwipe(for: group()) == [.edit, .disable] && permissions.trailingSwipe(for: group(status: "inactive")) == [.edit, .enable])
    #expect(GroupPermissions(me: simple, isReadOnlyToken: false).trailingSwipe(for: group()) == [.edit])
    #expect(GroupPermissions(me: simple, isReadOnlyToken: false).leadingSwipe(for: group(platform: "composite")).isEmpty)
    #expect(GroupPermissions(me: vendor(ops: true, billing: true), isReadOnlyToken: false).leadingSwipe(for: group()).isEmpty)
}

@Test func buttonRowPrimaryFollowsHealthAndDropsHiddenButtons() {
    func row(_ permissions: GroupPermissions, _ g: AdminGroup, _ health: GroupHealth) -> [String] {
        permissions.buttonRow(for: g, health: health).map { $0.action.menuTitle + ($0.isPrimary ? "（主）" : "") }
    }
    let owner = GroupPermissions(me: admin, isReadOnlyToken: false)
    #expect(row(owner, group(status: "inactive"), .off) == ["启用分组（主）", "编辑分组"])
    #expect(row(owner, group(), .noAvailable) == ["添加账号（主）", "编辑分组"] && row(owner, group(), .low) == ["添加账号（主）", "编辑分组"])
    #expect(row(owner, group(), .ok) == ["添加账号", "编辑分组（主）"])
    let ops = GroupPermissions(me: vendor(ops: true), isReadOnlyToken: false)
    #expect(row(ops, group(), .ok) == ["编辑分组（主）"] && row(ops, group(), .noAvailable) == ["编辑分组"])
    #expect(row(GroupPermissions(me: simple, isReadOnlyToken: false), group(status: "inactive"), .off) == ["编辑分组"])
    let readOnly = GroupPermissions(me: admin, isReadOnlyToken: true).buttonRow(for: group(), health: .ok)
    #expect(readOnly.map(\.action) == [.addAccounts, .edit] && readOnly.allSatisfy { $0.entry == .readOnly } && readOnly[1].isPrimary)
    #expect(readOnly[0].id == .addAccounts)
}

@Test func fieldAccessForNewAndExistingGroups() {
    let permissions = GroupPermissions(me: admin, isReadOnlyToken: false)
    #expect(permissions.access(.platform, in: nil) == .editable && permissions.access(.billingType, in: nil) == .editable)
    #expect(permissions.access(.status, in: nil) == .readOnly)
    #expect(permissions.access(.platform, in: group()) == .readOnly && permissions.access(.billingType, in: group()) == .readOnly)
    #expect(permissions.access(.status, in: group()) == .editable)
    for target in [nil, group()] {
        let editable = Set(GroupPermissions.Field.allCases.filter { permissions.access($0, in: target) == .editable })
        #expect(permissions.editableFields(in: target) == editable)
    }
    #expect(permissions.editableFields(in: group()) == [.name, .description, .status, .exclusive, .rateMultiplier, .rpmLimit, .limits])
    #expect(GroupPermissions.vendorMembersFootnote == "调整成员请在账号详情里修改分组")
}

@Test func memberBatchSupportGatesSimpleMode() {
    let unsupported = GroupPermissions(me: simple, isReadOnlyToken: false, supportsMemberBatch: false)
    #expect(unsupported.canEditMembers(group()) == .readOnly && unsupported.canEditMembers(group()).isShown && unsupported.membersBatchUnsupported)
    #expect(unsupported.canEditMembers(group(platform: "composite")) == .hidden)
    let menu = unsupported.menu(for: group())
    #expect(menu.map(\.action) == [.edit, .addAccounts, .delete] && menu.map(\.entry) == [.enabled, .readOnly, .enabled])
    #expect(unsupported.leadingSwipe(for: group()).isEmpty && unsupported.trailingSwipe(for: group()) == [.edit])
    #expect(unsupported.buttonRow(for: group(), health: .low).map(\.entry) == [.readOnly, .enabled])
    #expect(unsupported.canCreate == .enabled && unsupported.canEdit == .enabled && unsupported.canDelete == .enabled)
    let readOnly = GroupPermissions(me: simple, isReadOnlyToken: true, supportsMemberBatch: false)
    #expect(readOnly.canEditMembers(group()) == .readOnly && readOnly.membersBatchUnsupported)
    let supported = GroupPermissions(me: simple, isReadOnlyToken: false, supportsMemberBatch: true)
    #expect(supported.canEditMembers(group()) == .enabled && !supported.membersBatchUnsupported)
    #expect(supported == GroupPermissions(me: simple, isReadOnlyToken: false) && unsupported != supported)
    let legacy = GroupPermissions(me: admin, isReadOnlyToken: false, supportsMemberBatch: false)
    #expect(legacy.canEditMembers(group()) == .enabled && !legacy.membersBatchUnsupported && legacy.leadingSwipe(for: group()) == [.addAccounts])
    #expect(GroupPermissions.membersBatchUnsupportedNote == "服务器暂不支持批量调整成员")
}
