import Foundation
import Sub2Core

// S2-16 凭据 fixtures: what `GET :id` says of the demo accounts' credentials, and `POST :id/refresh`.
extension DemoData {
    /// dto.RedactCredentials on a demo account's wire keys: has_<key> for its stored secrets and C10's token_status for the token
    /// accounts. Claude-官方-02's token runs out in 40 minutes and has no refresh token; OpenAI-主力-01 goes through a relay.
    static func credentialFields(_ row: [String: Any], base: Date) -> [String: Any] {
        guard let id = row["id"] as? Int, let type = row["type"] as? String else { return row }
        var json = row
        var credentials = row["credentials"] as? [String: Any] ?? [:]
        if type == "oauth" || type == "setup-token" {
            json["credentials_status"] = id == 2 ? ["has_access_token": true] : ["has_access_token": true, "has_refresh_token": true]
            json["token_status"] = demoTokenStatus(id, base: base)
        } else {
            json["credentials_status"] = ["has_api_key": true]
        }
        if id == 4 { credentials["base_url"] = "https://relay.example.com/v1" }
        json["credentials"] = credentials
        return json
    }

    /// Expiry and last refresh as offsets from `base`, in seconds.
    private static func demoTokenStatus(_ id: Int, base: Date) -> [String: Any] {
        let (expires, refreshed): (TimeInterval, TimeInterval) = switch id {
        case 2: (2_400, -26_400)
        case 3: (10_800, -18_000)
        default: (18_000, -10_800)
        }
        return ["expires_at": ServerTime.utcTimestamp(base.addingTimeInterval(expires)), "lifetime_seconds": 28_800,
                "refreshed_at": ServerTime.utcTimestamp(base.addingTimeInterval(refreshed)), "auto_refresh": id != 2]
    }
}

extension AccountDemoStore {
    /// `POST :id/refresh`: an eight-hour token from `now`. Like the server, an id the site lacks is a 404 without reason and a key
    /// account 400 NOT_OAUTH; `refreshFail` answers 500.
    func refreshToken(id: Int, now: Date, arguments: [String]) throws -> AccountRefreshResult {
        guard var account = account(id: id) else { throw APIError.server(status: 404, reason: nil) }
        guard account.isTokenAccount else { throw APIError.server(status: 400, reason: "NOT_OAUTH") }
        if arguments.contains(DemoData.AccountFixture.refreshFail) { throw APIError.server(status: 500, reason: nil) }
        account.tokenStatus = AccountTokenStatus(expiresAt: ServerTime.utcTimestamp(now.addingTimeInterval(28_800)), lifetimeSeconds: 28_800,
                                                 refreshedAt: ServerTime.utcTimestamp(now), autoRefresh: account.tokenStatus?.autoRefresh ?? true)
        replace(account)
        return AccountRefreshResult(account: account)
    }
}
