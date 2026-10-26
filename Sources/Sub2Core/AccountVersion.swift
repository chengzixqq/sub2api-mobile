import Foundation

/// An account with its edit version (20 §0.4-5): the detail's `ETag` ("cv-N") that a PATCH sends back as If-Match.
public struct VersionedAccount: Sendable {
    public let account: UpstreamAccount
    /// The header as sent, quotes and any `W/` kept (the server parses both); nil on a server without `accounts.patch` or for an empty header.
    public let etag: String?
    public init(account: UpstreamAccount, etag: String?) { self.account = account; self.etag = etag }
}

extension APIClient {
    /// R08: the version goes to the caller and never into ConditionalCache. `admin/accounts/:id` is off the 00 §4.2 list, so no
    /// If-None-Match is sent either (the server never answers 304 there). `account(id:)` stays for read-only use.
    public func accountWithVersion(id: Int) async throws -> VersionedAccount {
        let response: APIResponse<UpstreamAccount> = try await requestWithHeaders("admin/accounts/\(validID(id))")
        let tag = response.header("ETag")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VersionedAccount(account: response.value, etag: tag?.isEmpty == false ? tag : nil)
    }
}
