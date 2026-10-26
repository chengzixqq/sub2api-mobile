import Foundation

/// The App's only request-type table (S4D1-07). `admin/usage` rows send the name, ops error rows the backend's number
/// (service/usage_log.go: 0 unknown, 1 sync, 2 stream, 3 ws_v2, 4 cyber, 5 live). `unknown` is not a type: it shows “—”.
public enum UsageRequestType: String, CaseIterable, Hashable, Sendable {
    // allCases is the fixed row order of the request-type chart (40 §2.3).
    case stream, sync, wsV2 = "ws_v2", cyber, live

    public init?(code: Int16) {
        switch code {
        case 1: self = .sync
        case 2: self = .stream
        case 3: self = .wsV2
        case 4: self = .cyber
        case 5: self = .live
        default: return nil
        }
    }
    /// Lists, filters and charts (40 §0.4).
    public var title: String {
        switch self {
        case .stream: "流式"
        case .sync: "同步"
        case .wsV2: "WS"
        case .cyber: "安全策略"
        case .live: "Live"
        }
    }
    /// The request detail's “方式” row (40 §7.3).
    public var detailTitle: String {
        switch self {
        case .stream: "流式"
        case .sync: "非流式"
        case .wsV2: "WebSocket"
        case .cyber: "安全策略"
        case .live: "Live"
        }
    }
}
