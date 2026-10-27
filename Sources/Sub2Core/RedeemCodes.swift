import Foundation

/// The four types of 60 §8–§10. CompensationType (IdempotentWrite.swift) is the balance / concurrency / subscription subset
/// that create-and-redeem accepts: an invitation code cannot be redeemed for a user. Stage 6 uses these two, no third enum.
public enum RedeemCodeType: String, Codable, CaseIterable, Sendable { case balance, concurrency, subscription, invitation }

/// `dto.AdminRedeemCode` (60 §8.2), the fields reconciliation needs; stage 6 extends it here. `type` stays a string
/// because the list also holds `admin_balance` / `admin_concurrency` rows. Old codes have no `batch_id`.
public struct AdminRedeemCode: Identifiable, Decodable, Sendable, Equatable {
    public let id: Int
    public let code: String
    public let type: String
    public let value: Decimal?
    public let status: String
    public let usedBy: Int?
    public let usedAt: Date?
    public let createdAt: Date?
    public let expiresAt: Date?
    public let groupID: Int?
    public let validityDays: Int?
    public let notes: String?
    public let batchID: UUID?
    public let createdBy: Int?
    /// Only the list carries these (60 §8.2); GET :id and the generate reply leave them out, see `keepingRelations(of:)`.
    public let user: RedeemCodeUser?
    public let group: RedeemCodeGroup?
    /// 60 §8.3: a code redeemed and later expired or disabled still counts as used.
    public var isRedeemed: Bool { status == "used" || usedBy != nil }
    /// nil for `admin_balance` / `admin_concurrency` and types this version does not know.
    public var codeType: RedeemCodeType? { RedeemCodeType(rawValue: type) }
    public var codeStatus: RedeemCodeStatus? { RedeemCodeStatus(rawValue: status) }
    /// The balance and concurrency adjustments kept as codes: never deleted from the App.
    public var isAdminAdjustment: Bool { type.hasPrefix("admin_") }
    /// A stored replay's codes are masked (`***`): the real ones are read back by id before they are shown.
    public var isRedacted: Bool { !code.contains { $0 != "*" } }

    public init(id: Int, code: String, type: String, value: Decimal? = nil, status: String, usedBy: Int? = nil, usedAt: Date? = nil,
                createdAt: Date? = nil, expiresAt: Date? = nil, groupID: Int? = nil, validityDays: Int? = nil, notes: String? = nil,
                batchID: UUID? = nil, createdBy: Int? = nil, user: RedeemCodeUser? = nil, group: RedeemCodeGroup? = nil) {
        self.id = id; self.code = code; self.type = type; self.value = value; self.status = status; self.usedBy = usedBy; self.usedAt = usedAt
        self.createdAt = createdAt; self.expiresAt = expiresAt; self.groupID = groupID; self.validityDays = validityDays; self.notes = notes
        self.batchID = batchID; self.createdBy = createdBy; self.user = user; self.group = group
    }
    /// A card refreshed through GET :id keeps the user and group the list gave it while they still match its `used_by` and
    /// `group_id` (an edit may move or clear the group); its own win when it has them.
    public func keepingRelations(of listed: AdminRedeemCode?) -> AdminRedeemCode {
        guard let listed, listed.id == id, user == nil || group == nil else { return self }
        let listedUser = listed.user.flatMap { $0.id == usedBy ? $0 : nil }
        let listedGroup = listed.group.flatMap { $0.id == groupID ? $0 : nil }
        return AdminRedeemCode(id: id, code: code, type: type, value: value, status: status, usedBy: usedBy, usedAt: usedAt, createdAt: createdAt,
                               expiresAt: expiresAt, groupID: groupID, validityDays: validityDays, notes: notes, batchID: batchID,
                               createdBy: createdBy, user: user ?? listedUser, group: group ?? listedGroup)
    }

    enum CodingKeys: String, CodingKey {
        case id, code, type, value, status, notes, user, group
        case usedBy = "used_by", usedAt = "used_at", createdAt = "created_at", expiresAt = "expires_at", groupID = "group_id"
        case validityDays = "validity_days", batchID = "batch_id", createdBy = "created_by"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); code = try c.decode(String.self, forKey: .code)
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
        value = try? c.optionalDecimal(.value)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        usedBy = try? c.decodeIfPresent(Int.self, forKey: .usedBy)
        usedAt = try c.optionalTimestamp(.usedAt); createdAt = try c.optionalTimestamp(.createdAt); expiresAt = try c.optionalTimestamp(.expiresAt)
        groupID = try? c.decodeIfPresent(Int.self, forKey: .groupID)
        validityDays = try? c.decodeIfPresent(Int.self, forKey: .validityDays)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        batchID = (try? c.decodeIfPresent(String.self, forKey: .batchID)).flatMap(UUID.init(uuidString:))
        createdBy = try? c.decodeIfPresent(Int.self, forKey: .createdBy)
        user = try? c.decodeIfPresent(RedeemCodeUser.self, forKey: .user)
        group = try? c.decodeIfPresent(RedeemCodeGroup.self, forKey: .group)
    }
}

