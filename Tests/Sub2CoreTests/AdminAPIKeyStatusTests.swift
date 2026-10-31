import Foundation
import Testing
@testable import Sub2Core

private let now = Date(timeIntervalSince1970: 1_792_663_200)
private func amount(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }

/// A key's stored fields; `expiresIn` is seconds from `now`, nil for a key that never expires.
struct APIKeyStatusFields: Sendable, CustomTestStringConvertible {
    var status = "active", expiresIn: TimeInterval? = nil, quota = "0", used = "0"

    var testDescription: String { "\(status) expiresIn=\(expiresIn.map { String($0) } ?? "nil") \(used)/\(quota)" }

    func derive() -> AdminAPIKeyStatus {
        AdminAPIKeyStatus.derive(status: status, expiresAt: expiresIn.map(now.addingTimeInterval), quota: amount(quota),
                                 quotaUsed: amount(used), now: now)
    }
    func resolve(_ effectiveStatus: String?) -> AdminAPIKeyStatus {
        AdminAPIKeyStatus.resolve(effectiveStatus: effectiveStatus, status: status, expiresAt: expiresIn.map(now.addingTimeInterval),
                                  quota: amount(quota), quotaUsed: amount(used), now: now)
    }
}

// 30 §7.3 fallback in the order of backend `EffectiveStatusAt` (service/api_key.go).
private let derivationTable: [(APIKeyStatusFields, AdminAPIKeyStatus)] = [
    (APIKeyStatusFields(), .active),
    (APIKeyStatusFields(status: "inactive"), .inactive),
    (APIKeyStatusFields(status: "disabled"), .inactive),
    (APIKeyStatusFields(status: "frozen"), .inactive),
    (APIKeyStatusFields(status: ""), .inactive),
    (APIKeyStatusFields(status: "Active"), .inactive),
    (APIKeyStatusFields(status: "quota_exhausted"), .quotaExhausted),
    (APIKeyStatusFields(status: "expired", expiresIn: 86_400), .expired),
    (APIKeyStatusFields(status: "quota_exhausted", expiresIn: -60), .quotaExhausted),
    (APIKeyStatusFields(expiresIn: -1), .expired),
    (APIKeyStatusFields(expiresIn: 0), .active),
    (APIKeyStatusFields(expiresIn: 60), .active),
    (APIKeyStatusFields(quota: "50", used: "50"), .quotaExhausted),
    (APIKeyStatusFields(quota: "50", used: "50.5"), .quotaExhausted),
    (APIKeyStatusFields(quota: "50", used: "49.99999999"), .active),
    (APIKeyStatusFields(quota: "0", used: "100"), .active),
    (APIKeyStatusFields(expiresIn: -1, quota: "50", used: "50"), .expired),
    (APIKeyStatusFields(status: "inactive", expiresIn: -1, quota: "50", used: "60"), .inactive)
]

@Test(arguments: derivationTable)
func localDerivationFollowsBackendOrder(fields: APIKeyStatusFields, expected: AdminAPIKeyStatus) {
    #expect(fields.derive() == expected)
    #expect(fields.resolve(nil) == expected)
}

@Test(arguments: AdminAPIKeyStatus.allCases)
func effectiveStatusFromServerWinsOverLocalDerivation(status: AdminAPIKeyStatus) {
    let locals = [APIKeyStatusFields(), APIKeyStatusFields(status: "inactive"), APIKeyStatusFields(quota: "50", used: "50"),
                  APIKeyStatusFields(expiresIn: -1)]
    for fields in locals {
        #expect(fields.resolve(status.rawValue) == status, "\(fields.status)")
    }
}

@Test(arguments: [nil, "", "weird", "ACTIVE", " active", "disabled"] as [String?])
func missingEmptyOrUnknownEffectiveStatusFallsBackToLocalDerivation(effectiveStatus: String?) {
    for (fields, expected) in derivationTable {
        #expect(fields.resolve(effectiveStatus) == expected, "\(fields.status)")
    }
}

@Test func statusRawValuesMatchBackendConstants() {
    #expect(AdminAPIKeyStatus.allCases.map(\.rawValue) == ["active", "inactive", "quota_exhausted", "expired"])
}

@Test func statusPresentationTableStandardMode() {
    let rows: [(AdminAPIKeyStatus, String, String?, Tone, Bool)] = [
        (.active, "活跃", nil, .ok, true), (.inactive, "已停用", "已停用", .neutral, false),
        (.quotaExhausted, "额度耗尽", "额度耗尽", .caution, false), (.expired, "已过期", "已过期", .neutral, false)
    ]
    #expect(rows.map { $0.0 } == AdminAPIKeyStatus.allCases)
    for (status, title, badge, tone, active) in rows {
        #expect(status.title == title, "\(status)")
        #expect(status.badge(simpleMode: false) == badge, "\(status)")
        #expect(status.tone == tone, "\(status)")
        #expect(status.countsAsActive(simpleMode: false) == active, "\(status)")
    }
}

@Test func simpleModeKeepsExpiredAndExhaustedKeysUsable() {
    let rows: [(AdminAPIKeyStatus, String?, Bool)] = [
        (.active, nil, true), (.inactive, "已停用", false),
        (.quotaExhausted, "额度耗尽 · 仍可调用", true), (.expired, "已过期 · 仍可调用", true)
    ]
    for (status, badge, active) in rows {
        #expect(status.badge(simpleMode: true) == badge, "\(status)")
        #expect(status.countsAsActive(simpleMode: true) == active, "\(status)")
    }
    // The tone does not follow the run mode.
    #expect(AdminAPIKeyStatus.quotaExhausted.tone == .caution)
    #expect(AdminAPIKeyStatus.expired.tone == .neutral)
}

@Test func sectionMetaCountsActiveKeys() {
    #expect(AdminAPIKeyStatus.sectionMeta([], simpleMode: false) == "0 个")
    #expect(AdminAPIKeyStatus.sectionMeta([.active, .inactive, .active], simpleMode: false) == "3 个 · 活跃 2")
    #expect(AdminAPIKeyStatus.sectionMeta([.active, .expired], simpleMode: true) == "2 个 · 活跃 2")
    #expect(AdminAPIKeyStatus.sectionMeta([.expired], simpleMode: false) == "1 个 · 活跃 0")
    #expect(AdminAPIKeyStatus.sectionMeta([.inactive, .quotaExhausted], simpleMode: true) == "2 个 · 活跃 1")
    #expect(AdminAPIKeyStatus.sectionMeta(Array(repeating: .active, count: 1_200), simpleMode: false) == "1,200 个 · 活跃 1,200")
}
