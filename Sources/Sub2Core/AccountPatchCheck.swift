import Foundation

/// One field an edit changes: a top-level member, or one key of `credentials` / `extra`.
enum AccountPatchField: Hashable, Sendable {
    case top(AccountPatchRequest.CodingKeys), credential(String), extra(String)
    /// The detail never shows a secret, so it can be neither compared nor read back.
    var isSecret: Bool {
        guard case .credential(let key) = self else { return false }
        return AccountCredentialKeys.isSensitive(key)
    }
}

/// 20 §0.4-6, decided after a 412 against the fresh `GET :id` (with its new ETag).
public enum AccountPatchConflict: Sendable, Equatable {
    /// Every field already holds its target and none is a secret: the first send went through; nothing is resent.
    case alreadyApplied
    /// Each field still holds the value the sheet opened with, or the target: resend once with the new ETag.
    case silentRetry
    /// Someone set a field to a third value: ask (“账号已被其他人修改”).
    case askUser
    /// Fields the request does not change are not looked at; a secret can be compared on neither side and never conflicts.
    public static func resolve(base: UpstreamAccount, current: UpstreamAccount, request: AccountPatchRequest) -> AccountPatchConflict {
        var applied = true
        for (field, target) in request.patchTargets() {
            guard !field.isSecret else { applied = false; continue }
            let now = current.patchValue(field)
            guard now != target else { continue }
            applied = false
            if now != base.patchValue(field) { return .askUser }
        }
        return applied ? .alreadyApplied : .silentRetry
    }
    /// `metadata.current_etag` of 412 ACCOUNT_VERSION_CONFLICT.
    public static func currentETag(in error: APIError) -> String? {
        guard error.statusCode == 412, error.reason == AccountWriteReason.versionConflict,
              let tag = error.metadata["current_etag"]?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty else { return nil }
        return tag
    }
}

/// 20 §0.4-5 / 00 §2.4 read-back after a timeout: every changed field already holds its target. A new secret cannot be seen in
/// the reply, so such an edit never counts as confirmed this way.
public enum AccountPatchReadback {
    public static func matches(account: UpstreamAccount, request: AccountPatchRequest) -> Bool {
        request.patchTargets().allSatisfy { field, target in !field.isSecret && account.patchValue(field) == target }
    }
}

extension AccountPatchRequest {
    /// What each changed field should read afterwards, in comparable form; `confirm_mixed_channel_risk` is not a field.
    func patchTargets() -> [(field: AccountPatchField, value: JSONValue?)] {
        let top = topLevelValues.map { (field: AccountPatchField.top($0.key), value: PatchComparable.normalized($0.key, $0.value)) }
        let credentials = credentialsPatch.map { (field: AccountPatchField.credential($0.key), value: PatchComparable.target($0.value)) }
        let extra = extraPatch.map { (field: AccountPatchField.extra($0.key), value: PatchComparable.target($0.value)) }
        return top + credentials + extra
    }
}

extension UpstreamAccount {
    /// The field as the detail shows it, in the same comparable form as `patchTargets()`.
    func patchValue(_ field: AccountPatchField) -> JSONValue? {
        switch field {
        case .top(let key): PatchComparable.normalized(key, wireValue(key))
        case .credential(let key): PatchComparable.present(credentials?[key])
        case .extra(let key): PatchComparable.present(extra?[key])
        }
    }
    private func wireValue(_ key: AccountPatchRequest.CodingKeys) -> JSONValue? {
        func number(_ value: Int?) -> JSONValue? { value.map { .number(Decimal($0)) } }
        switch key {
        case .name: return .string(name)
        case .notes: return notes.map(JSONValue.string)
        case .type: return .string(type)
        case .status: return .string(status)
        case .proxyID: return number(proxyID)
        case .concurrency: return number(concurrency)
        case .priority: return number(priority)
        case .loadFactor: return number(loadFactor)
        case .rateMultiplier: return rateMultiplier.map(JSONValue.number)
        case .groupIDs: return .array((groupIDs + groups.map(\.id)).map { .number(Decimal($0)) })
        case .expiresAt: return expiresAt.map { .number(Decimal($0)) }
        case .autoPauseOnExpired: return autoPauseOnExpired.map(JSONValue.bool)
        case .upstreamBillingProbeEnabled: return extra?["upstream_billing_probe_enabled"]
        case .upstreamBillingRateSyncEnabled: return extra?["upstream_billing_rate_sync_enabled"]
        case .confirmMixedChannelRisk, .credentialsPatch, .extraPatch, .credentials, .extra: return nil
        }
    }
}

/// The server's equivalent spellings made equal: null is missing; notes are trimmed and "" is missing; proxy, load factor and
/// expiry of 0 or less are missing; a missing flag is false; groups compare as a set. Numbers compare as Decimal (10 == 10.0).
enum PatchComparable {
    static func normalized(_ key: AccountPatchRequest.CodingKeys, _ value: JSONValue?) -> JSONValue? {
        let value = present(value)
        switch key {
        case .name:
            guard let text = value?.stringValue else { return value }
            return .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case .notes:
            let text = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : .string(text)
        case .proxyID, .loadFactor, .expiresAt:
            guard let number = value?.decimalValue else { return value }
            return number > 0 ? value : nil
        case .autoPauseOnExpired, .upstreamBillingProbeEnabled, .upstreamBillingRateSyncEnabled: return value ?? .bool(false)
        case .groupIDs:
            guard let ids = value?.arrayValue?.compactMap(\.intValue) else { return value }
            return .array(Set(ids).sorted().map { .number(Decimal($0)) })
        default: return value
        }
    }
    static func target(_ change: JSONPatchValue) -> JSONValue? {
        guard case .set(let value) = change else { return nil }
        return present(value)
    }
    static func present(_ value: JSONValue?) -> JSONValue? { value == .null ? nil : value }
}
