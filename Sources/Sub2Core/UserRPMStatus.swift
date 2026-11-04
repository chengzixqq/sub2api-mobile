import Foundation

/// `GET admin/users/:id/rpm-status` (30 §6.2, E08). Every field is read on its own; `tracked` is missing before E08.
public struct UserRPMStatus: Decodable, Sendable, Equatable {
    public struct Group: Decodable, Sendable, Equatable, Identifiable {
        public var id: Int { groupID }
        public let groupID: Int
        public let groupName: String
        public let used: Int?
        public let limit: Int?
        /// "group", "override", or "" when the group could not be read (limit and tracked are then only fallbacks).
        public let source: String?
        public let tracked: Bool?
        public init(groupID: Int, groupName: String = "", used: Int? = nil, limit: Int? = nil, source: String? = nil, tracked: Bool? = nil) {
            self.groupID = groupID; self.groupName = groupName; self.used = used; self.limit = limit; self.source = source; self.tracked = tracked
        }
        enum CodingKeys: String, CodingKey { case used, limit, source, tracked; case groupID = "group_id", groupName = "group_name" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func number(_ key: CodingKeys) -> Int? { try? c.decodeIfPresent(Int.self, forKey: key) }
            try self.init(groupID: c.decode(Int.self, forKey: .groupID), groupName: (try? c.decodeIfPresent(String.self, forKey: .groupName)) ?? "",
                          used: number(.used), limit: number(.limit), source: try? c.decodeIfPresent(String.self, forKey: .source),
                          tracked: try? c.decodeIfPresent(Bool.self, forKey: .tracked))
        }
    }
    public let userUsed: Int?
    public let userLimit: Int?
    public let userTracked: Bool?
    /// null (no key bound to a group), missing or malformed reads as [].
    public let perGroup: [Group]
    public init(userUsed: Int? = nil, userLimit: Int? = nil, userTracked: Bool? = nil, perGroup: [Group] = []) {
        self.userUsed = userUsed; self.userLimit = userLimit; self.userTracked = userTracked; self.perGroup = perGroup
    }
    enum CodingKeys: String, CodingKey {
        case userUsed = "user_rpm_used", userLimit = "user_rpm_limit", userTracked = "user_rpm_tracked", perGroup = "per_group"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(userUsed: try? c.decodeIfPresent(Int.self, forKey: .userUsed), userLimit: try? c.decodeIfPresent(Int.self, forKey: .userLimit),
                  userTracked: try? c.decodeIfPresent(Bool.self, forKey: .userTracked),
                  perGroup: (try? c.decodeIfPresent(LossyList<Group>.self, forKey: .perGroup))?.items ?? [])
    }
}

public enum UserRPMStatusReply: Sendable, Equatable {
    case status(UserRPMStatus)
    /// The whole block reads “RPM 状态暂不可用”.
    case unavailable
}

/// What the RPM block needs from `/admin/me`.
public struct UserRPMContext: Sendable, Equatable {
    public let isSimpleMode: Bool
    /// `users.rpm_tracked`: without it a limit of 0 reads as “不限 · 不计数” (E08 fallback).
    public let reportsTracking: Bool
    public init(isSimpleMode: Bool, reportsTracking: Bool) { self.isSimpleMode = isSimpleMode; self.reportsTracking = reportsTracking }
    public init(me: AdminMe?) {
        self.init(isSimpleMode: me?.isSimpleRunMode ?? false, reportsTracking: me?.has(.usersRPMTracked) ?? false)
    }
}

public struct UserRPMLine: Sendable, Equatable {
    /// Group rows only: “专属 RPM” / “分组 RPM” / “—”.
    public let label: String?
    public let value: String
    /// The user total only, when counted against a positive limit; clamped to 0…1.
    public let progress: Double?
    public let tone: Tone?
    public init(label: String?, value: String, progress: Double? = nil, tone: Tone? = nil) {
        self.label = label; self.value = value; self.progress = progress; self.tone = tone
    }
}

