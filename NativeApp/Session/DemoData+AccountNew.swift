import Foundation
import Sub2Core

// S2-19 新建账号 fixtures: the session's AccountDemoStore takes `POST admin/accounts` like the backend's buildAccountForCreate
// (the mixed-channel 409, the default group, `schedulable`), and a few launch arguments lose or misread the answer.

extension DemoData.AccountFixture {
    /// An older server: `schedulable: false` is ignored and the account starts in the scheduler.
    static let createLegacy = "-ui-account-create-legacy"
    /// The first create is stored but its answer is lost.
    static let createUnconfirmed = "-ui-account-create-unconfirmed"
    /// The first create is lost before it is stored; the same number again goes through.
    static let createLost = "-ui-account-create-lost"
    /// The check by name after an unknown result fails too: the form stays at 结果未确认.
    static let createCheckFail = "-ui-account-create-check-fail"
    /// `meta/catalog` fails: the form falls back to the built-in list and offers 重试.
    static let newCatalogError = "-ui-account-new-catalog-error"
    /// The e-mail exchange-code reports (Gemini reports none).
    static let oauthEmail = "ops@example.com"
    /// S2-20: a new account's test fails (401, marked as an error) until its credentials are saved again.
    static let newTestFail = "-ui-account-new-test-fail"
    /// S2-20: the create answers `schedulable: true` and the first stop after it is lost on the way; the next one works.
    static let newPauseFail = "-ui-account-new-pause-fail"
}

extension AccountDemoStore {
    /// `POST admin/accounts`. The fixture's create is not failed by `writeFail`: only the stop-scheduling after it is.
    func create(_ request: AccountCreateRequest, key: UUID?, now: Date, arguments: [String]) throws -> UpstreamAccount {
        guard let body = try JSONSerialization.jsonObject(with: request.requestBody()) as? [String: Any] else { throw APIError.invalidResponse }
        let groups = defaultGroups(request)
        if !request.confirmMixedChannelRisk,
           let conflict = mixedChannelConflict(platform: request.platform, groupIDs: groups, accountID: nil, arguments: arguments) {
            throw conflict
        }
        createAttempts += 1
        let first = createAttempts == 1
        if first, arguments.contains(DemoData.AccountFixture.createLost) { throw Self.lostAnswer(key) }
        let ignoresSwitch = arguments.contains(DemoData.AccountFixture.createLegacy) || arguments.contains(DemoData.AccountFixture.newPauseFail)
        let schedulable = ignoresSwitch || (body["schedulable"] as? Bool ?? true)
        let account = try Self.created(body, id: (accounts.map(\.id).max() ?? 0) + 1, groups: groups, schedulable: schedulable, now: now, base: base)
        insert(account)
        createdIDs.insert(account.id)
        if first, arguments.contains(DemoData.AccountFixture.createUnconfirmed) { throw Self.lostAnswer(key) }
        return account
    }
    /// S2-20: under `newTestFail` a new account's test passes only once its credentials were saved again; nil leaves it to S2-14's
    /// arguments.
    func newAccountTestPasses(id: Int) -> Bool? {
        guard createdIDs.contains(id), ProcessInfo.processInfo.arguments.contains(DemoData.AccountFixture.newTestFail) else { return nil }
        return (credentialRevisions[id] ?? 0) > 0
    }

    /// CreateAccount's default group: none picked joins an active “{platform}-default” group when the site has one (U18).
    private func defaultGroups(_ request: AccountCreateRequest) -> [Int] {
        guard request.groupIDs.isEmpty else { return request.groupIDs }
        let fallback = DemoData.accountGroups.first { $0.name == "\(request.platform)-default" && $0.status == "active" }
        return fallback.map { [$0.id] } ?? []
    }
    private static func lostAnswer(_ key: UUID?) -> any Error {
        guard let key else { return APIError(kind: .transport, message: "网络连接已中断") }
        return KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: key.uuidString.lowercased(), actionID: nil, lastError: nil)
    }
    /// The account DTO the server answers: its secrets are not sent back.
    private static func created(_ body: [String: Any], id: Int, groups: [Int], schedulable: Bool, now: Date, base: Date) throws -> UpstreamAccount {
        let names = Dictionary(uniqueKeysWithValues: DemoData.accountGroups.map { ($0.id, $0.name) })
        let stamp = ServerTime.utcTimestamp(now)
        var json: [String: Any] = ["id": id, "status": "active", "schedulable": schedulable, "group_ids": groups,
                                   "groups": groups.map { ["id": $0, "name": names[$0] ?? ""] as [String: Any] }, "current_concurrency": 0,
                                   "concurrency_available": true, "created_at": stamp, "updated_at": stamp]
        for key in ["name", "notes", "platform", "type", "extra", "concurrency", "priority", "rate_multiplier", "load_factor", "expires_at",
                    "auto_pause_on_expired"] {
            if let value = body[key] { json[key] = value }
        }
        let credentials = body["credentials"] as? [String: Any] ?? [:]
        json["credentials"] = credentials.filter { ["base_url", "account_mode", "api_protocol", "aws_region", "project_id", "location"].contains($0.key) }
        if let proxyID = body["proxy_id"] as? Int, let proxy = DemoData.proxyRows(base: base).first(where: { $0["id"] as? Int == proxyID }) {
            json["proxy_id"] = proxyID
            json["proxy"] = DemoData.accountProxyWire(proxy)
        }
        return try JSONDecoder().decode(UpstreamAccount.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
