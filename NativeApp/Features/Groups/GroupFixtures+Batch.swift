import Foundation
import Sub2Core

/// 50 §5 `-ui-testing` (S5-09, X44): the per-item results page's own fixture. Its sends otherwise go through the session's
/// member writer onto GroupFixtures+Members, `-ui-group-batch-partial` included.
extension GroupFixtures {
    /// S5D2a-12: every retry and undo of the page is lost on the way (the writer is not called), so the red line shows and the
    /// items stay.
    static let batchRetryOffline = "-ui-group-batch-retry-offline"

    static func batchSend(arguments: [String] = ProcessInfo.processInfo.arguments, write: @escaping GroupBatchEndpoints.Send) -> GroupBatchEndpoints.Send {
        guard arguments.contains(batchRetryOffline) else { return write }
        return { _ in .unconfirmed }
    }
}
