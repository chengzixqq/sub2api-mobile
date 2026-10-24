import Foundation

/// 10 §3.2 `rule`: the rule as it was when the event fired (OpsAlertEventRule). An `alert-rules` item decodes into the same
/// model for old servers without `ops.alert_event_details` (it has no `deleted`, which then reads false).
public struct AlertEventRule: Decodable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let metricType: String
    /// JSON `operator`: > < >= <= == !=.
    public let comparison: String
    public let threshold: Double?
    public let windowMinutes: Int
    public let sustainedMinutes: Int
    public let deleted: Bool

    public init(id: Int, name: String = "", metricType: String = "", comparison: String = "", threshold: Double? = nil, windowMinutes: Int = 0,
                sustainedMinutes: Int = 0, deleted: Bool = false) {
        self.id = id; self.name = name; self.metricType = metricType; self.comparison = comparison; self.threshold = threshold
        self.windowMinutes = windowMinutes; self.sustainedMinutes = sustainedMinutes; self.deleted = deleted
    }
    enum CodingKeys: String, CodingKey {
        case id, name, threshold, deleted
        case metricType = "metric_type", comparison = "operator", windowMinutes = "window_minutes", sustainedMinutes = "sustained_minutes"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func minutes(_ key: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0 }
        try self.init(id: c.decode(Int.self, forKey: .id), name: c.lenientString(.name), metricType: c.lenientString(.metricType),
                  comparison: c.lenientString(.comparison), threshold: try? c.decodeIfPresent(Double.self, forKey: .threshold),
                  windowMinutes: minutes(.windowMinutes), sustainedMinutes: minutes(.sustainedMinutes),
                  deleted: (try? c.decodeIfPresent(Bool.self, forKey: .deleted)) ?? false)
    }
}

/// The active silence covering an event's scope (D01). `until` is nil only when the server sent something unreadable.
public struct AlertSilenceRef: Decodable, Sendable, Equatable {
    public let id: Int
    public let until: Date?

    public init(id: Int, until: Date? = nil) { self.id = id; self.until = until }
    enum CodingKeys: String, CodingKey { case id, until }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(Int.self, forKey: .id), until: c.optionalTimestamp(.until))
    }
}

/// One `ops/alert-events` item (also `dashboard/home` `alerts.top`). Only `id` is required: every other field may be missing,
/// null or of the wrong type on an older server, and then reads as empty instead of failing the list.
public struct AlertEvent: Identifiable, Decodable, Sendable, Equatable {
    public let id: Int
    public let ruleID: Int?
    public let severity: String
    public let status: String
    /// "P1: 规则名" as the evaluator wrote it.
    public let title: String
    /// The evaluator's English summary; shown as is only when there is no rule to describe the condition.
    public let description: String
    public let metricValue: Double?
    /// Top-level `threshold_value`; the rule's own `threshold` wins when there is a rule (AlertPresentation.threshold).
    public let thresholdValue: Double?
    /// `dimensions.platform`, trimmed; nil when empty.
    public let platform: String?
    /// `dimensions.group_id`; nil unless positive.
    public let groupID: Int?
    public let firedAt: Date?
    public let resolvedAt: Date?
    public let silence: AlertSilenceRef?
    /// Whether the reply had a `silence` key at all (D01); servers before it leave the key out.
    public let silenceSupported: Bool
    public let rule: AlertEventRule?
    public let groupName: String?
    public let resolvedByUserName: String?

    public init(id: Int, ruleID: Int? = nil, severity: String = "", status: String = "", title: String = "", description: String = "",
                metricValue: Double? = nil, thresholdValue: Double? = nil, platform: String? = nil, groupID: Int? = nil, firedAt: Date? = nil,
                resolvedAt: Date? = nil, silence: AlertSilenceRef? = nil, silenceSupported: Bool = true, rule: AlertEventRule? = nil,
                groupName: String? = nil, resolvedByUserName: String? = nil) {
        self.id = id; self.ruleID = ruleID; self.severity = severity; self.status = status; self.title = title; self.description = description
        self.metricValue = metricValue; self.thresholdValue = thresholdValue; self.platform = platform; self.groupID = groupID
        self.firedAt = firedAt; self.resolvedAt = resolvedAt; self.silence = silence; self.silenceSupported = silenceSupported
        self.rule = rule; self.groupName = groupName; self.resolvedByUserName = resolvedByUserName
    }

    /// Same normalisation as `Tone.alert`, so a coloured row is always a firing one.
    public var isFiring: Bool { status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "firing" }

    /// A copy carrying `rule`, e.g. the `alert-rules` match on an old server. The original is unchanged.
    public func replacingRule(_ rule: AlertEventRule?) -> AlertEvent {
        AlertEvent(id: id, ruleID: ruleID, severity: severity, status: status, title: title, description: description, metricValue: metricValue,
                   thresholdValue: thresholdValue, platform: platform, groupID: groupID, firedAt: firedAt, resolvedAt: resolvedAt,
                   silence: silence, silenceSupported: silenceSupported, rule: rule, groupName: groupName, resolvedByUserName: resolvedByUserName)
    }

    enum CodingKeys: String, CodingKey {
        case id, severity, status, title, description, dimensions, silence, rule
        case ruleID = "rule_id", metricValue = "metric_value", thresholdValue = "threshold_value", firedAt = "fired_at"
        case resolvedAt = "resolved_at", groupName = "group_name", resolvedByUserName = "resolved_by_user_name"
    }
    private struct Dimensions: Decodable {
        let platform: String?
        let groupID: Int?
        enum CodingKeys: String, CodingKey { case platform; case groupID = "group_id" }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let trimmed = (try? c.decodeIfPresent(String.self, forKey: .platform))?.trimmingCharacters(in: .whitespacesAndNewlines)
            platform = trimmed?.isEmpty == false ? trimmed : nil
            groupID = (try? c.decodeIfPresent(Int.self, forKey: .groupID)).flatMap { $0 > 0 ? $0 : nil }
        }
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys) -> Double? { try? c.decodeIfPresent(Double.self, forKey: key) }
        func text(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
        let dimensions = try? c.decodeIfPresent(Dimensions.self, forKey: .dimensions)
        try self.init(id: c.decode(Int.self, forKey: .id), ruleID: try? c.decodeIfPresent(Int.self, forKey: .ruleID),
                  severity: c.lenientString(.severity), status: c.lenientString(.status), title: c.lenientString(.title),
                  description: c.lenientString(.description), metricValue: number(.metricValue), thresholdValue: number(.thresholdValue),
                  platform: dimensions?.platform, groupID: dimensions?.groupID, firedAt: c.optionalTimestamp(.firedAt),
                  resolvedAt: c.optionalTimestamp(.resolvedAt), silence: try? c.decodeIfPresent(AlertSilenceRef.self, forKey: .silence),
                  silenceSupported: c.contains(.silence), rule: try? c.decodeIfPresent(AlertEventRule.self, forKey: .rule),
                  groupName: text(.groupName), resolvedByUserName: text(.resolvedByUserName))
    }
}
