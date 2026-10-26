import Foundation

extension APIClient {
    /// `POST :id/recover-state` (20 §5.2): nil sends no body and leaves the switch alone; true / false set it as well. Unkeyed and
    /// sent once. 500 ACCOUNT_RECOVERED_SCHEDULABLE_FAILED (recovered, still paused) is thrown as is: the caller reads `GET :id`
    /// back and goes by its `schedulable`.
    public func recoverAccountState(id: Int, schedulable: Bool?) async throws -> UpstreamAccount {
        let path = try accountPath(id, "/recover-state")
        let body = try schedulable.map { try encode(["schedulable": $0]) }
        return try await request(path, method: "POST", body: body)
    }
}
