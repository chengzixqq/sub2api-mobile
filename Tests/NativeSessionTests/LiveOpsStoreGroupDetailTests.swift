import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S5-07, 50 §2.2: the group detail's alert banner reads through the ops switch's entries (S1D1-02).

private let detailedSite = liveOpsSite(liveOpsCapabilities + [.opsAlertEventDetails])

@MainActor @Test func groupFiringAlertAsksFiveFiringAndTakesTheFirst() async throws {
    let source = StubLiveOpsSource(.init(alertEvents: { _, _ in [firingEvent(41), firingEvent(39)] }))
    let harness = LiveOpsHarness(source, site: detailedSite)
    let shown = try await harness.store.groupFiringAlert(groupID: 2)
    #expect(shown?.id == 41)
    #expect(await source.count { $0 == .alertEvents(status: "firing", limit: LiveOpsStore.groupBannerLimit) } == 1)
    #expect(await source.calls.count == 1)
    #expect(LiveOpsStore.groupBannerLimit == 5)
    #expect(!harness.store.opsDisabled)
}

@MainActor @Test func groupFiringAlertWithNoEventsIsNil() async throws {
    let harness = LiveOpsHarness(StubLiveOpsSource(.init(alertEvents: { _, _ in [] })), site: detailedSite)
    #expect(try await harness.store.groupFiringAlert(groupID: 2) == nil)
}

@MainActor @Test func groupFiringAlertRecordsOpsDisabled() async {
    let harness = LiveOpsHarness(StubLiveOpsSource(.init(alertEvents: { _, _ in throw opsDisabledError })), site: detailedSite)
    await #expect(throws: opsDisabledError) { try await harness.store.groupFiringAlert(groupID: 2) }
    #expect(harness.store.opsDisabled)
}

/// The fixture site filters by group like the server: 标准组 has #41, 高级组 only an ended one; a manual resolve ends the banner.
@MainActor @Test func groupFiringAlertReadsOnlyThisGroupsFiringEvent() async throws {
    let source = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(), base: Date())
    let store = LiveOpsStore(generation: UUID(), source: source, site: { detailedSite }, isCurrent: { true }, serverNow: { Date() },
                             receipts: ReceiptCenter(sleep: { _ in throw CancellationError() }))
    #expect(try await store.groupFiringAlert(groupID: LiveOpsFixtureIDs.standardGroup)?.id == LiveOpsFixtureIDs.alertA)
    #expect(try await store.groupFiringAlert(groupID: LiveOpsFixtureIDs.premiumGroup) == nil)
    try await source.setAlertEventStatus(id: LiveOpsFixtureIDs.alertA, status: AlertEvent.manualResolved)
    #expect(try await store.groupFiringAlert(groupID: LiveOpsFixtureIDs.standardGroup) == nil)
}
