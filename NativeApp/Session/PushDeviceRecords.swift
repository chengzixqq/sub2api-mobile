import Foundation

/// Per site in UserDefaults (00 §7.6, §9.6; not secret): the push device this App registered and the ones whose deletion
/// failed. Signing out and deleting a site read them here; stage 6's PushCoordinator registers devices and retries
/// pending deletions on the next login. The switch “在本机接收推送” is kept apart from the id: signing out clears the id but
/// not the switch, so the next login registers again (00 §7.6); deleting the site clears both.
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
    /// Deleting another login of the connected site's address: the server keeps one device per token, so the device the
    /// connected site registered may be this site's too, and stays with the connected site.
    func teardownCandidates(serverID: UUID, keepingDeviceOf connected: UUID?) -> [Int] {
        let candidates = teardownCandidates(serverID: serverID)
        guard let connected, connected != serverID, let kept = registeredDeviceID(serverID: connected) else { return candidates }
        return candidates.filter { $0 != kept }
    }
    /// After signing out: nothing stays registered, failures wait for the next login.
    func apply(_ report: TeardownReport, serverID: UUID) {
        let deleted = Set(report.deletedPushDeviceIDs)
        let pending = (pendingDeletions(serverID: serverID) + report.failedPushDeviceIDs).reduce(into: [Int]()) { kept, id in
            if !deleted.contains(id) && !kept.contains(id) { kept.append(id) }
        }
        setRegisteredDeviceID(nil, serverID: serverID)
        setPendingDeletions(pending, serverID: serverID)
    }
    func isLocalPushOn(serverID: UUID) -> Bool { defaults.bool(forKey: Self.enabledKey(serverID)) }
    func setLocalPushOn(_ isOn: Bool, serverID: UUID) {
        if isOn { defaults.set(true, forKey: Self.enabledKey(serverID)) } else { defaults.removeObject(forKey: Self.enabledKey(serverID)) }
    }
    /// Deleted at last, or registered again by this phone (the server keeps one device per token).
    func resolvePendingDeletions(_ ids: [Int], serverID: UUID) {
        setPendingDeletions(pendingDeletions(serverID: serverID).filter { !ids.contains($0) }, serverID: serverID)
    }
    /// A deleted site has no next login to retry on; the receipt points to the Web instead.
    func removeAll(serverID: UUID) {
        defaults.removeObject(forKey: Self.deviceKey(serverID))
        defaults.removeObject(forKey: Self.pendingKey(serverID))
        defaults.removeObject(forKey: Self.enabledKey(serverID))
    }

    private func setPendingDeletions(_ ids: [Int], serverID: UUID) {
        if ids.isEmpty { defaults.removeObject(forKey: Self.pendingKey(serverID)) } else { defaults.set(ids, forKey: Self.pendingKey(serverID)) }
    }
    private static func deviceKey(_ serverID: UUID) -> String { "push.device." + serverID.uuidString }
    private static func pendingKey(_ serverID: UUID) -> String { "push.pendingDeletion." + serverID.uuidString }
    private static func enabledKey(_ serverID: UUID) -> String { "push.enabled." + serverID.uuidString }
}
