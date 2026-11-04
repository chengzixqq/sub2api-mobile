import Foundation

public enum AnnouncementStatus: String, Codable, CaseIterable, Sendable { case draft, active, archived }
public enum AnnouncementNotifyMode: String, Codable, CaseIterable, Sendable { case silent, popup }

/// One condition of `domain.AnnouncementCondition`. `type` and `operator` stay strings, so a kind this version does not know is
/// kept (and shown as “其他条件”) instead of being dropped. The backend leaves a balance of 0 out (`omitempty`).
public struct AnnouncementCondition: Codable, Sendable, Equatable {
    public static let subscriptionType = "subscription", balanceType = "balance", inOperator = "in"
    public static let balanceOperators = ["gt", "gte", "lt", "lte", "eq"]
    public let type: String
    public let `operator`: String
    public let groupIDs: [Int]
    public let value: Decimal?
    public init(type: String, operator comparison: String, groupIDs: [Int] = [], value: Decimal? = nil) {
        self.type = type; self.operator = comparison; self.groupIDs = groupIDs; self.value = value
    }
    public static func subscription(groupIDs: [Int]) -> AnnouncementCondition {
        AnnouncementCondition(type: subscriptionType, operator: inOperator, groupIDs: groupIDs)
    }
    public static func balance(_ comparison: String, value: Decimal) -> AnnouncementCondition {
        AnnouncementCondition(type: balanceType, operator: comparison, value: value)
    }
    public var effectiveValue: Decimal { value ?? 0 }
    /// The backend's `validate()`: anything else is 400 ANNOUNCEMENT_INVALID_TARGET.
    public var isValid: Bool {
        switch type {
        case Self.subscriptionType: self.operator == Self.inOperator && !groupIDs.isEmpty && groupIDs.allSatisfy { $0 > 0 }
        case Self.balanceType: Self.balanceOperators.contains(self.operator)
        default: false
        }
    }

    enum CodingKeys: String, CodingKey { case type, `operator`, value, groupIDs = "group_ids" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
        self.operator = (try? c.decodeIfPresent(String.self, forKey: .operator)) ?? ""
        groupIDs = (try? c.decodeIfPresent([Int].self, forKey: .groupIDs)) ?? []
        value = try? c.optionalDecimal(.value)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type); try c.encode(self.operator, forKey: .operator)
        if !groupIDs.isEmpty { try c.encode(groupIDs, forKey: .groupIDs) }
        try c.encodeIfPresent(value, forKey: .value)
    }
}

/// `all_of`: every condition must hold.
public struct AnnouncementConditionGroup: Codable, Sendable, Equatable {
    public let allOf: [AnnouncementCondition]
    public init(allOf: [AnnouncementCondition]) { self.allOf = allOf }
    enum CodingKeys: String, CodingKey { case allOf = "all_of" }
    public init(from decoder: any Decoder) throws {
        allOf = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([AnnouncementCondition].self, forKey: .allOf) ?? []
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !allOf.isEmpty { try c.encode(allOf, forKey: .allOf) }
    }
}

/// `domain.AnnouncementTargeting` (60 §15.2): any group may match. No group is everyone, encoded as `{}` like the backend, so
/// changing back to everyone sends `{}` explicitly (60 §17.4). A malformed block fails the decode rather than reading as everyone.
public struct AnnouncementTargeting: Codable, Sendable, Equatable {
    public static let everyone = AnnouncementTargeting(anyOf: [])
    public static let maxGroups = 50, maxConditions = 50
    public let anyOf: [AnnouncementConditionGroup]
    public init(anyOf: [AnnouncementConditionGroup]) { self.anyOf = anyOf }
    public static func single(_ condition: AnnouncementCondition) -> AnnouncementTargeting {
        AnnouncementTargeting(anyOf: [AnnouncementConditionGroup(allOf: [condition])])
    }
    public var isEveryone: Bool { anyOf.isEmpty }
    /// `NormalizeAndValidate`: at most 50 groups of 1…50 valid conditions.
    public var isValid: Bool {
        anyOf.count <= Self.maxGroups
            && anyOf.allSatisfy { (1...Self.maxConditions).contains($0.allOf.count) && $0.allOf.allSatisfy(\.isValid) }
    }
    enum CodingKeys: String, CodingKey { case anyOf = "any_of" }
    public init(from decoder: any Decoder) throws {
        anyOf = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([AnnouncementConditionGroup].self, forKey: .anyOf) ?? []
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !anyOf.isEmpty { try c.encode(anyOf, forKey: .anyOf) }
    }
}

