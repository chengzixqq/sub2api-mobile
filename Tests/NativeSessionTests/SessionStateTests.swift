import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

@MainActor @Test func pushRecordsArePerSiteAndFollowTheReport() throws {
    let suite = "push-records-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let records = PushDeviceRecords(defaults: defaults)
    let first = UUID(), second = UUID()
    records.setRegisteredDeviceID(12, serverID: first)
    records.setRegisteredDeviceID(40, serverID: second)
    #expect(records.teardownCandidates(serverID: first) == [12])
    records.apply(TeardownReport(failedPushDeviceIDs: [12]), serverID: first)
    #expect(records.registeredDeviceID(serverID: first) == nil); #expect(records.pendingDeletions(serverID: first) == [12])
    records.setRegisteredDeviceID(30, serverID: first)
    #expect(records.teardownCandidates(serverID: first) == [30, 12])
    records.apply(TeardownReport(deletedPushDeviceIDs: [12], failedPushDeviceIDs: [30]), serverID: first)
    #expect(records.pendingDeletions(serverID: first) == [30])
    records.apply(TeardownReport(deletedPushDeviceIDs: [30]), serverID: first)
    #expect(records.teardownCandidates(serverID: first).isEmpty)
    #expect(records.registeredDeviceID(serverID: second) == 40)
    records.removeAll(serverID: second)
    #expect(records.teardownCandidates(serverID: second).isEmpty)
}

@Test func loginPromptReusesTheSiteOnlyForTheSameAddressWithoutPendingRecords() throws {
    let site = ServerProfile(name: "站点 A", baseURL: URL(string: "https://a.example.com")!, authentication: .password)
    let reusing = LoginPrompt(profile: site, notice: "登录已失效，请重新登录", reusesSiteID: true)
    let same = reusing.profile(name: "站点 A2", url: URL(string: "https://a.example.com")!, authentication: .adminKey)
    #expect(same.id == site.id); #expect(same.name == "站点 A2"); #expect(same.authentication == .adminKey)
    let moved = reusing.profile(name: "站点 A", url: URL(string: "https://b.example.com")!, authentication: .password)
    #expect(moved.id != site.id); #expect(moved.baseURL.host == "b.example.com")
    // Records awaiting reconciliation stay on the old site id (D17).
    let pending = LoginPrompt(profile: site, notice: nil, reusesSiteID: false)
    #expect(pending.profile(name: "站点 A", url: site.baseURL, authentication: .password).id != site.id)
    #expect(LoginPrompt(profile: site, notice: nil, reusesSiteID: true) != reusing)
}
