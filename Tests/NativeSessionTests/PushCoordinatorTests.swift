import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 00 §7.1–§7.2, §7.6, 60 §7.4: the switch, registering on connect, pending deletions, teardowns of the same address and the
// token in memory (S6-23, S6D2b-05).

private let notFound = APIError.server(status: 404, reason: "PUSH_DEVICE_NOT_FOUND")
private let serverError = APIError.server(status: 500, reason: nil)

@MainActor private final class PushEndLog {
    var waits: [Duration] = []
    func record(_ duration: Duration) { waits.append(duration) }
}

private func body(_ request: URLRequest?) throws -> [String: Any] {
    let data = try #require(request?.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

// MARK: - 本机开关

@MainActor @Test func enableLocalDeniedTurnsBackOffWithoutRequests() async {
    for (status, grants) in [(PushAuthorization.denied, true), (.notDetermined, false), (.notDetermined, nil)] as [(PushAuthorization, Bool?)] {
        let store = PushTestDefaults(); defer { store.clear() }
        let authorizer = PushStubAuthorizer(status, grants: grants), registrar = PushStubRegistrar(), api = PushStubAPI()
        let coordinator = makePushCoordinator(store.records, authorizer: authorizer, registrar: registrar)
        let site = pushSite(api: api)
        coordinator.siteDidConnect(site)
        #expect(await coordinator.enableLocal(config: nil) == .permissionDenied)
        if grants != nil { #expect(coordinator.authorization == .denied) }
        #expect(registrar.calls == 0)
        #expect(await api.posts == 0)
        #expect(!coordinator.isLocalPushOn(serverID: site.serverID))
        #expect(!coordinator.isUpdating)
    }
}

@MainActor @Test func enableLocalAsksOnlyWhenNotDetermined() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let granted = PushStubAuthorizer(.authorized)
    let coordinator = makePushCoordinator(store.records, authorizer: granted)
    coordinator.siteDidConnect(pushSite(api: PushStubAPI()))
    #expect(await coordinator.enableLocal(config: nil) == .enabled(deviceID: 41))
    #expect(await granted.requests == 0)

    let other = PushTestDefaults(); defer { other.clear() }
    let asking = PushStubAuthorizer(.notDetermined), registrar = PushStubRegistrar(.silent)
    let second = makePushCoordinator(other.records, authorizer: asking, registrar: registrar)
    second.siteDidConnect(pushSite(api: PushStubAPI()))
    let enabling = Task { await second.enableLocal(config: nil) }
    await waitUntil { registrar.calls == 1 }
    #expect(second.isUpdating)
    second.didReceiveDeviceToken(pushTestToken)
    #expect(await enabling.value == .enabled(deviceID: 41))
    #expect(await asking.requests == 1)
    #expect(second.authorization == .authorized)
    #expect(!second.isUpdating)
}

@MainActor @Test func enableLocalBuildWithoutPushShowsSection7_5Copy() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let api = PushStubAPI()
    let coordinator = makePushCoordinator(store.records, registrar: PushStubRegistrar(.failure))
    let site = pushSite(api: api)
    coordinator.siteDidConnect(site)
    #expect(await coordinator.enableLocal(config: nil) == .failed(PushPresentation.buildWithoutPush))
    #expect(await api.posts == 0)
    #expect(coordinator.registeredDeviceID(serverID: site.serverID) == nil)
    #expect(!coordinator.isLocalPushOn(serverID: site.serverID))
}

@MainActor @Test func enableLocalTokenTimeoutFails() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let api = PushStubAPI()
    let coordinator = makePushCoordinator(store.records, registrar: PushStubRegistrar(.silent), sleep: { _ in })
    let site = pushSite(api: api)
    coordinator.siteDidConnect(site)
    #expect(await coordinator.enableLocal(config: nil) == .failed(PushCoordinator.tokenTimeoutMessage))
    // A token arriving late resumes nothing twice and registers nothing: the switch is off.
    coordinator.didReceiveDeviceToken(pushTestToken)
    await coordinator.settle()
    #expect(await api.posts == 0)
}

