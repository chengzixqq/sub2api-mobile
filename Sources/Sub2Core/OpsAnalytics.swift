import Foundation

// MARK: - 运维图表共用的范围与筛选（40 §1.2，S4-10）

/// The range and filters of every `ops/dashboard/*` chart (40 §1.2). Whether the site may filter by model is passed by the
/// caller, so a value also serves as a cache key.
public struct OpsQuery: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var groupID: Int?
    public var model: String?
    public var modelSource: ModelSource?

    public init(start: Date, end: Date, groupID: Int? = nil, model: String? = nil, modelSource: ModelSource? = nil) {
        self.start = start; self.end = end; self.groupID = groupID; self.model = model; self.modelSource = modelSource
    }

    /// UTC `Z` range and `group_id`; `model` + `model_source` only with the capability and a requested / upstream source (the
    /// server answers 400 for mapping, even without a model). Never `mode` (unread by the server) or `timezone`.
    public func queryItems(supportsModelFilter: Bool) -> [URLQueryItem] {
        var items = ServerTime.timeRangeItems(start: start, end: end)
        if let groupID { items.append(URLQueryItem(name: "group_id", value: String(groupID))) }
        if let name = appliedModel(supportsModelFilter: supportsModelFilter) {
            items += [URLQueryItem(name: "model", value: name), URLQueryItem(name: "model_source", value: (modelSource ?? .requested).rawValue)]
        }
        return items
    }

    /// A model filter is set but cannot be sent (mapping or no capability): the card header says it shows the whole site.
    /// False without a model filter.
    public func isSiteWide(supportsModelFilter: Bool) -> Bool {
        trimmedModel != nil && appliedModel(supportsModelFilter: supportsModelFilter) == nil
    }

    /// The server answers both cases with a 400 without a reason; every ops request checks this before sending.
    public func validate() throws {
        guard start < end, (groupID ?? 1) > 0 else { throw APIError(kind: .validation, message: "请选择有效的时间范围与分组。") }
    }

    private var trimmedModel: String? {
        guard let name = model?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }
    private func appliedModel(supportsModelFilter: Bool) -> String? {
        supportsModelFilter && modelSource != .mapping ? trimmedModel : nil
    }
}

extension OpsQuery {
    /// 40 §1.4: the last `hours` ending at `now` floored to a whole minute. Pass `serverClock.now()` (S0-07).
    public static func trailingWindow(hours: Int, endingAt now: Date, groupID: Int? = nil, model: String? = nil,
                                      modelSource: ModelSource? = nil) -> OpsQuery {
        let end = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        return OpsQuery(start: end.addingTimeInterval(-Double(hours) * 3_600), end: end, groupID: groupID, model: model, modelSource: modelSource)
    }
}

// MARK: - 运维趋势的桶长（40 §1.4、§2.2）

/// The bucket of every ops trend; the server picks it from the window length.
public enum OpsBucket: String, CaseIterable, Sendable {
    case minute = "1m", fiveMinutes = "5m", hour = "1h"
    public var seconds: TimeInterval {
        switch self { case .minute: 60; case .fiveMinutes: 300; case .hour: 3_600 }
    }
    public var label: String {
        switch self { case .minute: "1 分钟"; case .fiveMinutes: "5 分钟"; case .hour: "1 小时" }
    }
    /// The server's pickThroughputBucketSeconds: up to 2 hours 60 seconds, up to 24 hours 300 seconds, longer 3600 seconds.
    public static func forWindow(_ window: TimeInterval) -> OpsBucket {
        if window <= 7_200 { return .minute }
        return window <= 86_400 ? .fiveMinutes : .hour
    }
    /// A known label wins; a missing or unknown one is derived from the window.
    public static func resolve(_ label: String?, window: TimeInterval) -> OpsBucket {
        label.flatMap(OpsBucket.init(rawValue:)) ?? forWindow(window)
    }
    /// Bucket starts on whole multiples of the UTC epoch, as the server fills empty buckets: the first may begin before `start`
    /// and the last end after `end`.
    public func starts(from start: Date, to end: Date) -> [Date] {
        guard start < end else { return [] }
        let first = (start.timeIntervalSince1970 / seconds).rounded(.down)
        let last = (end.timeIntervalSince1970 / seconds).rounded(.up) - 1
        return stride(from: first, through: last, by: 1).map { Date(timeIntervalSince1970: $0 * seconds) }
    }
}

// S4-11 在此之后追加四个运维图表的模型与 APIClient 扩展。
