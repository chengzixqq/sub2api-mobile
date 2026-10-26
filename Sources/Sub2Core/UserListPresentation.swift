import Foundation

/// 30 §1.3 右列第二行. `hidden` is the search results' row (S6-21); `unavailable` is “今日 —” before the reply, after a failed
/// batch, for an entry the reply garbled and always for a read-only token (R14); an id the reply left out is `$0.00`.
public enum UserTodayCell: Sendable, Equatable {
    case hidden, unavailable, amount(Decimal)

    public var text: String? {
        switch self {
        case .hidden: nil
        case .unavailable: "今日 " + DisplayFormat.missing
        case .amount(let value): "今日 " + DisplayFormat.money(value)
        }
    }
    public var spokenText: String? {
        switch self {
        case .hidden: nil
        case .unavailable: "今日" + DisplayFormat.missingSpoken
        case .amount: text
        }
    }
}

/// The loaded pages of one query (30 §1.4, §1.6): a refresh replaces only the first page's rows, later pages stay until the
/// query changes; every change returns a new value.
public struct UserListSnapshot: Sendable, Equatable {
    public let rows: [AdminUser]
    public let total: Int?
    /// The last page read.
    public let page: Int
    public let pages: Int?
    /// How many of `rows` came from the first page.
    public let firstPageCount: Int
    private let lastPageHasMore: Bool

    public var hasMore: Bool { pages.map { page < $0 } ?? lastPageHasMore }

    public init(firstPage: Page<AdminUser>) {
        let rows = Self.unique(firstPage.items)
        self.init(rows: rows, total: firstPage.total, page: 1, pages: firstPage.pages, firstPageCount: rows.count,
                  lastPageHasMore: firstPage.hasMore)
    }
    private init(rows: [AdminUser], total: Int?, page: Int, pages: Int?, firstPageCount: Int, lastPageHasMore: Bool) {
        self.rows = rows; self.total = total; self.page = page; self.pages = pages
        self.firstPageCount = firstPageCount; self.lastPageHasMore = lastPageHasMore
    }

    /// The new first page, then the later pages without the ids it now holds; total and pages are the new ones.
    public func mergingFirstPage(_ first: Page<AdminUser>) -> UserListSnapshot {
        let fresh = UserListSnapshot(firstPage: first)
        guard page > 1, !fresh.rows.isEmpty else { return fresh }
        let ids = Set(fresh.rows.map(\.id))
        let later = rows.dropFirst(firstPageCount).filter { !ids.contains($0.id) }
        return UserListSnapshot(rows: fresh.rows + later, total: first.total, page: page, pages: first.pages,
                                firstPageCount: fresh.rows.count, lastPageHasMore: lastPageHasMore)
    }
    public func appending(_ next: Page<AdminUser>) -> UserListSnapshot {
        let ids = Set(rows.map(\.id))
        return UserListSnapshot(rows: rows + Self.unique(next.items).filter { !ids.contains($0.id) }, total: next.total ?? total,
                                page: next.page, pages: next.pages ?? pages, firstPageCount: firstPageCount, lastPageHasMore: next.hasMore)
    }
    /// Only a row already shown is replaced; nothing is inserted.
    public func replacing(_ user: AdminUser) -> UserListSnapshot {
        changing(rows.map { $0.id == user.id ? user : $0 })
    }
    public func updatingBalance(id: Int, balance: Decimal) -> UserListSnapshot {
        changing(rows.map { row in
            guard row.id == id else { return row }
            var copy = row
            copy.balance = balance
            return copy
        })
    }
    public func removing(id: Int) -> UserListSnapshot {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return self }
        var remaining = rows
        remaining.remove(at: index)
        return UserListSnapshot(rows: remaining, total: total.map { max($0 - 1, 0) }, page: page, pages: pages,
                                firstPageCount: index < firstPageCount ? firstPageCount - 1 : firstPageCount, lastPageHasMore: lastPageHasMore)
    }

    private func changing(_ rows: [AdminUser]) -> UserListSnapshot {
        UserListSnapshot(rows: rows, total: total, page: page, pages: pages, firstPageCount: firstPageCount, lastPageHasMore: lastPageHasMore)
    }
    private static func unique(_ users: [AdminUser]) -> [AdminUser] {
        var seen = Set<Int>()
        return users.filter { seen.insert($0.id).inserted }
    }
}

