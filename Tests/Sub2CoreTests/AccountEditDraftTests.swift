import Foundation
import Testing
@testable import Sub2Core

/// The site clock of every case: 2027-01-15T08:00:00Z.
private let editNow = Date(timeIntervalSince1970: 1_800_000_000)

/// An account detail decoded like a `GET :id` reply; `fields` are more top-level members.
private func account(type: String = "apikey", status: String = "active", _ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":4,"name":"OpenAI-主力-01","platform":"openai","type":"\#(type)","status":"\#(status)","schedulable":true"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func text(_ request: AccountPatchRequest?) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(try #require(request)), as: UTF8.self)
}
private func basic(_ base: UpstreamAccount) -> AccountEditForm { AccountEditForm(section: .basic, base: base) }
private func sched(_ base: UpstreamAccount) -> AccountEditForm { AccountEditForm(section: .sched, base: base) }

// MARK: - 基础

@Test func statusSegmentFollowsErrorState() throws {
    let failed = basic(try account(status: "error"))
    #expect(failed.statusOptions == [.error, .inactive])
    #expect(failed.statusFootnote == "清除错误用账号详情里的“恢复状态”")
    for status in ["active", "inactive"] {
        let form = basic(try account(status: status))
        #expect(form.statusOptions == [.active, .inactive])
        #expect(form.statusFootnote == "限流、过载等运行状态不在这里改")
    }
    for status in ["disabled", "paused"] {
        let base = try account(status: status)
        #expect(AccountEditDraft(base).status == .inactive)
        #expect(basic(base).change(AccountEditDraft(base), now: editNow) == nil)
    }
    #expect(AccountEditStatus.allCases.map(\.title) == ["正常", "停用", "错误"])
}

@Test func statusChangeSendsOnlyStatusAndUndoRestoresIt() throws {
    let cases: [(from: String, to: AccountEditStatus, sent: String, undone: String)] = [
        ("active", .inactive, "inactive", "active"), ("inactive", .active, "active", "inactive"), ("error", .inactive, "inactive", "error")
    ]
    for item in cases {
        let base = try account(status: item.from)
        var draft = AccountEditDraft(base)
        draft.status = item.to
        let change = try #require(basic(base).change(draft, now: editNow))
        #expect(try text(change.request) == #"{"status":"\#(item.sent)"}"#)
        #expect(try text(change.undo) == #"{"status":"\#(item.undone)"}"#)
        #expect(change.fieldNames == ["账号状态"])
    }
}

@Test func nameIsRequiredAfterTrimming() throws {
    let base = try account()
    let form = basic(base)
    for blank in ["", "   "] {
        var draft = AccountEditDraft(base)
        draft.name = blank
        #expect(form.errors(draft, now: editNow)[.name] == "请输入账号名称")
        #expect(form.change(draft, now: editNow) == nil)
        #expect(form.changedFields(draft) == [.name])
    }
    var padded = AccountEditDraft(base)
    padded.name = "  OpenAI-主力-01 "
    #expect(form.changedFields(padded).isEmpty)
    var renamed = AccountEditDraft(base)
    renamed.name = " 主力 "
    let change = try #require(form.change(renamed, now: editNow))
    #expect(try text(change.request) == #"{"name":"主力"}"#)
    #expect(try text(change.undo) == #"{"name":"OpenAI-主力-01"}"#)
}

