import Foundation
import Sub2Core

// X05: the push chapter's UI-test data. S6-24 and S6-25 add their own MARK sections at the end of this file, and one branch
// each at the top of PushDemoStore.registerPushDevice (S6D2b-06).

// MARK: - S6-23 推送协调器、登记与点按

extension DemoData {
    /// The system is never asked: `-ui-push-denied` refuses notifications, `-ui-push-no-capability` is a build without the
    /// push entitlement. The device details are fixed.
    @MainActor static func pushCoordinator(records: PushDeviceRecords) -> PushCoordinator {
        let arguments = ProcessInfo.processInfo.arguments
        return PushCoordinator(records: records, authorizer: FixtureNotificationAuthorizer(denies: arguments.contains("-ui-push-denied")),
                               registrar: FixtureRemoteRegistrar(isCapable: !arguments.contains("-ui-push-no-capability")),
                               device: PushDeviceInfo(bundleID: "com.chengzixqq.sub2mobile", deviceName: { "UI 测试 iPhone" },
                                                      timeZone: { "Asia/Shanghai" }, sandbox: false))
    }
    /// Every fixture site's push devices, for the whole run.
    static let pushStore = PushDemoStore()

    /// `-ui-push-tap <type>[:<id>]@<站点名>` with an optional `-ui-push-tap-when <站点名>` (the target site by default): about
    /// 300 ms after that site connects, a notification of the target site is tapped, with the backend's payload, through the
    /// same PushDeepLink.parse and openTap as the system's (00 §7.5). A name no site has is sent as is. Once per launch.
    @MainActor static func deliverPushTapFixture(after connected: ServerProfile, model: AppModel) {
        guard !pushTapDelivered, let fixture = PushTapFixture(arguments: ProcessInfo.processInfo.arguments), fixture.when == connected.name else { return }
        pushTapDelivered = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            let site = model.profiles.first { $0.name == fixture.site }?.id.uuidString ?? fixture.site
            await model.pushCoordinator.openTap(PushDeepLink.parse(fixture.payload(site: site)), navigator: model)
        }
    }
    @MainActor private static var pushTapDelivered = false
}

/// `-ui-push-tap ops_alert.fired:41@推送站点`.
private struct PushTapFixture: Sendable {
    let type: String
    let id: Int?
    let site: String
    let when: String

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-ui-push-tap"), arguments.indices.contains(index + 1),
              let at = arguments[index + 1].lastIndex(of: "@") else { return nil }
        let spec = arguments[index + 1]
        let head = spec[..<at].split(separator: ":", maxSplits: 1)
        guard let type = head.first else { return nil }
        self.type = String(type)
        id = head.count > 1 ? Int(head[1]) : nil
        site = String(spec[spec.index(after: at)...])
        let whenIndex = arguments.firstIndex(of: "-ui-push-tap-when").map { $0 + 1 }
        when = whenIndex.flatMap { arguments.indices.contains($0) ? arguments[$0] : nil } ?? site
    }

    /// push_sender_apns.go apnsPayload: `aps`, `type`, `site` and the ids as JSON numbers (NSNumber in userInfo).
    func payload(site: String) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = ["aps": ["alert": ["title": "UI 测试", "body": "推送点按"], "sound": "default"], "type": type, "site": site]
        guard let id else { return info }
        switch type {
        case PushEvent.opsAlertFired.rawValue, PushEvent.opsAlertResolved.rawValue:
            info["alert_event_id"] = NSNumber(value: id); info["rule_id"] = NSNumber(value: 3)
        case PushEvent.accountTestFinished.rawValue:
            info["account_id"] = NSNumber(value: id); info["run_id"] = "tr_fixture"; info["status"] = "success"
        default: info["account_id"] = NSNumber(value: id)
        }
        return info
    }
}

/// Undetermined until asked, then granted; `-ui-push-denied` starts and stays denied.
actor FixtureNotificationAuthorizer: NotificationAuthorizing {
    private var status: PushAuthorization
    init(denies: Bool) { status = denies ? .denied : .notDetermined }
    func authorizationStatus() async -> PushAuthorization { status }
    func requestAuthorization() async throws -> Bool {
        guard status != .denied else { return false }
        status = .authorized
        return true
    }
}