/// 30 §1.5: 403 FORBIDDEN has its own page; every other failure shows the catalog text, never the server message.
public enum UserListFailure: Sendable, Equatable {
    case forbidden
    case failed(reason: String?)

    public init(_ error: any Error) {
        if let failure = error as? APIError, failure.statusCode == 403, failure.reason == "FORBIDDEN" { self = .forbidden }
        else { self = .failed(reason: error.localizedDescription) }
    }
}

/// One avatar of the quick top-up strip (30 §1.3). `pendingNoun` is set while this phone holds a balance record awaiting
/// reconciliation for the user: the avatar then opens the detail to reconcile instead of the keypad.
public struct QuickTopupEntry: Sendable, Equatable, Identifiable {
    public let id: Int
    public let displayName: String
    public let balance: Decimal?
    /// 充值 / 退款 / 余额设置.
    public let pendingNoun: String?

    public var initial: String { UserPresentation.initial(displayName) }
    public var isPending: Bool { pendingNoun != nil }
    public var caption: String { isPending ? "去核对" : DisplayFormat.money(balance) }
    public var spokenLabel: String {
        if let pendingNoun { return "\(displayName)，上一笔\(pendingNoun)待核对，打开详情去核对" }
        return "给\(displayName)充值，" + UserListPresentation.spoken("余额", DisplayFormat.money(balance))
    }
}

/// 30 §1: the user list's pure rules, so the page only runs requests and draws.
public enum UserListPresentation {
    /// 30 §1.6: the first page, the strip and today's spend again every 60 seconds while the tab is shown.
    public static let autoRefreshInterval: TimeInterval = 60

    /// `recent` in the server's order, then the low-balance users not shown yet; users awaiting reconciliation move last.
    public static func quickTopupEntries(recent: [QuickTopupUser], lowBalance: [QuickTopupUser], pendingNouns: [Int: String]) -> [QuickTopupEntry] {
        var seen = Set<Int>()
        let entries = (recent + lowBalance).filter { seen.insert($0.userID).inserted }.map { item in
            QuickTopupEntry(id: item.userID, displayName: item.displayName, balance: item.balance, pendingNoun: pendingNouns[item.userID])
        }
        return entries.filter { !$0.isPending } + entries.filter(\.isPending)
    }
    /// R02 by direction (S0-12's `BalanceDirection`): credit only → 充值, debit only → 退款, both (a `set` above 0) → 余额设置.
    public static func pendingNoun(for record: PendingBalanceOperation) -> String {
        let directions = BalanceDirection.directions(of: record)
        if directions == [.credit] { return "充值" }
        if directions == [.debit] { return "退款" }
        return "余额设置"
    }
    /// Each user's oldest balance record at the connected address (X34): the list marks, the rail, the strip's order and
    /// whether an avatar opens the detail all read this. Compensations are not balance records and never mark a row.
    public static func pendingNouns(_ records: [PendingBalanceOperation], serverIDs: Set<UUID>) -> [Int: String] {
        let ordered = records.filter { serverIDs.contains($0.serverID) }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        return ordered.reduce(into: [:]) { nouns, record in
            if nouns[record.userID] == nil { nouns[record.userID] = pendingNoun(for: record) }
        }
    }

    /// “<站点> · 128 位”; only the site before the first page arrives.
    public static func subtitle(siteName: String, total: Int?) -> String {
        guard let total else { return siteName }
        return "\(siteName) · \(DisplayFormat.grouped(total)) 位"
    }