@MainActor @Test func enableLocalRegistersIOSDeviceAndSavesID() async throws {
    let store = PushTestDefaults(); defer { store.clear() }
    let transport = SessionTransport { _ in sessionOK(#"{"id":41,"platform":"ios","created":true}"#) }
    let coordinator = makePushCoordinator(store.records)
    let site = pushSite(api: sessionClient(transport))
    coordinator.siteDidConnect(site)
    await coordinator.settle()
    // Left by an earlier sign-out; the server answers the same token with the same id.
    store.records.apply(TeardownReport(failedPushDeviceIDs: [41, 8]), serverID: site.serverID)
    let before = coordinator.revision
    #expect(await coordinator.enableLocal(config: PushAPNsConfig(ready: true)) == .enabled(deviceID: 41))
    let request = await transport.requests.last
    let sent = try body(request)
    #expect(request?.httpMethod == "POST")
    #expect(request?.url?.path == "/api/v1/admin/push/devices")
    #expect(sent["platform"] as? String == "ios")
    #expect(sent["apns_token"] as? String == pushTestTokenHex)
    #expect(sent["bundle_id"] as? String == "com.example.sub2")
    #expect(sent["device_name"] as? String == "测试 iPhone")
    #expect(sent["locale"] as? String == "zh-Hans")
    #expect(sent["timezone"] as? String == "Asia/Shanghai")
    #expect(sent["site_tag"] as? String == site.serverID.uuidString)
    #expect(sent["subscription"] == nil && sent["environment"] == nil)
    #expect(coordinator.registeredDeviceID(serverID: site.serverID) == 41)
    #expect(coordinator.isLocalPushOn(serverID: site.serverID))
    #expect(coordinator.pendingDeletions(serverID: site.serverID) == [8])
    #expect(coordinator.revision > before)
}

@MainActor @Test func sandboxBuildSendsSandboxEnvironmentOnly() async throws {
    for sandbox in [true, false] {
        let store = PushTestDefaults(); defer { store.clear() }
        let transport = SessionTransport { _ in sessionOK(#"{"id":41,"platform":"ios"}"#) }
        let coordinator = makePushCoordinator(store.records, sandbox: sandbox)
        coordinator.siteDidConnect(pushSite(api: sessionClient(transport)))
        #expect(await coordinator.enableLocal(config: nil) == .enabled(deviceID: 41))
        let request = await transport.requests.last
        #expect(try body(request)["environment"] as? String == (sandbox ? "sandbox" : nil))
        let text = String(decoding: request?.httpBody ?? Data(), as: UTF8.self)
        #expect(!text.contains("production"))
    }
}

@MainActor @Test func notReadyConfigStartsNothing() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let authorizer = PushStubAuthorizer(.notDetermined), registrar = PushStubRegistrar(), api = PushStubAPI()
    let coordinator = makePushCoordinator(store.records, authorizer: authorizer, registrar: registrar)
    coordinator.siteDidConnect(pushSite(api: api))
    await coordinator.settle()
    let reads = await authorizer.statusReads
    #expect(await coordinator.enableLocal(config: PushAPNsConfig(ready: false)) == .notReady)
    #expect(await authorizer.statusReads == reads)
    #expect(await authorizer.requests == 0)
    #expect(registrar.calls == 0)
    #expect(await api.posts == 0)
    // A config that could not be read does not block the switch.
    #expect(await coordinator.enableLocal(config: nil) == .enabled(deviceID: 41))
}

@MainActor @Test func registrationErrorKeepsSwitchOffWithMessage() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let api = PushStubAPI()
    await api.fail(APIError.server(status: 409, reason: "PUSH_DEVICE_LIMIT_REACHED"))
    let coordinator = makePushCoordinator(store.records)
    let site = pushSite(api: api)
    coordinator.siteDidConnect(site)
    #expect(await coordinator.enableLocal(config: nil) == .failed("最多 20 个推送目标，先删除不用的"))
    #expect(coordinator.registeredDeviceID(serverID: site.serverID) == nil)
    #expect(!coordinator.isLocalPushOn(serverID: site.serverID))
    await api.fail(CancellationError())
    #expect(await coordinator.enableLocal(config: nil) == .cancelled)
}

@MainActor @Test func disableLocalDeletesDeviceAndClearsState() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let api = PushStubAPI(deleteErrors: [41: serverError])
    let coordinator = makePushCoordinator(store.records)
    let site = pushSite(api: api)
    coordinator.siteDidConnect(site)
    #expect(await coordinator.enableLocal(config: nil) == .enabled(deviceID: 41))
    #expect(await coordinator.disableLocal() == .failed(PushPresentation.failureMessage(serverError)))
    #expect(coordinator.registeredDeviceID(serverID: site.serverID) == 41)
    #expect(coordinator.isLocalPushOn(serverID: site.serverID))

    let working = PushStubAPI(), gone = PushStubAPI(deleteErrors: [41: notFound])
    for target in [working, gone] {
        let records = PushTestDefaults(); defer { records.clear() }
        let next = makePushCoordinator(records.records)
        let connected = pushSite(api: target)
        next.siteDidConnect(connected)
        #expect(await next.enableLocal(config: nil) == .enabled(deviceID: 41))
        let before = next.revision
        #expect(await next.disableLocal() == .disabled)
        #expect(await target.calls.filter { $0 == "DELETE 41" }.count == 1)
        #expect(next.registeredDeviceID(serverID: connected.serverID) == nil)
        #expect(!next.isLocalPushOn(serverID: connected.serverID))
        #expect(next.revision > before)
        // Turning it on again sends the same token again.
        #expect(await next.enableLocal(config: nil) == .enabled(deviceID: 41))
        #expect(await target.posts == 2)
    }
}

@MainActor @Test func forgetLocalDeviceClearsTheSwitch() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let api = PushStubAPI()
    let coordinator = makePushCoordinator(store.records)
    let site = pushSite(api: api)
    coordinator.siteDidConnect(site)
    #expect(await coordinator.enableLocal(config: nil) == .enabled(deviceID: 41))
    let before = coordinator.revision
    coordinator.forgetLocalDevice()
    #expect(coordinator.revision > before)
    #expect(coordinator.registeredDeviceID(serverID: site.serverID) == nil)
    #expect(!coordinator.isLocalPushOn(serverID: site.serverID))
    coordinator.siteDidConnect(pushSite(site.serverID, api: api))
    await coordinator.settle()
    #expect(await api.posts == 1)
}

