import Foundation

/// The list's filters (60 §8.2–§8.4): the search, a status chip and the type menu, or the same batch, which replaces all
/// three until its chip is removed (U49). Queries are built by S6-03's RedeemCodeListQuery; this only fills it in.
public struct RedeemListFilter: Equatable, Sendable {
    public var search: String
    public var status: RedeemCodeStatus?
    /// nil = 全部类型.
    public var type: RedeemCodeType?
    public var batch: RedeemBatchChip?
    public init(search: String = "", status: RedeemCodeStatus? = nil, type: RedeemCodeType? = nil, batch: RedeemBatchChip? = nil) {
        self.search = search; self.status = status; self.type = type; self.batch = batch
    }
    /// `.redeem(query:status:type:)`: raw values; an unknown status or type opens 全部.
    public init(route query: String?, status: String?, type: String?) {
        self.init(search: query ?? "", status: status.flatMap(RedeemCodeStatus.init(rawValue:)), type: type.flatMap(RedeemCodeType.init(rawValue:)))
    }

    public var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Nothing narrows the list, so an empty one means the site has no codes.
    public var isUnfiltered: Bool { trimmedSearch.isEmpty && status == nil && type == nil && batch == nil }

    /// “查看同一批”: only `batch_id` goes out (60 §8.4); the search, status and type are left behind.
    public func showingBatch(_ batchID: UUID) -> RedeemListFilter { RedeemListFilter(batch: RedeemBatchChip(batchID: batchID)) }

    /// `sendsTypes` is `redeem_codes.stats` (U43). A batch sends neither types nor status nor search.
    public func listQuery(supportsStats: Bool) -> RedeemCodeListQuery {
        if let batch { return RedeemCodeListQuery(batchID: batch.batchID, sendsTypes: supportsStats, pageSize: RedeemListPolicy.pageSize) }
        return RedeemCodeListQuery(search: trimmedSearch, type: type, status: status, sendsTypes: supportsStats, pageSize: RedeemListPolicy.pageSize)
    }
    /// The chips' counts follow the search and the type, never the status; none without the capability, none for a batch
    /// (its chips are hidden).
    public func statsQuery(supportsStats: Bool) -> RedeemCodeListQuery? {
        guard supportsStats, batch == nil else { return nil }
        return RedeemCodeListQuery(search: trimmedSearch, type: type, sendsTypes: true)
    }
    /// The subtitle's “N 个” counts every code of the four types, whatever the search (60 §8.3).
    public static func totalQuery(supportsStats: Bool) -> RedeemCodeListQuery? { RedeemListFilter().statsQuery(supportsStats: supportsStats) }
}

extension RedeemListFilter: CustomStringConvertible, CustomDebugStringConvertible {
    /// A search may be part of a code: descriptions and logs say only whether there is one.
    public var description: String {
        "RedeemListFilter(search: \(trimmedSearch.isEmpty ? "none" : "set"), status: \(status?.rawValue ?? "all"), "
            + "type: \(type?.rawValue ?? "all"), batch: \(batch == nil ? "none" : "set"))"
    }
    public var debugDescription: String { description }
}

/// The removable chip of “查看同一批”.
public struct RedeemBatchChip: Equatable, Sendable {
    public let batchID: UUID
    public init(batchID: UUID) { self.batchID = batchID }
    /// “同一批 · 20 个”; “同一批” until the batch's first page tells its total.
    public func title(total: Int?) -> String { total.map { "同一批 · \(DisplayFormat.grouped($0)) 个" } ?? "同一批" }
    public func removeLabel(total: Int?) -> String { "移除筛选 " + title(total: total) }
}

/// The pages read so far, in the server's order (id descending). Page 1 replaces them; a later page appends, a code seen
/// again (a new one pushed it down a page) takes its new values in place. Rows the query does not admit are dropped.
public struct RedeemListPage: Equatable, Sendable {
    public let codes: [AdminRedeemCode]
    public let lastServerPage: Int
    public let hasMore: Bool
    /// The server's count for the query, before the phone dropped admin rows; nil when the envelope has none.
    public let serverTotal: Int?
    public init(codes: [AdminRedeemCode], lastServerPage: Int, hasMore: Bool, serverTotal: Int?) {
        self.codes = codes; self.lastServerPage = lastServerPage; self.hasMore = hasMore; self.serverTotal = serverTotal
    }
    public static let empty = RedeemListPage(codes: [], lastServerPage: 0, hasMore: false, serverTotal: nil)