    public static func todayCell(userID: Int, costs: [Int: Decimal], isReadOnlyToken: Bool) -> UserTodayCell {
        guard !isReadOnlyToken, let cost = costs[userID] else { return .unavailable }
        return .amount(cost)
    }
    /// The ids of one `users-usage` request each, positive, unique and ascending (00 §4.5, S3D1-07's batch size). The page
    /// sends them one by one, so a failed batch clears only its own ids.
    public static func usageBatches(_ ids: [Int]) -> [[Int]] {
        AccountBatchIDs.batches(AccountBatchIDs.normalized(ids), size: UserListQuery.usageBatchSize)
    }
    /// A requested id the reply left out spent nothing today; an entry whose cost did not decode is unknown.
    public static func mergingTodayCosts(_ reply: [Int: UserTodayUsage], requested ids: [Int], into costs: [Int: Decimal]) -> [Int: Decimal] {
        ids.reduce(into: costs) { merged, id in
            if let usage = reply[id] { merged[id] = usage.todayActualCost } else { merged[id] = 0 }
        }
    }
    public static func clearingTodayCosts(_ ids: [Int], from costs: [Int: Decimal]) -> [Int: Decimal] {
        let cleared = Set(ids)
        return costs.filter { !cleared.contains($0.key) }
    }

    /// The row as VoiceOver reads it: name, email, balance, mark, today, then the search results' extras.
    public static func rowSpokenLabel(displayName: String, email: String, balance: Decimal?, mark: UserListMark?, today: UserTodayCell,
                                      showsDisabledBadge: Bool = false, trailingNote: String? = nil) -> String {
        let badge = showsDisabledBadge && mark != .disabled ? UserListMark.disabled.label : nil
        let note = trailingNote?.trimmingCharacters(in: CharacterSet(charactersIn: "· ").union(.whitespaces))
        let parts = [displayName, email, spoken("余额", DisplayFormat.money(balance)), mark?.label, badge, today.spokenText, note]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
    }
    public static func noMatchText(query: String) -> String { "没有匹配“\(query)”的用户" }
    /// 30 §1.5 with the server's clock and zone, like every time on the page.
    public static func staleBanner(updatedAt: Date?, timeZone: TimeZone) -> String {
        guard let updatedAt else { return "刷新失败" }
        return "刷新失败 · \(DisplayFormat.clock(updatedAt, timeZone: timeZone)) 的数据"
    }
    /// The rest of a 429 wait; otherwise the backed-off interval counted from the last refresh (00 §4.6). 0 when never refreshed.
    public static func autoRefreshDelay(lastRefreshAt: Date?, refresh: BlockRefresh, now: Date, base: TimeInterval = autoRefreshInterval) -> TimeInterval {
        guard refresh.allowsRequest(at: now) else { return refresh.nextDelay(base: base, at: now) }
        guard let lastRefreshAt else { return 0 }
        return max(0, refresh.nextDelay(base: base, at: now) - now.timeIntervalSince(lastRefreshAt))
    }

    /// “余额 $12.40”, and “余额无数据” for the missing mark.
    static func spoken(_ title: String, _ text: String) -> String {
        text == DisplayFormat.missing ? title + DisplayFormat.missingSpoken : title + " " + text
    }
}

extension QuickTopupReply {
    /// A balance write elsewhere moves the avatar's amount before the strip is read again (30 §1.4).
    public func updatingBalance(id: Int, balance: Decimal) -> QuickTopupReply {
        let update: (QuickTopupUser) -> QuickTopupUser = { $0.userID == id ? $0.with(balance: balance) : $0 }
        return QuickTopupReply(recent: recent.map(update), lowBalance: lowBalance.map(update), lowBalanceEnabled: lowBalanceEnabled)
    }
    public func removing(id: Int) -> QuickTopupReply {
        QuickTopupReply(recent: recent.filter { $0.userID != id }, lowBalance: lowBalance.filter { $0.userID != id }, lowBalanceEnabled: lowBalanceEnabled)
    }
}

private extension QuickTopupUser {
    func with(balance: Decimal) -> QuickTopupUser {
        QuickTopupUser(userID: userID, email: email, username: username, status: status, balance: balance, lastAdjustedAt: lastAdjustedAt,
                       lastDelta: lastDelta, lastOperation: lastOperation, effectiveThreshold: effectiveThreshold,
                       thresholdSource: thresholdSource, thresholdType: thresholdType)
    }
}