/// `read_stats` of a list item or detail, only with `include_read_stats=true` (H06).
public struct AnnouncementReadStats: Decodable, Sendable, Equatable {
    public let eligibleCount: Int
    public let readCount: Int
    public let eligibleReadCount: Int
    public init(eligibleCount: Int, readCount: Int, eligibleReadCount: Int) {
        self.eligibleCount = eligibleCount; self.readCount = readCount; self.eligibleReadCount = eligibleReadCount
    }
    enum CodingKeys: String, CodingKey { case eligibleCount = "eligible_count", readCount = "read_count", eligibleReadCount = "eligible_read_count" }
}

/// `dto.Announcement` (60 §15.2): every field but `id` may be missing. An unknown status reads as nil and an unknown notify
/// mode as the backend default, silent.
public struct Announcement: Identifiable, Decodable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public let content: String
    public let status: AnnouncementStatus?
    public let notifyMode: AnnouncementNotifyMode
    public let targeting: AnnouncementTargeting
    public let startsAt: Date?
    public let endsAt: Date?
    public let createdBy: Int?
    public let updatedBy: Int?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let readStats: AnnouncementReadStats?
    public init(id: Int, title: String = "", content: String = "", status: AnnouncementStatus? = .draft, notifyMode: AnnouncementNotifyMode = .silent,
                targeting: AnnouncementTargeting = .everyone, startsAt: Date? = nil, endsAt: Date? = nil, createdBy: Int? = nil, updatedBy: Int? = nil,
                createdAt: Date? = nil, updatedAt: Date? = nil, readStats: AnnouncementReadStats? = nil) {
        self.id = id; self.title = title; self.content = content; self.status = status; self.notifyMode = notifyMode; self.targeting = targeting
        self.startsAt = startsAt; self.endsAt = endsAt; self.createdBy = createdBy; self.updatedBy = updatedBy
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.readStats = readStats
    }
    enum CodingKeys: String, CodingKey {
        case id, title, content, status, targeting
        case notifyMode = "notify_mode", startsAt = "starts_at", endsAt = "ends_at", createdBy = "created_by", updatedBy = "updated_by"
        case createdAt = "created_at", updatedAt = "updated_at", readStats = "read_stats"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        status = (try? c.decodeIfPresent(String.self, forKey: .status)).flatMap(AnnouncementStatus.init(rawValue:))
        notifyMode = (try? c.decodeIfPresent(String.self, forKey: .notifyMode)).flatMap(AnnouncementNotifyMode.init(rawValue:)) ?? .silent
        targeting = try c.decodeIfPresent(AnnouncementTargeting.self, forKey: .targeting) ?? .everyone
        startsAt = try c.optionalTimestamp(.startsAt); endsAt = try c.optionalTimestamp(.endsAt)
        createdBy = try? c.decodeIfPresent(Int.self, forKey: .createdBy); updatedBy = try? c.decodeIfPresent(Int.self, forKey: .updatedBy)
        createdAt = try c.optionalTimestamp(.createdAt); updatedAt = try c.optionalTimestamp(.updatedAt)
        readStats = try? c.decodeIfPresent(AnnouncementReadStats.self, forKey: .readStats)
    }
}