extension AdminRedeemCode: CustomDebugStringConvertible {
    /// A code is worth money: logs and test failures show what the list shows, never the whole code.
    public var debugDescription: String {
        "AdminRedeemCode(id: \(id), code: \(RedeemPresentation.shortCode(code)), type: \(type), status: \(status))"
    }
}

/// `user` of a list row (the backend's full user DTO; only these are read).
public struct RedeemCodeUser: Decodable, Sendable, Equatable {
    public let id: Int
    public let email: String?
    public let username: String?
    public init(id: Int, email: String?, username: String?) { self.id = id; self.email = email; self.username = username }
    enum CodingKeys: String, CodingKey { case id, email, username }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        email = try? c.decodeIfPresent(String.self, forKey: .email); username = try? c.decodeIfPresent(String.self, forKey: .username)
    }
}

public struct RedeemCodeGroup: Decodable, Sendable, Equatable {
    public let id: Int
    public let name: String?
    public init(id: Int, name: String?) { self.id = id; self.name = name }
    enum CodingKeys: String, CodingKey { case id, name }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try? c.decodeIfPresent(String.self, forKey: .name)
    }
}

/// The list's status filter; the server maps an unused code past its expiry to `expired`.
public enum RedeemCodeStatus: String, CaseIterable, Sendable { case unused, used, expired, disabled }

/// `GET admin/redeem-codes` (60 §8.2, R19). `sendsTypes` is `redeem_codes.stats` (U43: G04 shipped with it). With it the
/// list sends `types`; without it one type goes out as the old `type` and “全部类型” sends none, so `admits(_:)` drops the
/// admin adjustments on the phone. `type` and `types` never go together (400 REDEEM_CODE_TYPE_CONFLICT); a batch query
/// sends neither, nor `status` (60 §8.4 查看同一批, §11.2).
public struct RedeemCodeListQuery: Equatable, Sendable {
    public var search: String
    public var batchID: UUID?
    /// nil = 全部类型.
    public var type: RedeemCodeType?
    public var status: RedeemCodeStatus?
    public var sendsTypes: Bool
    public var pageSize: Int
    public var sortBy: String
    public var ascending: Bool
    public init(search: String = "", batchID: UUID? = nil, type: RedeemCodeType? = nil, status: RedeemCodeStatus? = nil, sendsTypes: Bool = false,
                pageSize: Int = 50, sortBy: String = "id", ascending: Bool = false) {
        self.search = search; self.batchID = batchID; self.type = type; self.status = status; self.sendsTypes = sendsTypes
        self.pageSize = pageSize; self.sortBy = sortBy; self.ascending = ascending
    }
    /// What `types` carries; nil when it is not sent.
    public var types: [RedeemCodeType]? {
        guard batchID == nil, sendsTypes else { return nil }
        return type.map { [$0] } ?? RedeemCodeType.allCases
    }
    /// “全部类型” on a server without `types`: the page may hold admin adjustments that the phone leaves out.
    public var excludesAdminAdjustments: Bool { batchID == nil && !sendsTypes && type == nil }
    public func admits(_ code: AdminRedeemCode) -> Bool { !excludesAdminAdjustments || !code.isAdminAdjustment }

    public func queryItems(page: Int) throws -> [URLQueryItem] {
        guard page > 0, (1...PageSize.maximum).contains(pageSize), !sortBy.isEmpty else {
            throw APIError(kind: .validation, message: "兑换码的查询条件无效。")
        }
        var values = filters(includingStatus: true)
        values["page"] = String(page); values["page_size"] = String(pageSize); values["sort_by"] = sortBy; values["sort_order"] = ascending ? "asc" : "desc"
        return Self.items(values)
    }
    /// `GET admin/redeem-codes/stats` takes the same filters; it ignores `status` and has no paging.
    public func statsQueryItems() -> [URLQueryItem] { Self.items(filters(includingStatus: false)) }