/// The simulator has no APNs token: a fixed one on the next turn, or the failure of a build without the entitlement.
@MainActor struct FixtureRemoteRegistrar: RemoteNotificationRegistering {
    nonisolated static let fixedToken = Data((0..<32).map { UInt8($0 * 7) })
    nonisolated static var fixedTokenHex: String { PushDeviceRegistration.apnsTokenHex(fixedToken) }
    let isCapable: Bool

    func registerForRemoteNotifications(reportingTo coordinator: PushCoordinator) {
        let isCapable = isCapable
        Task { @MainActor in
            if isCapable { coordinator.didReceiveDeviceToken(Self.fixedToken) } else { coordinator.didFailToRegister(FixtureNoPushEntitlement()) }
        }
    }
}
private struct FixtureNoPushEntitlement: Error {}

/// The fixture sites' push devices (S6D2b-06). One device per platform, site tag and token key (iOS: `apns_token`; Bark, ntfy
/// and Webhook: endpoint and token, without a site tag), as the backend keeps one row per token: registering it again keeps
/// the id, enables it and keeps its subscription; a new one gets the next id from 9001 and the default subscription.
actor PushDemoStore: PushDeviceAPI {
    private struct Identity: Hashable { let platform: PushPlatform; let siteTag: String?; let key: String }
    private var stored: [PushDevice] = []
    private var identities: [Int: Identity] = [:]
    private var nextID = 9001

    func registerPushDevice(_ registration: PushDeviceRegistration) async throws -> (device: PushDevice, created: Bool) {
        try registration.validate()
        let fields = try Self.fields(of: registration)
        let identity = Identity(platform: registration.platform, siteTag: registration.siteTag, key: fields.key)
        if let id = identities.first(where: { $0.value == identity })?.key, let index = stored.firstIndex(where: { $0.id == id }) {
            stored[index] = Self.enabledAgain(stored[index])
            return (stored[index], false)
        }
        let now = Date()
        let device = PushDevice(id: nextID, platform: registration.platform, tokenHint: fields.hint, endpointHost: fields.host,
                                bundleID: registration.bundleID, environment: registration.environment, deviceName: registration.deviceName,
                                locale: PushDeviceRegistration.locale, timezone: registration.timezone, siteTag: registration.siteTag,
                                subscription: .default, createdAt: now, updatedAt: now)
        nextID += 1
        stored.append(device)
        identities[device.id] = identity
        return (device, true)
    }
    func deletePushDevice(id: Int) async throws {
        guard let index = stored.firstIndex(where: { $0.id == id }) else { throw APIError.server(status: 404, reason: "PUSH_DEVICE_NOT_FOUND") }
        stored.remove(at: index)
        identities[id] = nil
    }
    func devices() -> [PushDevice] { stored.sorted { $0.id < $1.id } }

    /// The request body is the only way to the token: PushDeviceRegistration keeps it private.
    private static func fields(of registration: PushDeviceRegistration) throws -> (key: String, hint: String?, host: String?) {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(registration)) as? [String: Any] ?? [:]
        let token = body[registration.platform == .ios ? "apns_token" : "token"] as? String ?? ""
        let endpoint = body["endpoint"] as? String
        return ((endpoint ?? "") + " " + token, token.isEmpty ? nil : String(token.suffix(4)), endpoint.flatMap { URL(string: $0)?.host() })
    }
    private static func enabledAgain(_ device: PushDevice) -> PushDevice {
        PushDevice(id: device.id, platform: device.platform, rawPlatform: device.rawPlatform, tokenHint: device.tokenHint, endpointHost: device.endpointHost,
                   bundleID: device.bundleID, environment: device.environment, deviceName: device.deviceName, locale: device.locale,
                   timezone: device.timezone, siteTag: device.siteTag, lastSuccessAt: device.lastSuccessAt, lastError: device.lastError,
                   lastErrorAt: device.lastErrorAt, credentialsEncrypted: device.credentialsEncrypted, subscription: device.subscription,
                   createdAt: device.createdAt, updatedAt: Date())
    }
}