/// `GET admin/announcements/:id/read-summary` (60 §16.2): counts only users not deleted; `read_count` includes those who read it
/// and no longer qualify. `computed_at` is UTC.
public struct AnnouncementReadSummary: Decodable, Sendable, Equatable {
    public let announcementID: Int?
    public let totalUsers: Int
    public let eligibleCount: Int
    public let readCount: Int
    public let eligibleReadCount: Int
    public let computedAt: Date?
    public var readButIneligible: Int { max(0, readCount - eligibleReadCount) }
    public init(announcementID: Int? = nil, totalUsers: Int, eligibleCount: Int, readCount: Int, eligibleReadCount: Int, computedAt: Date?) {
        self.announcementID = announcementID; self.totalUsers = totalUsers; self.eligibleCount = eligibleCount; self.readCount = readCount
        self.eligibleReadCount = eligibleReadCount; self.computedAt = computedAt
    }
    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id", totalUsers = "total_users", eligibleCount = "eligible_count", readCount = "read_count"
        case eligibleReadCount = "eligible_read_count", computedAt = "computed_at"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(announcementID: try? c.decodeIfPresent(Int.self, forKey: .announcementID), totalUsers: try c.decode(Int.self, forKey: .totalUsers),
                  eligibleCount: try c.decode(Int.self, forKey: .eligibleCount), readCount: try c.decode(Int.self, forKey: .readCount),
                  eligibleReadCount: try c.decode(Int.self, forKey: .eligibleReadCount), computedAt: try c.optionalTimestamp(.computedAt))
    }
}

/// A row of `GET admin/announcements/:id/read-status` (60 §18.2).
public struct AnnouncementReadStatusRow: Identifiable, Decodable, Sendable, Equatable {
    public let userID: Int
    public var id: Int { userID }
    public let email: String
    public let username: String
    public let balance: Decimal?
    public let eligible: Bool
    public let readAt: Date?
    public init(userID: Int, email: String, username: String = "", balance: Decimal? = nil, eligible: Bool, readAt: Date? = nil) {
        self.userID = userID; self.email = email; self.username = username; self.balance = balance; self.eligible = eligible; self.readAt = readAt
    }
    enum CodingKeys: String, CodingKey { case email, username, balance, eligible, userID = "user_id", readAt = "read_at" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(Int.self, forKey: .userID)
        email = (try? c.decodeIfPresent(String.self, forKey: .email)) ?? ""
        username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? ""
        balance = try? c.optionalDecimal(.balance)
        eligible = (try? c.decodeIfPresent(Bool.self, forKey: .eligible)) ?? false
        readAt = try c.optionalTimestamp(.readAt)
    }
}

/// The four segment counts (60 §15.2): the backend has no statistics endpoint, so each is a list `total`. nil = that query
/// failed or its envelope had no total; the segment then shows its name only.
public struct AnnouncementCounts: Sendable, Equatable {
    public let all: Int?
    public let active: Int?
    public let draft: Int?
    public let archived: Int?
    public init(all: Int?, active: Int?, draft: Int?, archived: Int?) { self.all = all; self.active = active; self.draft = draft; self.archived = archived }
    /// nil = 全部.
    public func count(for status: AnnouncementStatus?) -> Int? {
        switch status {
        case nil: all
        case .active?: active
        case .draft?: draft
        case .archived?: archived
        }
    }
}

/// `DELETE admin/announcements/:id`: 404 ANNOUNCEMENT_NOT_FOUND counts as deleted (60 §16.4).
public enum AnnouncementDeleteResult: Sendable, Equatable { case deleted, alreadyGone }