    private func filters(includingStatus: Bool) -> [String: String] {
        var values = [String: String]()
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty { values["search"] = search }
        if let batchID {
            values["batch_id"] = batchID.uuidString.lowercased()
            return values
        }
        if let types { values["types"] = types.map(\.rawValue).joined(separator: ",") }
        else if let type { values["type"] = type.rawValue }
        if includingStatus, let status { values["status"] = status.rawValue }
        return values
    }
    private static func items(_ values: [String: String]) -> [URLQueryItem] {
        values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
}

/// `GET admin/redeem-codes/stats` (G08). A server from before it answered zeros without `by_status`; that reads as a failure,
/// so the chips show names only instead of a row of zeros.
public struct RedeemCodeStats: Decodable, Sendable, Equatable {
    public let total: Int
    public let unused: Int
    public let used: Int
    public let expired: Int
    public let disabled: Int
    public let byType: [String: Int]
    /// The balance of used balance codes.
    public let totalValueDistributed: Decimal?
    public init(total: Int, unused: Int, used: Int, expired: Int, disabled: Int, byType: [String: Int] = [:], totalValueDistributed: Decimal? = nil) {
        self.total = total; self.unused = unused; self.used = used; self.expired = expired; self.disabled = disabled
        self.byType = byType; self.totalValueDistributed = totalValueDistributed
    }
    /// nil = 全部.
    public func count(_ status: RedeemCodeStatus?) -> Int {
        switch status {
        case nil: total
        case .unused?: unused
        case .used?: used
        case .expired?: expired
        case .disabled?: disabled
        }
    }
    enum CodingKeys: String, CodingKey { case total = "total_codes", byStatus = "by_status", byType = "by_type", value = "total_value_distributed" }
    private struct StatusCounts: Decodable { let unused, used, expired, disabled: Int }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let total = try c.decode(Int.self, forKey: .total), counts = try c.decode(StatusCounts.self, forKey: .byStatus)
        self.init(total: total, unused: counts.unused, used: counts.used, expired: counts.expired, disabled: counts.disabled,
                  byType: (try? c.decodeIfPresent([String: Int].self, forKey: .byType)) ?? [:], totalValueDistributed: try? c.optionalDecimal(.value))
    }
}

/// `fields` of `POST admin/redeem-codes/batch-update` (60 §9.2, §9.4): a nil property leaves its key out; `never` and `cleared`
/// send JSON null, which clears the expiry or the group. Only the keys the sheet changed go out.
public struct RedeemBatchUpdateFields: Encodable, Sendable, Equatable {
    public enum Status: String, Sendable { case unused, disabled }
    public enum Expiry: Sendable, Equatable { case never, at(Date) }
    /// Not `none`, which would read as Optional.none at a call site.
    public enum Group: Sendable, Equatable { case cleared, id(Int) }
    public var status: Status?
    public var expiresAt: Expiry?
    public var groupID: Group?
    public var notes: String?
    public init(status: Status? = nil, expiresAt: Expiry? = nil, groupID: Group? = nil, notes: String? = nil) {
        self.status = status; self.expiresAt = expiresAt; self.groupID = groupID; self.notes = notes
    }
    /// The server rejects an empty `fields` (REDEEM_CODE_BATCH_UPDATE_EMPTY).
    public var isEmpty: Bool { status == nil && expiresAt == nil && groupID == nil && notes == nil }
    /// A redeemed code only takes new notes (409 REDEEM_CODE_USED for the rest).
    public var touchesUsedSensitiveFields: Bool { status != nil || expiresAt != nil || groupID != nil }

    enum CodingKeys: String, CodingKey { case status, notes, expiresAt = "expires_at", groupID = "group_id" }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status?.rawValue, forKey: .status)
        try c.encodeIfPresent(notes, forKey: .notes)
        switch expiresAt {
        case nil: break
        case .never?: try c.encodeNil(forKey: .expiresAt)
        case .at(let date)?: try c.encode(ServerTime.utcTimestamp(date), forKey: .expiresAt)
        }
        switch groupID {
        case nil: break
        case .cleared?: try c.encodeNil(forKey: .groupID)
        case .id(let id)?:
            guard id > 0 else { throw APIError(kind: .validation, message: "分组无效，请重新选择") }
            try c.encode(id, forKey: .groupID)
        }
    }
}

/// `DELETE admin/redeem-codes/:id`: 404 REDEEM_CODE_NOT_FOUND counts as deleted (60 §8.4).
public enum RedeemDeleteResult: Sendable, Equatable { case deleted, alreadyGone }

