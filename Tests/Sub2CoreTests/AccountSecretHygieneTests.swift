import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// S2-23 凭据专项复核: an account's secrets never reach a printed or encoded form, and the PUT fallback (S2-05, S2-16) sends only
// the key it changes. Every value here is made up.

private let legacyAccountJSON = #"""
{"id":12,"name":"主号","platform":"anthropic","type":"apikey","status":"active","schedulable":true,
 "credentials":{"api_key":"sk-test-SECRET-1","refresh_token":"rt-SECRET-2","access_token":"at-SECRET-3",
                "service_account_json":"{\"private_key\":\"SECRET-4\"}","aws_secret_access_key":"SECRET-5",
                "base_url":"https://api.example.invalid","model_mapping":{"a":"a"}},
 "extra":{"openai_passthrough":true},
 "proxy":{"id":3,"name":"代理","protocol":"socks5","host":"proxy.example.invalid","port":1080,"username":"u","password":"SECRET-6"}}
"""#

private func printedForms(_ value: Any) -> [String] {
    var dumped = ""
    dump(value, to: &dumped)
    return [String(describing: value), String(reflecting: value), dumped, "\(value)"]
}

@Test func accountTextFormsNeverCarrySecrets() throws {
    let account = try JSONDecoder().decode(UpstreamAccount.self, from: Data(legacyAccountJSON.utf8))
    #expect(account.credentialsStatus?["has_api_key"] == true && account.credentialsStatus?["has_access_token"] == true)
    let wrapped: [Any] = [account, VersionedAccount(account: account, etag: "\"cv-3\""),
                          AccountListPage(items: [account], total: 1, page: 1, pageSize: 500, pages: 1), [account]]
    for value in wrapped {
        for form in printedForms(value) { #expect(!form.contains("SECRET"), "\(type(of: value))") }
    }
    // Credentials are read but never encoded, not even the non-secret keys.
    let encoded = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)
    #expect(!encoded.contains("SECRET") && !encoded.contains("\"credentials\":") && encoded.contains("has_api_key"))
}

/// The PATCH body is the one place a new key appears, once; every printed form of the request and of what holds it shows names.
@Test func patchRequestAndItsHoldersPrintKeyNamesOnly() throws {
    let account = try JSONDecoder().decode(UpstreamAccount.self, from: Data(legacyAccountJSON.utf8))
    let request = AccountPatchRequest(credentialsPatch: ["api_key": .set(.string("sk-test-SECRET-9"))])
    let change = AccountEditChange(fieldNames: ["API Key"], request: request, undo: nil)
    let attempt = AccountPatchAttempt(accountID: 12, base: AccountEditBase(account: account, etag: "\"cv-3\""), request: request)
    for value in [request, [request], change, attempt, [attempt]] as [Any] {
        for form in printedForms(value) { #expect(!form.contains("SECRET"), "\(type(of: value))") }
    }
    let body = String(decoding: try request.requestBody(), as: UTF8.self)
    #expect(body.components(separatedBy: "sk-test-SECRET-9").count == 2)
}

/// 20 §6.4 (S2-16) without `accounts.patch`: back to the official address deletes base_url alone, a new key adds api_key alone; the
/// other non-secret keys stay and no secret, credentials_status entry or credentials_patch goes back.
@Test func putFallbackTouchesOnlyTheTargetKeyAndNeverEchoesSecrets() throws {
    let base = try JSONDecoder().decode(UpstreamAccount.self, from: Data(#"""
    {"id":12,"name":"主号","platform":"openai","type":"apikey","status":"active","schedulable":true,
     "credentials":{"base_url":"https://relay.example.invalid/v1","model_mapping":{"a":"a"},"pool_mode":true,"custom_error_codes":[429]},
     "credentials_status":{"has_api_key":true}}
    """#.utf8))
    func credentials(_ patch: [String: JSONPatchValue]) throws -> [String: Any] {
        let body = try AccountPatchRequest(credentialsPatch: patch).fullUpdateBody(base: base)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["credentials_patch"] == nil && object["credentials_status"] == nil)
        return try #require(object["credentials"] as? [String: Any])
    }
    let official = try credentials(["base_url": .delete])
    #expect(Set(official.keys) == ["model_mapping", "pool_mode", "custom_error_codes"])
    let replaced = try credentials(["api_key": .set(.string("sk-test-NEW"))])
    #expect(Set(replaced.keys) == ["base_url", "model_mapping", "pool_mode", "custom_error_codes", "api_key"])
    for keys in [Set(official.keys), Set(replaced.keys).subtracting(["api_key"])] {
        #expect(keys.isDisjoint(with: UpstreamAccount.sensitiveCredentialKeys) && !keys.contains { $0.hasPrefix("has_") })
    }
    let request = AccountPatchRequest(credentialsPatch: ["api_key": .set(.string("sk-test-NEW"))])
    let first = try request.fullUpdateBody(base: base), second = try request.fullUpdateBody(base: base)
    #expect(first == second)
    #expect(String(decoding: first, as: UTF8.self).components(separatedBy: "sk-test-NEW").count == 2)
}
