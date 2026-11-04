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
    public private(set) var status: String
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
    public private(set) var resolvedAt: Date?
    public private(set) var silence: AlertSilenceRef?
    /// Whether the reply had a `silence` key at all (D01); servers before it leave the key out.
    public let silenceSupported: Bool
    public private(set) var rule: AlertEventRule?
    public private(set) var groupName: String?
    public let resolvedByUserName: String?
    /// The `before_*` pair for the next older page, keeping the server's fractional seconds (S1D1-04).
    public let cursor: AlertEventCursor?

    public init(id: Int, ruleID: Int? = nil, severity: String = "", status: String = "", title: String = "", description: String = "",
                metricValue: Double? = nil, thresholdValue: Double? = nil, platform: String? = nil, groupID: Int? = nil, firedAt: Date? = nil,
                resolvedAt: Date? = nil, silence: AlertSilenceRef? = nil, silenceSupported: Bool = true, rule: AlertEventRule? = nil,
                groupName: String? = nil, resolvedByUserName: String? = nil, cursor: AlertEventCursor? = nil) {
        self.id = id; self.ruleID = ruleID; self.severity = severity; self.status = status; self.title = title; self.description = description
        self.metricValue = metricValue; self.thresholdValue = thresholdValue; self.platform = platform; self.groupID = groupID
        self.firedAt = firedAt; self.resolvedAt = resolvedAt; self.silence = silence; self.silenceSupported = silenceSupported
        self.rule = rule; self.groupName = groupName; self.resolvedByUserName = resolvedByUserName
        self.cursor = cursor ?? firedAt.flatMap { id > 0 ? AlertEventCursor(firedAt: $0, id: id) : nil }
    }

    /// Same normalisation as `Tone.alert`, so a coloured row is always a firing one.
    public var isFiring: Bool { status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "firing" }

    // Local copies: every other field, the cursor included, is kept and the original is unchanged.

    /// Carrying `rule`, e.g. the `alert-rules` match on an old server.
    public func replacingRule(_ rule: AlertEventRule?) -> AlertEvent { var copy = self; copy.rule = rule; return copy }
    /// The group name an old server left out (S1D1-16); blank is nil.
    public func replacingGroupName(_ name: String?) -> AlertEvent {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        var copy = self; copy.groupName = trimmed?.isEmpty == false ? trimmed : nil; return copy
    }
    /// 10 §7.1: what a confirmed manual resolve looks like until the list is read again.
    public func resolvedLocally(at date: Date) -> AlertEvent {
        var copy = self; copy.status = Self.manualResolved; copy.resolvedAt = date; return copy
    }
    /// nil ends the silence; `silenceSupported` stays as the server reported it.
    public func withSilence(_ silence: AlertSilenceRef?) -> AlertEvent { var copy = self; copy.silence = silence; return copy }
    public static let manualResolved = "manual_resolved"

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
        let id = try c.decode(Int.self, forKey: .id)
        try self.init(id: id, ruleID: try? c.decodeIfPresent(Int.self, forKey: .ruleID),
                  severity: c.lenientString(.severity), status: c.lenientString(.status), title: c.lenientString(.title),
                  description: c.lenientString(.description), metricValue: number(.metricValue), thresholdValue: number(.thresholdValue),
                  platform: dimensions?.platform, groupID: dimensions?.groupID, firedAt: c.optionalTimestamp(.firedAt),
                  resolvedAt: c.optionalTimestamp(.resolvedAt), silence: try? c.decodeIfPresent(AlertSilenceRef.self, forKey: .silence),
                  silenceSupported: c.contains(.silence), rule: try? c.decodeIfPresent(AlertEventRule.self, forKey: .rule),
                  groupName: text(.groupName), resolvedByUserName: text(.resolvedByUserName),
                  cursor: AlertEventCursor(serverFiredAt: text(.firedAt), id: id))
    }
}

/// `alert-events/counts` (10 §6.2): firing events by level, silenced ones included. P0–P3 are always present; level names are
/// trimmed and uppercased, and other names are kept. A missing `firing` is the sum of the levels.
public struct AlertCounts: Decodable, Sendable, Equatable {
    public static let severities = ["P0", "P1", "P2", "P3"]
    public let firing: Int
    public let bySeverity: [String: Int]

