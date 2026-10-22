import Foundation

/// 10 §0.5: the state of one data block. In `loading` and `failed`, `previous` and `at` are the last successful value
/// and its time; both are present or both are absent.
public enum BlockState<Value: Sendable>: Sendable {
    case idle
    case loading(previous: Value?, at: Date?)
    case loaded(Value, at: Date)
    /// A backend reason such as OPS_DISABLED or CHANNEL_MONITOR_DISABLED; the page owns the wording.
    case disabled(reason: String)
    /// `reason` is display text from the catalog, never the server message.
    case failed(reason: String?, previous: Value?, at: Date?)

    public var value: Value? {
        switch self {
        case .loading(let previous, _), .failed(_, let previous, _): previous
        case .loaded(let value, _): value
        case .idle, .disabled: nil
        }
    }
    public var updatedAt: Date? {
        switch self {
        case .loading(_, let at), .failed(_, _, let at): at
        case .loaded(_, let at): at
        case .idle, .disabled: nil
        }
    }
    public var isLoading: Bool {
        if case .loading = self { true } else { false }
    }
    public var failureReason: String? {
        if case .failed(let reason, _, _) = self { reason } else { nil }
    }
    public var disabledReason: String? {
        if case .disabled(let reason) = self { reason } else { nil }
    }

    public func withLoading() -> BlockState { .loading(previous: value, at: updatedAt) }
    public func withFailure(_ reason: String?) -> BlockState { .failed(reason: reason, previous: value, at: updatedAt) }
    /// A cancelled or superseded load returns to the last success, or to idle; other states are kept.
    public func withCancelledLoad() -> BlockState {
        guard case .loading(let previous, let at) = self else { return self }
        guard let previous, let at else { return .idle }
        return .loaded(previous, at: at)
    }

    /// 10 §0.5 display rule: show the value whenever there is one; a failed refresh keeps it.
    public var display: BlockDisplay<Value> {
        switch self {
        case .idle: return .placeholder
        case .loading(let previous, let at):
            guard let previous else { return .placeholder }
            return .value(previous, at: at, isRefreshing: true, updateFailed: false)
        case .loaded(let value, let at): return .value(value, at: at, isRefreshing: false, updateFailed: false)
        case .disabled(let reason): return .disabled(reason: reason)
        case .failed(let reason, let previous, let at):
            guard let previous else { return .failed(reason: reason) }
            return .value(previous, at: at, isRefreshing: false, updateFailed: true)
        }
    }
}

extension BlockState: Equatable where Value: Equatable {}

public enum BlockDisplay<Value: Sendable>: Sendable {
    /// Idle or first load: skeleton or “正在加载…”, never 0.
    case placeholder
    /// `updateFailed` adds “更新失败” beside the block title; the numbers stay.
    case value(Value, at: Date?, isRefreshing: Bool, updateFailed: Bool)
    /// No earlier value: number slots show “—” and the block shows “加载失败 · 重试”.
    case failed(reason: String?)
    case disabled(reason: String)
}

extension BlockDisplay: Equatable where Value: Equatable {}

/// 00 §2.7.2 and §4.6: a block that got 429 sends nothing before `notBefore`; consecutive failures stretch its polling.
public struct BlockRefresh: Sendable, Equatable {
    public static let maximumInterval: TimeInterval = 300
    public let notBefore: Date?
    public let consecutiveFailures: Int

    public init() { self.init(notBefore: nil, consecutiveFailures: 0) }
    private init(notBefore: Date?, consecutiveFailures: Int) {
        self.notBefore = notBefore; self.consecutiveFailures = consecutiveFailures
    }

    /// Doubles per consecutive failure, at most 300 seconds (60 → 120 → 240 → 300); a success restores `base`.
    public static func nextRefreshInterval(base: TimeInterval = 60, consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return base }
        return min(base * pow(2, Double(min(consecutiveFailures, 16))), max(base, maximumInterval))
    }

    public func allowsRequest(at now: Date) -> Bool { notBefore.map { now >= $0 } ?? true }
    public func recordingSuccess() -> BlockRefresh { BlockRefresh() }
    /// A 429 waits `retry_after` (default 30 seconds); any other failure only counts toward the backoff.
    public func recordingFailure(_ error: any Error, at now: Date) -> BlockRefresh {
        let limited = (error as? APIError).flatMap { $0.statusCode == 429 ? $0 : nil }
        let wait = limited.map { TimeInterval($0.retryAfter ?? RetryAfter.rateLimitDefault) }
        return BlockRefresh(notBefore: wait.map(now.addingTimeInterval), consecutiveFailures: consecutiveFailures + 1)
    }
    /// “请求过于频繁，N 秒后自动重试” while a 429 wait lasts, N rounded up.
    public func throttleMessage(at now: Date) -> String? {
        remainingWait(at: now).map { "请求过于频繁，\(Int($0)) 秒后自动重试" }
    }
    /// The next polling delay: the rest of a 429 wait, otherwise the backed-off interval.
    public func nextDelay(base: TimeInterval = 60, at now: Date) -> TimeInterval {
        remainingWait(at: now) ?? Self.nextRefreshInterval(base: base, consecutiveFailures: consecutiveFailures)
    }
    private func remainingWait(at now: Date) -> TimeInterval? {
        guard let notBefore, notBefore > now else { return nil }
        return max(1, notBefore.timeIntervalSince(now).rounded(.up))
    }
}