/// `GET admin/announcements` (60 §15.2): newest first, no ETag. `includeReadStats` is `announcements.read_stats` (U44); nil
/// status = 全部.
public struct AnnouncementListQuery: Sendable, Equatable {
    public static let defaultPageSize = 20
    public var status: AnnouncementStatus?
    public var search: String
    public var includeReadStats: Bool
    public var pageSize: Int
    public init(status: AnnouncementStatus? = nil, search: String = "", includeReadStats: Bool = false,
                pageSize: Int = AnnouncementListQuery.defaultPageSize) {
        self.status = status; self.search = search; self.includeReadStats = includeReadStats; self.pageSize = pageSize
    }
    public func queryItems(page: Int) throws -> [URLQueryItem] {
        let pageText = try AnnouncementQuery.page(page)
        var values = ["page": pageText, "page_size": String(PageSize.clamped(pageSize)), "sort_by": "created_at", "sort_order": "desc"]
        if let status { values["status"] = status.rawValue }
        values["search"] = AnnouncementQuery.searchTerm(search)
        if includeReadStats { values["include_read_stats"] = "true" }
        return AnnouncementQuery.items(values)
    }
}

/// `GET admin/announcements/:id/read-status` (60 §18.2). Without `announcements.read_stats` only search and the email /
/// username / balance sorts go out, and the old path reads subscriptions per user, so a page stays within 20–50 (H06).
public struct AnnouncementReadStatusQuery: Sendable, Equatable {
    public enum ReadState: String, CaseIterable, Sendable {
        case all, read, unread
        public var title: String {
            switch self {
            case .all: "全部"
            case .read: "已读"
            case .unread: "未读"
            }
        }
    }
    public enum Sort: String, CaseIterable, Sendable {
        case email, username, balance
        case readAt = "read_at"
        public var title: String {
            switch self {
            case .email: "按邮箱"
            case .username: "按用户名"
            case .balance: "按余额"
            case .readAt: "按阅读时间"
            }
        }
        public var detail: String {
            switch self {
            case .email, .username: "升序"
            case .balance: "从高到低"
            case .readAt: "最新在前"
            }
        }
        /// Highest balance and latest read first; the server puts unread rows last.
        public var isDescending: Bool { self == .balance || self == .readAt }
        public var requiresReadStats: Bool { self == .readAt }
        public static func available(supportsReadStats: Bool) -> [Sort] { allCases.filter { supportsReadStats || !$0.requiresReadStats } }
    }
    public static let pageSizeWithReadStats = 50
    public static let legacyPageSizes = 20...50
    public var search: String
    public var readState: ReadState
    public var eligibleOnly: Bool
    public var sort: Sort
    public var pageSize: Int
    public let supportsReadStats: Bool
    public init(search: String = "", readState: ReadState = .all, eligibleOnly: Bool = false, sort: Sort = .email,
                pageSize: Int = AnnouncementReadStatusQuery.pageSizeWithReadStats, supportsReadStats: Bool) {
        self.search = search; self.readState = readState; self.eligibleOnly = eligibleOnly; self.sort = sort; self.pageSize = pageSize
        self.supportsReadStats = supportsReadStats
    }
    public var effectiveSort: Sort { supportsReadStats || !sort.requiresReadStats ? sort : .email }
    public var effectivePageSize: Int {
        supportsReadStats ? PageSize.clamped(pageSize) : min(max(pageSize, Self.legacyPageSizes.lowerBound), Self.legacyPageSizes.upperBound)
    }
    /// What “找到 N 位” follows: a search, or a filter the site supports. The sort does not count.
    public var isFiltered: Bool {
        AnnouncementQuery.searchTerm(search) != nil || (supportsReadStats && (readState != .all || eligibleOnly))
    }
    public func queryItems(page: Int) throws -> [URLQueryItem] {
        let pageText = try AnnouncementQuery.page(page), sort = effectiveSort
        var values = ["page": pageText, "page_size": String(effectivePageSize), "sort_by": sort.rawValue,
                      "sort_order": sort.isDescending ? "desc" : "asc"]
        values["search"] = AnnouncementQuery.searchTerm(search)
        if supportsReadStats, readState != .all { values["read_state"] = readState.rawValue }
        if supportsReadStats, eligibleOnly { values["eligible"] = "true" }
        return AnnouncementQuery.items(values)
    }
}

