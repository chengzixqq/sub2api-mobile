import Foundation

/// C-26, D17 (S6D2a-04): an older login is a saved site whose credential was cleared and that still holds money records, beside
/// another saved site of the same address. Signing in to it again would make yet another site id (D17), so the site list leads
/// to the same address's site instead, and the login page's pending rows lead to a saved site of the record's address: its
/// records are then checked with the current identity in 设置 → 待核对. Only an address without a saved site opens its Web.
public enum OldLoginPresentation {
    /// Where a pending row of the login page leads.
    public enum RootAction: Equatable, Sendable {
        case signIn(ServerProfile)
        case openOriginalSite(URL)
        /// The record's site is not known at all.
        case none
    }

    public static let rootSectionTitle = "待核对"
    public static let rootFootnote = "以下写入保留原操作编号，结果还没确认。登录同一地址的站点后在“设置 → 待核对”里核对；地址已不在站点列表里的，请在原站点 Web 后台核对，勿新建重复操作。"
    public static func signInTitle(_ site: ServerProfile) -> String { "登录「\(site.name)」后核对" }
    /// The site list's note under an older login; `isActive` when it leads to the connected site.
    public static func rowNote(target: ServerProfile, isActive: Bool) -> String {
        isActive ? "旧登录 · 记录在下方“待核对”里核对" : "旧登录 · 切换到「\(target.name)」后在“待核对”里核对"
    }

    /// The older logins of the site list and the saved site each leads to. A row counts when it is not the connected site, has
    /// records, has no credential and its address has another saved site that `target` picks; otherwise it opens its own login.
    public static func oldLogins(saved: [ServerProfile], activeID: UUID?, withRecords: Set<UUID>, withoutCredential: Set<UUID>,
                                 reusable: Set<UUID>) -> [UUID: ServerProfile] {
        var leads: [UUID: ServerProfile] = [:]
        for profile in saved where profile.id != activeID && withRecords.contains(profile.id) && withoutCredential.contains(profile.id) {
            let others = sameAddress(as: profile, in: saved).filter { $0.id != profile.id }
            leads[profile.id] = target(among: others, activeID: activeID, withoutCredential: withoutCredential, reusable: reusable)
        }
        return leads
    }

    /// The login page has no connected site: a saved site of the record's address with a credential, else one that keeps its
    /// id when signed in again, else the last of them (it then gets a new id, D17, and still checks the record, C-26).
    public static func rootAction(recordSite: ServerProfile?, saved: [ServerProfile], withoutCredential: Set<UUID>, reusable: Set<UUID>) -> RootAction {
        guard let recordSite else { return .none }
        let candidates = sameAddress(as: recordSite, in: saved)
        guard let last = candidates.last else { return .openOriginalSite(recordSite.baseURL) }
        return .signIn(target(among: candidates, activeID: nil, withoutCredential: withoutCredential, reusable: reusable) ?? last)
    }

    /// The connected site, else one with a credential, else one without records; the later in the list within a tier.
    static func target(among candidates: [ServerProfile], activeID: UUID?, withoutCredential: Set<UUID>, reusable: Set<UUID>) -> ServerProfile? {
        if let activeID, let active = candidates.first(where: { $0.id == activeID }) { return active }
        return candidates.last { !withoutCredential.contains($0.id) } ?? candidates.last { reusable.contains($0.id) }
    }
    /// The saved sites at `site`'s address, in list order (MoneyRecordOrigin's grouping, C-26).
    static func sameAddress(as site: ServerProfile, in saved: [ServerProfile]) -> [ServerProfile] {
        let ids = MoneyRecordOrigin.sameAddressIDs(of: site, among: saved)
        return saved.filter { ids.contains($0.id) }
    }
}
