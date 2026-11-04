import Foundation
import Sub2Core

/// 00 §3.4 rule 2 (D29): the “详情” of the root alert — S0-02's diagnostics plus the time in UTC. Built only from what
/// `APIError` keeps, so the server's message and metadata values never reach it.
struct ErrorDetails: Identifiable, Sendable, Equatable {
    struct Row: Identifiable, Sendable, Equatable {
        /// The `error.details.*` identifier suffix.
        let id: String
        let label: String
        let value: String
    }
    let id = UUID()
    /// The alert text these details belong to (the catalog wording, never the server's).
    let message: String
    let rows: [Row]

    /// nil for anything but an `APIError`: a cancellation or a local failure has nothing to report to the site owner.
    init?(_ error: any Error, occurredAt: Date = Date()) {
        guard let error = error as? APIError else { return nil }
        message = error.localizedDescription
        let diagnostics = zip(["status", "reason", "request-id"], error.diagnostics).map { Row(id: $0, label: $1.label, value: $1.value) }
        rows = diagnostics + [Row(id: "time", label: "时间", value: ServerTime.utcTimestamp(occurredAt))]
    }

    /// What “复制详情” puts on the pasteboard.
    var text: String { rows.map { "\($0.label)：\($0.value)" }.joined(separator: "\n") }
}