// MARK: - 连接成功后

@MainActor @Test func connectDeletesPendingBeforeRegisteringAgain() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let serverID = UUID()
    store.records.setRegisteredDeviceID(9, serverID: serverID)
    store.records.setLocalPushOn(true, serverID: serverID)
    store.records.apply(TeardownReport(failedPushDeviceIDs: [3, 4]), serverID: serverID)
    store.records.setRegisteredDeviceID(9, serverID: serverID)
    let api = PushStubAPI(registeredID: 9, devices: [9], deleteErrors: [3: notFound, 4: serverError])
    let coordinator = makePushCoordinator(store.records)
    coordinator.didReceiveDeviceToken(pushTestToken)
    let before = coordinator.revision
    coordinator.siteDidConnect(pushSite(serverID, api: api))
    await coordinator.settle()
    #expect(await api.calls == ["DELETE 3", "DELETE 4", "POST " + serverID.uuidString])
    #expect(coordinator.pendingDeletions(serverID: serverID) == [4])
    #expect(coordinator.registeredDeviceID(serverID: serverID) == 9)
    #expect(coordinator.revision > before)
}

@MainActor @Test func connectRegistersOncePerSessionAndToken() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let serverID = UUID()
    store.records.setLocalPushOn(true, serverID: serverID)
    let api = PushStubAPI()
    let coordinator = makePushCoordinator(store.records)
    coordinator.didReceiveDeviceToken(pushTestToken)
    coordinator.siteDidConnect(pushSite(serverID, api: api))
    await coordinator.settle()
    coordinator.didReceiveDeviceToken(pushTestToken)
    await coordinator.settle()
    #expect(await api.posts == 1)
    coordinator.siteDidConnect(pushSite(serverID, api: api))
    await coordinator.settle()
    #expect(await api.posts == 2)

    let off = UUID(), quiet = PushStubAPI(deleteErrors: [5: notFound])
    store.records.apply(TeardownReport(failedPushDeviceIDs: [5]), serverID: off)
    coordinator.siteDidConnect(pushSite(off, api: quiet))
    await coordinator.settle()
    #expect(await quiet.calls == ["DELETE 5"])
}