/// 30 §6.3 RPM 状态块.
public enum UserRPMPresentation {
    public static let title = "RPM 状态 · 本分钟"
    public static let unavailableText = "RPM 状态暂不可用"
    public static let failedText = "RPM 状态加载失败 · 重试"
    static let simpleModeText = "简易模式不计数"
    static let untrackedText = "不限 · 不计数"
    static let cautionRatio = 0.75
    static let criticalRatio = 0.9

    /// The more specific rule first: simple mode, not counted, no `users.rpm_tracked` with limit 0, missing limit, limit 0
    /// (“不限制”), then “used / limit” with a progress bar.
    public static func total(_ status: UserRPMStatus, context: UserRPMContext) -> UserRPMLine {
        if context.isSimpleMode { return UserRPMLine(label: nil, value: simpleModeText) }
        if status.userTracked == false { return UserRPMLine(label: nil, value: untrackedText) }
        guard let limit = status.userLimit else { return UserRPMLine(label: nil, value: DisplayFormat.missing) }
        if limit == 0 { return UserRPMLine(label: nil, value: context.reportsTracking ? "不限制" : untrackedText) }
        let value = DisplayFormat.grouped(status.userUsed) + " / " + DisplayFormat.grouped(limit)
        guard let used = status.userUsed, limit > 0 else { return UserRPMLine(label: nil, value: value) }
        return UserRPMLine(label: nil, value: value, progress: min(max(Double(used) / Double(limit), 0), 1), tone: tone(used: used, limit: limit))
    }
    /// The label follows `source` only. An exempt override (limit 0, not counted) is “免检”; group rows have no bar.
    public static func group(_ row: UserRPMStatus.Group, context: UserRPMContext) -> UserRPMLine {
        let label = switch row.source { case "override"?: "专属 RPM"; case "group"?: "分组 RPM"; default: DisplayFormat.missing }
        return UserRPMLine(label: label, value: groupValue(row, context: context))
    }
    public static func groupName(_ row: UserRPMStatus.Group) -> String {
        let name = row.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "分组 #\(row.groupID)" : name
    }
    /// ≥ 90% critical, ≥ 75% caution.
    public static func tone(used: Int, limit: Int) -> Tone? {
        guard limit > 0 else { return nil }
        let ratio = Double(used) / Double(limit)
        if ratio >= criticalRatio { return .critical }
        return ratio >= cautionRatio ? .caution : nil
    }
    private static func groupValue(_ row: UserRPMStatus.Group, context: UserRPMContext) -> String {
        if context.isSimpleMode { return simpleModeText }
        if row.source == "" { return DisplayFormat.missing }
        if row.tracked == false { return row.limit == 0 && row.source == "override" ? "免检" : untrackedText }
        if !context.reportsTracking && row.limit == 0 { return untrackedText }
        guard let limit = row.limit else { return DisplayFormat.missing }
        return limit == 0 ? "不限" : DisplayFormat.grouped(row.used) + " / " + DisplayFormat.grouped(limit)
    }
}

extension APIClient {
    /// A read (retried like any other). 501 RPM_STATUS_UNAVAILABLE (no RPM cache) and a site without the route (non-JSON
    /// 404) are `.unavailable`; any other failure is thrown, shown as “RPM 状态加载失败 · 重试”.
    public func userRPMStatus(id: Int) async throws -> UserRPMStatusReply {
        let path = "admin/users/\(try validID(id))/rpm-status"
        do { return .status(try await request(path)) }
        catch let error as APIError where error.isRPMStatusUnavailable { return .unavailable }
    }
}

extension APIError {
    var isRPMStatusUnavailable: Bool {
        (statusCode == 501 && reason == "RPM_STATUS_UNAVAILABLE") || (statusCode == 404 && kind == .unsupported)
    }
}
