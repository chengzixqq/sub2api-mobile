import Foundation
import Sub2Core

// S5-07, 50 §2.2: the group detail's alert banner. Its two 24-hour counts are S1-17's alertErrorCount (R19, one errorCount).

extension LiveOpsStore {
    nonisolated static let groupBannerLimit = 5

    /// `status=firing&group_id&limit=5` (R19's alertEvents) through the ops switch's entries (S1D1-02), which record OPS_DISABLED
    /// and throw it on; filled in like every event read (S1D1-16). The server's newest first, or nil when the group has none.
    func groupFiringAlert(groupID: Int) async throws -> AlertEvent? {
        let limit = Self.groupBannerLimit
        let events = try await controlled {
            try await $0.alertEvents(status: "firing", timeRange: nil, limit: limit, before: nil, groupID: groupID, platform: nil)
        }()
        return await normalizeReceivedAlerts(events).first { $0.isFiring }
    }
}
