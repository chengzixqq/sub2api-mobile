import Foundation

/// C-30 (X31): the log row's “首字/耗时”. Kept beside DisplayFormat.swift, whose body is frozen.
extension DisplayFormat {
    /// "1.2s/3.2s" in the list style (40 §0.5); a missing or negative part is "—" ("—/3.2s" without a first token), and a
    /// row with neither is a single "—".
    public static func firstTokenAndDuration(firstTokenMs: Int?, durationMs: Int?) -> String {
        let first = duration(firstTokenMs, style: .list), total = duration(durationMs, style: .list)
        guard first != missing || total != missing else { return missing }
        return first + "/" + total
    }
}