@MainActor @Test func connectWaitsForTeardownOfSameAddress() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let serverID = UUID(), gate = SessionGate()
    store.records.setLocalPushOn(true, serverID: serverID)
    store.records.apply(TeardownReport(failedPushDeviceIDs: [3]), serverID: serverID)
    let api = PushStubAPI(deleteErrors: [3: notFound])
    let coordinator = makePushCoordinator(store.records)
    coordinator.didReceiveDeviceToken(pushTestToken)
    coordinator.siteDidConnect(pushSite(serverID, api: api, teardown: gate))
    await waitUntil { await gate.arrived }
    for _ in 0..<50 { await Task.yield() }
    #expect(await api.calls.isEmpty)
    await gate.open()
    await coordinator.settle()
    #expect(await api.calls == ["DELETE 3", "POST " + serverID.uuidString])
}

@MainActor @Test func firstTokenAfterLaunchRegistersCurrentSite() async {
    for status in [PushAuthorization.authorized, .denied, .notDetermined] {
        let store = PushTestDefaults(); defer { store.clear() }
        let serverID = UUID()
        store.records.setLocalPushOn(true, serverID: serverID)
        let authorizer = PushStubAuthorizer(status), registrar = PushStubRegistrar(.silent), api = PushStubAPI()
        let coordinator = makePushCoordinator(store.records, authorizer: authorizer, registrar: registrar)
        coordinator.siteDidConnect(pushSite(serverID, api: api))
        await coordinator.settle()
        #expect(registrar.calls == (status == .authorized ? 1 : 0))
        #expect(await authorizer.requests == 0)
        guard status == .authorized else { continue }
        coordinator.didReceiveDeviceToken(pushTestToken)
        await coordinator.settle()
        #expect(await api.calls == ["POST " + serverID.uuidString])
    }
}

@MainActor @Test func tokenChangeReregistersOnlyCurrentSite() async throws {
    let store = PushTestDefaults(); defer { store.clear() }
    let siteA = UUID(), siteB = UUID()
    for id in [siteA, siteB] { store.records.setLocalPushOn(true, serverID: id) }
    let apiA = PushStubAPI(), apiB = PushStubAPI()
    let coordinator = makePushCoordinator(store.records)
    coordinator.didReceiveDeviceToken(pushTestToken)
    coordinator.siteDidConnect(pushSite(siteB, api: apiB))
    await coordinator.settle()
    #expect(await apiB.posts == 1)
    let newToken = Data(repeating: 0x5C, count: 32)
    coordinator.didReceiveDeviceToken(newToken)
    await coordinator.settle()
    #expect(await apiB.posts == 2)
    #expect(await apiB.registrations.last?.siteTag == siteB.uuidString)
    #expect(await apiA.posts == 0)
    coordinator.siteDidConnect(pushSite(siteA, api: apiA))
    await coordinator.settle()
    #expect(await apiA.calls == ["POST " + siteA.uuidString])
    let last = await apiA.registrations.last
    let sent = String(decoding: try JSONEncoder().encode(try #require(last)), as: UTF8.self)
    #expect(sent.contains(PushDeviceRegistration.apnsTokenHex(newToken)))
}

@MainActor @Test func siteWithoutPushCapabilityOnlyDeletesPending() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let serverID = UUID()
    store.records.setLocalPushOn(true, serverID: serverID)
    store.records.apply(TeardownReport(failedPushDeviceIDs: [6]), serverID: serverID)
    let registrar = PushStubRegistrar(), api = PushStubAPI(deleteErrors: [6: notFound])
    let coordinator = makePushCoordinator(store.records, registrar: registrar)
    coordinator.siteDidConnect(pushSite(serverID, supportsPush: false, api: api))
    await coordinator.settle()
    #expect(await api.calls == ["DELETE 6"])
    #expect(registrar.calls == 0)
    #expect(await coordinator.enableLocal(config: nil) == .cancelled)
}

// MARK: - 会话结束

@MainActor @Test func siteDidEndClearsStateButKeepsToken() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let first = UUID(), second = UUID(), gate = SessionGate()
    for id in [first, second] { store.records.setLocalPushOn(true, serverID: id) }
    let registrar = PushStubRegistrar(), api = PushStubAPI()
    let coordinator = makePushCoordinator(store.records, registrar: registrar)
    coordinator.didReceiveDeviceToken(pushTestToken)
    coordinator.siteDidConnect(pushSite(first, api: api, teardown: gate))
    let navigator = PushStubNavigator(active: first, profiles: [ServerProfile(id: first, name: "a", baseURL: URL(string: "https://a.example.invalid")!, authentication: .password)])
    await coordinator.openTap(PushTap(type: "push.test", siteTag: first.uuidString, target: .pushSettings), navigator: navigator)
    #expect(coordinator.pendingTarget != nil)
    coordinator.siteDidEnd(serverID: first)
    #expect(coordinator.pendingTarget == nil)
    await gate.open()
    await coordinator.settle()
    #expect(await api.posts == 0)
    coordinator.siteDidConnect(pushSite(second, api: api))
    await coordinator.settle()
    #expect(await api.calls == ["POST " + second.uuidString])
    #expect(registrar.calls == 0)
}

