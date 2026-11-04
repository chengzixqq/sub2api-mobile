import Foundation

/// 30 §4.3 拆分 (E10): total_recharged is redeem + admin + grant; affiliate and promo are reported beside it. A missing or
/// malformed source reads 0.
public struct RechargeBreakdown: Decodable, Sendable, Equatable {
    public let redeem: Decimal
    public let admin: Decimal
    public let grant: Decimal
    public let affiliate: Decimal
    public let promo: Decimal
    public init(redeem: Decimal = 0, admin: Decimal = 0, grant: Decimal = 0, affiliate: Decimal = 0, promo: Decimal = 0) {
        self.redeem = redeem; self.admin = admin; self.grant = grant; self.affiliate = affiliate; self.promo = promo
    }
    enum CodingKeys: String, CodingKey { case redeem, admin, grant, affiliate, promo }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func amount(_ key: CodingKeys) -> Decimal { (try? c.optionalDecimal(key)) ?? 0 }
        self.init(redeem: amount(.redeem), admin: amount(.admin), grant: amount(.grant), affiliate: amount(.affiliate), promo: amount(.promo))
    }
}

/// One row of `GET admin/users/:id/balance-history` (30 §4.2, `dto.AdminBalanceHistoryItem`). Only `id` is required; it is
/// negative for an affiliate transfer. The four ledger fields are set on admin adjustments only (before / after are null on
/// migrated rows). The code is worth money: it stays in memory and descriptions never show it (60 §0.4).
public struct BalanceHistoryItem: Identifiable, Decodable, Sendable, Equatable, CustomDebugStringConvertible {
    public let id: Int
    public let code: String
    public let type: String
    public let value: Decimal?
    public let status: String
    public let usedBy: Int?
    public let usedAt: Date?
    public let createdAt: Date?
    public let groupID: Int?
    public let groupName: String?
    public let validityDays: Int
    public let notes: String
    public let batchID: UUID?
    public let createdBy: Int?
    public let adjustmentID: Int?
    public let beforeValue: Decimal?
    public let afterValue: Decimal?
    public let operatorEmail: String?

    public init(id: Int, code: String = "", type: String, value: Decimal?, status: String = "used", usedBy: Int? = nil, usedAt: Date? = nil,
                createdAt: Date? = nil, groupID: Int? = nil, groupName: String? = nil, validityDays: Int = 0, notes: String = "",
                batchID: UUID? = nil, createdBy: Int? = nil, adjustmentID: Int? = nil, beforeValue: Decimal? = nil, afterValue: Decimal? = nil,
                operatorEmail: String? = nil) {
        self.id = id; self.code = code; self.type = type; self.value = value; self.status = status; self.usedBy = usedBy; self.usedAt = usedAt
        self.createdAt = createdAt; self.groupID = groupID; self.groupName = groupName; self.validityDays = validityDays; self.notes = notes
        self.batchID = batchID; self.createdBy = createdBy; self.adjustmentID = adjustmentID; self.beforeValue = beforeValue
        self.afterValue = afterValue; self.operatorEmail = operatorEmail
    }
    public var debugDescription: String { "BalanceHistoryItem(id: \(id), type: \(type), code: <redacted>)" }

    enum CodingKeys: String, CodingKey {
        case id, code, type, value, status, group, notes
        case usedBy = "used_by", usedAt = "used_at", createdAt = "created_at", groupID = "group_id", validityDays = "validity_days"
        case batchID = "batch_id", createdBy = "created_by", adjustmentID = "adjustment_id", beforeValue = "before_value"
        case afterValue = "after_value", operatorEmail = "operator_email"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
        func number(_ key: CodingKeys) -> Int? { try? c.decodeIfPresent(Int.self, forKey: key) }
        func amount(_ key: CodingKeys) -> Decimal? { try? c.optionalDecimal(key) }
        let group = (try? c.decodeIfPresent(LedgerGroupName.self, forKey: .group))?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(id: try c.decode(Int.self, forKey: .id), code: text(.code) ?? "", type: text(.type) ?? "", value: amount(.value),
                  status: text(.status) ?? "", usedBy: number(.usedBy), usedAt: try? c.optionalTimestamp(.usedAt),
                  createdAt: try? c.optionalTimestamp(.createdAt), groupID: number(.groupID), groupName: group?.isEmpty == false ? group : nil,
                  validityDays: number(.validityDays) ?? 0, notes: text(.notes) ?? "", batchID: text(.batchID).flatMap(UUID.init(uuidString:)),
                  createdBy: number(.createdBy), adjustmentID: number(.adjustmentID), beforeValue: amount(.beforeValue),
                  afterValue: amount(.afterValue), operatorEmail: text(.operatorEmail))
    }
}

/// `group` of a row; only the name is shown.
private struct LedgerGroupName: Decodable { let name: String? }

