import Foundation

/// 10 §0.5, §1.5, 00 §2.7.2: what a data block shows beside its title, and in its one-line failure row when it has no earlier
/// value. BlockStatusAccessory and BlockFailureRow (NativeApp/Views/BlockStatusViews.swift) draw it for every page from stage 1 on.
public enum BlockStatusPresentation {
    public static let updateFailed = "更新失败"
    /// The failure reasons of BlockState, kept once in HomeBlockText (S1D1-03).
    public static let timedOut = HomeBlockText.timedOut
    public static let loadFailed = HomeBlockText.failed
    public static let retryTitle = "重试"
    public static let complianceTitle = "完成合规确认"
    public static let refreshingLabel = "正在刷新"

    public enum Accessory: Sendable, Equatable { case none, refreshing, updateFailed, timedOut, throttled(String) }
    public enum RowAction: Sendable, Equatable { case retry, waiting, completeCompliance }
    public struct FailureRow: Sendable, Equatable {
        public let text: String
        public let action: RowAction
        public init(text: String, action: RowAction) { self.text = text; self.action = action }
    }

    /// Only a block with a value shows something here; without one the failure row (or the skeleton) speaks. A refresh in flight
    /// comes first, then a 429 wait, then the failure of the last refresh.
    public static func accessory<Value: Sendable>(for state: BlockState<Value>, refresh: BlockRefresh, at now: Date) -> Accessory {
        guard state.value != nil else { return .none }
        if state.isLoading { return .refreshing }
        if let message = refresh.throttleMessage(at: now) { return .throttled(message) }
        guard let reason = state.failureReason else { return .none }
        return reason == timedOut ? .timedOut : .updateFailed
    }
    /// A 429 wait counts down with 重试 held back; a compliance refusal offers 完成合规确认 (BACKLOG); otherwise `title` and 重试.
    public static func failureRow(title: String, error: APIError?, refresh: BlockRefresh, at now: Date) -> FailureRow {
        if let message = refresh.throttleMessage(at: now) { return FailureRow(text: message, action: .waiting) }
        if let error, needsCompliance(error) { return FailureRow(text: error.localizedDescription, action: .completeCompliance) }
        return FailureRow(text: title, action: .retry)
    }
    /// 10 §1.5: a timed-out section says 加载超时, any other failure 加载失败.
    public static func failureTitle<Value: Sendable>(for state: BlockState<Value>) -> String {
        state.failureReason == timedOut ? timedOut : loadFailed
    }
    /// A 423 the administrator has not cleared yet.
    public static func needsCompliance(_ error: APIError?) -> Bool {
        guard let error else { return false }
        return SecurityInterruption(error) == .complianceRequired && error.securityOutcome != .passed
    }
}