@MainActor @Test func registrationFinishingAfterSignOutIsQueuedForDeletion() async {
    for switchesSite in [false, true] {
        let store = PushTestDefaults(); defer { store.clear() }
        let serverID = UUID(), gate = SessionGate()
        store.records.setLocalPushOn(true, serverID: serverID)
        let api = PushStubAPI(registeredID: 77)
        await api.hold(post: gate)
        let coordinator = makePushCoordinator(store.records)
        coordinator.didReceiveDeviceToken(pushTestToken)
        coordinator.siteDidConnect(pushSite(serverID, api: api))
        await waitUntil { await gate.arrived }
        let before = coordinator.revision
        if switchesSite { coordinator.siteDidConnect(pushSite(api: PushStubAPI())) } else { coordinator.siteDidEnd(serverID: serverID) }
        await gate.open()
        await coordinator.settle()
        #expect(coordinator.revision > before)
        if switchesSite {
            #expect(coordinator.registeredDeviceID(serverID: serverID) == 77)
        } else {
            #expect(coordinator.registeredDeviceID(serverID: serverID) == nil)
            #expect(coordinator.pendingDeletions(serverID: serverID) == [77])
        }
    }
}

/// Signing out or deleting the connected site while its POST is out: the client's cancelAll would leave a device the server may
/// have created without its id, so the teardown waits for it (within endWait) and deletes it.
@MainActor @Test func siteWillEndWaitsForTheRegistrationInFlight() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let serverID = UUID(), gate = SessionGate()
    store.records.setLocalPushOn(true, serverID: serverID)
    let api = PushStubAPI(registeredID: 77)
    await api.hold(post: gate)
    let coordinator = makePushCoordinator(store.records)
    coordinator.didReceiveDeviceToken(pushTestToken)
    coordinator.siteDidConnect(pushSite(serverID, api: api))
    await waitUntil { await gate.arrived }
    let ended = PushEndLog()
    let ending = Task { await coordinator.siteWillEnd(serverID: serverID); ended.waits.append(.zero) }
    for _ in 0..<50 { await Task.yield() }
    #expect(ended.waits.isEmpty)
    // Nothing new starts meanwhile.
    coordinator.registerAgain()
    await gate.open()
    await ending.value
    #expect(coordinator.registeredDeviceID(serverID: serverID) == nil)
    #expect(store.records.teardownCandidates(serverID: serverID) == [77])
    await coordinator.settle()
    #expect(await api.posts == 1)
    // Nothing out: at once.
    await coordinator.siteWillEnd(serverID: serverID)
}