/// The balance-history reply: the page counters checked as `Page` checks them, plus the totals of 30 §4.3.
public struct BalanceHistoryPage: Decodable, Sendable, Equatable {
    public let items: [BalanceHistoryItem]
    public let total: Int
    public let page: Int
    public let pageSize: Int
    /// At least 1, as the server writes it.
    public let pages: Int
    public let totalRecharged: Decimal?
    /// nil without `users.balance_ledger` or when the server could not split it.
    public let breakdown: RechargeBreakdown?
    public var hasMore: Bool { page < pages }

    public init(items: [BalanceHistoryItem], total: Int, page: Int, pageSize: Int, pages: Int, totalRecharged: Decimal?, breakdown: RechargeBreakdown?) {
        self.items = items; self.total = total; self.page = page; self.pageSize = pageSize; self.pages = pages
        self.totalRecharged = totalRecharged; self.breakdown = breakdown
    }
    private enum TotalKeys: String, CodingKey { case totalRecharged = "total_recharged", breakdown = "total_recharged_breakdown" }
    public init(from decoder: any Decoder) throws {
        let base = try Page<BalanceHistoryItem>(from: decoder)
        let c = try decoder.container(keyedBy: TotalKeys.self)
        self.init(items: base.items, total: base.total ?? base.items.count, page: base.page, pageSize: base.pageSize,
                  pages: max(base.pages ?? base.page, 1), totalRecharged: try? c.optionalDecimal(.totalRecharged),
                  breakdown: try? c.decodeIfPresent(RechargeBreakdown.self, forKey: .breakdown))
    }
}

/// 30 §4.6: the pages read so far. A later page adds only ids not shown yet (a record written meanwhile shifts the pages)
/// and brings the latest totals; a pull starts again from `init(firstPage:)`, which drops the later pages.
public struct BalanceHistoryFeed: Sendable, Equatable {
    public let items: [BalanceHistoryItem]
    public let total: Int
    public let totalRecharged: Decimal?
    public let breakdown: RechargeBreakdown?
    public let page: Int
    public let pages: Int
    public var hasMore: Bool { page < pages }
    public var nextPage: Int { page + 1 }

    public init(firstPage: BalanceHistoryPage) { self.init(items: Self.unseen(firstPage.items, after: []), latest: firstPage) }
    public func appending(_ next: BalanceHistoryPage) -> BalanceHistoryFeed {
        BalanceHistoryFeed(items: items + Self.unseen(next.items, after: items), latest: next)
    }
    private init(items: [BalanceHistoryItem], latest: BalanceHistoryPage) {
        self.items = items; total = latest.total; totalRecharged = latest.totalRecharged; breakdown = latest.breakdown
        page = latest.page; pages = latest.pages
    }
    private static func unseen(_ rows: [BalanceHistoryItem], after shown: [BalanceHistoryItem]) -> [BalanceHistoryItem] {
        var seen = Set(shown.map(\.id))
        return rows.filter { seen.insert($0.id).inserted }
    }
}

/// 30 §4.3 wording of the records and their header; the time is the server's (00 §6.3).
public enum UserLedger {
    private static let moneyTypes: Set<String> = ["balance", "affiliate_balance", "admin_balance"]
    private static let concurrencyTypes: Set<String> = ["concurrency", "admin_concurrency"]
    /// Redeemed by the user, so the code means something to them (as Web); adjustments and affiliate transfers have internal codes.
    private static let redeemedTypes: Set<String> = ["balance", "concurrency", "subscription"]

