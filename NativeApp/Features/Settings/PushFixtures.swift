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
    // S6-24: the push page's launch arguments and the site's APNs settings (its MARK section at the end of the file).
    private let arguments: [String]
    private var config: PushAPNsConfig

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
        config = PushEditFixture.config(PushFixture.config(arguments: arguments), arguments: arguments)
        let targets = PushFixture.otherTargets
        stored = targets.map(\.0)
        identities = Dictionary(uniqueKeysWithValues: targets.compactMap { device, registration in Self.identity(of: registration).map { (device.id, $0) } })
    }

    func registerPushDevice(_ registration: PushDeviceRegistration) async throws -> (device: PushDevice, created: Bool) {
        if arguments.contains(PushFixture.registerFailsArgument) { throw PushFixture.limitReached }
        if registration.platform != .ios { try Self.checkTarget(registration) }
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

// MARK: - S6-24 推送设置页与接收方式详情

/// The push page's launch arguments and ids. `-ui-push-denied` and `-ui-push-no-capability` are S6-23's.
enum PushFixture {
    /// APNs not enabled and no private key: `ready` false.
    static let notReadyArgument = "-ui-push-not-ready"
    /// `GET admin/push/config` answers 403 FORBIDDEN.
    static let configFailsArgument = "-ui-push-config-fails"
    /// This phone's target 11 is registered and on, last delivered a day ago.
    static let localOnArgument = "-ui-push-local-on"
    /// This phone's target 11 is registered but stopped as `unregistered`.
    static let localUnregisteredArgument = "-ui-push-local-unregistered"
    /// Every subscription PUT answers 500.
    static let subscriptionFailsArgument = "-ui-push-subscription-fails"
    /// Every test answers 502 PUSH_DELIVERY_FAILED (BadDeviceToken, 400) and stops the target as `bad_device_token`.
    static let testFailsArgument = "-ui-push-test-fails"
    /// Every registration answers 409 PUSH_DEVICE_LIMIT_REACHED (max 20), on every platform (S6D2b-06).
    static let registerFailsArgument = "-ui-push-register-fails"
    /// Every list read answers 503 SERVICE_UNAVAILABLE.
    static let listFailsArgument = "-ui-push-list-fails"
    /// A device whose deletion failed when signing out waits for the next login (00 §7.6).
    static let pendingDeletionArgument = "-ui-push-pending-deletion"
    static let localID = 11
    static let barkID = 12
    static let webhookID = 13
    static let pendingDeletionID = 99

    static let limitReached = APIError.server(status: 409, envelope: ErrorEnvelope(reason: "PUSH_DEVICE_LIMIT_REACHED", metadata: ["max": "20"]))
    static let notFound = APIError.server(status: 404, reason: PushWriteFailure.notFoundReason)
    static let providerRefusal = APIError.server(status: 502, envelope: ErrorEnvelope(reason: "PUSH_DELIVERY_FAILED",
                                                                                      metadata: ["provider_reason": "BadDeviceToken", "provider_status": "400"]))

    static func config(arguments: [String]) -> PushAPNsConfig {
        guard arguments.contains(notReadyArgument) else {
            return PushAPNsConfig(enabled: true, teamID: "ABCDE12345", keyID: "KEY1234567", privateKeyConfigured: true, encryptionKeyConfigured: true,
                                  ready: true)
        }
        return PushAPNsConfig(enabled: false, teamID: "ABCDE12345", keyID: "KEY1234567", encryptionKeyConfigured: true, ready: false)
    }
    /// 我的 Bark (on) and a nameless Webhook the provider stopped (`endpoint_gone`); neither carries a site tag.
    static var otherTargets: [(PushDevice, PushDeviceRegistration)] {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let bark = PushDeviceRegistration.bark(deviceKey: "fixturek3y9", deviceName: "我的 Bark", timezone: "Asia/Shanghai")
        let webhook = PushDeviceRegistration.webhook(endpoint: "https://hooks.example.com/sub2", secret: nil, deviceName: "", timezone: "Asia/Shanghai")
        return [(PushDevice(id: barkID, platform: .bark, tokenHint: "k3y9", endpointHost: "api.day.app", deviceName: "我的 Bark",
                            timezone: "Asia/Shanghai", subscription: .default, createdAt: created, updatedAt: created), bark),
                (PushDevice(id: webhookID, platform: .webhook, endpointHost: "hooks.example.com", timezone: "Asia/Shanghai", enabled: false,
                            disabledReason: .endpointGone, disabledAt: created, subscription: .default, createdAt: created, updatedAt: created), webhook)]
    }
}

extension PushDemoStore: PushSettingsSource {
    func pushDevices() async throws -> [PushDevice] {
        if arguments.contains(PushFixture.listFailsArgument) { throw APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE") }
        return devices()
    }
    func pushConfig() async throws -> PushAPNsConfig {
        if arguments.contains(PushFixture.configFailsArgument) { throw APIError.server(status: 403, reason: "FORBIDDEN") }
        return config
    }
    /// Stored as the backend normalizes it and echoed.
    func updatePushSubscription(id: Int, _ subscription: PushSubscription) async throws -> PushDevice {
        if arguments.contains(PushFixture.subscriptionFailsArgument) { throw APIError.server(status: 500, reason: nil) }
        try subscription.validate()
        guard let index = stored.firstIndex(where: { $0.id == id }) else { throw PushFixture.notFound }
        let device = stored[index]
        stored[index] = Self.revised(device, subscription: subscription.normalized, disabledReason: device.disabledReason,
                                     lastSuccessAt: device.lastSuccessAt, lastError: device.lastError, lastErrorAt: device.lastErrorAt)
        return stored[index]
    }
    /// Delivered: the target is enabled again with a new delivery time (MarkDeviceSuccess).
    func testPushDevice(id: Int) async throws -> PushTestResult {
        guard let index = stored.firstIndex(where: { $0.id == id }) else { throw PushFixture.notFound }
        let device = stored[index], now = Date()
        if arguments.contains(PushFixture.testFailsArgument) {
            stored[index] = Self.revised(device, subscription: device.subscription, disabledReason: .badDeviceToken, lastSuccessAt: device.lastSuccessAt,
                                         lastError: "HTTP 400: BadDeviceToken", lastErrorAt: now)
            throw PushFixture.providerRefusal
        }
        stored[index] = Self.revised(device, subscription: device.subscription, disabledReason: nil, lastSuccessAt: now,
                                     lastError: device.lastError, lastErrorAt: device.lastErrorAt)
        return PushTestResult(delivered: true, providerStatus: 200)
    }
    /// This phone's target as S6-23's fixture registrar would have registered it for the site, so turning the switch on
    /// again answers the same id (S6D2b-06).
    func seedLocalDevice(id: Int, serverID: UUID, tokenHex: String, disabledReason: PushDisabledReason?) {
        let registration = PushDeviceRegistration.ios(apnsToken: tokenHex, bundleID: "com.chengzixqq.sub2mobile", deviceName: "UI 测试 iPhone",
                                                      timezone: "Asia/Shanghai", siteID: serverID, sandbox: false)
        let now = Date()
        let device = PushDevice(id: id, platform: .ios, tokenHint: String(tokenHex.suffix(4)), bundleID: registration.bundleID,
                                deviceName: registration.deviceName, locale: PushDeviceRegistration.locale, timezone: registration.timezone,
                                siteTag: registration.siteTag, enabled: disabledReason == nil, disabledReason: disabledReason,
                                disabledAt: disabledReason == nil ? nil : now, lastSuccessAt: now.addingTimeInterval(-86_400),
                                subscription: .default, createdAt: now.addingTimeInterval(-7 * 86_400), updatedAt: now)
        seed(device, registeredAs: registration)
    }
    /// The device whose deletion failed (`-ui-push-pending-deletion`): an older registration of this phone the server still
    /// holds, listed under 其他接收方式, where the pending banner sends the user (U-23).
    func seedPendingDevice() {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        stored.removeAll { $0.id == PushFixture.pendingDeletionID }
        stored.append(PushDevice(id: PushFixture.pendingDeletionID, platform: .ios, tokenHint: "0f3c", bundleID: "com.chengzixqq.sub2mobile",
                                 deviceName: "旧 iPhone", timezone: "Asia/Shanghai", subscription: .default, createdAt: created, updatedAt: created))
    }

    private func seed(_ device: PushDevice, registeredAs registration: PushDeviceRegistration) {
        stored.removeAll { $0.id == device.id }
        stored.append(device)
        identities[device.id] = Self.identity(of: registration)
    }
    private static func identity(of registration: PushDeviceRegistration) -> Identity? {
        (try? fields(of: registration)).map { Identity(platform: registration.platform, siteTag: registration.siteTag, key: $0.key) }
    }
    private static func revised(_ device: PushDevice, subscription: PushSubscription?, disabledReason: PushDisabledReason?, lastSuccessAt: Date?,
                                lastError: String?, lastErrorAt: Date?) -> PushDevice {
        PushDevice(id: device.id, platform: device.platform, rawPlatform: device.rawPlatform, tokenHint: device.tokenHint, endpointHost: device.endpointHost,
                   bundleID: device.bundleID, environment: device.environment, deviceName: device.deviceName, locale: device.locale,
                   timezone: device.timezone, siteTag: device.siteTag, enabled: disabledReason == nil, disabledReason: disabledReason,
                   disabledAt: disabledReason == nil ? nil : device.disabledAt ?? Date(), lastSuccessAt: lastSuccessAt, lastError: lastError,
                   lastErrorAt: lastErrorAt, credentialsEncrypted: device.credentialsEncrypted, subscription: subscription,
                   createdAt: device.createdAt, updatedAt: Date())
    }
}

extension DemoData {
    /// The push page's source. Under `-ui-testing` each site's records are seeded once per launch — the pending deletion
    /// first, as `apply` clears the registered id — and this phone's target 11 is put in the store; callers read the records
    /// after this returns (S6D2b-06).
    @MainActor static func pushSettingsSource(serverID: UUID, records: PushDeviceRecords) async -> any PushSettingsSource {
        if let seeding = pushSeeds[serverID] { await seeding.value; return pushStore }
        let arguments = ProcessInfo.processInfo.arguments
        let seedsPending = arguments.contains(PushFixture.pendingDeletionArgument)
        if seedsPending {
            records.apply(TeardownReport(failedPushDeviceIDs: [PushFixture.pendingDeletionID]), serverID: serverID)
        }
        let unregistered = arguments.contains(PushFixture.localUnregisteredArgument)
        let seedsLocal = unregistered || arguments.contains(PushFixture.localOnArgument)
        if seedsLocal {
            records.setRegisteredDeviceID(PushFixture.localID, serverID: serverID)
            records.setLocalPushOn(true, serverID: serverID)
        }
        let seeding = Task {
            if seedsPending { await pushStore.seedPendingDevice() }
            guard seedsLocal else { return }
            await pushStore.seedLocalDevice(id: PushFixture.localID, serverID: serverID, tokenHex: FixtureRemoteRegistrar.fixedTokenHex,
                                            disabledReason: unregistered ? .unregistered : nil)
        }
        pushSeeds[serverID] = seeding
        await seeding.value
        return pushStore
    }
    @MainActor private static var pushSeeds: [UUID: Task<Void, Never>] = [:]
}

// MARK: - S6-25 添加接收方式与 APNs 配置

/// S6-25's launch argument and the fixture site's private key.
enum PushEditFixture {
    /// `encryption_key_configured` is false: a private key is refused with SECRET_ENCRYPTION_KEY_NOT_CONFIGURED.
    static let noEncryptionKeyArgument = "-ui-apns-no-encryption-key"
    /// Every APNs save is stored, then answered 502 without a reason: the App cannot tell it was saved.
    static let saveUnconfirmedArgument = "-ui-apns-save-unconfirmed"
    /// The only key the fixture site takes (made-up base64, not a key); any other well-formed PEM is “not P-256”.
    static let acceptedPrivateKey = "-----BEGIN PRIVATE KEY-----\nU1VCMi1VSS1URVNULUZJWFRVUkU=\n-----END PRIVATE KEY-----"

    /// S6-24's settings with this launch's encryption key.
    static func config(_ config: PushAPNsConfig, arguments: [String]) -> PushAPNsConfig {
        PushAPNsConfig(enabled: config.enabled, teamID: config.teamID, keyID: config.keyID, privateKeyConfigured: config.privateKeyConfigured,
                       topic: config.topic, environment: config.environment,
                       encryptionKeyConfigured: !arguments.contains(noEncryptionKeyArgument), ready: config.ready)
    }
    static func invalidConfig(_ field: String) -> APIError {
        .server(status: 400, envelope: ErrorEnvelope(reason: "INVALID_APNS_CONFIG", metadata: ["field": field]))
    }
}

extension PushDemoStore {
    /// A Bark, ntfy or Webhook address the backend refuses with push_targets' defaults: not https, or a local or private
    /// host → 400 INVALID_PUSH_TARGET (field endpoint).
    static func checkTarget(_ registration: PushDeviceRegistration) throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(registration)) as? [String: Any] ?? [:]
        let parts = URLComponents(string: body["endpoint"] as? String ?? "")
        guard parts?.scheme?.lowercased() == "https", let host = parts?.host?.lowercased(), !host.isEmpty, !isPrivateHost(host) else {
            throw APIError.server(status: 400, envelope: ErrorEnvelope(reason: "INVALID_PUSH_TARGET", metadata: ["field": "endpoint"]))
        }
    }
    /// PUT admin/push/config in the backend's order (push_config_service.go): the IDs, Topic and environment, then the private
    /// key, then APNs on without all three; saved and returned with `ready` worked out again.
    func updateConfig(_ update: PushAPNsConfigUpdate) throws -> PushAPNsConfig {
        let current = config
        let team = try Self.identifier(update.teamID, current: current.teamID, field: "apns_team_id")
        let key = try Self.identifier(update.keyID, current: current.keyID, field: "apns_key_id")
        var topic = current.topic
        if let raw = update.topic?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard raw.isEmpty || APNsConfigDraft.isBundleID(raw) else { throw PushEditFixture.invalidConfig("apns_topic") }
            topic = raw.isEmpty ? nil : raw
        }
        var hasKey = current.privateKeyConfigured
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any] ?? [:]
        if let pem = (body["apns_private_key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !pem.isEmpty {
            guard pem == PushEditFixture.acceptedPrivateKey else { throw PushEditFixture.invalidConfig("apns_private_key") }
            guard current.encryptionKeyConfigured else { throw APIError.server(status: 400, reason: "SECRET_ENCRYPTION_KEY_NOT_CONFIGURED") }
            hasKey = true
        }
        let enabled = update.enabled ?? current.enabled, complete = team != nil && key != nil && hasKey
        guard !enabled || complete else { throw PushEditFixture.invalidConfig("apns_enabled") }
        config = PushAPNsConfig(enabled: enabled, teamID: team, keyID: key, privateKeyConfigured: hasKey, topic: topic,
                                environment: update.environment ?? current.environment, encryptionKeyConfigured: current.encryptionKeyConfigured,
                                ready: enabled && complete)
        if arguments.contains(PushEditFixture.saveUnconfirmedArgument) { throw APIError.server(status: 502, reason: nil) }
        return config
    }

    private static func identifier(_ new: String?, current: String?, field: String) throws -> String? {
        guard let new else { return current }
        let value = new.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.isEmpty || APNsConfigDraft.isAPNsIdentifier(value) else { throw PushEditFixture.invalidConfig(field) }
        return value.isEmpty ? nil : value
    }
    /// localhost, .local and the private, loopback and link-local IPv4 ranges.
    private static func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (169, 254), (192, 168): return true
        case (172, let second): return (16...31).contains(second)
        default: return false
        }
    }
}