@MainActor @Test func siteWillEndWaitsAtMostEndWait() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let serverID = UUID(), gate = SessionGate()
    store.records.setLocalPushOn(true, serverID: serverID)
    let api = PushStubAPI(registeredID: 77)
    await api.hold(post: gate)
    let waited = PushEndLog()
    let coordinator = makePushCoordinator(store.records, sleep: { duration in await waited.record(duration) })
    coordinator.didReceiveDeviceToken(pushTestToken)
    coordinator.siteDidConnect(pushSite(serverID, api: api))
    await waitUntil { await gate.arrived }
    await coordinator.siteWillEnd(serverID: serverID)
    #expect(waited.waits == [PushCoordinator.endWait])
    #expect(store.records.teardownCandidates(serverID: serverID).isEmpty)
    await gate.open()
    await coordinator.settle()
    #expect(coordinator.pendingDeletions(serverID: serverID) == [77])
}

@MainActor @Test func registerAgainAfterTokenRevocationClearedRecords() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let api = PushStubAPI(), coordinator = makePushCoordinator(store.records)
    let site = pushSite(api: api)
    coordinator.siteDidConnect(site)
    #expect(await coordinator.enableLocal(config: nil) == .enabled(deviceID: 41))
    // The revocation deleted the device first, then the DELETE of the token failed: the session goes on.
    store.records.apply(TeardownReport(deletedPushDeviceIDs: [41]), serverID: site.serverID)
    let before = coordinator.revision
    coordinator.registerAgain()
    await coordinator.settle()
    #expect(await api.posts == 2)
    #expect(coordinator.registeredDeviceID(serverID: site.serverID) == 41)
    #expect(coordinator.revision > before)
    #expect(await coordinator.disableLocal() == .disabled)
    coordinator.registerAgain()
    await coordinator.settle()
    #expect(await api.posts == 2)
}

@MainActor @Test func enableDuringPendingDeletionKeepsTheNewDevice() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let serverID = UUID(), gate = SessionGate()
    store.records.apply(TeardownReport(failedPushDeviceIDs: [9]), serverID: serverID)
    let api = PushStubAPI(registeredID: 9, devices: [9])
    await api.hold(delete: 9, at: gate)
    let coordinator = makePushCoordinator(store.records)
    coordinator.siteDidConnect(pushSite(serverID, api: api))
    await waitUntil { await gate.arrived }
    let enabling = Task { await coordinator.enableLocal(config: nil) }
    for _ in 0..<50 { await Task.yield() }
    await gate.open()
    #expect(await enabling.value == .enabled(deviceID: 9))
    await coordinator.settle()
    #expect(coordinator.registeredDeviceID(serverID: serverID) == 9)
    #expect(coordinator.pendingDeletions(serverID: serverID).isEmpty)
    #expect(await api.devices.contains(9))
}

// MARK: - 记录与收尾登记

@MainActor @Test func recordsLocalSwitchSurvivesSignOutButNotRemoval() {
    let store = PushTestDefaults(); defer { store.clear() }
    let records = store.records, site = UUID()
    records.setLocalPushOn(true, serverID: site)
    records.setRegisteredDeviceID(9, serverID: site)
    records.apply(TeardownReport(deletedPushDeviceIDs: [9]), serverID: site)
    #expect(records.isLocalPushOn(serverID: site))
    #expect(records.registeredDeviceID(serverID: site) == nil)
    records.apply(TeardownReport(failedPushDeviceIDs: [3, 4]), serverID: site)
    records.resolvePendingDeletions([3], serverID: site)
    #expect(records.pendingDeletions(serverID: site) == [4])
    records.resolvePendingDeletions([4, 8], serverID: site)
    #expect(store.defaults.object(forKey: "push.pendingDeletion." + site.uuidString) == nil)
    records.removeAll(serverID: site)
    #expect(!records.isLocalPushOn(serverID: site))
    #expect(store.defaults.object(forKey: "push.enabled." + site.uuidString) == nil)
    records.setLocalPushOn(true, serverID: site)
    records.setLocalPushOn(false, serverID: site)
    #expect(store.defaults.object(forKey: "push.enabled." + site.uuidString) == nil)
}