    public init(firing: Int? = nil, bySeverity: [String: Int] = [:]) {
        var levels = Dictionary(uniqueKeysWithValues: Self.severities.map { ($0, 0) })
        for (name, count) in bySeverity {
            let key = Self.key(name)
            if !key.isEmpty { levels[key, default: 0] += count }
        }
        self.bySeverity = levels
        self.firing = firing ?? levels.values.reduce(0, +)
    }
    public func count(severity: String?) -> Int { bySeverity[Self.key(severity ?? "")] ?? 0 }
    private static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

    enum CodingKeys: String, CodingKey { case firing; case bySeverity = "by_severity" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(firing: try? c.decodeIfPresent(Int.self, forKey: .firing),
                  bySeverity: (try? c.decodeIfPresent([String: Int].self, forKey: .bySeverity)) ?? [:])
    }
}

/// A full `alert-silences` object (10 §7.1). `platform` is nil when the rule's scope has none (the server sends "");
/// region, reason and the audit fields are not read.
public struct AlertSilence: Identifiable, Decodable, Sendable, Equatable {
    public let id: Int
    public let ruleID: Int?
    public let platform: String?
    public let groupID: Int?
    public let until: Date?
    public var ref: AlertSilenceRef { AlertSilenceRef(id: id, until: until) }

    public init(id: Int, ruleID: Int? = nil, platform: String? = nil, groupID: Int? = nil, until: Date? = nil) {
        let trimmed = platform?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id; self.ruleID = ruleID; self.platform = trimmed?.isEmpty == false ? trimmed : nil; self.groupID = groupID; self.until = until
    }
    enum CodingKeys: String, CodingKey { case id, platform, until; case ruleID = "rule_id", groupID = "group_id" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(Int.self, forKey: .id), ruleID: try? c.decodeIfPresent(Int.self, forKey: .ruleID),
                      platform: try? c.decodeIfPresent(String.self, forKey: .platform),
                      groupID: (try? c.decodeIfPresent(Int.self, forKey: .groupID)).flatMap { $0 > 0 ? $0 : nil }, until: c.optionalTimestamp(.until))
    }
}

/// `before_fired_at` + `before_id` (10 §6.2). The server compares `fired_at` to the microsecond and one evaluation round gives
/// all its events the same `fired_at`, so the text keeps the server's own fraction (converted to UTC `Z`): a millisecond `Date`
/// would skip the older events of that round (S1D1-04). Ordered like the server's `fired_at DESC, id DESC`, ascending here.
public struct AlertEventCursor: Sendable, Equatable, Comparable {
    public let firedAt: String
    public let id: Int

    /// nil when `raw` is not an RFC3339 time or `id` is not positive.
    public init?(serverFiredAt raw: String?, id: Int) {
        guard let raw, id > 0 else { return nil }
        let fraction = raw.range(of: #"\.\d+"#, options: .regularExpression)
        let whole = fraction.map { raw.replacingCharacters(in: $0, with: "") } ?? raw
        guard let date = ServerTime.parseTimestamp(whole) else { return nil }
        let utc = ServerTime.utcTimestamp(date)
        firedAt = fraction.map { String(utc.dropLast()) + String(raw[$0]) + "Z" } ?? utc
        self.id = id
    }
    /// Millisecond precision, for fixtures and events built without a server timestamp.
    public init(firedAt: Date, id: Int) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        self.firedAt = formatter.string(from: firedAt); self.id = id
    }

    var queryItems: [URLQueryItem] { [URLQueryItem(name: "before_fired_at", value: firedAt), URLQueryItem(name: "before_id", value: String(id))] }

    /// Whole seconds first, then the fraction padded to the same width, then the id.
    public static func < (lhs: AlertEventCursor, rhs: AlertEventCursor) -> Bool {
        let (left, right) = (lhs.parts, rhs.parts)
        if left.seconds != right.seconds { return left.seconds < right.seconds }
        let width = max(left.fraction.count, right.fraction.count)
        let (leftFraction, rightFraction) = (left.fraction.padding(toLength: width, withPad: "0", startingAt: 0),
                                             right.fraction.padding(toLength: width, withPad: "0", startingAt: 0))
        if leftFraction != rightFraction { return leftFraction < rightFraction }
        return lhs.id < rhs.id
    }
    private var parts: (seconds: Substring, fraction: String) {
        let body = firedAt.dropLast()
        guard let dot = body.firstIndex(of: ".") else { return (body, "") }
        return (body[..<dot], String(body[body.index(after: dot)...]))
    }
}
