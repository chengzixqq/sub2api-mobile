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
    /// 60 §8.3: a code redeemed and later expired or disabled still counts as used.
    public var isRedeemed: Bool { status == "used" || usedBy != nil }

    enum CodingKeys: String, CodingKey {
        case id, code, type, value, status, notes
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
    }
}

/// `GET admin/redeem-codes` filters used so far; stage 6 adds `types` and `status` here (R19).
public struct RedeemCodeListQuery: Equatable, Sendable {
    public var search: String
    public var batchID: UUID?
    public var pageSize: Int
    public var sortBy: String
    public var ascending: Bool
    public init(search: String = "", batchID: UUID? = nil, pageSize: Int = 50, sortBy: String = "id", ascending: Bool = false) {
        self.search = search; self.batchID = batchID; self.pageSize = pageSize; self.sortBy = sortBy; self.ascending = ascending
    }
    public func queryItems(page: Int) throws -> [URLQueryItem] {
        guard page > 0, (1...PageSize.maximum).contains(pageSize), !sortBy.isEmpty else {
            throw APIError(kind: .validation, message: "兑换码的查询条件无效。")
        }
        var values = ["page": String(page), "page_size": String(pageSize), "sort_by": sortBy, "sort_order": ascending ? "asc" : "desc"]
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty { values["search"] = search }
        if let batchID { values["batch_id"] = batchID.uuidString.lowercased() }
        return values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
}

/// What one `POST admin/redeem-codes/generate` asks for (60 §10.2). Stage 6 adds the full form rules (60 §10: count 1–100,
/// expiry 1–3650 days, notes ≤ 1000, balance at most 2 decimals); this item only needs the body and the basic checks.
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
    public func redeemCodes(page: Int, query: RedeemCodeListQuery) async throws -> Page<AdminRedeemCode> {
        try await request("admin/redeem-codes", query: query.queryItems(page: page))
    }
}
