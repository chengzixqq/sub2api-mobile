import Foundation
import Sub2Core

/// 60 §15–§18 `-ui-testing` fixtures (X05). The eight announcements follow the design's VMO_NOTICES; group names come from
/// DemoData.accountGroups through the group directory (1 高级组, 4 企业专线, X11). S6-17…S6-19 append below.
extension DemoData {
    enum AnnouncementFixture {
        /// No announcement at all; every count is 0.
        static let empty = "-ui-announcements-empty"
        /// Without 27, 24 and 21, so 已归档 is empty.
        static let noArchived = "-ui-announcements-no-archived"
        /// 25 more archived ones, “历史公告 1…25” (ids 101…125, older than 21): 33 in all, page 2 ends with 101.
        static let many = "-ui-announcements-many"
        /// The session's first page-1 read fails with 502.
        static let listError = "-ui-announcements-error"
        /// Every count read fails, as all four failing would.
        static let countsError = "-ui-announcements-counts-error"
        /// The first page-2 read fails.
        static let pageError = "-ui-announcements-page-error"
    }

    static func announcementFixtures(base: Date, arguments: [String]) -> [Announcement] {
        guard !arguments.contains(AnnouncementFixture.empty) else { return [] }
        var items = baseAnnouncements(base: base)
        if arguments.contains(AnnouncementFixture.noArchived) { items.removeAll { $0.status == .archived } }
        if arguments.contains(AnnouncementFixture.many) { items += (1...25).map { historyAnnouncement($0, base: base) } }
        return items
    }

    private static func baseAnnouncements(base: Date) -> [Announcement] {
        func at(days: Double = 0, hours: Double = 0, minutes: Double = 0) -> Date {
            base.addingTimeInterval(days * 86_400 + hours * 3_600 + minutes * 60)
        }
        let enterprise = AnnouncementCondition.subscription(groupIDs: [4])
        return [
            Announcement(id: 31, title: "10 月 18 日凌晨维护通知", content: maintenanceText, status: .active, notifyMode: .popup,
                         startsAt: at(hours: -1), endsAt: at(days: 2), createdAt: at(hours: -2), updatedAt: at(hours: -1),
                         readStats: AnnouncementReadStats(eligibleCount: 1036, readCount: 412, eligibleReadCount: 410)),
            Announcement(id: 30, title: "企业专线新增 gpt-4.1 长上下文", content: "**企业专线**订阅用户现在可以使用 gpt-4.1 的长上下文。\n\n- 计费倍率与原来相同\n- 每日、每周、每月限额不变",
                         status: .active, notifyMode: .silent, targeting: .single(enterprise), createdAt: at(days: -3), updatedAt: at(days: -3),
                         readStats: AnnouncementReadStats(eligibleCount: 38, readCount: 12, eligibleReadCount: 12)),
            Announcement(id: 33, title: "充值赠送活动预告", content: "下周起单笔充值满 **$100** 赠送 5% 余额。", status: .active, notifyMode: .popup,
                         targeting: .single(.balance("gte", value: 10)), startsAt: at(days: 1), endsAt: at(days: 8), createdAt: at(days: -4),
                         updatedAt: at(days: -4), readStats: AnnouncementReadStats(eligibleCount: 0, readCount: 0, eligibleReadCount: 0)),
            Announcement(id: 32, title: "旧专线停用通知", content: "旧专线已停止服务，请改用企业专线。", status: .active, notifyMode: .silent,
                         targeting: .single(.subscription(groupIDs: [99])), startsAt: at(days: -10), endsAt: at(days: -1), createdAt: at(days: -12),
                         updatedAt: at(days: -10), readStats: AnnouncementReadStats(eligibleCount: 5, readCount: 3, eligibleReadCount: 3)),
            Announcement(id: 29, title: "余额不足提醒", content: "你的余额已低于 **$5.00**。为避免请求中断，请及时充值。", status: .draft, notifyMode: .popup,
                         targeting: .single(.balance("lt", value: 5)), createdAt: at(days: -13), updatedAt: at(minutes: -30),
                         readStats: AnnouncementReadStats(eligibleCount: 9, readCount: 0, eligibleReadCount: 0)),
            Announcement(id: 27, title: "国庆期间客服时间调整", content: "10 月 1 日至 8 日，客服在线时间调整为 **10:00–18:00**。\n\n工单仍然 24 小时受理。",
                         status: .archived, notifyMode: .silent, startsAt: at(days: -25), endsAt: at(days: -18), createdAt: at(days: -28),
                         updatedAt: at(days: -17), readStats: AnnouncementReadStats(eligibleCount: 1020, readCount: 640, eligibleReadCount: 636)),
            Announcement(id: 24, title: "新模型计费说明", content: "## 计费口径\n\n- 实际扣费 = 标准价 × 分组倍率\n- 缓存读取按官方折扣计费",
                         status: .archived, notifyMode: .silent,
                         targeting: AnnouncementTargeting(anyOf: [AnnouncementConditionGroup(allOf: [enterprise, .balance("gte", value: 10)]),
                                                                  AnnouncementConditionGroup(allOf: [.balance("gte", value: 500)])]),
                         startsAt: at(days: -35), endsAt: at(days: -20), createdAt: at(days: -37), updatedAt: at(days: -19),
                         readStats: AnnouncementReadStats(eligibleCount: 41, readCount: 30, eligibleReadCount: 29)),
            Announcement(id: 21, title: "高级组与企业专线限额调整", content: "高级组与企业专线的每日限额自下月起调整。", status: .archived, notifyMode: .popup,
                         targeting: .single(.subscription(groupIDs: [1, 4])), startsAt: at(days: -60), endsAt: at(days: -40), createdAt: at(days: -62),
                         updatedAt: at(days: -39), readStats: AnnouncementReadStats(eligibleCount: 120, readCount: 96, eligibleReadCount: 90))
        ]
    }

