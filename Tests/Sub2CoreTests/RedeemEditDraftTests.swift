import Foundation
import Testing
@testable import Sub2Core

// 60 §9.3 / §9.4 row by row: modes and choices, the fields each row sends (as bytes), the custom time, titles, footnotes,
// receipts, the reasons and the read-back.

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let newYork = TimeZone(identifier: "America/New_York")!
private func instant(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let now = instant("2026-10-16T09:41:00+08:00")
private let fullCode = "a3f01b2c3d4e5f60718293a4b5c6d4e8"
private let original = instant("2026-10-23T09:12:00+08:00")

private func code(_ status: String, type: String = "balance", usedBy: Int? = nil, expiresAt: Date? = original, groupID: Int? = nil,
                  notes: String? = "活动") -> AdminRedeemCode {
    AdminRedeemCode(id: 7, code: fullCode, type: type, value: 10, status: status, usedBy: usedBy, expiresAt: expiresAt, groupID: groupID,
                    validityDays: type == "subscription" ? 30 : nil, notes: notes)
}
private func bytes(_ fields: RedeemBatchUpdateFields) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(fields), as: UTF8.self)
}
private func draft(_ code: AdminRedeemCode, _ edit: (inout RedeemEditDraft) -> Void = { _ in }) -> RedeemEditDraft {
    var draft = RedeemEditDraft(code: code, now: now)
    edit(&draft)
    return draft
}

// MARK: 9.3 modes and choices

@Test func modeFollowsStatusAndRedemption() {
    #expect(RedeemEditMode(code: code("unused")) == .toggleable)
    #expect(RedeemEditMode(code: code("disabled")) == .toggleable)
    #expect(RedeemEditMode(code: code("expired")) == .expired)
    #expect(RedeemEditMode(code: code("used")) == .notesOnly)
    // Redeemed, then disabled or expired: still only notes.
    #expect(RedeemEditMode(code: code("disabled", usedBy: 3)) == .notesOnly)
    #expect(RedeemEditMode(code: code("expired", usedBy: 3)) == .notesOnly)
    #expect(RedeemEditMode(code: code("archived")) == .notesOnly)
}

@Test func choicesStartFromTheOriginalExpiry() {
    let kept = draft(code("unused"))
    #expect(kept.expiry == .keep)
    #expect(kept.expiryChoices == [.keep, .never, .days(1), .days(3), .days(7), .days(30), .custom])
    let endless = draft(code("unused", expiresAt: nil))
    #expect(endless.expiry == .never)
    #expect(endless.expiryChoices == [.never, .days(1), .days(3), .days(7), .days(30), .custom])
    #expect(RedeemEditExpiryChoice.presetDays == [1, 3, 7, 30])
    #expect(kept.expiryChoices.map(\.identifier) == ["keep", "never", "d1", "d3", "d7", "d30", "custom"])
    #expect(!draft(code("used")).showsExpiry && !draft(code("used")).showsStatus)
    #expect(draft(code("unused", type: "subscription", groupID: 4)).showsGroup)
    #expect(!draft(code("unused")).showsGroup && !draft(code("used", type: "subscription", groupID: 4)).showsGroup)
    #expect(draft(code("disabled")).status == .disabled && draft(code("unused")).status == .unused)
}

/// An expired code always offers 保持 first, with or without a time to keep, so opening it never counts as a renewal (9.4).
@Test func expiredWithoutAnExpiryStartsAtKeep() {
    let stale = draft(code("expired", expiresAt: nil))
    #expect(stale.expiry == .keep)
    #expect(stale.expiryChoices == [.keep, .never, .days(1), .days(3), .days(7), .days(30), .custom])
    #expect(!stale.isRenewing && stale.saveTitle == "保存" && stale.statusTitles == ["已过期"])
    #expect(!stale.canSave(now: now))
    #expect(stale.title(for: .keep, now: now, timeZone: shanghai) == "保持（已过期）")
    #expect(stale.expiryFootnote(now: now, timeZone: shanghai) == "选一个新的过期时间即可续期；保持原时间只改备注。")
}