@Test func notesCanBeClearedWithEmptyString() throws {
    let noted = try account(#""notes":"团队账单""#)
    var cleared = AccountEditDraft(noted)
    cleared.notes = ""
    let change = try #require(basic(noted).change(cleared, now: editNow))
    #expect(try text(change.request) == #"{"notes":""}"#)
    #expect(try text(change.undo) == #"{"notes":"团队账单"}"#)
    let bare = try account()
    #expect(basic(bare).changedFields(AccountEditDraft(bare)).isEmpty)
    var written = AccountEditDraft(bare)
    written.notes = "备用"
    #expect(try text(basic(bare).change(written, now: editNow)?.undo) == #"{"notes":""}"#)
}

// MARK: - 调度

@Test func concurrencyAndPrioritySentOnlyWhenChanged() throws {
    let base = try account(#""concurrency":0,"priority":3"#)
    let form = sched(base)
    #expect(form.change(AccountEditDraft(base), now: editNow) == nil)
    var draft = AccountEditDraft(base)
    draft.concurrency = 5
    let change = try #require(form.change(draft, now: editNow))
    #expect(try text(change.request) == #"{"concurrency":5}"#)
    #expect(try text(change.undo) == #"{"concurrency":0}"#)
    draft = AccountEditDraft(base)
    draft.priority = 0
    #expect(try text(form.change(draft, now: editNow)?.request) == #"{"priority":0}"#)
    #expect(try text(form.change(draft, now: editNow)?.undo) == #"{"priority":3}"#)
}

@Test(arguments: ["1", "0", "0.5", "12.345"])
func rateMultiplierAcceptsPlainDecimals(_ value: String) throws {
    let base = try account(#""rate_multiplier":2"#)
    var draft = AccountEditDraft(base)
    draft.rateMultiplier = value
    #expect(sched(base).errors(draft, now: editNow)[.rateMultiplier] == nil)
    #expect(sched(base).change(draft, now: editNow)?.request.rateMultiplier == Decimal(string: value))
}

@Test(arguments: ["", "-1", "1.", ".5", "1e3", "abc", "１.２", " 1", "1 "])
func rateMultiplierRejectsOtherText(_ value: String) throws {
    let base = try account(#""rate_multiplier":2"#)
    var draft = AccountEditDraft(base)
    draft.rateMultiplier = value
    #expect(sched(base).errors(draft, now: editNow)[.rateMultiplier] == "账号计费倍率需要是不小于 0 的数字")
    #expect(sched(base).change(draft, now: editNow) == nil)
}

@Test func rateMultiplierEqualValueIsNoChange() throws {
    let base = try account(#""rate_multiplier":1"#)
    var draft = AccountEditDraft(base)
    #expect(draft.rateMultiplier == "1")
    draft.rateMultiplier = "1.0"
    #expect(sched(base).changedFields(draft).isEmpty)
    draft.rateMultiplier = "1.25"
    #expect(try text(sched(base).change(draft, now: editNow)?.request) == #"{"rate_multiplier":1.25}"#)
}

@Test func rateMultiplierLockedWhileUpstreamRateSyncIsOn() throws {
    let base = try account(#""rate_multiplier":1,"extra":{"upstream_billing_rate_sync_enabled":true}"#)
    let form = sched(base)
    #expect(form.isRateLocked)
    var draft = AccountEditDraft(base)
    draft.rateMultiplier = "3"
    draft.priority = 7
    #expect(form.changedFields(draft) == [.priority])
    #expect(try text(form.change(draft, now: editNow)?.request) == #"{"priority":7}"#)
    #expect(!sched(try account()).isRateLocked)
}

@Test func loadFactorEmptyOrZeroMeansDefault() throws {
    let base = try account(#""load_factor":50"#)
    for blank in ["", "0"] {
        var draft = AccountEditDraft(base)
        draft.loadFactor = blank
        let change = try #require(sched(base).change(draft, now: editNow))
        #expect(try text(change.request) == #"{"load_factor":0}"#)
        #expect(try text(change.undo) == #"{"load_factor":50}"#)
    }
    let unset = try account()
    #expect(AccountEditDraft(unset).loadFactor == "")
    #expect(sched(unset).changedFields(AccountEditDraft(unset)).isEmpty)
    for valid in ["1", "10000"] {
        var draft = AccountEditDraft(unset)
        draft.loadFactor = valid
        #expect(sched(unset).change(draft, now: editNow)?.request.loadFactor == Int(valid))
    }
    for invalid in ["10001", "-1", "1.5", "abc"] {
        var draft = AccountEditDraft(unset)
        draft.loadFactor = invalid
        #expect(sched(unset).errors(draft, now: editNow)[.loadFactor] == "负载因子为 1–10000 的整数；留空或 0 恢复默认")
    }
}

@Test func groupChangeKeepsOrderAndUndoRestoresOriginalOrder() throws {
    let base = try account(#""group_ids":[5,1],"groups":[{"id":5,"name":"五"},{"id":1,"name":"一"}]"#)
    #expect(AccountEditDraft(base).groupIDs == [5, 1])
    var draft = AccountEditDraft(base)
    draft.groupIDs = [1, 10]
    let change = try #require(sched(base).change(draft, now: editNow))
    #expect(change.request.groupIDs == [1, 10])
    #expect(change.undo?.groupIDs == [5, 1])
    #expect(change.touchesGroups)
    draft.groupIDs = [1, 5]
    #expect(sched(base).changedFields(draft).isEmpty)
    var other = AccountEditDraft(base)
    other.priority = 4
    #expect(sched(base).change(other, now: editNow)?.touchesGroups == false)
}

@Test func groupOrderFallsBackToGroupsWhenIDsAreMissing() throws {
    let base = try account(#""group_ids":[3],"groups":[{"id":7,"name":"七"},{"id":3,"name":"三"}]"#)
    #expect(AccountEditDraft(base).groupIDs == [3, 7])
    let named = try account(#""groups":[{"id":7,"name":"七"},{"id":3,"name":"三"}]"#)
    #expect(AccountEditDraft(named).groupIDs == [7, 3])
}

@Test func expiryNeverSendsZeroAndAutoPauseOnlyWithExpiry() throws {
    let expiring = try account(#""expires_at":1900000000,"auto_pause_on_expired":true"#)
    var never = AccountEditDraft(expiring)
    never.expiresAt = nil
    never.autoPauseOnExpired = false
    let change = try #require(sched(expiring).change(never, now: editNow))
    #expect(try text(change.request) == #"{"expires_at":0}"#)
    #expect(try text(change.undo) == #"{"expires_at":1900000000}"#)
    #expect(change.fieldNames == ["过期时间"])
    let open = try account()
    var dated = AccountEditDraft(open)
    dated.expiresAt = 1_900_000_000
    dated.autoPauseOnExpired = true
    let added = try #require(sched(open).change(dated, now: editNow))
    #expect(try text(added.request) == #"{"auto_pause_on_expired":true,"expires_at":1900000000}"#)
    #expect(try text(added.undo) == #"{"auto_pause_on_expired":false,"expires_at":0}"#)
}

@Test func changedExpiryMustBeLaterThanServerNow() throws {
    let open = try account()
    var past = AccountEditDraft(open)
    past.expiresAt = Int64(editNow.timeIntervalSince1970)
    #expect(sched(open).errors(past, now: editNow)[.expiresAt] == "到期时间要晚于现在")
    #expect(sched(open).change(past, now: editNow) == nil)
    let lapsed = try account(#""expires_at":1700000000"#)
    var untouched = AccountEditDraft(lapsed)
    untouched.priority = 2
    #expect(sched(lapsed).errors(untouched, now: editNow).isEmpty)
    #expect(sched(lapsed).change(untouched, now: editNow) != nil)
}

@Test func quotaRowsOnlyForAPIKeyAndBedrock() throws {
    for type in ["apikey", "bedrock"] { #expect(AccountEditForm.supportsQuota(type: type)) }
    for type in ["oauth", "setup-token", "upstream", "service_account"] {
        #expect(!AccountEditForm.supportsQuota(type: type))
        let base = try account(type: type)
        var draft = AccountEditDraft(base)
        draft.quotaDaily = "20"
        #expect(sched(base).changedFields(draft).isEmpty)
    }
}

@Test func quotaEmptyOrZeroDeletesKeyInExtraPatch() throws {
    let base = try account(#""quota_daily_limit":150,"quota_daily_used":96.3"#)
    for blank in ["", "0"] {
        var draft = AccountEditDraft(base)
        draft.quotaDaily = blank
        let change = try #require(sched(base).change(draft, now: editNow))
        #expect(change.request.extraPatch == ["quota_daily_limit": .delete])
        #expect(change.undo?.extraPatch == ["quota_daily_limit": .set(.number(150))])
    }
    var raised = AccountEditDraft(base)
    raised.quotaDaily = "200.5"
    #expect(try text(sched(base).change(raised, now: editNow)?.request) == #"{"extra_patch":{"quota_daily_limit":200.5}}"#)
    var wrong = AccountEditDraft(base)
    wrong.quotaDaily = "abc"
    #expect(sched(base).errors(wrong, now: editNow)[.quotaDaily] == "填写美元金额，留空表示不限")
    let open = try account()
    var limits = AccountEditDraft(open)
    limits.quotaWeekly = "30"
    limits.quotaTotal = "500"
    let change = try #require(sched(open).change(limits, now: editNow))
    #expect(change.request.extraPatch == ["quota_weekly_limit": .set(.number(30)), "quota_limit": .set(.number(500))])
    #expect(change.undo?.extraPatch == ["quota_weekly_limit": .delete, "quota_limit": .delete])
    #expect(change.fieldNames == ["周限额", "总限额"])
}

@Test func requestBytesContainOnlyChangedKeys() throws {
    let base = try account(#""quota_daily_limit":150,"priority":1,"concurrency":8"#)
    var draft = AccountEditDraft(base)
    draft.name = "主力-改"
    draft.quotaDaily = ""
    let basicChange = try #require(basic(base).change(draft, now: editNow))
    let schedChange = try #require(sched(base).change(draft, now: editNow))
    #expect(try basicChange.request.requestBody() == Data(#"{"name":"主力-改"}"#.utf8))
    #expect(try schedChange.request.requestBody() == Data(#"{"extra_patch":{"quota_daily_limit":null}}"#.utf8))
}

// MARK: - 名称、回执与放弃确认

@Test func changedFieldNamesFollowSheetOrder() throws {
    let base = try account(#""notes":"旧","rate_multiplier":1,"load_factor":5,"expires_at":1900000000"#)
    var draft = AccountEditDraft(base)
    draft.notes = "新"; draft.status = .inactive; draft.name = "新名"
    draft.quotaTotal = "9"; draft.expiresAt = nil; draft.groupIDs = [2]; draft.loadFactor = ""; draft.rateMultiplier = "2"
    draft.priority = 9; draft.concurrency = 3; draft.quotaDaily = "1"; draft.quotaWeekly = "2"
    #expect(basic(base).changedFields(draft) == [.name, .status, .notes])
    #expect(sched(base).changedFields(draft) == [.concurrency, .priority, .rateMultiplier, .loadFactor, .groups, .expiresAt,
                                                .quotaDaily, .quotaWeekly, .quotaTotal])
    #expect(sched(base).change(draft, now: editNow)?.fieldNames == ["并发数", "优先级", "账号计费倍率", "负载因子", "分组", "过期时间",
                                                                     "日限额", "周限额", "总限额"])
}

@Test func savedReceiptNamesFirstThreeThenCount() {
    #expect(AccountEditCopy.savedReceipt(["名称"]) == "已保存：名称")
    #expect(AccountEditCopy.savedReceipt(["名称", "账号状态", "备注"]) == "已保存：名称、账号状态、备注")
    #expect(AccountEditCopy.savedReceipt(["并发数", "优先级", "账号计费倍率", "负载因子", "分组"]) == "已保存：并发数、优先级、账号计费倍率 等 5 项")
}

@Test func discardMessageCountsAndListsAllNames() {
    #expect(AccountEditCopy.discardTitle == "放弃未保存的改动？")
    #expect(AccountEditCopy.discardMessage(["名称", "备注"]) == "2 项改动不会保存：名称、备注")
    #expect(AccountEditCopy.discardMessage(["并发数", "优先级", "账号计费倍率", "负载因子", "分组"])
            == "5 项改动不会保存：并发数、优先级、账号计费倍率、负载因子、分组")
}

@Test func noChangeOrInvalidDraftYieldsNoChange() throws {
    let base = try account()
    #expect(basic(base).change(AccountEditDraft(base), now: editNow) == nil)
    #expect(basic(base).changedFields(AccountEditDraft(base)).isEmpty)
    var draft = AccountEditDraft(base)
    draft.notes = "新备注"
    draft.name = ""
    #expect(basic(base).changedFields(draft) == [.name, .notes])
    #expect(basic(base).change(draft, now: editNow) == nil)
}

@Test func rateTextUsesDisplayFormatDecimal() {
    #expect(AccountEditCopy.rate(Decimal(string: "1.2")) == "×1.2")
    #expect(AccountEditCopy.rate(1) == "×1")
    #expect(AccountEditCopy.rate(Decimal(string: "1.23456")) == "×1.235")
    #expect(AccountEditCopy.rate(0) == "×0")
    #expect(AccountEditCopy.rate(nil) == "—")
    #expect(AccountEditCopy.quotaUsed(Decimal(string: "96.3")) == "已用 $96.30")
    #expect(AccountEditCopy.quotaUsed(nil) == nil)
}

@Test func sectionsAndFieldsCarryTheirTitles() {
    #expect(AccountEditSection.allCases.map(\.title) == ["基础", "调度", "模型", "高级"])
    #expect(AccountEditSection.allCases.map(\.sheetTitle) == ["编辑基础信息", "编辑调度", "编辑模型", "编辑高级设置"])
    #expect(AccountEditField.allCases.filter { $0.section == .basic } == [.name, .status, .notes])
    #expect(AccountEditField.autoPauseOnExpired.title == "过期自动暂停调度")
}

@Test func changePrintsFieldAndKeyNamesOnly() throws {
    let base = try account()
    var draft = AccountEditDraft(base)
    draft.notes = "sk-secret-notes"
    let change = try #require(basic(base).change(draft, now: editNow))
    for printed in [String(describing: change), String(reflecting: change), "\(change)"] {
        #expect(!printed.contains("sk-secret-notes"))
        #expect(printed.contains("备注") && printed.contains("notes"))
    }
    var dumped = ""
    dump(change, to: &dumped)
    #expect(!dumped.contains("sk-secret-notes"))
}