    public var nextServerPage: Int { lastServerPage + 1 }
    public func contains(id: Int) -> Bool { codes.contains { $0.id == id } }

    public func merging(_ page: Page<AdminRedeemCode>, query: RedeemCodeListQuery) -> RedeemListPage {
        let admitted = page.items.filter(query.admits)
        var codes = page.page == 1 ? [] : self.codes
        for code in admitted {
            if let index = codes.firstIndex(where: { $0.id == code.id }) { codes[index] = code } else { codes.append(code) }
        }
        return RedeemListPage(codes: codes, lastServerPage: page.page, hasMore: page.hasMore, serverTotal: page.total ?? serverTotal)
    }
    public static func admittedCount(of page: Page<AdminRedeemCode>, query: RedeemCodeListQuery) -> Int { page.items.filter(query.admits).count }

    /// After a write or GET :id; a code not loaded is left out.
    public func replacing(_ code: AdminRedeemCode) -> RedeemListPage {
        RedeemListPage(codes: codes.map { $0.id == code.id ? code : $0 }, lastServerPage: lastServerPage, hasMore: hasMore, serverTotal: serverTotal)
    }
    public func removing(id: Int) -> RedeemListPage {
        RedeemListPage(codes: codes.filter { $0.id != id }, lastServerPage: lastServerPage, hasMore: hasMore, serverTotal: serverTotal)
    }
}

/// 60 §8.2 and §8.6: the page size, the search debounce, when a shown list is read again, and how far an old server's page
/// thinned by admin rows is continued on its own.
public enum RedeemListPolicy {
    public static let pageSize = 50
    public static let searchDebounce: Duration = .milliseconds(300)
    public static let staleAfter: TimeInterval = 60
    /// Afterwards the bottom of the list asks for the next page as usual.
    public static let maxAutomaticReads = 3

    /// Never read, read 60 seconds ago or more, or a clock that went back.
    public static func isStale(lastLoadedAt: Date?, now: Date) -> Bool {
        guard let lastLoadedAt else { return true }
        let elapsed = now.timeIntervalSince(lastLoadedAt)
        return elapsed >= staleAfter || elapsed < 0
    }
    /// Without `types`, “全部类型” drops admin rows on the phone; a page left short with more to come reads the next one.
    public static func continuesAutomatically(after page: Page<AdminRedeemCode>, query: RedeemCodeListQuery, automaticReads: Int) -> Bool {
        query.excludesAdminAdjustments && page.hasMore && automaticReads < maxAutomaticReads
            && RedeemListPage.admittedCount(of: page, query: query) < query.pageSize
    }
    /// The end of the list offers “加载更多” where reaching the last card cannot read on (60 §8.2): an old server's pages may add
    /// few cards or none once its admin rows are dropped, and a list left without cards has no last card.
    public static func offersLoadMore(_ page: RedeemListPage, query: RedeemCodeListQuery) -> Bool {
        page.hasMore && (query.excludesAdminAdjustments || page.codes.isEmpty)
    }
}

/// One day group of the list (60 §8.3 组头): its codes in list order and how many are loaded.
public struct RedeemListSection: Equatable, Sendable, Identifiable {
    public let group: RedeemDayGroup
    public let codes: [AdminRedeemCode]
    public var id: RedeemDayGroup { group }
    public var title: String { group.title }
    public var countText: String { DisplayFormat.grouped(codes.count) }
}

public enum RedeemListLayout {
    /// Today, yesterday, earlier on the server's calendar (RedeemPresentation.dayGroup); empty groups are left out.
    public static func sections(_ codes: [AdminRedeemCode], now: Date, timeZone: TimeZone) -> [RedeemListSection] {
        let grouped = Dictionary(grouping: codes) { RedeemPresentation.dayGroup($0.createdAt, now: now, timeZone: timeZone) }
        return RedeemDayGroup.allCases.compactMap { group in grouped[group].map { RedeemListSection(group: group, codes: $0) } }
    }
    /// `.redeem(open:)`: the code read by id stays on top only while the loaded pages do not hold it (60 §8.1).
    public static func pinned(_ located: AdminRedeemCode?, in codes: [AdminRedeemCode]) -> AdminRedeemCode? {
        guard let located, !codes.contains(where: { $0.id == located.id }) else { return nil }
        return located
    }
}

