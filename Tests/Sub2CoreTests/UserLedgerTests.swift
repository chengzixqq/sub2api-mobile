import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let ledgerZone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let ledgerNow = ServerTime.parseTimestamp("2026-10-27T04:00:00Z")!
private func ledgerAmount(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func decodeLedgerPage(_ json: String) throws -> BalanceHistoryPage {
    try JSONDecoder().decode(BalanceHistoryPage.self, from: Data(json.utf8))
}
private func ledgerItem(_ type: String, _ value: String?, id: Int = 1, code: String = "", usedAt: String? = nil, createdAt: String? = nil,
                        notes: String = "", groupName: String? = nil, validityDays: Int = 0, before: String? = nil, after: String? = nil,
                        operatorEmail: String? = nil) -> BalanceHistoryItem {
    BalanceHistoryItem(id: id, code: code, type: type, value: value.map(ledgerAmount), usedAt: ServerTime.parseTimestamp(usedAt),
                       createdAt: ServerTime.parseTimestamp(createdAt), groupName: groupName, validityDays: validityDays, notes: notes,
                       beforeValue: before.map(ledgerAmount), afterValue: after.map(ledgerAmount), operatorEmail: operatorEmail)
}
private func ledgerPage(_ ids: [Int], page: Int, pages: Int, total: Int = 3, recharged: Decimal? = 70,
                        breakdown: RechargeBreakdown? = RechargeBreakdown(redeem: 40, admin: 30)) -> BalanceHistoryPage {
    BalanceHistoryPage(items: ids.map { ledgerItem("balance", "1", id: $0) }, total: total, page: page, pageSize: 20, pages: pages,
                       totalRecharged: recharged, breakdown: breakdown)
}

private let backendLedgerJSON = #"""
{"items":[
 {"id":124,"code":"e81c6a0f5d2b4c3a9e7f1a2b3c4d5e6f","type":"balance","value":10,"status":"used","used_by":1,
  "used_at":"2026-10-16T09:20:00.123456+08:00","created_at":"2026-10-01T00:00:00Z","group_id":null,"validity_days":0,
  "notes":"社群活动 · 第 3 批","adjustment_id":null,"before_value":null,"after_value":null,"operator_email":null},
 {"id":122,"code":"ADJ-9002","type":"admin_balance","value":-5,"status":"used","used_by":1,"used_at":"2026-10-08T01:15:00Z",
  "created_at":"2026-10-08T01:15:00Z","group_id":null,"validity_days":0,"notes":"退回未用额度","batch_id":"5B0D9A41-7C21-4E5B-9C0A-1F2E3D4C5B6A",
  "created_by":7,"adjustment_id":9001,"before_value":"32.40000000","after_value":"27.40000000","operator_email":"ops@example.com"},
 {"id":-7,"code":"AFF-7","type":"affiliate_balance","value":5,"status":"used","used_by":1,"used_at":"2026-10-07T12:30:00Z",
  "created_at":"2026-10-07T12:30:00Z","group_id":null,"validity_days":0,"notes":"","adjustment_id":null,"before_value":null,
  "after_value":null,"operator_email":null},
 {"id":118,"code":"4e7c0b95aa11bb22cc33dd44ee55ff66","type":"subscription","value":30,"status":"used","used_by":1,
  "used_at":"2026-10-03T05:12:00Z","created_at":"2026-10-01T00:00:00Z","group_id":4,"validity_days":30,
  "group":{"id":4,"name":"企业专线","platform":"openai"},"notes":"","adjustment_id":null,"before_value":null,"after_value":null,
  "operator_email":null}
],"total":24,"page":1,"page_size":20,"pages":2,"total_recharged":70,
 "total_recharged_breakdown":{"redeem":40,"admin":20,"grant":10,"affiliate":5,"promo":0}}
"""#

@Test func balanceHistoryPageDecodesBackendShape() throws {
    let page = try decodeLedgerPage(backendLedgerJSON)
    #expect(page.items.map(\.id) == [124, 122, -7, 118])
    let redeemed = page.items[0], adjusted = page.items[1], affiliate = page.items[2], subscription = page.items[3]
    #expect(redeemed.value == 10 && redeemed.code == "e81c6a0f5d2b4c3a9e7f1a2b3c4d5e6f" && redeemed.notes == "社群活动 · 第 3 批")
    #expect(redeemed.usedAt == ServerTime.parseTimestamp("2026-10-16T01:20:00.123Z") && redeemed.status == "used" && redeemed.usedBy == 1)
    #expect(redeemed.adjustmentID == nil && redeemed.beforeValue == nil && redeemed.afterValue == nil && redeemed.operatorEmail == nil)
    #expect(adjusted.value == -5 && adjusted.beforeValue == ledgerAmount("32.4") && adjusted.afterValue == ledgerAmount("27.4"))
    #expect(adjusted.adjustmentID == 9001 && adjusted.operatorEmail == "ops@example.com" && adjusted.createdBy == 7)
    #expect(adjusted.batchID == UUID(uuidString: "5B0D9A41-7C21-4E5B-9C0A-1F2E3D4C5B6A"))
    #expect(affiliate.id == -7 && affiliate.code == "AFF-7" && affiliate.notes.isEmpty)
    #expect(subscription.groupID == 4 && subscription.groupName == "企业专线" && subscription.validityDays == 30)
    #expect(page.total == 24 && page.page == 1 && page.pageSize == 20 && page.pages == 2 && page.hasMore)
    #expect(page.totalRecharged == 70)
    #expect(page.breakdown == RechargeBreakdown(redeem: 40, admin: 20, grant: 10, affiliate: 5))
}

@Test func balanceHistoryPageTreatsMissingAndMalformedFieldsAsAbsent() throws {
    let old = try decodeLedgerPage(#"""
    {"items":[{"id":3,"code":"abc","type":"balance","value":2,"used_at":"2026-10-01T00:00:00Z"}],"total":1,"page":1,"page_size":20,
     "pages":1,"total_recharged":2}
    """#)
    let item = try #require(old.items.first)
    #expect(old.breakdown == nil && old.totalRecharged == 2 && !old.hasMore)
    #expect(item.adjustmentID == nil && item.beforeValue == nil && item.afterValue == nil && item.operatorEmail == nil)
    #expect(item.groupName == nil && item.notes.isEmpty && item.validityDays == 0 && item.status.isEmpty && item.createdAt == nil)
    let broken = try decodeLedgerPage(#"""
    {"items":[{"id":4,"type":"admin_balance","value":"x","before_value":"abc","after_value":12,"used_at":"not-a-date",
     "group":{"id":1,"name":"  "},"notes":7,"validity_days":"3","operator_email":"ops@example.com"}],"total":1,"page":1,"page_size":20,
     "total_recharged":"abc","total_recharged_breakdown":null}
    """#)
    let bad = try #require(broken.items.first)
    #expect(bad.value == nil && bad.beforeValue == nil && bad.afterValue == 12 && bad.usedAt == nil)
    #expect(bad.groupName == nil && bad.notes.isEmpty && bad.validityDays == 0 && bad.code.isEmpty && bad.operatorEmail == "ops@example.com")
    #expect(broken.totalRecharged == nil && broken.breakdown == nil)
    let partial = try decodeLedgerPage(#"{"items":[],"total":0,"page":1,"page_size":20,"total_recharged_breakdown":{"redeem":"5.5","admin":null}}"#)
    #expect(partial.breakdown == RechargeBreakdown(redeem: ledgerAmount("5.5")))
}

@Test func balanceHistoryPageRejectsBrokenCountersAndDerivesPages() throws {
    for json in [#"{"items":[],"total":1,"page":0,"page_size":20}"#, #"{"items":[],"total":1,"page":1,"page_size":0}"#,
                 #"{"items":[],"total":-1,"page":1,"page_size":20}"#, #"{"total":1,"page":1,"page_size":20}"#] {
        #expect(throws: (any Error).self, "\(json)") { try decodeLedgerPage(json) }
    }
    let derived = try decodeLedgerPage(#"{"items":[],"total":21,"page":1,"page_size":20}"#)
    #expect(derived.pages == 2 && derived.hasMore)
    let bare = try decodeLedgerPage(#"{"items":[{"id":1},{"id":2}],"page":3,"page_size":20}"#)
    #expect(bare.total == 2 && bare.pages == 3 && !bare.hasMore)
    let empty = try decodeLedgerPage(#"{"items":[],"total":0,"page":1,"page_size":20,"pages":0}"#)
    #expect(empty.pages == 1 && !empty.hasMore)
    let last = try decodeLedgerPage(#"{"items":[],"total":40,"page":2,"page_size":20,"pages":2}"#)
    #expect(!last.hasMore)
}

@Test func titleFollowsWebForEveryType() {
    let cases: [(String, String?, String)] = [
        ("balance", "10", "余额充值（兑换）"), ("affiliate_balance", "5", "余额充值（返利转入）"),
        ("admin_balance", "20", "余额充值（管理员）"), ("admin_balance", "0", "余额充值（管理员）"), ("admin_balance", nil, "余额充值（管理员）"),
        ("admin_balance", "-5", "余额扣除（管理员）"), ("concurrency", "2", "并发增加（兑换）"),
        ("admin_concurrency", "2", "并发增加（管理员）"), ("admin_concurrency", "0", "并发增加（管理员）"),
        ("admin_concurrency", "-1", "并发减少（管理员）"), ("subscription", "30", "订阅已分配"),
        ("invitation", "0", "其他记录"), ("", "1", "其他记录"), ("unknown", "1", "其他记录")
    ]
    for (type, value, expected) in cases { #expect(UserLedger.title(for: ledgerItem(type, value)) == expected, "\(type) \(value ?? "nil")") }
}

@Test func valueTextSignsMoneyAndConcurrencyAndNamesSubscriptionDays() {
    let cases: [(BalanceHistoryItem, String)] = [
        (ledgerItem("balance", "10"), "+$10.00"), (ledgerItem("admin_balance", "-5"), "\u{2212}$5.00"),
        (ledgerItem("affiliate_balance", "1234.5"), "+$1,234.50"), (ledgerItem("admin_balance", "0"), "$0.00"),
        (ledgerItem("admin_balance", "0.004"), "$0.00"), (ledgerItem("admin_balance", "-0.004"), "$0.00"),
        (ledgerItem("balance", "0.005"), "+$0.01"), (ledgerItem("balance", nil), "—"),
        (ledgerItem("concurrency", "2"), "+2 并发"), (ledgerItem("admin_concurrency", "-1"), "\u{2212}1 并发"),
        (ledgerItem("admin_concurrency", "0"), "0 并发"), (ledgerItem("concurrency", "1500"), "+1,500 并发"),
        (ledgerItem("concurrency", nil), "—"),
        (ledgerItem("subscription", "30", groupName: "企业专线", validityDays: 30), "企业专线 · 30 天"),
        (ledgerItem("subscription", "7.6"), "8 天"), (ledgerItem("subscription", nil, groupName: "企业专线"), "企业专线"),
        (ledgerItem("subscription", nil), "—"), (ledgerItem("invitation", "0"), "—")
    ]
    for (item, expected) in cases { #expect(UserLedger.valueText(for: item) == expected, "\(item.type) \(String(describing: item.value))") }
}

@Test func codePrefixCopyAndSpokenOnlyForRedeemedTypes() {
    let code = "3f9a2c1b77d0e4a5b6c7d8e9f0a1b2c3"
    for type in ["balance", "concurrency", "subscription"] {
        let item = ledgerItem(type, "1", code: code)
        #expect(UserLedger.codePrefix(for: item) == "3f9a2c1b...", "\(type)")
        #expect(UserLedger.copyableCode(for: item) == code && UserLedger.codeSpoken(for: item) == "兑换码 3f9a2c1b 开头", "\(type)")
    }
    for type in ["admin_balance", "admin_concurrency", "affiliate_balance", "invitation"] {
        let item = ledgerItem(type, "1", code: type == "affiliate_balance" ? "AFF-7" : code)
        #expect(UserLedger.codePrefix(for: item) == nil && UserLedger.copyableCode(for: item) == nil && UserLedger.codeSpoken(for: item) == nil, "\(type)")
    }
    #expect(UserLedger.codePrefix(for: ledgerItem("balance", "1")) == nil && UserLedger.copyableCode(for: ledgerItem("balance", "1")) == nil)
    #expect(UserLedger.codePrefix(for: ledgerItem("balance", "1", code: "abc")) == "abc...")
    #expect(UserLedger.codePrefix(for: ledgerItem("balance", "1", code: "兑换码一二三四五六七")) == "兑换码一二三四五...")
}

@Test func secondLineUsesUsedAtThenCreatedAtInServerTimeZone() throws {
    let both = ledgerItem("balance", "1", usedAt: "2026-10-15T16:30:00Z", createdAt: "2026-10-01T00:00:00Z")
    #expect(UserLedger.secondLine(for: both, timeZone: ledgerZone, now: ledgerNow) == "10/16 00:30")
    let york = try #require(ServerTimeZone(identifier: "America/New_York", utcOffset: nil))
    #expect(UserLedger.secondLine(for: both, timeZone: york, now: ledgerNow) == "10/15 12:30")
    let created = ledgerItem("balance", "1", createdAt: "2026-09-05T00:07:00Z")
    #expect(UserLedger.secondLine(for: created, timeZone: ledgerZone, now: ledgerNow) == "09/05 08:07")
    let noted = ledgerItem("balance", "1", usedAt: "2026-10-16T01:20:00Z", notes: "  社群活动\n第 3 批 ")
    #expect(UserLedger.secondLine(for: noted, timeZone: ledgerZone, now: ledgerNow) == "10/16 09:20 · 社群活动 第 3 批")
    let lastYear = ledgerItem("balance", "1", usedAt: "2025-10-16T01:20:00Z")
    #expect(UserLedger.secondLine(for: lastYear, timeZone: ledgerZone, now: ledgerNow) == "2025/10/16 09:20")
    #expect(UserLedger.secondLine(for: ledgerItem("balance", "1"), timeZone: ledgerZone, now: ledgerNow) == "—")
    #expect(UserLedger.secondLine(for: ledgerItem("balance", "1", notes: "补发"), timeZone: ledgerZone, now: ledgerNow) == "— · 补发")
}

@Test func thirdLineNeedsAdminRowLedgerCapabilityAndAllThreeFields() {
    let balance = ledgerItem("admin_balance", "20", before: "12.40000000", after: "32.40000000", operatorEmail: "ops@example.com")
    #expect(UserLedger.thirdLine(for: balance, ledgerAvailable: true) == "余额 $12.40 → $32.40 · ops@example.com")
    let concurrency = ledgerItem("admin_concurrency", "2", before: "5.00000000", after: "7.00000000", operatorEmail: "ops@example.com")
    #expect(UserLedger.thirdLine(for: concurrency, ledgerAvailable: true) == "并发 5 → 7 · ops@example.com")
    let missing = [
        ledgerItem("admin_balance", "-3", operatorEmail: "ops@example.com"),
        ledgerItem("admin_balance", "10", before: "0", after: "10"),
        ledgerItem("admin_balance", "10", before: "0", after: "10", operatorEmail: "  "),
        ledgerItem("admin_concurrency", "1", before: "5", operatorEmail: "ops@example.com"),
        ledgerItem("balance", "10", before: "0", after: "10", operatorEmail: "ops@example.com")
    ]
    for item in missing { #expect(UserLedger.thirdLine(for: item, ledgerAvailable: true) == nil, "\(item.type)") }
    #expect(UserLedger.thirdLine(for: balance, ledgerAvailable: false) == nil)
}

@Test func breakdownLinesOmitZeroSourcesAndNoteAffiliatePromo() {
    #expect(UserLedger.breakdownLines(RechargeBreakdown(redeem: 40, admin: 20), ledgerAvailable: true) == ["兑换 $40.00 · 管理员 $20.00"])
    #expect(UserLedger.breakdownLines(RechargeBreakdown(redeem: 40, admin: 20, grant: 10, affiliate: 5), ledgerAvailable: true)
            == ["兑换 $40.00 · 管理员 $20.00 · 站点赠送 $10.00", "另有返利转入 $5.00，不计入总充值"])
    #expect(UserLedger.breakdownLines(RechargeBreakdown(affiliate: 5, promo: 3), ledgerAvailable: true) == ["另有返利转入 $5.00、优惠码 $3.00，不计入总充值"])
    let tiny = ledgerAmount("0.004")
    #expect(UserLedger.breakdownLines(RechargeBreakdown(redeem: tiny, admin: tiny, grant: tiny, affiliate: tiny, promo: tiny), ledgerAvailable: true).isEmpty)
    #expect(UserLedger.breakdownLines(RechargeBreakdown(), ledgerAvailable: true).isEmpty)
    #expect(UserLedger.breakdownLines(nil, ledgerAvailable: true).isEmpty)
    #expect(UserLedger.breakdownLines(RechargeBreakdown(redeem: 40), ledgerAvailable: false).isEmpty)
}

@Test func headerTextsCountRechargedAndUpdatedAt() {
    #expect(UserLedger.countText(24) == "24 条" && UserLedger.countText(1234) == "1,234 条" && UserLedger.countText(0) == "0 条")
    #expect(UserLedger.rechargedText(70) == "总充值 $70.00" && UserLedger.rechargedText(nil) == "总充值 —")
    #expect(UserLedger.updatedText(ServerTime.parseTimestamp("2026-10-16T01:41:00Z"), timeZone: ledgerZone) == "更新于 09:41")
    #expect(UserLedger.updatedText(nil, timeZone: ledgerZone) == "更新于 —")
}

@Test func spokenLabelReadsRowInOrderAndMissingAsNoData() {
    let redeemed = ledgerItem("balance", "10", code: "e81c6a0f5d2b4c3a", usedAt: "2026-10-16T01:20:00Z", notes: "社群活动 · 第 3 批")
    #expect(UserLedger.spokenLabel(for: redeemed, timeZone: ledgerZone, now: ledgerNow, adjustmentLine: nil)
            == "余额充值（兑换），+$10.00，10/16 09:20 · 社群活动 · 第 3 批，兑换码 e81c6a0f 开头")
    let adjusted = ledgerItem("admin_balance", "20", usedAt: "2026-10-12T06:02:00Z")
    #expect(UserLedger.spokenLabel(for: adjusted, timeZone: ledgerZone, now: ledgerNow, adjustmentLine: "余额 $12.40 → $32.40 · ops@example.com")
            == "余额充值（管理员），+$20.00，10/12 14:02，余额 $12.40 → $32.40 · ops@example.com")
    let other = ledgerItem("invitation", "0", code: "INVITE-2026", usedAt: "2026-10-01T09:00:00Z")
    #expect(UserLedger.spokenLabel(for: other, timeZone: ledgerZone, now: ledgerNow, adjustmentLine: nil) == "其他记录，无数据，10/01 17:00")
    let undated = ledgerItem("balance", "2", notes: "补发")
    #expect(UserLedger.spokenLabel(for: undated, timeZone: ledgerZone, now: ledgerNow, adjustmentLine: nil) == "余额充值（兑换），+$2.00，无数据 · 补发")
}

@Test func feedAppendsNextPageByIDAndRefreshStartsOver() {
    let first = BalanceHistoryFeed(firstPage: ledgerPage([124, 123, -7, 123], page: 1, pages: 2))
    #expect(first.items.map(\.id) == [124, 123, -7] && first.hasMore && first.nextPage == 2)
    let second = ledgerPage([-7, 102], page: 2, pages: 2, total: 4, recharged: 80, breakdown: RechargeBreakdown(redeem: 50, admin: 30))
    let merged = first.appending(second)
    #expect(merged.items.map(\.id) == [124, 123, -7, 102] && !merged.hasMore && merged.page == 2 && merged.pages == 2)
    #expect(merged.total == 4 && merged.totalRecharged == 80 && merged.breakdown == RechargeBreakdown(redeem: 50, admin: 30))
    #expect(first.items.map(\.id) == [124, 123, -7] && first.page == 1 && first.total == 3)
    let refreshed = BalanceHistoryFeed(firstPage: ledgerPage([125, 124], page: 1, pages: 2))
    #expect(refreshed.items.map(\.id) == [125, 124] && refreshed.page == 1)
    let emptyNext = first.appending(ledgerPage([], page: 2, pages: 3))
    #expect(emptyNext.items.map(\.id) == [124, 123, -7] && emptyNext.page == 2 && emptyNext.nextPage == 3 && emptyNext.hasMore)
}

@Test func balanceHistorySendsOnlyPageAndPageSize() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"items":[{"id":5,"type":"balance","value":1}],"total":21,"page":2,"page_size":20,"pages":2}"#) }
    let client = APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate)
    let page = try await client.balanceHistory(userID: 42, page: 2)
    #expect(page.items.map(\.id) == [5] && page.page == 2)
    _ = try await client.balanceHistory(userID: 42, page: 1, pageSize: 5)
    let sent = await transport.requests
    #expect(sent.count == 2 && sent.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    #expect(sent.allSatisfy { $0.url?.path == "/api/v1/admin/users/42/balance-history" })
    let first = sent.first.flatMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    #expect(first == [URLQueryItem(name: "page", value: "2"), URLQueryItem(name: "page_size", value: "20")])
    let second = sent.last.flatMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    #expect(second == [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "page_size", value: "5")])
    #expect(await thrownAPIError { _ = try await client.balanceHistory(userID: 0, page: 1) }?.kind == .validation)
    #expect(await thrownAPIError { _ = try await client.balanceHistory(userID: 42, page: 0) }?.kind == .validation)
    #expect(await transport.requests.count == 2)
}

@Test func balanceHistoryUserNotFoundIsRecognised() async {
    let transport = ScriptedTransport { _ in errorReply(404, reason: "USER_NOT_FOUND") }
    let client = APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate)
    let error = await thrownAPIError { _ = try await client.balanceHistory(userID: 9, page: 1) }
    #expect(error?.isUserNotFound == true)
    #expect(await transport.requests.count == 1)
    #expect(!APIError.server(status: 401, reason: "USER_NOT_FOUND").isUserNotFound)
    #expect(!APIError.server(status: 404, reason: "GROUP_NOT_FOUND").isUserNotFound)
    #expect(!APIError.server(status: 404, reason: nil).isUserNotFound)
}

@Test func balanceHistoryItemDescriptionsRedactCode() throws {
    let code = "e81c6a0f5d2b4c3a9e7f1a2b3c4d5e6f"
    let item = ledgerItem("balance", "10", id: 124, code: code)
    let page = BalanceHistoryPage(items: [item], total: 1, page: 1, pageSize: 20, pages: 1, totalRecharged: 10, breakdown: nil)
    for text in [String(describing: item), String(reflecting: item), String(describing: page), String(reflecting: page),
                 String(describing: BalanceHistoryFeed(firstPage: page))] {
        #expect(!text.contains(code) && !text.contains("e81c6a0f5d"), "\(text)")
    }
    #expect(item.debugDescription.contains("<redacted>") && item.debugDescription.contains("124"))
}
