import Foundation
import Testing
@testable import Sub2Core

// 60 §10.2 form rules and §10.3 receipt / confirmation texts.

private func decimal(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
private let batchID = UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!
private let batchKey = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let utc = TimeZone(identifier: "UTC")!
private let now = ServerTime.parseTimestamp("2026-10-16T09:41:00+08:00")!
private func summary(_ spec: RedeemGenerateSpec, now: Date = now, timeZone: TimeZone = shanghai) -> RedeemGenerateSummary {
    RedeemGenerateSummary(spec: spec, now: now, timeZone: timeZone)
}

@Test func balanceFormNeedsPositiveAmountWithTwoDecimals() throws {
    for amount: Decimal? in [nil, 0, -1, decimal("10.001"), decimal("1000000")] {
        let form = RedeemGenerateForm(type: .balance, amount: amount)
        #expect(form.invalidFields == [.value]); #expect(!form.isValid)
    }
    for amount in [decimal("0.01"), decimal("999999.99"), 10] { #expect(RedeemGenerateForm(type: .balance, amount: amount).isValid) }
    let spec = try RedeemGenerateForm(type: .balance, amount: decimal("10.5"), concurrency: 9, groupID: 3, validityDays: 30, count: 20).validated()
    #expect(spec == RedeemGenerateSpec(type: .balance, value: decimal("10.5"), count: 20))
}

@Test func concurrencyFormAcceptsOneToFifty() throws {
    for value in [0, 51, -1] { #expect(RedeemGenerateForm(type: .concurrency, concurrency: value).invalidFields == [.concurrency]) }
    for value in [1, 50] { #expect(RedeemGenerateForm(type: .concurrency, concurrency: value).isValid) }
    let spec = try RedeemGenerateForm(type: .concurrency, amount: 10, concurrency: 2, count: 5).validated()
    #expect(spec == RedeemGenerateSpec(type: .concurrency, value: 2, count: 5))
}

@Test func subscriptionFormNeedsGroupAndValidityDays() throws {
    #expect(RedeemGenerateForm(type: .subscription, groupID: nil).invalidFields == [.group])
    #expect(RedeemGenerateForm(type: .subscription, groupID: 0).invalidFields == [.group])
    for days: Int? in [nil, 0, 3651] { #expect(RedeemGenerateForm(type: .subscription, groupID: 3, validityDays: days).invalidFields == [.validityDays]) }
    for days in [1, 3650] { #expect(RedeemGenerateForm(type: .subscription, groupID: 3, validityDays: days).isValid) }
    let form = RedeemGenerateForm(type: .subscription, amount: 10, concurrency: 4, groupID: 3, groupName: " 企业专线 ", validityDays: 30, count: 5)
    let spec = try form.validated()
    #expect(spec == RedeemGenerateSpec(type: .subscription, value: 0, count: 5, groupID: 3, groupName: "企业专线", validityDays: 30))
    #expect(text(try spec.requestBody(batchID: batchID))
            == #"{"batch_id":"\#(batchKey)","count":5,"group_id":3,"type":"subscription","validity_days":30,"value":0}"#)
}

@Test func invitationFormSendsZeroValueAndIgnoresOtherFields() throws {
    let form = RedeemGenerateForm(type: .invitation, amount: 10, concurrency: 99, groupID: -1, groupName: "x", validityDays: 0, count: 10)
    #expect(form.isValid)
    let spec = try form.validated()
    #expect(spec == RedeemGenerateSpec(type: .invitation, value: 0, count: 10))
    #expect(text(try spec.requestBody(batchID: batchID)) == #"{"batch_id":"\#(batchKey)","count":10,"type":"invitation","value":0}"#)
}

@Test func countAndExpiryRanges() throws {
    for count in [0, 101] { #expect(RedeemGenerateForm(type: .invitation, count: count).invalidFields == [.count]) }
    for count in [1, 100] { #expect(RedeemGenerateForm(type: .invitation, count: count).isValid) }
    for days in [0, 3651] { #expect(RedeemGenerateForm(type: .invitation, expiresInDays: days).invalidFields == [.expiresInDays]) }
    for days in [1, 3650] { #expect(RedeemGenerateForm(type: .invitation, expiresInDays: days).isValid) }
    let never = try RedeemGenerateForm(type: .invitation).validated()
    #expect(never.expiresInDays == nil); #expect(!text(try never.requestBody(batchID: batchID)).contains("expires_in_days"))
    let week = try RedeemGenerateForm(type: .invitation, expiresInDays: 7).validated()
    #expect(text(try week.requestBody(batchID: batchID)).contains(#""expires_in_days":7"#))
    #expect(RedeemGenerateForm(type: .balance, amount: 0, count: 0, expiresInDays: 0).invalidFields == [.value, .count, .expiresInDays])
}

@Test func notesLimitCountsTrimmedScalars() throws {
    let limit = String(repeating: "备", count: 1_000)
    #expect(RedeemGenerateForm(type: .invitation, notes: limit).isValid)
    #expect(RedeemGenerateForm(type: .invitation, notes: limit + "注").invalidFields == [.notes])
    let padded = try RedeemGenerateForm(type: .invitation, notes: "  " + limit + "\n").validated()
    #expect(padded.notes == limit)
    // A skin-tone emoji is two scalars, as the server counts runes.
    #expect(RedeemGenerateForm(type: .invitation, notes: String(repeating: "👍🏽", count: 500)).isValid)
    #expect(RedeemGenerateForm(type: .invitation, notes: String(repeating: "👍🏽", count: 501)).invalidFields == [.notes])
    let blank = try RedeemGenerateForm(type: .invitation, notes: "  \n ").validated()
    #expect(blank.notes.isEmpty); #expect(!text(try blank.requestBody(batchID: batchID)).contains("notes"))
}

@Test func validatedThrowsAndSpecBasicValidationUnchanged() throws {
    let error = #expect(throws: APIError.self) { _ = try RedeemGenerateForm(type: .balance, amount: nil).validated() }
    #expect(error?.kind == .validation)
    // The spec keeps only its basic checks, so a record saved earlier still encodes when it is retried.
    let saved = RedeemGenerateSpec(type: .balance, value: decimal("10.001"), count: 200, expiresInDays: 9_999)
    #expect(throws: Never.self) { _ = try saved.requestBody(batchID: batchID) }
}

@Test func summaryReceiptForBalance() {
    let receipt = summary(RedeemGenerateSpec(type: .balance, value: 10, count: 20, expiresInDays: 7))
    #expect(receipt.typeLabel == "余额"); #expect(receipt.each == "$10.00"); #expect(receipt.quantity == "× 20")
    #expect(receipt.expiry == "7 天后过期（10/23）"); #expect(receipt.total == "$200.00"); #expect(receipt.totalAmount == 200)
    #expect(receipt.submitTitle == "生成 20 个兑换码"); #expect(receipt.batchLine == "20 个 × $10.00 · 合计 $200.00")
}

@Test func summaryReceiptForOtherTypes() {
    let concurrency = summary(RedeemGenerateSpec(type: .concurrency, value: 2, count: 5))
    #expect(concurrency.each == "+2 并发"); #expect(concurrency.expiry == "永不过期"); #expect(concurrency.total == nil); #expect(concurrency.totalAmount == nil)
    #expect(concurrency.batchLine == "5 个 × +2 并发"); #expect(concurrency.typeLabel == "并发数")
    let subscription = summary(RedeemGenerateSpec(type: .subscription, value: 0, count: 5, groupID: 3, groupName: "企业专线", validityDays: 30))
    #expect(subscription.each == "企业专线 · 30 天"); #expect(subscription.batchLine == "5 个 × 企业专线 · 30 天")
    #expect(summary(RedeemGenerateSpec(type: .subscription, value: 0, count: 5, groupID: 3, validityDays: 30)).each == "分组 #3 · 30 天")
    let invitation = summary(RedeemGenerateSpec(type: .invitation, value: 0, count: 10, expiresInDays: 3))
    #expect(invitation.each == "注册邀请"); #expect(invitation.batchLine == "10 个 × 注册邀请"); #expect(invitation.expiry == "3 天后过期（10/19）")
    let yearEnd = ServerTime.parseTimestamp("2026-12-28T10:00:00+08:00")!
    #expect(summary(RedeemGenerateSpec(type: .invitation, value: 0, count: 1, expiresInDays: 7), now: yearEnd).expiry == "7 天后过期（2027/01/04）")
    // 20:00 UTC is already the next day in Shanghai.
    let evening = ServerTime.parseTimestamp("2026-10-16T20:00:00Z")!
    let week = RedeemGenerateSpec(type: .invitation, value: 0, count: 1, expiresInDays: 7)
    #expect(summary(week, now: evening).expiry == "7 天后过期（10/24）"); #expect(summary(week, now: evening, timeZone: utc).expiry == "7 天后过期（10/23）")
}

@Test func confirmDialogTextsPerType() {
    let balance = summary(RedeemGenerateSpec(type: .balance, value: 10, count: 20, expiresInDays: 7))
    #expect(balance.confirmTitle == "生成 20 个余额兑换码，合计 $200.00？"); #expect(balance.confirmButton == "生成 $200.00"); #expect(balance.isDestructive)
    #expect(balance.confirmMessage(siteName: "主站", faceIDLine: nil) == "站点 主站 · 每个 $10.00\n7 天后过期（10/23）")
    #expect(balance.confirmMessage(siteName: "主站", faceIDLine: "合计超过 $100，确认后验证 Face ID。")
            == "站点 主站 · 每个 $10.00\n7 天后过期（10/23）\n合计超过 $100，确认后验证 Face ID。")
    let concurrency = summary(RedeemGenerateSpec(type: .concurrency, value: 2, count: 5))
    #expect(concurrency.confirmTitle == "生成 5 个并发数兑换码？"); #expect(concurrency.confirmButton == "生成 5 个"); #expect(!concurrency.isDestructive)
    #expect(concurrency.confirmMessage(siteName: "主站", faceIDLine: nil) == "站点 主站 · 每个 +2 并发\n永不过期")
    let subscription = summary(RedeemGenerateSpec(type: .subscription, value: 0, count: 5, groupID: 3, groupName: "企业专线", validityDays: 30))
    #expect(subscription.confirmTitle == "生成 5 个订阅兑换码？"); #expect(subscription.confirmButton == "生成 5 个")
    let invitation = summary(RedeemGenerateSpec(type: .invitation, value: 0, count: 10))
    #expect(invitation.confirmTitle == "生成 10 个邀请码？"); #expect(invitation.confirmButton == "生成 10 个"); #expect(!invitation.isDestructive)
}

@Test func balanceMoneyUsesExactAmountNotRounded() {
    let cents = summary(RedeemGenerateSpec(type: .balance, value: decimal("0.01"), count: 3))
    #expect(cents.each == "$0.01"); #expect(cents.total == "$0.03"); #expect(cents.totalAmount == decimal("0.03"))
    let half = summary(RedeemGenerateSpec(type: .balance, value: decimal("12.5"), count: 100))
    #expect(half.each == "$12.50"); #expect(half.total == "$1,250.00"); #expect(half.confirmButton == "生成 $1,250.00")
}

@Test func generateHintsForTypeTiles() {
    #expect(RedeemCodeType.allCases.map(\.generateHint) == [
        "余额金额（美元），兑换后计入用户余额。", "并发数增量，兑换后提高用户的并发上限。", "兑换后开通或延长所选订阅分组。",
        "邀请码用于限制用户注册，使用后自动标记为已使用。"
    ])
}