    private static let maintenanceText = "**维护时间**：10 月 18 日 02:00–04:00（北京时间）\n\n维护期间：\n- API 请求可能短暂返回 502，请在客户端开启重试\n"
        + "- 控制台暂停充值与兑换\n\n如有问题，请在[工单中心](https://example.com/ticket)联系我们。"

    private static func historyAnnouncement(_ index: Int, base: Date) -> Announcement {
        let created = base.addingTimeInterval(-Double(96 - index) * 86_400)
        return Announcement(id: 100 + index, title: "历史公告 \(index)", content: "第 \(index) 条历史公告。", status: .archived, notifyMode: .silent,
                            startsAt: created, endsAt: created.addingTimeInterval(7 * 86_400), createdAt: created, updatedAt: created,
                            readStats: AnnouncementReadStats(eligibleCount: 100, readCount: 50, eligibleReadCount: 50))
    }
}

/// The fixture site's announcements for one session (`current(for:base:)`), so a later item's write fixtures change what the
/// list and the detail read in that session only. Lists sort like the backend: created_at, then id, both descending.
@MainActor
final class AnnouncementDemoStore {
    let base: Date
    private(set) var items: [Announcement]
    private let arguments: [String]
    private var firstPageReads = 0
    private var secondPageReads = 0
    private static var latest: (generation: UUID, store: AnnouncementDemoStore)?
    private static let failure = APIError.server(status: 502, reason: nil)

    init(base: Date, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.base = base; self.arguments = arguments
        items = Self.sorted(DemoData.announcementFixtures(base: base, arguments: arguments))
    }
    /// Only the newest session's store is kept.
    static func current(for generation: UUID, base: @autoclosure () -> Date) -> AnnouncementDemoStore {
        if let latest, latest.generation == generation { return latest.store }
        let store = AnnouncementDemoStore(base: base())
        latest = (generation, store)
        return store
    }

