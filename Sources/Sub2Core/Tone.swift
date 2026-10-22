import Foundation

/// 00 §8.2.2 semantic tone. The colours are added in NativeApp/Design/Palette.swift (`base` / `ink` / `wash`).
public enum Tone: String, Sendable, CaseIterable {
    case ok, caution, critical, neutral, model

    /// 00 §8.1: only caution, critical and model rows, cards and banners draw the status capsule.
    public var drawsRail: Bool { self == .caution || self == .critical || self == .model }

    /// Design `codeTone`: 2xx ok, 429 caution, every other code critical; a missing or impossible code is neutral.
    public static func httpStatus(_ code: Int?) -> Tone {
        guard let code, (100...599).contains(code) else { return .neutral }
        if (200..<300).contains(code) { return .ok }
        return code == 429 ? .caution : .critical
    }

    /// 10 §0.6 `alertTone`: only firing events have a tone; P0 critical, P3 neutral, P1 / P2 and unknown levels caution.
    public static func alert(severity: String?, status: String?) -> Tone? {
        guard status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "firing" else { return nil }
        switch severity?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "P0": return .critical
        case "P3": return .neutral
        default: return .caution
        }
    }
}

/// Backend `service.AccountScheduleState` values (account_status_summary.go); `allCases` follows the design's STATE_ORDER.
public enum AccountScheduleState: String, Sendable, CaseIterable {
    case error, overloaded
    case rateLimited = "rate_limited"
    case tempUnschedulable = "temp_unschedulable"
    case paused, inactive, available

    /// 00 §8.1 status words.
    public var label: String {
        switch self {
        case .error: "错误"
        case .overloaded: "过载中"
        case .rateLimited: "限流中"
        case .tempUnschedulable: "临时不可调度"
        case .paused: "暂停"
        case .inactive: "停用"
        case .available: "正常"
        }
    }
    /// 10 §0.6, design STATE_META.
    public var tone: Tone {
        switch self {
        case .error, .overloaded: .critical
        case .rateLimited, .tempUnschedulable: .caution
        case .paused, .inactive: .neutral
        case .available: .ok
        }
    }
}