    /// Web's getItemTitle; a missing value counts as an increase, as there.
    public static func title(for item: BalanceHistoryItem) -> String {
        let decrease = (item.value ?? 0) < 0
        switch item.type {
        case "balance": return "余额充值（兑换）"
        case "affiliate_balance": return "余额充值（返利转入）"
        case "admin_balance": return decrease ? "余额扣除（管理员）" : "余额充值（管理员）"
        case "concurrency": return "并发增加（兑换）"
        case "admin_concurrency": return decrease ? "并发减少（管理员）" : "并发增加（管理员）"
        case "subscription": return "订阅已分配"
        default: return "其他记录"
        }
    }
    /// Signed, never coloured; a value rounding to zero has no sign (00 §6.1). Other types have no value to show.
    public static func valueText(for item: BalanceHistoryItem) -> String {
        if item.type == "subscription" { return subscriptionText(item) }
        guard let value = item.value else { return DisplayFormat.missing }
        if moneyTypes.contains(item.type) { return plus(value, digits: 2) + DisplayFormat.money(value) }
        guard concurrencyTypes.contains(item.type) else { return DisplayFormat.missing }
        return plus(value, digits: 0) + count(value) + " 并发"
    }
    /// The whole code, for “复制兑换码”; nil where no code is shown.
    public static func copyableCode(for item: BalanceHistoryItem) -> String? {
        redeemedTypes.contains(item.type) && !item.code.isEmpty ? item.code : nil
    }
    /// The first 8 characters and "..." (design ledgerCode).
    public static func codePrefix(for item: BalanceHistoryItem) -> String? { copyableCode(for: item).map { String($0.prefix(8)) + "..." } }
    public static func codeSpoken(for item: BalanceHistoryItem) -> String? { copyableCode(for: item).map { "兑换码 \($0.prefix(8)) 开头" } }
    /// used_at, else created_at, then the note on one line.
    public static func secondLine(for item: BalanceHistoryItem, timeZone: ServerTimeZone, now: Date) -> String {
        [time(item, timeZone: timeZone, now: now), note(item)].compactMap { $0 }.joined(separator: " · ")
    }
    /// The full list's third line (U31): an admin adjustment with its before, after and operator; any of them missing hides it.
    public static func thirdLine(for item: BalanceHistoryItem, ledgerAvailable: Bool) -> String? {
        guard ledgerAvailable, let before = item.beforeValue, let after = item.afterValue,
              let operatorEmail = item.operatorEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !operatorEmail.isEmpty else { return nil }
        switch item.type {
        case "admin_balance": return "余额 \(DisplayFormat.money(before)) → \(DisplayFormat.money(after)) · \(operatorEmail)"
        case "admin_concurrency": return "并发 \(count(before)) → \(count(after)) · \(operatorEmail)"
        default: return nil
        }
    }
    /// The row as VoiceOver reads it, in display order; a missing value or time reads as “无数据”.
    public static func spokenLabel(for item: BalanceHistoryItem, timeZone: ServerTimeZone, now: Date, adjustmentLine: String?) -> String {
        let when = [DisplayFormat.spoken(time(item, timeZone: timeZone, now: now)), note(item)].compactMap { $0 }.joined(separator: " · ")
        return [title(for: item), DisplayFormat.spoken(valueText(for: item)), when, codeSpoken(for: item), adjustmentLine]
            .compactMap { $0 }.joined(separator: "，")
    }
    /// The small print under the header: the counted sources, then affiliate and promo; sources rounding to zero are left out.
    public static func breakdownLines(_ breakdown: RechargeBreakdown?, ledgerAvailable: Bool) -> [String] {
        guard ledgerAvailable, let breakdown else { return [] }
        let counted = sources([("兑换", breakdown.redeem), ("管理员", breakdown.admin), ("站点赠送", breakdown.grant)]) { $0 != 0 }
        let beside = sources([("返利转入", breakdown.affiliate), ("优惠码", breakdown.promo)]) { $0 > 0 }
        return (counted.isEmpty ? [] : [counted.joined(separator: " · ")])
            + (beside.isEmpty ? [] : ["另有\(beside.joined(separator: "、"))，不计入总充值"])
    }
    public static func countText(_ total: Int) -> String { DisplayFormat.grouped(total) + " 条" }
    public static func rechargedText(_ totalRecharged: Decimal?) -> String { "总充值 " + DisplayFormat.money(totalRecharged) }
    /// 00 §4.6 beside “刷新失败 · 重试”: when the rows shown were read.
    public static func updatedText(_ date: Date?, timeZone: ServerTimeZone) -> String {
        "更新于 " + DisplayFormat.clock(date, timeZone: timeZone.timeZone)
    }

    private static func time(_ item: BalanceHistoryItem, timeZone: ServerTimeZone, now: Date) -> String {
        DisplayFormat.monthDayClock(item.usedAt ?? item.createdAt, timeZone: timeZone, now: now)
    }
    /// One line: surrounding blanks dropped, inner runs of blanks and line breaks become one space.
    private static func note(_ item: BalanceHistoryItem) -> String? {
        let text = item.notes.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : text
    }
    private static func subscriptionText(_ item: BalanceHistoryItem) -> String {
        let days: Int? = item.validityDays > 0 ? item.validityDays : item.value.map { NSDecimalNumber(decimal: DisplayFormat.rounded($0, digits: 0)).intValue }
        let parts = [item.groupName, days.map { "\($0) 天" }].compactMap { $0 }
        return parts.isEmpty ? DisplayFormat.missing : parts.joined(separator: " · ")
    }
    private static func plus(_ value: Decimal, digits: Int) -> String { DisplayFormat.rounded(value, digits: digits) > 0 ? "+" : "" }
    private static func count(_ value: Decimal) -> String { DisplayFormat.number(value, minFraction: 0, maxFraction: 0) }
    private static func sources(_ pairs: [(name: String, amount: Decimal)], keep: (Decimal) -> Bool) -> [String] {
        pairs.filter { keep(DisplayFormat.rounded($0.amount, digits: 2)) }.map { "\($0.name) \(DisplayFormat.money($0.amount))" }
    }
}

extension APIError {
    /// 404 USER_NOT_FOUND from a user read: the user is gone. 401 with the same reason is the session's (00 §1.7).
    public var isUserNotFound: Bool { statusCode == 404 && reason == "USER_NOT_FOUND" }
}

extension APIClient {
    /// 30 §4.2: newest first. Only page and page_size go out; neither the full list nor the detail filters by type.
    public func balanceHistory(userID: Int, page: Int, pageSize: Int = PageSize.standard) async throws -> BalanceHistoryPage {
        try await request("admin/users/\(validID(userID))/balance-history", query: pagination(page, pageSize: pageSize, search: "", status: nil))
    }
}