    /// `GET admin/announcements`: the status filter, then pages; read_stats only when asked for.
    func page(_ page: Int, query: AnnouncementListQuery) throws -> Page<Announcement> {
        _ = try query.queryItems(page: page)
        if page == 1 { firstPageReads += 1 }
        if page == 2 { secondPageReads += 1 }
        if arguments.contains(DemoData.AnnouncementFixture.listError), page == 1, firstPageReads == 1 { throw Self.failure }
        if arguments.contains(DemoData.AnnouncementFixture.pageError), page == 2, secondPageReads == 1 { throw Self.failure }
        let matched = items.filter { query.status == nil || $0.status == query.status }
        let size = PageSize.clamped(query.pageSize)
        let shown = matched.dropFirst((page - 1) * size).prefix(size).map { query.includeReadStats ? $0 : Self.withoutReadStats($0) }
        return Page(items: Array(shown), total: matched.count, page: page, pageSize: size, pages: max(1, (matched.count + size - 1) / size))
    }
    /// The four `page_size=1` totals.
    func counts() throws -> AnnouncementCounts {
        if arguments.contains(DemoData.AnnouncementFixture.countsError) { throw Self.failure }
        func count(_ status: AnnouncementStatus) -> Int { items.filter { $0.status == status }.count }
        return AnnouncementCounts(all: items.count, active: count(.active), draft: count(.draft), archived: count(.archived))
    }
    /// For the write fixtures of S6-17 and S6-18.
    func replace(_ items: [Announcement]) { self.items = Self.sorted(items) }

    private static func sorted(_ items: [Announcement]) -> [Announcement] {
        items.sorted { ($0.createdAt ?? .distantPast, $0.id) > ($1.createdAt ?? .distantPast, $1.id) }
    }
    private static func withoutReadStats(_ item: Announcement) -> Announcement {
        Announcement(id: item.id, title: item.title, content: item.content, status: item.status, notifyMode: item.notifyMode, targeting: item.targeting,
                     startsAt: item.startsAt, endsAt: item.endsAt, createdBy: item.createdBy, updatedBy: item.updatedBy, createdAt: item.createdAt,
                     updatedAt: item.updatedAt)
    }
}

extension AnnouncementListSource {
    static func fixture(_ store: AnnouncementDemoStore) -> AnnouncementListSource {
        AnnouncementListSource(page: { try await store.page($0, query: $1) }, counts: { try await store.counts() })
    }
}

// MARK: - 详情（S6-17）

extension DemoData.AnnouncementFixture {
    /// 32 reads and writes as 404 ANNOUNCEMENT_NOT_FOUND; the list still shows it.
    static let detailMissing = "-ui-announcement-detail-missing"
    /// Every read-summary fails with 502.
    static let detailSummaryError = "-ui-announcement-detail-summary-error"
    /// The fixture site's user count behind every summary.
    static let totalUsers = 1_036
}

extension AnnouncementDemoStore {
    private static let notFound = APIError.server(status: 404, reason: AnnouncementWriteFailure.notFoundReason)

    /// `GET admin/announcements/:id`.
    func announcement(id: Int, includeReadStats: Bool) throws -> Announcement {
        let item = try existing(id)
        return includeReadStats ? item : Self.withoutReadStats(item)
    }
    /// `GET :id/read-summary` from the item's read_stats, computed now.
    func readSummary(id: Int, now: Date) throws -> AnnouncementReadSummary {
        if arguments.contains(DemoData.AnnouncementFixture.detailSummaryError) { throw Self.failure }
        let stats = try existing(id).readStats
        return AnnouncementReadSummary(announcementID: id, totalUsers: DemoData.AnnouncementFixture.totalUsers, eligibleCount: stats?.eligibleCount ?? 0,
                                       readCount: stats?.readCount ?? 0, eligibleReadCount: stats?.eligibleReadCount ?? 0, computedAt: now)
    }
    /// `PUT :id`: the keys sent, checked like the server (the merged start and end too); returned without read_stats like the
    /// server.
    func update(id: Int, _ request: AnnouncementUpdateRequest, now: Date) throws -> Announcement {
        let item = try existing(id)
        _ = try request.requestBody()
        let startsAt = Self.applying(request.startsAt, to: item.startsAt), endsAt = Self.applying(request.endsAt, to: item.endsAt)
        if let startsAt, let endsAt, startsAt >= endsAt { throw APIError.server(status: 400, reason: "ANNOUNCEMENT_TIME_RANGE_INVALID") }
        let updated = Announcement(id: item.id, title: request.title.map(Self.trimmed) ?? item.title,
                                   content: request.content.map(Self.trimmed) ?? item.content, status: request.status ?? item.status,
                                   notifyMode: request.notifyMode ?? item.notifyMode, targeting: request.targeting ?? item.targeting,
                                   startsAt: startsAt, endsAt: endsAt, createdBy: item.createdBy, updatedBy: item.updatedBy,
                                   createdAt: item.createdAt, updatedAt: now, readStats: item.readStats)
        replace(items.map { $0.id == id ? updated : $0 })
        return Self.withoutReadStats(updated)
    }
    /// `DELETE :id`.
    func delete(id: Int) -> AnnouncementDeleteResult {
        guard items.contains(where: { $0.id == id }) else { return .alreadyGone }
        replace(items.filter { $0.id != id })
        return .deleted
    }

