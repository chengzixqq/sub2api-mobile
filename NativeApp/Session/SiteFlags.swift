import Foundation

/// Per site in UserDefaults (30 §3.4, not secret): a proxy in front of the site rewrote the X-Request-ID of a balance write,
/// so the ledger's request_id is not the App's and reconciliation matches by action_id only. Stored per site id and read
/// across the ids of one address, because the proxy belongs to the address and a new login there gets a new id (D17).
@MainActor
struct SiteFlags {
    let defaults: UserDefaults

    func requestIDUnreliable(serverID: UUID) -> Bool { defaults.bool(forKey: Self.requestIDKey(serverID)) }
    func markRequestIDUnreliable(serverID: UUID) { defaults.set(true, forKey: Self.requestIDKey(serverID)) }
    /// `serverIDs`: one address (AppModel.sameAddressServerIDs); any marked id of it decides.
    func requestIDUsable(sameAddress serverIDs: Set<UUID>) -> Bool { !serverIDs.contains { requestIDUnreliable(serverID: $0) } }
    func removeAll(serverID: UUID) { defaults.removeObject(forKey: Self.requestIDKey(serverID)) }
    /// A deleted site leaves the address set, so its flag goes to the ids still at its address (`sameAddress` may include it);
    /// the last id of an address takes the flag with it.
    func remove(serverID: UUID, handingOverTo sameAddress: Set<UUID>) {
        if requestIDUnreliable(serverID: serverID) { sameAddress.subtracting([serverID]).forEach(markRequestIDUnreliable) }
        removeAll(serverID: serverID)
    }

    static func requestIDKey(_ serverID: UUID) -> String { "site.requestIDUnreliable." + serverID.uuidString }
}