/// The server keeps one device per token: another login of the connected site's address that registered the same device
/// leaves it to the connected site when deleted.
@MainActor @Test func teardownCandidatesKeepTheConnectedSitesDevice() {
    let store = PushTestDefaults(); defer { store.clear() }
    let records = store.records, removed = UUID(), connected = UUID()
    records.setRegisteredDeviceID(5, serverID: removed)
    records.apply(TeardownReport(failedPushDeviceIDs: [3, 5]), serverID: removed)
    records.setRegisteredDeviceID(5, serverID: removed)
    #expect(records.teardownCandidates(serverID: removed, keepingDeviceOf: nil) == [5, 3])
    #expect(records.teardownCandidates(serverID: removed, keepingDeviceOf: connected) == [5, 3])
    records.setRegisteredDeviceID(5, serverID: connected)
    #expect(records.teardownCandidates(serverID: removed, keepingDeviceOf: connected) == [3])
    #expect(records.teardownCandidates(serverID: connected, keepingDeviceOf: connected) == [5])
}

@MainActor @Test func teardownTrackerWaitsForSameAddressOnly() async {
    let tracker = SiteTeardownTracker(), gate = SessionGate()
    let address = "https://a.example.invalid"
    let running = Task { await tracker.run(address: address) { await gate.wait(); return 7 } }
    await waitUntil { await gate.arrived }
    #expect(!tracker.isIdle)
    await tracker.waitForTeardowns(address: "https://b.example.invalid")
    await tracker.waitForTeardowns(address: nil)
    let waiting = Task { await tracker.waitForTeardowns(address: address); return true }
    for _ in 0..<50 { await Task.yield() }
    await gate.open()
    #expect(await waiting.value)
    #expect(await running.value == 7)
    #expect(tracker.isIdle)

    let cancelled = Task { await tracker.run(address: address) { () -> Bool in
        do { try await Task.sleep(for: .seconds(30)); return false } catch { return true }
    } }
    await waitUntil { !tracker.isIdle }
    cancelled.cancel()
    #expect(await cancelled.value)
    #expect(tracker.isIdle)
}

@MainActor @Test func recordsWritesBumpRevision() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let api = PushStubAPI(deleteErrors: [3: notFound])
    let coordinator = makePushCoordinator(store.records)
    let site = pushSite(api: api)
    store.records.apply(TeardownReport(failedPushDeviceIDs: [3]), serverID: site.serverID)
    var seen = coordinator.revision
    func bumped() -> Bool { defer { seen = coordinator.revision }; return coordinator.revision > seen }
    coordinator.siteDidConnect(site)
    await coordinator.settle()
    #expect(bumped())
    #expect(await coordinator.enableLocal(config: nil) == .enabled(deviceID: 41))
    #expect(bumped())
    store.records.apply(TeardownReport(deletedPushDeviceIDs: [41]), serverID: site.serverID)
    coordinator.registerAgain()
    await coordinator.settle()
    #expect(bumped())
    #expect(await coordinator.disableLocal() == .disabled)
    #expect(bumped())
    coordinator.forgetLocalDevice()
    #expect(bumped())
}

/// S6-26: a teardown of an older login (another site id) still running at the same address, written differently, holds the new
/// site's registration until it ends (BACKLOG “推送登记要等待该站点的收尾结束”).
@MainActor @Test func registrationWaitsForTheTeardownOfAnotherSiteIDAtTheSameAddress() async throws {
    let store = PushTestDefaults(); defer { store.clear() }
    let tracker = SiteTeardownTracker(), gate = SessionGate()
    let oldAddress = MoneyRecordOrigin.addressKey(of: try #require(URL(string: "https://Push.Example.invalid:443")))
    let newAddress = MoneyRecordOrigin.addressKey(of: try #require(URL(string: "https://push.example.invalid")))
    let teardown = Task { await tracker.run(address: oldAddress) { await gate.wait() } }
    await waitUntil { await gate.arrived }
    let newSite = UUID(), api = PushStubAPI()
    store.records.setLocalPushOn(true, serverID: newSite)
    let coordinator = makePushCoordinator(store.records)
    coordinator.didReceiveDeviceToken(pushTestToken)
    coordinator.siteDidConnect(PushSite(serverID: newSite, generation: UUID(), supportsPush: true, api: api,
                                        waitForTeardowns: { await tracker.waitForTeardowns(address: newAddress) }))
    for _ in 0..<50 { await Task.yield() }
    #expect(await api.calls.isEmpty)
    await gate.open()
    await teardown.value
    await coordinator.settle()
    #expect(await api.calls == ["POST " + newSite.uuidString])
}
