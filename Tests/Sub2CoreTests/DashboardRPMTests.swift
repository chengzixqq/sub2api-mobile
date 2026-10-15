import Foundation
import Testing
@testable import Sub2Core

@Test func dashboardRPMAvailabilitySurvivesWireRoundtrip() throws {
    let wire = #"{"today_requests":10,"today_tokens":20,"today_cost":1,"total_users":2,"total_accounts":3,"error_accounts":0,"rpm":0,"rpm_available":false,"tpm":100}"#
    let stats = try JSONDecoder().decode(DashboardStats.self, from: Data(wire.utf8))
    let encoded = try JSONEncoder().encode(stats)
    let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(fields["rpm_available"] as? Bool == false)
    #expect(stats.rpm == 0)
}

@Test(arguments: [true, false]) func dashboardRPMUsesTheLiveAvailabilityFlag(available: Bool) throws {
    let wire = "{\"today_requests\":10,\"today_tokens\":20,\"today_cost\":1,\"total_users\":2,\"total_accounts\":3,\"error_accounts\":0,\"rpm\":0,\"rpm_available\":\(available),\"tpm\":100}"
    let stats = try JSONDecoder().decode(DashboardStats.self, from: Data(wire.utf8))
    #expect(stats.rpmAvailable == available)
    #expect(DashboardPresentation.rpmValue(stats) == (available ? "0" : "不可用"))
    #expect(DashboardPresentation.performanceWindow(stats).contains("RPM 近60秒"))
    #expect(DashboardPresentation.performanceWindow(stats).contains("TPM 近5分钟"))
}

@Test func legacyDashboardDoesNotClaimARollingWindow() throws {
    let wire = #"{"today_requests":10,"today_tokens":20,"today_cost":1,"total_users":2,"total_accounts":3,"error_accounts":0,"rpm":1234,"tpm":100}"#
    let stats = try JSONDecoder().decode(DashboardStats.self, from: Data(wire.utf8))
    #expect(stats.rpmAvailable == nil)
    #expect(DashboardPresentation.rpmValue(stats) == "1.23K")
    #expect(!DashboardPresentation.performanceWindow(stats).contains("近60秒"))
}

@Test func accountRollingRPMIsNeverUsedAsTheSchedulingCounter() throws {
    let data = Data(#"{"id":1,"name":"Fixture","platform":"anthropic","type":"oauth","status":"active","schedulable":true,"current_rpm":107,"scheduling_rpm":4,"base_rpm":60}"#.utf8)
    var account = try JSONDecoder().decode(UpstreamAccount.self, from: data)
    #expect(AccountFieldPresentation.value(.rpm, account: account) == "107")
    #expect(AccountFieldPresentation.capacity(account).contains("调度 RPM 4 / 60（自然分钟）"))
    account.schedulingRPM = nil
    #expect(AccountFieldPresentation.capacity(account).contains("调度 RPM 不可用 / 60"))
    #expect(!AccountFieldPresentation.capacity(account).contains("107 / 60"))
}
