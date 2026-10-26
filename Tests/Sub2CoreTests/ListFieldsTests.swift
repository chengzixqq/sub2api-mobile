import Foundation
import Testing
@testable import Sub2Core

@Test func listFieldSelectionRepairsUnknownAndDuplicateSavedFields() {
    let saved = #"{"version":1,"order":["groups","unknown","groups","platform"],"enabled":["groups","unknown","groups"]}"#
    let selection = ListFieldSelection<AccountListField>(rawValue: saved)
    #expect(Array(selection.orderedFields.prefix(2)) == [.groups, .platform])
    #expect(Set(selection.orderedFields).count == AccountListField.allCases.count)
    #expect(selection.orderedFields.count == AccountListField.allCases.count)
    #expect(selection.isEnabled(.groups))
    #expect(!selection.isEnabled(.platform))
    #expect(selection.isEnabled(.concurrency))
    #expect(!selection.rawValue.contains("unknown"))
    #expect(ListFieldSelection<AccountListField>(rawValue: selection.rawValue) == selection)
}

@Test func hiddenFieldsAndReorderingSurvivePersistence() {
    var selection = ListFieldSelection<UserListField>()
    selection.setEnabled(false, for: .balance)
    selection.setEnabled(true, for: .notes)
    let noteIndex = selection.orderedFields.firstIndex(of: .notes)!
    selection.move(fromOffsets: IndexSet(integer: noteIndex), toOffset: 0)
    let restored = ListFieldSelection<UserListField>(rawValue: selection.rawValue)
    #expect(restored.visibleFields.first == .notes)
    #expect(!restored.isEnabled(.balance))
    #expect(restored == selection)
    for field in UserListField.allCases { selection.setEnabled(false, for: field) }
    #expect(ListFieldSelection<UserListField>(rawValue: selection.rawValue).visibleFields.isEmpty)
}

@Test func multipleFieldMovesPreserveRelativeOrderAndIgnoreStaleIndices() {
    var selection = ListFieldSelection<AccountListField>()
    let original = selection.orderedFields
    selection.move(fromOffsets: IndexSet([0, 2]), toOffset: original.count)
    #expect(Array(selection.orderedFields.suffix(2)) == [original[0], original[2]])
    #expect(Set(selection.orderedFields).count == original.count)
    let moved = selection
    selection.move(fromOffsets: IndexSet(integer: 10_000), toOffset: 0)
    #expect(selection == moved)
}

@Test func corruptFieldPreferencesUseDefaultsAndSavedIdentitiesStaySeparate() {
    for raw in ["not json", "{}", #"{"version":2,"order":[],"enabled":[]}"#] {
        #expect(ListFieldSelection<UserListField>(rawValue: raw) == ListFieldSelection<UserListField>())
    }
    let first = UUID(), second = UUID()
    #expect(ListFieldSelection<UserListField>.storageKey(profileID: first) != ListFieldSelection<UserListField>.storageKey(profileID: second))
    #expect(ListFieldSelection<UserListField>.storageKey(profileID: first) != ListFieldSelection<AccountListField>.storageKey(profileID: first))
    #expect(ListFieldSelection<UserListField>.storageKey(profileID: first) == ListFieldSelection<UserListField>.storageKey(profileID: first))
}

@Test func accountListDecodesActualGroupsAndOptionalFieldsWithoutDetailRequests() throws {
    let payload = #"{"id":8,"name":"upstream","platform":"openai","type":"oauth","status":"active","schedulable":true,"concurrency":3,"priority":9,"rate_multiplier":"0.75000001","notes":"备用","last_used_at":"2026-10-15T01:02:03.123456Z","expires_at":1792051200,"created_at":"2026-10-01T00:00:00Z","base_rpm":120,"quota_used":"12.34567890","group_ids":[2,3],"groups":[{"id":2,"name":"主分组"},null],"account_groups":[{"group":{"id":2,"name":"重复"}},{"group":{"id":3,"name":"备用组"}},{"group":null}],"credentials":{"api_key":"never-decoded"}}"#
    let account = try JSONDecoder().decode(UpstreamAccount.self, from: Data(payload.utf8))
    #expect(account.groups == [.init(id: 2, name: "主分组"), .init(id: 3, name: "备用组")])
    #expect(account.groupIDs == [2, 3])
    #expect(account.priority == 9)
    #expect(account.rateMultiplier == Decimal(string: "0.75000001"))
    #expect(account.quotaUsed == Decimal(string: "12.34567890"))
    #expect(account.expiresAt == 1_792_051_200)
    #expect(account.baseRPM == 120)
    #expect(account.notes == "备用")
    #expect(ListFieldPresentation.timestamp(account.lastUsedAt) != "时间格式不受支持")
    let encoded = try JSONEncoder().encode(account)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("never-decoded"))
    #expect(try JSONDecoder().decode(UpstreamAccount.self, from: encoded).groups == account.groups)
    #expect(account.credentialsStatus?["has_api_key"] == true && account.credentials?["api_key"] == nil)
}

@Test func accountListKeepsOldResponsesCompatibleAndGroupIDsAvailable() throws {
    let old = #"{"id":1,"name":"old","platform":"anthropic","type":"apikey","status":"active","schedulable":false}"#
    let oldAccount = try JSONDecoder().decode(UpstreamAccount.self, from: Data(old.utf8))
    #expect(oldAccount.groups.isEmpty && oldAccount.groupIDs.isEmpty)
    #expect(oldAccount.quotaUsed == nil && oldAccount.rateMultiplier == nil)
    #expect(oldAccount.lastUsedAt == nil && oldAccount.createdAt == nil)
    let lite = String(old.dropLast()) + #","group_ids":[17,28]}"#
    let liteAccount = try JSONDecoder().decode(UpstreamAccount.self, from: Data(lite.utf8))
    #expect(liteAccount.groups.isEmpty && liteAccount.groupIDs == [17, 28])
    #expect(ListFieldPresentation.timestamp(nil) == "暂无记录")
    #expect(ListFieldPresentation.timestamp(seconds: nil) == "未设置")
}
