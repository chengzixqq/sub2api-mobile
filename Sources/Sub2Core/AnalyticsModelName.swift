import Foundation

/// 40 §4.3: a model name of `dashboard/models` as one rank row shows it. The mapping source names a row “a -> b” (the backend's
/// requested || ' -> ' || upstream): the row shows a and its detail line starts with “→ b”. The model page and its usage
/// records go by the raw name (S4D2b-11; S4-19 extends this type).
public struct AnalyticsModelName: Hashable, Sendable {
    public static let arrow = " -> "
    public static let unnamed = "未命名"

    /// As sent; “a -> b” for the mapping source.
    public let raw: String
    public let source: ModelSource
    /// The mapping source split at its first “ -> ” with both sides non-blank: a; otherwise the raw name.
    public let requested: String
    /// The same split's b (“b -> c” for “a -> b -> c”); otherwise nil.
    public let upstream: String?

    /// nil reads as "".
    public init(_ raw: String?, source: ModelSource) {
        let raw = raw ?? ""
        self.raw = raw
        self.source = source
        if source == .mapping, let arrow = raw.range(of: Self.arrow) {
            let requested = raw[..<arrow.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let upstream = raw[arrow.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !requested.isEmpty, !upstream.isEmpty {
                self.requested = requested
                self.upstream = upstream
                return
            }
        }
        requested = raw
        upstream = nil
    }

    /// 未命名 for a blank name.
    public var displayName: String { isBlank ? Self.unnamed : requested }
    public var isBlank: Bool { requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
