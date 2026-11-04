import Foundation
import Sub2Core

/// “Open this site's login page” (00 §1.1, §1.7.4, §3.2): after its credential was cleared or its session ended, with the
/// original sign-in method preselected and the reason shown above the form.
struct LoginPrompt: Identifiable, Equatable, Sendable {
    let id = UUID()
    let profile: ServerProfile
    let notice: String?
    /// False while the site has records awaiting reconciliation: another administrator signing in under the same site id
    /// could retry them under the same key (D17), so the login becomes a new site instead.
    let reusesSiteID: Bool

    /// The site this login is saved as: the same id (device ID, push records and list fields kept) only for the same address.
    func profile(name: String, url: URL, authentication: AuthenticationKind) -> ServerProfile {
        guard reusesSiteID, url == profile.baseURL else { return ServerProfile(name: name, baseURL: url, authentication: authentication) }
        return ServerProfile(id: profile.id, name: name, baseURL: url, authentication: authentication)
    }
}
