import Foundation

extension APIClient {
    /// 00 §1.7.5 step 1, §7.6: done before signing out, because revoking a session does not remove its device. Stage 6 adds
    /// registration, subscriptions and tests to this file (60 §7.7).
    public func deletePushDevice(id: Int) async throws {
        let _: EmptyReply = try await request("admin/push/devices/\(validID(id))", method: "DELETE")
    }
}
