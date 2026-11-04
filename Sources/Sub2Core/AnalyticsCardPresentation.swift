import Foundation

/// 40 §1.6: what every analytics card says in place of its value, or under it once a refresh failed.
public enum AnalyticsCardText {
    public static let loadFailed = "加载失败"
    public static let timedOut = "统计较慢，加载超时"
    public static let invalidRequest = "请求参数无效"
    public static let forbidden = "当前身份无权查看"
    public static let retry = "重试本项"
    public static let updateFailed = "更新失败"

    /// “更新失败 · 显示的是 09:40 的数据”: the time of the value still shown, in the site's zone; without one only “更新失败”.
    public static func staleLine(shownAt: Date?, timeZone: TimeZone) -> String {
        guard let shownAt else { return updateFailed }
        return updateFailed + " · 显示的是 " + DisplayFormat.clock(shownAt, timeZone: timeZone) + " 的数据"
    }
}

/// A card's failure line while it has no value. A timeout (504 or the transport's) says the statistics are slow; a 400, or the
/// query's own check, is an invalid request and a 403 a refusal, neither worth retrying (40 §1.6; RequestLog already logs them);
/// anything else, 429 and 423 included, is 加载失败 with 重试本项, BlockFailureRow taking over the countdown and the compliance button.
public struct AnalyticsCardFailure: Equatable, Sendable {
    public let title: String
    public let allowsRetry: Bool

    public init(error: APIError?) {
        let failure = Self.classify(error)
        title = failure.title
        allowsRetry = failure.allowsRetry
    }

    private static func classify(_ error: APIError?) -> (title: String, allowsRetry: Bool) {
        if let error, HomeFallback.isTimeout(error) { return (AnalyticsCardText.timedOut, true) }
        if error?.statusCode == 400 || (error?.kind == .validation && error?.statusCode == nil) { return (AnalyticsCardText.invalidRequest, false) }
        if error?.statusCode == 403 { return (AnalyticsCardText.forbidden, false) }
        return (AnalyticsCardText.loadFailed, true)
    }
}

/// One of a card's small figures (账号成本 / 标准 / 利润 and the like): `value` is DisplayFormat's output, “—” when missing.
public struct AnalyticsFigure: Equatable, Identifiable, Sendable {
    public let key: String
    public let label: String
    public let value: String
    public var id: String { key }

    public init(_ key: String, label: String, value: String) {
        self.key = key; self.label = label; self.value = value
    }
}