public enum RedeemListText {
    public static let title = "兑换码"
    public static let searchPrompt = "搜索兑换码或邮箱"
    public static let loading = "正在读取兑换码…"
    public static let generateTitle = "生成兑换码"
    public static let clearSearch = "清除搜索"
    public static let loadMore = "加载更多"
    public static let loadMoreFailed = "加载失败 · 重试"
    public static let copiedReceipt = "已复制兑换码"
    public static let locatedGone = "这个兑换码已被删除"
    public static let locatedHeader = "定位的兑换码"
    /// “主站 · 128 个”; the site name alone without the count (counts failed or no capability).
    public static func subtitle(siteName: String, total: Int?) -> String {
        total.map { "\(siteName) · \(DisplayFormat.grouped($0)) 个" } ?? siteName
    }
}

/// 60 §8.5: what a loaded list without rows says.
public enum RedeemListEmpty: Equatable, Sendable {
    case noCodes, noSearchMatch(String), noTypeMatch
    /// nil while not loaded, with rows, or while later pages may still hold some. A site known to have no code says so whatever
    /// the chip, but a search keeps its own wording.
    public static func resolve(page: RedeemListPage?, filter: RedeemListFilter, siteTotal: Int?) -> RedeemListEmpty? {
        guard let page, page.codes.isEmpty, !page.hasMore else { return nil }
        let search = filter.trimmedSearch
        if !search.isEmpty, filter.batch == nil { return .noSearchMatch(search) }
        return filter.isUnfiltered || siteTotal == 0 ? .noCodes : .noTypeMatch
    }
    public var title: String {
        switch self {
        case .noCodes: "还没有兑换码"
        case .noSearchMatch(let search): "没有匹配“\(search)”的兑换码"
        case .noTypeMatch: "没有这类兑换码"
        }
    }
}

/// 60 §11.3 and X34: the list's banner for the earliest redeem batch of this address awaiting its result. The other kinds of
/// records belong to other pages; “等 N 批” counts the address's batches.
public struct RedeemPendingBanner: Equatable, Sendable {
    public static let titleText = "兑换码生成结果待核对"
    public let batchID: UUID
    public let title: String
    /// “20 个 × $10.00 · 合计 $200.00” (RedeemGenerateSummary.batchLine, S6D1-05).
    public let amountLine: String
    /// “5 分钟前发起，未确认是否已生成”, plus “ · 这笔在本站点的旧登录下发起” for an older login's record.
    public let timeLine: String
    public let origin: MoneyRecordOrigin.Kind

    /// `records` are AppModel.pendingMoneyWrites(sameAddressAs:); a batch outside `sameAddress` is not this address's.
    public static func make(records: [any PendingMoneyWrite], currentServerID: UUID, sameAddress: Set<UUID>, now: Date,
                            timeZone: TimeZone) -> RedeemPendingBanner? {
        let batches = records.compactMap { $0 as? PendingRedeemBatch }
            .filter { $0.serverID == currentServerID || sameAddress.contains($0.serverID) }
        guard let earliest = batches.min(by: { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }) else { return nil }
        let origin = MoneyRecordOrigin.Kind(recordServerID: earliest.serverID, currentServerID: currentServerID, sameAddress: sameAddress)
        let time = DisplayFormat.relativeTime(earliest.createdAt, now: now, timeZone: timeZone)
        let note = origin == .sameAddressOldLogin ? " · 这笔在" + MoneyRecordOrigin.oldLoginNote : ""
        return RedeemPendingBanner(batchID: earliest.id, title: titleText + (batches.count > 1 ? "等 \(batches.count) 批" : ""),
                                   amountLine: RedeemGenerateSummary(spec: earliest.spec, now: now, timeZone: timeZone).batchLine,
                                   timeLine: time + (time.last?.isNumber == true ? " " : "") + "发起，未确认是否已生成" + note, origin: origin)
    }
}

/// 60 §8.5: a list or lookup failure. The three parameter reasons are the App's own mistake: shown as the catalog's
/// “请求无效” and logged by reason (never the code or the search).
public enum RedeemListFailure: Equatable, Sendable {
    case parameter(reason: String), notFound, other
    public static let parameterReasons: Set<String> = ["REDEEM_CODE_TYPE_INVALID", "REDEEM_CODE_TYPE_CONFLICT", "REDEEM_BATCH_ID_INVALID"]

    public init(_ error: any Error) {
        guard let error = error as? APIError, let reason = error.reason else { self = .other; return }
        if error.statusCode == 400, Self.parameterReasons.contains(reason) { self = .parameter(reason: reason) }
        else if error.statusCode == 404, reason == "REDEEM_CODE_NOT_FOUND" { self = .notFound }
        else { self = .other }
    }
}