    private func existing(_ id: Int) throws -> Announcement {
        if arguments.contains(DemoData.AnnouncementFixture.detailMissing), id == 32 { throw Self.notFound }
        guard let item = items.first(where: { $0.id == id }) else { throw Self.notFound }
        return item
    }
}

extension AnnouncementDetailSource {
    static func fixture(_ store: AnnouncementDemoStore) -> AnnouncementDetailSource {
        AnnouncementDetailSource(load: { try await store.announcement(id: $0, includeReadStats: $1) },
                                 summary: { id in try await store.readSummary(id: id, now: Date()) },
                                 update: { try await store.update(id: $0, $1, now: Date()) },
                                 delete: { await store.delete(id: $0) })
    }
}

// MARK: - 编辑 / 新建（S6-18）

extension AnnouncementDemoStore {
    /// `POST admin/announcements`: checked like the server, then the next id, created and updated now; read_stats once it is
    /// not a draft.
    func create(_ request: AnnouncementCreateRequest, now: Date) throws -> Announcement {
        _ = try request.requestBody()
        let stats = request.status == .draft ? nil : AnnouncementReadStats(eligibleCount: 0, readCount: 0, eligibleReadCount: 0)
        let item = Announcement(id: (items.map(\.id).max() ?? 0) + 1, title: Self.trimmed(request.title), content: Self.trimmed(request.content),
                                status: request.status, notifyMode: request.notifyMode, targeting: request.targeting, startsAt: request.startsAt.map(Self.whole),
                                endsAt: request.endsAt.map(Self.whole), createdAt: now, updatedAt: now, readStats: stats)
        replace(items + [item])
        return Self.withoutReadStats(item)
    }
    /// `GET admin/announcements?search=` for H07: title or body contains it, newest first, five at most.
    func recent(title: String) -> [Announcement] {
        let term = Self.trimmed(title)
        return Array(items.filter { $0.title.localizedCaseInsensitiveContains(term) || $0.content.localizedCaseInsensitiveContains(term) }.prefix(5))
            .map(Self.withoutReadStats)
    }

    fileprivate static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    fileprivate static func whole(_ date: Date) -> Date { Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)) }
    fileprivate static func applying(_ schedule: AnnouncementUpdateRequest.Schedule?, to date: Date?) -> Date? {
        switch schedule {
        case nil: date
        case .clear?: nil
        case .at(let value)?: whole(value)
        }
    }
}

extension AnnouncementEditSource {
    static func fixture(_ store: AnnouncementDemoStore) -> AnnouncementEditSource {
        AnnouncementEditSource(create: { request, _, _, _ in WriteOutcome(value: try await store.create(request, now: Date())) },
                               update: { try await store.update(id: $0, $1, now: Date()) },
                               load: { try await store.announcement(id: $0, includeReadStats: false) },
                               recent: { await store.recent(title: $0) })
    }
}