/// `POST admin/announcements` (60 §17.2). Times go out as Unix seconds and are left out for 立即 / 永久; title and content as
/// typed (the server trims them). The same value always encodes to the same bytes.
public struct AnnouncementCreateRequest: Encodable, Sendable, Equatable {
    public static let titleByteLimit = 200
    public let title: String
    public let content: String
    public let status: AnnouncementStatus
    public let notifyMode: AnnouncementNotifyMode
    public let targeting: AnnouncementTargeting
    public let startsAt: Date?
    public let endsAt: Date?
    public init(title: String, content: String, status: AnnouncementStatus = .draft, notifyMode: AnnouncementNotifyMode = .silent,
                targeting: AnnouncementTargeting = .everyone, startsAt: Date? = nil, endsAt: Date? = nil) {
        self.title = title; self.content = content; self.status = status; self.notifyMode = notifyMode; self.targeting = targeting
        self.startsAt = startsAt; self.endsAt = endsAt
    }
    /// The server's rules, checked before sending; the error carries the server's reason (60 §17.4).
    public func validate() throws {
        try AnnouncementCheck.title(title); try AnnouncementCheck.content(content)
        guard targeting.isValid else { throw AnnouncementCheck.invalidTarget }
        try AnnouncementCheck.schedule(startsAt: startsAt.map(AnnouncementCheck.seconds), endsAt: endsAt.map(AnnouncementCheck.seconds))
    }
    public func requestBody() throws -> Data {
        try validate()
        return try AnnouncementCheck.encoded(self)
    }
    enum CodingKeys: String, CodingKey { case title, content, status, targeting, notifyMode = "notify_mode", startsAt = "starts_at", endsAt = "ends_at" }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title); try c.encode(content, forKey: .content); try c.encode(status, forKey: .status)
        try c.encode(notifyMode, forKey: .notifyMode); try c.encode(targeting, forKey: .targeting)
        try c.encodeIfPresent(startsAt.map(AnnouncementCheck.encodedSeconds), forKey: .startsAt)
        try c.encodeIfPresent(endsAt.map(AnnouncementCheck.encodedSeconds), forKey: .endsAt)
    }
}

/// `PUT admin/announcements/:id` (60 §17.2): only the keys that changed. `clear` sends 0, back to 立即 / 永久; `.everyone`
/// sends `{}`; a read-only multi-condition targeting stays nil and is not sent.
public struct AnnouncementUpdateRequest: Encodable, Sendable, Equatable {
    public enum Schedule: Sendable, Equatable { case clear, at(Date) }
    public var title: String?
    public var content: String?
    public var status: AnnouncementStatus?
    public var notifyMode: AnnouncementNotifyMode?
    public var targeting: AnnouncementTargeting?
    public var startsAt: Schedule?
    public var endsAt: Schedule?
    public init(title: String? = nil, content: String? = nil, status: AnnouncementStatus? = nil, notifyMode: AnnouncementNotifyMode? = nil,
                targeting: AnnouncementTargeting? = nil, startsAt: Schedule? = nil, endsAt: Schedule? = nil) {
        self.title = title; self.content = content; self.status = status; self.notifyMode = notifyMode; self.targeting = targeting
        self.startsAt = startsAt; self.endsAt = endsAt
    }
    /// Publish, archive, publish again (60 §16.4): exactly `{"status":"…"}`.
    public static func status(_ status: AnnouncementStatus) -> AnnouncementUpdateRequest { AnnouncementUpdateRequest(status: status) }
    public var isEmpty: Bool {
        title == nil && content == nil && status == nil && notifyMode == nil && targeting == nil && startsAt == nil && endsAt == nil
    }
    /// The create rules for the keys present; the server checks the merged schedule again.
    public func validate() throws {
        guard !isEmpty else { throw APIError(kind: .validation, message: "没有要保存的修改。") }
        if let title { try AnnouncementCheck.title(title) }
        if let content { try AnnouncementCheck.content(content) }
        if let targeting, !targeting.isValid { throw AnnouncementCheck.invalidTarget }
        try AnnouncementCheck.schedule(startsAt: startsAt.flatMap(Self.date).map(AnnouncementCheck.seconds),
                                       endsAt: endsAt.flatMap(Self.date).map(AnnouncementCheck.seconds))
    }
    public func requestBody() throws -> Data {
        try validate()
        return try AnnouncementCheck.encoded(self)
    }
    private static func date(_ schedule: Schedule) -> Date? { if case .at(let date) = schedule { date } else { nil } }
    enum CodingKeys: String, CodingKey { case title, content, status, targeting, notifyMode = "notify_mode", startsAt = "starts_at", endsAt = "ends_at" }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title); try c.encodeIfPresent(content, forKey: .content); try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(notifyMode, forKey: .notifyMode); try c.encodeIfPresent(targeting, forKey: .targeting)
        try c.encodeIfPresent(startsAt.map(Self.seconds), forKey: .startsAt); try c.encodeIfPresent(endsAt.map(Self.seconds), forKey: .endsAt)
    }
    private static func seconds(_ schedule: Schedule) throws -> Int64 {
        guard case .at(let date) = schedule else { return 0 }
        return try AnnouncementCheck.encodedSeconds(date)
    }
}