@Test func choiceTitlesKeepTheOriginalTimeOnThePhone() {
    #expect(draft(code("unused")).title(for: .keep, now: now, timeZone: shanghai) == "保持 10/23 09:12")
    #expect(draft(code("expired", expiresAt: instant("2026-10-10T09:12:00+08:00"))).title(for: .keep, now: now, timeZone: shanghai)
        == "保持 10/10 09:12（已过期）")
    // A disabled code past its date reads the same.
    #expect(draft(code("disabled", expiresAt: instant("2026-10-10T09:12:00+08:00"))).title(for: .keep, now: now, timeZone: shanghai)
        == "保持 10/10 09:12（已过期）")
    #expect(draft(code("unused")).title(for: .keep, now: now, timeZone: newYork) == "保持 10/22 21:12")
    let titles = draft(code("unused")).expiryChoices.dropFirst().map { draft(code("unused")).title(for: $0, now: now, timeZone: shanghai) }
    #expect(titles == ["永不过期", "1 天", "3 天", "7 天", "30 天", "自定义"])
}

// MARK: 9.4 fields, one row each

struct RedeemEditFieldsRow: Sendable, CustomTestStringConvertible {
    let name: String
    let code: AdminRedeemCode
    let edit: @Sendable (inout RedeemEditDraft) -> Void
    let expected: String
    var testDescription: String { name }
}

private let sevenDays = "2026-10-23T01:41:00Z"

