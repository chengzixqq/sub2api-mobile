import Foundation

/// Per site in UserDefaults (00 §7.6, §9.6; not secret): the push device this App registered and the ones whose deletion
/// failed. Signing out and deleting a site read them here; stage 6's PushCoordinator registers devices and retries
/// pending deletions on the next login.
@MainActor
struct PushDeviceRecords {
    let defaults: UserDefaults

    func registeredDeviceID(serverID: UUID) -> Int? { defaults.object(forKey: Self.deviceKey(serverID)) as? Int }
    func setRegisteredDeviceID(_ id: Int?, serverID: UUID) { defaults.set(id, forKey: Self.deviceKey(serverID)) }
    func pendingDeletions(serverID: UUID) -> [Int] { defaults.array(forKey: Self.pendingKey(serverID)) as? [Int] ?? [] }
    /// Every device the server may still hold for this site, registered one first.
    func teardownCandidates(serverID: UUID) -> [Int] {
        let pending = pendingDeletions(serverID: serverID)
        guard let registered = registeredDeviceID(serverID: serverID) else { return pending }
        return [registered] + pending.filter { $0 != registered }
    }
    /// After signing out: nothing stays registered, failures wait for the next login.
    func apply(_ report: TeardownReport, serverID: UUID) {
        let deleted = Set(report.deletedPushDeviceIDs)
        let pending = (pendingDeletions(serverID: serverID) + report.failedPushDeviceIDs).reduce(into: [Int]()) { kept, id in
            if !deleted.contains(id) && !kept.contains(id) { kept.append(id) }
        }
        setRegisteredDeviceID(nil, serverID: serverID)
        if pending.isEmpty { defaults.removeObject(forKey: Self.pendingKey(serverID)) } else { defaults.set(pending, forKey: Self.pendingKey(serverID)) }
    }
    /// A deleted site has no next login to retry on; the receipt points to the Web instead.
    func removeAll(serverID: UUID) {
        defaults.removeObject(forKey: Self.deviceKey(serverID))
        defaults.removeObject(forKey: Self.pendingKey(serverID))
    }

    private static func deviceKey(_ serverID: UUID) -> String { "push.device." + serverID.uuidString }
    private static func pendingKey(_ serverID: UUID) -> String { "push.pendingDeletion." + serverID.uuidString }
}