/// Paging and search shared by the list and the read-status query.
fileprivate enum AnnouncementQuery {
    static let searchByteLimit = 200
    static func page(_ page: Int) throws -> String {
        guard page >= 1 else { throw APIError(kind: .validation, message: "页码必须从 1 开始。") }
        return String(page)
    }
    /// Trimmed and cut to at most 200 UTF-8 bytes at a character boundary (the server cuts bytes and may split a character); nil when empty.
    static func searchTerm(_ raw: String) -> String? {
        var bytes = 0, result = ""
        for character in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            bytes += String(character).utf8.count
            guard bytes <= searchByteLimit else { break }
            result.append(character)
        }
        return result.isEmpty ? nil : result
    }
    static func items(_ values: [String: String]) -> [URLQueryItem] {
        values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
}

/// The server's write rules (service/announcement_service.go, domain/announcement.go), checked before anything is sent.
fileprivate enum AnnouncementCheck {
    /// 9999-12-31T23:59:59Z: the server rejects later years.
    static let latestSecond: Int64 = 253_402_300_799
    static let invalidTitle = APIError(kind: .validation, reason: "ANNOUNCEMENT_TITLE_INVALID", message: "标题不能为空，最多 200 字节")
    static let contentRequired = APIError(kind: .validation, reason: "ANNOUNCEMENT_CONTENT_REQUIRED", message: "请填写正文")
    static let invalidTarget = APIError(kind: .validation, reason: "ANNOUNCEMENT_INVALID_TARGET", message: "可见对象条件无效，请重新设置")
    static let invalidTimeRange = APIError(kind: .validation, reason: "ANNOUNCEMENT_TIME_RANGE_INVALID", message: "结束时间要晚于开始时间")

    static func title(_ title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= AnnouncementCreateRequest.titleByteLimit else { throw invalidTitle }
    }
    static func content(_ content: String) throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw contentRequired }
    }
    /// Whole seconds, rounded down, as sent; nil outside 1970-01-01T00:00:01Z…9999 (0 would mean 立即 / 永久).
    static func seconds(_ date: Date) -> Int64? {
        let value = date.timeIntervalSince1970.rounded(.down)
        guard value >= 1, value <= Double(latestSecond) else { return nil }
        return Int64(value)
    }
    static func encodedSeconds(_ date: Date) throws -> Int64 {
        guard let value = seconds(date) else { throw invalidTimeRange }
        return value
    }
    /// Each `Int64??`: nil = not set, .some(nil) = a time out of range. Compared after rounding, as the server sees them.
    static func schedule(startsAt: Int64??, endsAt: Int64??) throws {
        for value in [startsAt, endsAt] { if case .some(nil) = value { throw invalidTimeRange } }
        if let starts = startsAt ?? nil, let ends = endsAt ?? nil, starts >= ends { throw invalidTimeRange }
    }
    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
