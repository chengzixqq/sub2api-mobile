import Foundation

// S1-09: the overview's whole-page state, the subtitle's refresh status and the six cells' rows (10 §0.1, §1.3.1, §1.3.2, §1.5).

/// One home block as the page sees it, whatever its value type.
public enum HomeBlockPhase: Sendable, Equatable {
    /// Idle or a first load without a value.
    case placeholder
    case value(updateFailed: Bool)
    /// Failed without an earlier value.
    case failed
    case disabled
}

extension BlockDisplay {
    public var homePhase: HomeBlockPhase {
        switch self {
        case .placeholder: .placeholder
        case .value(_, _, _, let updateFailed): .value(updateFailed: updateFailed)
        case .failed: .failed
        case .disabled: .disabled
        }
    }
}

extension HomeBlocks {
    /// The seven blocks in the server's order.
    public var phases: [HomeBlockPhase] {
        [stats.display.homePhase, rates.display.homePhase, hourly.display.homePhase, ops.display.homePhase, alerts.display.homePhase,
         availability.display.homePhase, channels.display.homePhase]
    }
}

public enum HomeScreenState: Sendable, Equatable {
    case vendorPlaceholder, skeleton, unreachable, content

    /// 10 §0.1: a vendor workspace has no site-wide overview. 10 §1.5: any value shows the page; a first load (or a retry without
    /// values) is the skeleton, never 0; nothing to show after home failed, or after every block failed, is 无法连接到站点.
    /// `requestFailed` is home's own failure (a 5xx or a 429), which leaves the blocks as they were.
    public static func resolve(isVendor: Bool, sections: [HomeBlockPhase], requestFailed: Bool) -> HomeScreenState {
        if isVendor { return .vendorPlaceholder }
        if sections.contains(where: \.hasValue) { return .content }
        if !sections.isEmpty, sections.allSatisfy({ $0 == .disabled }) { return .content }
        if requestFailed { return .unreachable }
        if sections.isEmpty || sections.contains(.placeholder) { return .skeleton }
        return .unreachable
    }

    /// 10 §1.3.1: 正在加载… before any value; 部分数据未更新 while a block or home itself failed; otherwise the last time every
    /// block succeeded, on the caller's clock.
    public static func refreshStatus(sections: [HomeBlockPhase], lastFullSuccessAt: Date?, requestFailed: Bool) -> HomeRefreshStatus {
        if !sections.contains(where: \.hasValue), sections.contains(.placeholder), !requestFailed { return .loading }
        if requestFailed || sections.contains(where: \.isFailure) { return .partial }
        return lastFullSuccessAt.map { .updated(at: $0) } ?? .loading
    }
}

/// 10 §1.3.2: 3 × 2 in the fixed order; at accessibility text sizes two columns, so no figure is cut (S1-09).
public enum HomeTickerLayout {
    public static func columnCount(isAccessibilitySize: Bool) -> Int { isAccessibilitySize ? 2 : 3 }
    /// Row by row, the order kept; fewer than one column counts as one.
    public static func rows<Cell>(_ cells: [Cell], columns: Int) -> [[Cell]] {
        let width = max(1, columns)
        return stride(from: 0, to: cells.count, by: width).map { Array(cells[$0..<min($0 + width, cells.count)]) }
    }
}

private extension HomeBlockPhase {
    var hasValue: Bool { if case .value = self { true } else { false } }
    var isFailure: Bool { self == .failed || self == .value(updateFailed: true) }
}