@Test(arguments: [
    RedeemEditFieldsRow(name: "redeemed: notes only", code: code("used", usedBy: 3), edit: { $0.notes = "补发"; $0.expiry = .never; $0.status = .disabled },
              expected: #"{"notes":"补发"}"#),
    RedeemEditFieldsRow(name: "unchanged: nothing", code: code("unused"), edit: { _ in }, expected: "{}"),
    RedeemEditFieldsRow(name: "status changed", code: code("unused"), edit: { $0.status = .disabled }, expected: #"{"status":"disabled"}"#),
    RedeemEditFieldsRow(name: "status back to the same", code: code("disabled"), edit: { $0.status = .disabled }, expected: "{}"),
    RedeemEditFieldsRow(name: "keep sends no expiry", code: code("unused"), edit: { $0.expiry = .keep; $0.notes = "x" }, expected: #"{"notes":"x"}"#),
    RedeemEditFieldsRow(name: "never is null", code: code("unused"), edit: { $0.expiry = .never }, expected: #"{"expires_at":null}"#),
    RedeemEditFieldsRow(name: "never on an endless code is nothing", code: code("unused", expiresAt: nil), edit: { $0.expiry = .never }, expected: "{}"),
    RedeemEditFieldsRow(name: "7 days from now", code: code("disabled"), edit: { $0.expiry = .days(7) }, expected: #"{"expires_at":"\#(sevenDays)"}"#),
    RedeemEditFieldsRow(name: "custom time", code: code("unused"), edit: { $0.expiry = .custom; $0.customExpiry = instant("2026-11-01T08:00:00+08:00") },
              expected: #"{"expires_at":"2026-11-01T00:00:00Z"}"#),
    RedeemEditFieldsRow(name: "subscription group changed", code: code("unused", type: "subscription", groupID: 4), edit: { $0.groupID = 5 },
              expected: #"{"group_id":5}"#),
    RedeemEditFieldsRow(name: "subscription group kept", code: code("unused", type: "subscription", groupID: 4), edit: { $0.groupID = 4 }, expected: "{}"),
    RedeemEditFieldsRow(name: "other types never send a group", code: code("unused", groupID: 4), edit: { $0.groupID = 5 }, expected: "{}"),
    RedeemEditFieldsRow(name: "notes changed, trimmed", code: code("unused"), edit: { $0.notes = "  工单 #8812\n" }, expected: #"{"notes":"工单 #8812"}"#),
    RedeemEditFieldsRow(name: "notes only re-spaced", code: code("unused"), edit: { $0.notes = " 活动 " }, expected: "{}"),
    RedeemEditFieldsRow(name: "notes cleared", code: code("unused"), edit: { $0.notes = "" }, expected: #"{"notes":""}"#),
    RedeemEditFieldsRow(name: "notes added", code: code("unused", notes: nil), edit: { $0.notes = "新" }, expected: #"{"notes":"新"}"#),
    RedeemEditFieldsRow(name: "expired: new time renews", code: code("expired"), edit: { $0.expiry = .days(7) },
              expected: #"{"expires_at":"\#(sevenDays)","status":"unused"}"#),
    RedeemEditFieldsRow(name: "expired: never renews", code: code("expired"), edit: { $0.expiry = .never }, expected: #"{"expires_at":null,"status":"unused"}"#),
    RedeemEditFieldsRow(name: "expired: keep sends notes only", code: code("expired"), edit: { $0.notes = "x"; $0.status = .disabled },
              expected: #"{"notes":"x"}"#),
    // Web 的“使过期” sets only the status: an expired code without an expiry opens at 保持 too.
    RedeemEditFieldsRow(name: "expired without an expiry: unchanged sends nothing", code: code("expired", expiresAt: nil), edit: { _ in }, expected: "{}"),
    RedeemEditFieldsRow(name: "expired without an expiry: notes only", code: code("expired", expiresAt: nil), edit: { $0.notes = "已泄露作废" },
              expected: #"{"notes":"已泄露作废"}"#),
    RedeemEditFieldsRow(name: "expired without an expiry: never renews", code: code("expired", expiresAt: nil), edit: { $0.expiry = .never },
              expected: #"{"expires_at":null,"status":"unused"}"#),
    RedeemEditFieldsRow(name: "expired subscription: group changed", code: code("expired", type: "subscription", groupID: 4), edit: { $0.groupID = 5 },
              expected: #"{"group_id":5}"#),
    RedeemEditFieldsRow(name: "everything", code: code("unused", type: "subscription", groupID: 4),
              edit: { $0.status = .disabled; $0.groupID = 5; $0.expiry = .days(7); $0.notes = "批次" },
              expected: #"{"expires_at":"\#(sevenDays)","group_id":5,"notes":"批次","status":"disabled"}"#),
])
func fieldsFollowTheRows(_ row: RedeemEditFieldsRow) throws {
    let fields = draft(row.code, row.edit).fields(now: now)
    #expect(try bytes(fields) == row.expected)
    #expect(draft(row.code, row.edit).canSave(now: now) == !fields.isEmpty)
}

@Test func customMustBeLaterThanNow() {
    for at in [now, now.addingTimeInterval(-60)] {
        let custom = draft(code("unused")) { $0.expiry = .custom; $0.customExpiry = at }
        #expect(!custom.customIsValid(now: now))
        #expect(!custom.canSave(now: now))
        #expect(custom.expiryFootnote(now: now, timeZone: shanghai) == "过期时间要晚于现在。")
    }
    let later = draft(code("unused")) { $0.expiry = .custom; $0.customExpiry = now.addingTimeInterval(60) }
    #expect(later.customIsValid(now: now) && later.canSave(now: now))
    // The custom field starts at the minute: the original future expiry, or a week from now.
    #expect(draft(code("unused")).customExpiry == original)
    #expect(draft(code("expired", expiresAt: instant("2026-10-10T09:12:00+08:00"))).customExpiry == instant("2026-10-23T09:41:00+08:00"))
    #expect(draft(code("unused", expiresAt: instant("2026-10-23T09:12:31+08:00"))).customExpiry == original)
    // A redeemed code ignores whatever expiry it holds.
    #expect(draft(code("used", usedBy: 3)) { $0.expiry = .custom; $0.customExpiry = now; $0.notes = "x" }.canSave(now: now))
}

// MARK: Titles, footnotes and receipts

@Test func titlesAndSaveButton() {
    #expect(draft(code("used")).sheetTitle == "编辑备注")
    #expect(draft(code("expired")).sheetTitle == "续期兑换码")
    #expect(draft(code("unused")).sheetTitle == "编辑兑换码")
    #expect(draft(code("expired")).saveTitle == "保存")
    #expect(draft(code("expired")) { $0.expiry = .days(7) }.saveTitle == "续期")
    #expect(draft(code("expired")) { $0.expiry = .days(7) }.isRenewing)
    #expect(draft(code("unused")) { $0.expiry = .days(7) }.saveTitle == "保存")
    #expect(draft(code("expired")).expirySectionTitle == "新的过期时间")
    #expect(draft(code("disabled")).expirySectionTitle == "过期时间")
    #expect(draft(code("expired")).statusTitles == ["已过期"])
    #expect(draft(code("expired")) { $0.expiry = .never }.statusTitles == ["已过期", "未使用"])
}

@Test func expiryFootnotes() {
    #expect(draft(code("unused")).expiryFootnote(now: now, timeZone: shanghai) == "从现在算起；永不过期 = 一直可兑换。")
    #expect(draft(code("expired")).expiryFootnote(now: now, timeZone: shanghai) == "选一个新的过期时间即可续期；保持原时间只改备注。")
    #expect(draft(code("expired")) { $0.expiry = .days(14) }.expiryFootnote(now: now, timeZone: shanghai) == "保存后 10/30 09:41 过期，状态改回“未使用”。")
    #expect(draft(code("expired")) { $0.expiry = .never }.expiryFootnote(now: now, timeZone: shanghai) == "保存后永不过期，状态改回“未使用”。")
}

@Test func successReceipts() {
    let renewed = draft(code("expired")) { $0.expiry = .days(14) }
    #expect(renewed.successReceipt(for: renewed.fields(now: now), now: now, timeZone: shanghai) == "已续期 · 10/30 过期，改回未使用")
    let endless = draft(code("expired")) { $0.expiry = .never }
    #expect(endless.successReceipt(for: endless.fields(now: now), now: now, timeZone: shanghai) == "已续期 · 永不过期，改回未使用")
    for notesOnly in [draft(code("used", usedBy: 3)) { $0.notes = "x" }, draft(code("unused")) { $0.notes = "x" }, draft(code("expired")) { $0.notes = "x" }] {
        #expect(notesOnly.successReceipt(for: notesOnly.fields(now: now), now: now, timeZone: shanghai) == "已保存备注")
    }
    let saved = draft(code("unused")) { $0.status = .disabled; $0.notes = "x" }
    #expect(saved.successReceipt(for: saved.fields(now: now), now: now, timeZone: shanghai) == "已保存兑换码")
}

@Test func switchToNotesOnlyKeepsTheNotes() throws {
    var raced = draft(code("unused")) { $0.status = .disabled; $0.expiry = .days(7); $0.notes = "新备注" }
    raced.switchToNotesOnly()
    #expect(raced.mode == .notesOnly && raced.wasSwitchedToNotesOnly)
    #expect(raced.sheetTitle == "编辑备注")
    #expect(try bytes(raced.fields(now: now)) == #"{"notes":"新备注"}"#)
    #expect(!draft(code("used", usedBy: 3)).wasSwitchedToNotesOnly)
}

@Test func copyIsTheSpecText() {
    #expect(RedeemEditCopy.targetLine(code("unused")) == "余额 · $10.00 · 面值生成后不能改")
    #expect(RedeemEditCopy.targetLine(code("unused", type: "subscription", groupID: 4)) == "订阅 · 30 天 · 面值生成后不能改")
    #expect(RedeemEditCopy.usedBanner == "已使用的兑换码只能改备注。")
    #expect(RedeemEditCopy.usedBy(name: "小王", at: "10/16 09:20") == "使用者 小王 · 10/16 09:20")
    #expect(RedeemEditCopy.statusFootnote == "禁用后不能再兑换，可以随时重新启用。")
    #expect(RedeemEditCopy.notesPlaceholder == "例如：活动批次、工单号")
    #expect(RedeemEditCopy.notesFootnote == "只有管理员看得到。")
    #expect(RedeemEditCopy.disabled == "已禁用 · 不能再兑换" && RedeemEditCopy.enabled == "已启用 · 可以兑换")
    #expect(RedeemEditCopy.toggleUsed == "这个码已被兑换，不能再改状态")
    #expect(RedeemEditCopy.editUsed == "这个码已被兑换，只能改备注")
    #expect(RedeemEditCopy.deleteUsed == "已被兑换的兑换码不能删除")
    #expect(RedeemEditCopy.gone == "这个兑换码已被删除")
    #expect(RedeemEditCopy.deleteConsequence(code("unused")) == "余额 · $10.00 · 未使用")
    #expect(RedeemEditCopy.groupDisabled("企业专线") == "企业专线（已停用）")
}

// MARK: Reasons (9.4) and read-back

struct RedeemWriteFailureRow: Sendable, CustomTestStringConvertible {
    let name: String
    let error: any Error & Sendable
    let expected: RedeemWriteFailure
    var testDescription: String { name }
}

@Test(arguments: [
    RedeemWriteFailureRow(name: "409 used", error: APIError.server(status: 409, reason: "REDEEM_CODE_USED"), expected: .used),
    RedeemWriteFailureRow(name: "404 gone", error: APIError.server(status: 404, reason: "REDEEM_CODE_NOT_FOUND"), expected: .gone),
    RedeemWriteFailureRow(name: "expiry", error: APIError.server(status: 400, reason: "REDEEM_CODE_EXPIRES_AT_INVALID"), expected: .expiresAtInvalid),
    RedeemWriteFailureRow(name: "status", error: APIError.server(status: 400, reason: "REDEEM_CODE_STATUS_INVALID"), expected: .groupInvalid),
    RedeemWriteFailureRow(name: "group", error: APIError.server(status: 400, reason: "REDEEM_CODE_GROUP_ID_INVALID"), expected: .groupInvalid),
    RedeemWriteFailureRow(name: "empty", error: APIError.server(status: 400, reason: "REDEEM_CODE_BATCH_UPDATE_EMPTY"),
               expected: .other(APIError.server(status: 400, reason: "REDEEM_CODE_BATCH_UPDATE_EMPTY").localizedDescription)),
    RedeemWriteFailureRow(name: "timeout", error: APIError(kind: .transport, message: "连接超时"), expected: .unconfirmed),
    RedeemWriteFailureRow(name: "502", error: APIError.server(status: 502, reason: nil), expected: .unconfirmed),
    RedeemWriteFailureRow(name: "504", error: APIError.server(status: 504, envelope: nil), expected: .unconfirmed),
    RedeemWriteFailureRow(name: "cancelled", error: CancellationError(), expected: .cancelled),
    RedeemWriteFailureRow(name: "read-only token", error: APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"),
               expected: .other(ReasonCatalog.entry(status: 403, reason: "ACCESS_TOKEN_READ_ONLY").message)),
])
func failuresFollowTheReasons(_ row: RedeemWriteFailureRow) {
    #expect(RedeemWriteFailure.classify(row.error) == row.expected)
}

@Test func clearedSecurityPromptAsksAgain() {
    let cleared = APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed)
    #expect(RedeemWriteFailure.classify(cleared) == .reconfirm(cleared.localizedDescription))
    #expect(RedeemWriteFailure.classify(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled)) == .cancelled)
    #expect(RedeemWriteFailure.expiresAtInvalid.message == "过期时间要晚于现在")
    #expect(RedeemWriteFailure.groupInvalid.message == "分组无效，请重新选择")
    #expect(RedeemWriteFailure.other("x").message == "x")
}

@Test func readBackComparesOnlyWhatWasSent() {
    let sent = RedeemBatchUpdateFields(status: .unused, expiresAt: .at(instant("2026-10-23T01:41:00Z")))
    #expect(sent.isReflected(in: code("unused", expiresAt: instant("2026-10-23T01:41:00.400Z"), notes: "别的")))
    #expect(!sent.isReflected(in: code("expired", expiresAt: instant("2026-10-23T01:41:00Z"))))
    #expect(!sent.isReflected(in: code("unused", expiresAt: instant("2026-10-23T01:42:00Z"))))
    #expect(!sent.isReflected(in: code("unused", expiresAt: nil)))
    #expect(RedeemBatchUpdateFields(expiresAt: .never).isReflected(in: code("unused", expiresAt: nil)))
    #expect(RedeemBatchUpdateFields(groupID: .id(5)).isReflected(in: code("unused", groupID: 5)))
    #expect(!RedeemBatchUpdateFields(groupID: .id(5)).isReflected(in: code("unused", groupID: 4)))
    #expect(RedeemBatchUpdateFields(notes: "").isReflected(in: code("unused", notes: nil)))
    #expect(!RedeemBatchUpdateFields(notes: "新").isReflected(in: code("unused")))
    #expect(RedeemBatchUpdateFields(notes: "x").touchesOnlyNotes && !RedeemBatchUpdateFields(status: .disabled, notes: "x").touchesOnlyNotes)
    #expect(code("unused").replacing(status: "disabled").status == "disabled")
    #expect(code("unused").replacing(status: "disabled").notes == "活动")
}
