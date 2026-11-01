import Foundation
import Sub2Core
@testable import NativeSessionSupport

// Stand-ins for PushCoordinatorTests and PushDeepLinkTests (S6-23).

/// 32 bytes, so `apnsTokenHex` gives the 64 lowercase digits the backend accepts.
let pushTestToken = Data((0..<32).map { UInt8(0xA0 + $0) })
let pushTestTokenHex = PushDeviceRegistration.apnsTokenHex(pushTestToken)

/// The system permission: `status`, and what asking answers (nil throws).
actor PushStubAuthorizer: NotificationAuthorizing {
    private(set) var status: PushAuthorization
    private let grants: Bool?
    private(set) var statusReads = 0
    private(set) var requests = 0
    init(_ status: PushAuthorization, grants: Bool? = true) { self.status = status; self.grants = grants }
    func authorizationStatus() async -> PushAuthorization { statusReads += 1; return status }
    func requestAuthorization() async throws -> Bool {
        requests += 1
        guard let grants else { throw URLError(.cancelled) }
        status = grants ? .authorized : .denied
        return grants
    }
}

/// `registerForRemoteNotifications()`: answers at once with `reply`, or never.
@MainActor final class PushStubRegistrar: RemoteNotificationRegistering {
    enum Reply { case token(Data), failure, silent }
    var reply: Reply
    private(set) var calls = 0
    init(_ reply: Reply = .token(pushTestToken)) { self.reply = reply }
    func registerForRemoteNotifications(reportingTo coordinator: PushCoordinator) {
        calls += 1
        switch reply {
        case .token(let data): coordinator.didReceiveDeviceToken(data)
        case .failure: coordinator.didFailToRegister(URLError(.unsupportedURL))
        case .silent: break
        }
    }
}

/// The site's push endpoints: calls in order (“POST” with the site tag, “DELETE <id>”), the devices it holds, optional gates.
actor PushStubAPI: PushDeviceAPI {
    private(set) var calls: [String] = []
    private(set) var registrations: [PushDeviceRegistration] = []
    private(set) var devices: Set<Int>
    private var registeredID: Int
    private var registerError: (any Error)?
    private var deleteErrors: [Int: any Error]
    private var postGate: SessionGate?
    private var deleteGates: [Int: SessionGate] = [:]
    init(registeredID: Int = 41, devices: Set<Int> = [], deleteErrors: [Int: any Error] = [:]) {
        self.registeredID = registeredID; self.devices = devices; self.deleteErrors = deleteErrors
    }
    func answer(id: Int) { registeredID = id }
    func fail(_ error: (any Error)?) { registerError = error }
    func hold(post gate: SessionGate?) { postGate = gate }
    func hold(delete id: Int, at gate: SessionGate) { deleteGates[id] = gate }
    var posts: Int { calls.filter { $0.hasPrefix("POST") }.count }

    func registerPushDevice(_ registration: PushDeviceRegistration) async throws -> (device: PushDevice, created: Bool) {
        calls.append("POST " + (registration.siteTag ?? "-"))
        registrations.append(registration)
        if let gate = postGate { await gate.wait() }
        if let registerError { throw registerError }
        let id = registeredID
        let created = !devices.contains(id)
        devices.insert(id)
        return (PushDevice(id: id, platform: .ios, siteTag: registration.siteTag), created)
    }
    func deletePushDevice(id: Int) async throws {
        calls.append("DELETE \(id)")
        if let gate = deleteGates[id] { await gate.wait() }
        if let error = deleteErrors[id] { throw error }
        devices.remove(id)
    }
}

/// AppModel's half of a tap: which site is connected and what opening another one gives.
@MainActor final class PushStubNavigator: PushSiteNavigating {
    var activeServerID: UUID?
    var profiles: [ServerProfile]
    var opening: PushSiteOpening
    private(set) var opened: [UUID] = []
    init(active: UUID?, profiles: [ServerProfile], opening: PushSiteOpening = .connected) {
        activeServerID = active; self.profiles = profiles; self.opening = opening
    }
    func openSite(_ profile: ServerProfile) async -> PushSiteOpening {
        opened.append(profile.id)
        if opening == .connected { activeServerID = profile.id }
        return opening
    }
}

@MainActor final class PushTestClock { var date = Date(timeIntervalSince1970: 1_800_000_000) }

/// A fresh UserDefaults suite per test; `clear()` removes it.
struct PushTestDefaults {
    let suite = "PushTests." + UUID().uuidString
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    @MainActor var records: PushDeviceRecords { PushDeviceRecords(defaults: defaults) }
    func clear() { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
}

func pushProfile(_ name: String) -> ServerProfile {
    ServerProfile(name: name, baseURL: URL(string: "https://\(name).example.invalid")!, authentication: .password)
}

@MainActor func pushSite(_ serverID: UUID = UUID(), generation: UUID = UUID(), supportsPush: Bool = true, api: any PushDeviceAPI,
                         teardown gate: SessionGate? = nil) -> PushSite {
    PushSite(serverID: serverID, generation: generation, supportsPush: supportsPush, api: api, waitForTeardowns: { await gate?.wait() })
}

@MainActor func makePushCoordinator(_ records: PushDeviceRecords, authorizer: any NotificationAuthorizing = PushStubAuthorizer(.authorized),
                                    registrar: PushStubRegistrar? = nil, sandbox: Bool = false,
                                    now: @escaping @MainActor () -> Date = { Date() },
                                    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) -> PushCoordinator {
    let device = PushDeviceInfo(bundleID: "com.example.sub2", deviceName: { "测试 iPhone" }, timeZone: { "Asia/Shanghai" }, sandbox: sandbox)
    return PushCoordinator(records: records, authorizer: authorizer, registrar: registrar ?? PushStubRegistrar(), device: device, now: now, sleep: sleep)
}