/// What one `POST admin/redeem-codes/generate` asks for (60 §10.2). The full form rules are RedeemGenerateForm's
/// (RedeemGenerate.swift); these basic checks stay as they are, so a record saved earlier still encodes when it is retried.
public struct RedeemGenerateSpec: Codable, Sendable, Equatable {
    public let type: RedeemCodeType
    /// USD per code, concurrency increase; 0 for subscription and invitation codes.
    public let value: Decimal
    public let count: Int
    public let groupID: Int?
    public let groupName: String?
    public let validityDays: Int?
    /// nil = never expires.
    public let expiresInDays: Int?
    public let notes: String
    public init(type: RedeemCodeType, value: Decimal, count: Int, groupID: Int? = nil, groupName: String? = nil, validityDays: Int? = nil,
                expiresInDays: Int? = nil, notes: String = "") {
        self.type = type; self.value = value; self.count = count; self.groupID = groupID; self.groupName = groupName
        self.validityDays = validityDays; self.expiresInDays = expiresInDays; self.notes = notes
    }
    /// Only balance codes add up to money.
    public var total: Decimal? { type == .balance ? value * Decimal(count) : nil }
    public func validate() throws {
        let needsValue = type == .balance || type == .concurrency
        guard count > 0, !value.isNaN, value >= 0, !needsValue || value > 0 else {
            throw APIError(kind: .validation, message: "兑换码的数量与面值必须大于 0。")
        }
    }
    /// Sorted keys, `value` a JSON number straight from Decimal (00 §6.1), `batch_id` the lowercased key (G03); fields
    /// without a value and empty notes are left out.
    public func requestBody(batchID: UUID) throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Body(batchID: batchID.uuidString.lowercased(), count: count, expiresInDays: expiresInDays, groupID: groupID,
                                       notes: notes.isEmpty ? nil : notes, type: type, validityDays: validityDays, value: value))
    }
    private struct Body: Encodable {
        let batchID: String; let count: Int; let expiresInDays: Int?; let groupID: Int?; let notes: String?; let type: RedeemCodeType
        let validityDays: Int?; let value: Decimal
        enum CodingKeys: String, CodingKey {
            case count, notes, type, value, batchID = "batch_id", expiresInDays = "expires_in_days", groupID = "group_id", validityDays = "validity_days"
        }
    }
}

/// A generate call kept on disk until its result is known (60 §11.2, R01): `id` is the batch_id and the Idempotency-Key.
public struct PendingRedeemBatch: PendingMoneyWrite, Equatable {
    public let id: UUID
    public let serverID: UUID
    public let actorUserID: Int?
    public let createdAt: Date
    public let idempotencyExpiresAt: Date?
    public let spec: RedeemGenerateSpec
    public init(id: UUID = UUID(), serverID: UUID, actorUserID: Int?, createdAt: Date = Date(), idempotencyExpiresAt: Date? = nil, spec: RedeemGenerateSpec) {
        self.id = id; self.serverID = serverID; self.actorUserID = actorUserID; self.createdAt = createdAt
        self.idempotencyExpiresAt = idempotencyExpiresAt; self.spec = spec
    }
    public var count: Int { spec.count }
    public var total: Decimal? { spec.total }
    public var summary: PendingMoneyWriteSummary { PendingMoneyWriteSummary(subject: .redeemBatch(count: count, total: total), createdAt: createdAt) }
    public func requestBody() throws -> Data { try spec.requestBody(batchID: id) }
}

extension APIClient {
    /// The list and the counts have no ETag (60 §0.2), so they never go through ConditionalCache.
    public func redeemCodes(page: Int, query: RedeemCodeListQuery) async throws -> Page<AdminRedeemCode> {
        try await request("admin/redeem-codes", query: query.queryItems(page: page))
    }
    /// Only with `redeem_codes.stats`; the caller decides.
    public func redeemCodeStats(query: RedeemCodeListQuery) async throws -> RedeemCodeStats {
        try await request("admin/redeem-codes/stats", query: query.statsQueryItems())
    }
    /// Without user and group: keep the listed ones with `keepingRelations(of:)`.
    public func redeemCode(id: Int) async throws -> AdminRedeemCode {
        try await request("admin/redeem-codes/\(validID(id))")
    }
    /// Absolute values, so no key (60 §8.4): sent once and never retried on its own (00 §2.4). Repeated ids keep their first
    /// place. Returns `updated`.
    public func updateRedeemCodes(ids: [Int], fields: RedeemBatchUpdateFields) async throws -> Int {
        var seen = Set<Int>()
        let unique = try ids.map { try validID($0) }.filter { seen.insert($0).inserted }
        guard !unique.isEmpty, !fields.isEmpty else { throw APIError(kind: .validation, message: "没有要保存的兑换码修改。") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(RedeemBatchUpdateBody(fields: fields, ids: unique))
        let reply: RedeemBatchUpdateReply = try await request("admin/redeem-codes/batch-update", method: "POST", body: body)
        return reply.updated
    }
    /// A non-JSON 404 (no such endpoint), 409 REDEEM_CODE_USED and the rest are thrown. Sent once.
    public func deleteRedeemCode(id: Int) async throws -> RedeemDeleteResult {
        let id = try validID(id)
        do {
            let _: EmptyReply = try await request("admin/redeem-codes/\(id)", method: "DELETE")
            return .deleted
        } catch let error as APIError where error.statusCode == 404 && error.reason == "REDEEM_CODE_NOT_FOUND" {
            return .alreadyGone
        }
    }
}

private struct RedeemBatchUpdateBody: Encodable { let fields: RedeemBatchUpdateFields; let ids: [Int] }
private struct RedeemBatchUpdateReply: Decodable, Sendable { let updated: Int }
