import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func pushClient(_ transport: ScriptedTransport, credential: Credential = .adminKey("fixture-key")) -> APIClient {
    APIClient(server: stubServer(), credential: credential, deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private func decodeDevice(_ json: String) throws -> PushDevice { try JSONDecoder().decode(PushDevice.self, from: Data(json.utf8)) }
private func bytes(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
private func object(_ value: some Encodable) throws -> [String: String] {
    let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]
    return raw.compactMapValues { $0 as? String }
}
private func keys(_ value: some Encodable) throws -> Set<String> {
    Set((try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]).keys)
}
private func instant(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }

private let fullDevice = #"""
{"id":5,"platform":"ios","token_hint":"a3f0","endpoint_host":"","bundle_id":"com.example.sub2","environment":"sandbox",
"device_name":"测试 iPhone","locale":"zh-Hans","timezone":"Asia/Shanghai","site_tag":"6F9619FF-8B86-D011-B42D-00C04FC964FF",
"enabled":false,"disabled_reason":"unregistered","disabled_at":"2026-10-17T09:41:00.123456789+08:00",
"last_success_at":"2026-10-16T01:00:00Z","last_error":"HTTP 410: Unregistered","last_error_at":"2026-10-17T01:41:00.5Z",
"credentials_encrypted":true,"subscription":{"events":["ops_alert.fired","account.test_finished"],"min_severity":"P2",
"group_ids":[3,8],"platforms":["anthropic"],"quiet_hours":{"start":"23:00","end":"07:00"}},
"created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-17T01:41:00Z"}
"""#
private let siteID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
private let apnsToken = String(repeating: "AB", count: 32)

// MARK: Device decoding (60 §7.2)

@Test func pushDeviceDecodesEveryListedField() throws {
    let device = try decodeDevice(fullDevice)
    #expect(device.id == 5); #expect(device.platform == .ios); #expect(device.rawPlatform == "ios"); #expect(device.tokenHint == "a3f0")
    #expect(device.endpointHost == nil); #expect(device.bundleID == "com.example.sub2"); #expect(device.environment == "sandbox")
    #expect(device.deviceName == "测试 iPhone"); #expect(device.locale == "zh-Hans"); #expect(device.timezone == "Asia/Shanghai")
    #expect(device.siteTag == siteID.uuidString); #expect(device.enabled == false); #expect(device.disabledReason == .unregistered)
    #expect(device.disabledAt == instant("2026-10-17T01:41:00.123Z")); #expect(device.lastSuccessAt == instant("2026-10-16T01:00:00Z"))
    #expect(device.lastError == "HTTP 410: Unregistered"); #expect(device.lastErrorAt == instant("2026-10-17T01:41:00.500Z"))
    #expect(device.credentialsEncrypted == true)
    #expect(device.createdAt == instant("2026-10-01T00:00:00Z")); #expect(device.updatedAt == instant("2026-10-17T01:41:00Z"))
    let subscription = try #require(device.subscription)
    #expect(subscription.events == [.opsAlertFired, .accountTestFinished]); #expect(subscription.minSeverity == .p2)
    #expect(subscription.groupIDs == [3, 8]); #expect(subscription.platforms == ["anthropic"])
    #expect(subscription.quietHours == PushQuietHours(start: "23:00", end: "07:00"))
}

@Test func pushDeviceToleratesMissingNullAndEmptyFields() throws {
    let bare = try decodeDevice(#"{"id":3}"#)
    #expect(bare.platform == nil); #expect(bare.rawPlatform == nil); #expect(bare.enabled); #expect(bare.disabledReason == nil)
    #expect(bare.subscription == nil); #expect(bare.effectiveSubscription == .default); #expect(bare.lastSuccessAt == nil)
    let empty = try decodeDevice(#"""
    {"id":4,"platform":"bark","environment":"","disabled_reason":" ","last_error":"","token_hint":"","device_name":"  ",
    "disabled_at":null,"last_success_at":"not a time","last_error_at":42,"enabled":"yes","subscription":"x","locale":7}
    """#)
    #expect(empty.platform == .bark); #expect(empty.environment == nil); #expect(empty.disabledReason == nil); #expect(empty.lastError == nil)
    #expect(empty.tokenHint == nil); #expect(empty.deviceName == nil); #expect(empty.disabledAt == nil); #expect(empty.lastSuccessAt == nil)
    #expect(empty.lastErrorAt == nil); #expect(empty.enabled); #expect(empty.subscription == nil); #expect(empty.locale == nil)
    let stopped = try decodeDevice(#"{"id":6,"disabled_reason":"topic_mismatch"}"#)
    #expect(stopped.enabled == false); #expect(stopped.disabledReason == .topicMismatch)
    #expect(throws: (any Error).self) { try decodeDevice(#"{"id":0}"#) }
    #expect(throws: (any Error).self) { try decodeDevice(#"{"platform":"ios"}"#) }
}

@Test func pushDeviceKeepsUnknownPlatformAndReasonRaw() throws {
    let device = try decodeDevice(#"{"id":8,"platform":"apns2","disabled_reason":"quota","enabled":false}"#)
    #expect(device.platform == nil); #expect(device.rawPlatform == "apns2"); #expect(device.disabledReason == .other("quota"))
    #expect(try decodeDevice(#"{"id":9,"disabled_reason":"endpoint_gone"}"#).disabledReason == .endpointGone)
    #expect(try decodeDevice(#"{"id":9,"disabled_reason":"bad_device_token"}"#).disabledReason == .badDeviceToken)
    #expect(try decodeDevice(#"{"id":9,"disabled_reason":"secret_undecryptable"}"#).disabledReason == .secretUndecryptable)
    #expect(PushDisabledReason(rawValue: "quota")?.rawValue == "quota"); #expect(PushDisabledReason.topicMismatch.rawValue == "topic_mismatch")
}

@Test func pushDevicesListsItemsAndSkipsUnreadableOnes() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"items":[{"id":2,"platform":"ntfy"},{"platform":"ios"},{"id":0},{"id":"7"},{"id":4}]}"#) }
    let devices = try await pushClient(transport).pushDevices()
    #expect(devices.map(\.id) == [2, 4])
    let list = try #require(await transport.requests.first)
    #expect(list.httpMethod == "GET"); #expect(list.url?.path == "/api/v1/admin/push/devices"); #expect(list.httpBody == nil)
    for body in [#"{"items":null}"#, "{}"] {
        #expect(try await pushClient(ScriptedTransport { _ in okReply(body) }).pushDevices().isEmpty)
    }
}

@Test func pushDevicesReadIsRetriedLikeOtherReads() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(503)), .reply(errorReply(503)), .reply(okReply(#"{"items":[{"id":1}]}"#))])
    #expect(try await pushClient(transport).pushDevices().map(\.id) == [1])
    #expect(await transport.requests.count == 3)
}

// MARK: Registration (00 §7.2, 60 §7.2 / §7.4)

@Test func apnsTokenHexIsLowercaseTwoDigitsPerByte() {
    #expect(PushDeviceRegistration.apnsTokenHex(Data([0xAB, 0x01, 0xFF])) == "ab01ff")
    #expect(PushDeviceRegistration.apnsTokenHex(Data(repeating: 0x0C, count: 32)).count == 64)
}

@Test func iosRegistrationOmitsEnvironmentAndSubscription() throws {
    let registration = PushDeviceRegistration.ios(apnsToken: apnsToken, bundleID: "com.example.sub2", deviceName: "测试 iPhone",
                                                  timezone: "Asia/Shanghai", siteID: siteID, sandbox: false)
    #expect(try keys(registration) == ["platform", "apns_token", "bundle_id", "device_name", "locale", "timezone", "site_tag"])
    let body = try object(registration)
    #expect(body["platform"] == "ios"); #expect(body["apns_token"] == apnsToken.lowercased()); #expect(body["locale"] == "zh-Hans")
    #expect(body["site_tag"] == siteID.uuidString); #expect(body["device_name"] == "测试 iPhone"); #expect(body["timezone"] == "Asia/Shanghai")
    #expect(try !bytes(registration).contains("production"))
}

@Test func iosRegistrationSendsSandboxOnlyWhenAsked() throws {
    let sandbox = PushDeviceRegistration.ios(apnsToken: apnsToken, bundleID: nil, deviceName: "iPhone", timezone: "UTC", siteID: siteID, sandbox: true)
    #expect(try object(sandbox)["environment"] == "sandbox"); #expect(sandbox.environment == "sandbox")
    #expect(try !keys(sandbox).contains("bundle_id"))
    let release = PushDeviceRegistration.ios(apnsToken: apnsToken, bundleID: "  ", deviceName: "iPhone", timezone: "UTC", siteID: siteID, sandbox: false)
    #expect(try !keys(release).contains("environment")); #expect(try !keys(release).contains("bundle_id"))
    for value in [sandbox, release] { #expect(try !bytes(value).contains("production")) }
}

@Test func barkNtfyWebhookRegistrationBodies() throws {
    let bark = PushDeviceRegistration.bark(deviceKey: "barkDeviceKey123", deviceName: "我的 Bark", timezone: "Asia/Shanghai")
    #expect(try object(bark) == ["platform": "bark", "endpoint": "https://api.day.app", "token": "barkDeviceKey123",
                                 "device_name": "我的 Bark", "locale": "zh-Hans", "timezone": "Asia/Shanghai"])
    for blank in [nil, "", "  "] {
        let ntfy = PushDeviceRegistration.ntfy(topic: "ntfyTopic_9", accessToken: blank, deviceName: "ntfy", timezone: "UTC")
        #expect(try object(ntfy) == ["platform": "ntfy", "endpoint": "https://ntfy.sh", "token": "ntfyTopic_9",
                                     "device_name": "ntfy", "locale": "zh-Hans", "timezone": "UTC"])
        #expect(ntfy.hasSecret == false)
    }
    let secured = PushDeviceRegistration.ntfy(endpoint: "https://ntfy.example.com", topic: "alerts", accessToken: "tk_secret", deviceName: "n", timezone: "UTC")
    #expect(try object(secured)["secret"] == "tk_secret"); #expect(try object(secured)["endpoint"] == "https://ntfy.example.com")
    let webhook = PushDeviceRegistration.webhook(endpoint: "https://hooks.example.com/sub2", secret: "webhook-hmac-secret", deviceName: "钩子", timezone: "UTC")
    #expect(try object(webhook) == ["platform": "webhook", "endpoint": "https://hooks.example.com/sub2", "secret": "webhook-hmac-secret",
                                    "device_name": "钩子", "locale": "zh-Hans", "timezone": "UTC"])
    let plain = PushDeviceRegistration.webhook(endpoint: "https://hooks.example.com/sub2", secret: nil, deviceName: "钩子", timezone: "UTC")
    #expect(try !keys(plain).contains("secret"))
    for value in [bark, secured, webhook] {
        let sent = try keys(value)
        #expect(!sent.contains("site_tag")); #expect(!sent.contains("apns_token")); #expect(!sent.contains("subscription"))
    }
}

@Test func registrationAndConfigUpdateRedactSecrets() {
    let pem = "-----BEGIN PRIVATE KEY-----\nPRIVATEKEYBODY\n-----END PRIVATE KEY-----"
    let secrets = [apnsToken, apnsToken.lowercased(), "barkDeviceKey123", "ntfyTopic_9", "ntfy-access-secret", "webhook-hmac-secret",
                   "hooks.example.com", "PRIVATEKEYBODY"]
    let values: [Any] = [
        PushDeviceRegistration.ios(apnsToken: apnsToken, bundleID: nil, deviceName: "iPhone", timezone: "UTC", siteID: siteID, sandbox: false),
        PushDeviceRegistration.bark(deviceKey: "barkDeviceKey123", deviceName: "b", timezone: "UTC"),
        PushDeviceRegistration.ntfy(topic: "ntfyTopic_9", accessToken: "ntfy-access-secret", deviceName: "n", timezone: "UTC"),
        PushDeviceRegistration.webhook(endpoint: "https://hooks.example.com/x", secret: "webhook-hmac-secret", deviceName: "w", timezone: "UTC"),
        PushAPNsConfigUpdate(teamID: "ABCDE12345", privateKey: pem)
    ]
    for value in values {
        var dumped = ""
        dump(value, to: &dumped)
        for text in [String(describing: value), String(reflecting: value), "\(value)", dumped] {
            #expect(text.contains("<redacted>"))
            for secret in secrets { #expect(!text.contains(secret)) }
        }
    }
}

@Test func registerPushDeviceCreatedComesFromBodyThenStatus() async throws {
    let cases: [(status: Int, created: String, expected: Bool)] = [(201, "", true), (200, "", false), (200, #","created":false"#, false),
                                                                   (201, #","created":true"#, true), (200, #","created":true"#, true)]
    let registration = PushDeviceRegistration.bark(deviceKey: "key", deviceName: "b", timezone: "UTC")
    for item in cases {
        let transport = ScriptedTransport { _ in okReply(#"{"id":11,"platform":"bark""# + item.created + "}", status: item.status) }
        let result = try await pushClient(transport).registerPushDevice(registration)
        #expect(result.created == item.expected); #expect(result.device.id == 11); #expect(result.device.platform == .bark)
    }
    let missingID = ScriptedTransport { _ in okReply(#"{"platform":"bark","created":true}"#, status: 201) }
    #expect(await thrownAPIError { _ = try await pushClient(missingID).registerPushDevice(registration) } == APIError.invalidResponse)
}

@Test func registerPushDeviceIsSentOnceAndNotRetried() async throws {
    let registration = PushDeviceRegistration.ios(apnsToken: apnsToken, bundleID: nil, deviceName: "iPhone", timezone: "UTC", siteID: siteID, sandbox: false)
    let transport = ScriptedTransport { _ in errorReply(503) }
    let error = try #require(await thrownAPIError { _ = try await pushClient(transport).registerPushDevice(registration) })
    #expect(error.statusCode == 503)
    let sent = try #require(await transport.requests.first)
    #expect(await transport.requests.count == 1)
    #expect(sent.httpMethod == "POST"); #expect(sent.url?.path == "/api/v1/admin/push/devices")
    #expect(sentHeader(sent, "Content-Type") == "application/json"); #expect(sentHeader(sent, "X-Request-ID") != nil)
    #expect(sent.httpBody == (try JSONEncoder.sorted.encode(registration)))
    let lost = ScriptedTransport { _ in throw URLError(.networkConnectionLost) }
    #expect(await thrownAPIError { _ = try await pushClient(lost).registerPushDevice(registration) } != nil)
    #expect(await lost.requests.count == 1)
}

@Test func registerPushDeviceRejectsIncompleteRegistrationLocally() async throws {
    let incomplete = [
        PushDeviceRegistration.ios(apnsToken: "xyz", bundleID: nil, deviceName: "iPhone", timezone: "UTC", siteID: siteID, sandbox: false),
        PushDeviceRegistration.ios(apnsToken: String(repeating: "a", count: 62), bundleID: nil, deviceName: "i", timezone: "UTC", siteID: siteID, sandbox: false),
        PushDeviceRegistration.bark(deviceKey: " ", deviceName: "b", timezone: "UTC"),
        PushDeviceRegistration.ntfy(endpoint: "", topic: "alerts", accessToken: nil, deviceName: "n", timezone: "UTC"),
        PushDeviceRegistration.webhook(endpoint: "  ", secret: nil, deviceName: "w", timezone: "UTC")
    ]
    let transport = ScriptedTransport { _ in okReply(#"{"id":1}"#) }
    for registration in incomplete {
        #expect(await thrownAPIError { _ = try await pushClient(transport).registerPushDevice(registration) }?.kind == .validation)
    }
    #expect(await transport.requests.isEmpty)
}

// MARK: Subscription (00 §7.3)

@Test func subscriptionEncodesWholeObjectWithNullQuietHours() throws {
    #expect(try bytes(PushSubscription(events: [])) == #"{"events":[],"group_ids":[],"min_severity":"P1","platforms":[],"quiet_hours":null}"#)
    #expect(PushSubscription(events: []).isPaused); #expect(PushSubscription.default.events == [.opsAlertFired, .accountError])
}

@Test func subscriptionEncodingIsNormalized() throws {
    let subscription = PushSubscription(events: [.accountTestFinished, .opsAlertFired, .accountTestFinished], minSeverity: .p0, groupIDs: [5, 3, 5],
                                        platforms: [" OpenAI", "anthropic", "openai", " "], quietHours: PushQuietHours(start: "23:00", end: "07:00"))
    #expect(try bytes(subscription) == #"{"events":["ops_alert.fired","account.test_finished"],"group_ids":[3,5],"min_severity":"P0","platforms":["anthropic","openai"],"quiet_hours":{"end":"07:00","start":"23:00"}}"#)
    let empty = PushSubscription(events: [.accountError], quietHours: PushQuietHours(start: "08:00", end: "08:00"))
    #expect(try bytes(empty).hasSuffix(#""quiet_hours":null}"#)); #expect(empty.normalized.quietHours == nil)
}

@Test func subscriptionDecodingIsTolerant() throws {
    func decode(_ json: String) throws -> PushSubscription { try JSONDecoder().decode(PushSubscription.self, from: Data(json.utf8)) }
    #expect(try decode("{}").events == PushSubscription.default.events)
    #expect(try decode(#"{"events":null}"#).events == PushSubscription.default.events)
    #expect(try decode(#"{"events":[]}"#).isPaused)
    #expect(try decode(#"{"events":["account.error","push.test",3]}"#).events == [.accountError])
    #expect(try decode("{}").minSeverity == .p1); #expect(try decode(#"{"min_severity":"P9"}"#).minSeverity == .p1)
    #expect(try decode(#"{"min_severity":"P3"}"#).minSeverity == .p3)
    #expect(try decode(#"{"group_ids":[1,"2",3],"platforms":["openai",7]}"#).groupIDs == [1, 3])
    #expect(try decode(#"{"platforms":["openai",7]}"#).platforms == ["openai"])
    for window in [#"{"start":"24:00","end":"07:00"}"#, #"{"start":"7:00","end":"08:00"}"#, #"{"start":"07:00"}"#, "null", #""23:00""#] {
        #expect(try decode(#"{"quiet_hours":"# + window + "}").quietHours == nil)
    }
    let full = PushSubscription(events: [.opsAlertFired, .opsAlertResolved], minSeverity: .p2, groupIDs: [1, 9], platforms: ["gemini"],
                                quietHours: PushQuietHours(start: "22:30", end: "06:15"))
    #expect(try JSONDecoder().decode(PushSubscription.self, from: JSONEncoder().encode(full)) == full)
}

@Test func subscriptionValidationLimitsBlockSending() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"id":9}"#) }
    let client = pushClient(transport)
    let invalid = [PushSubscription(events: [.accountError], groupIDs: Array(1...101)), PushSubscription(events: [], groupIDs: [0]),
                   PushSubscription(events: [], platforms: (1...21).map { "p\($0)" }), PushSubscription(events: [], platforms: ["open ai"]),
                   PushSubscription(events: [], platforms: [String(repeating: "a", count: 33)])]
    for subscription in invalid {
        #expect(await thrownAPIError { _ = try await client.updatePushSubscription(id: 9, subscription) }?.kind == .validation)
    }
    #expect(await transport.requests.isEmpty)
    _ = try await client.updatePushSubscription(id: 9, PushSubscription(events: [], groupIDs: Array(1...100), platforms: (1...20).map { "p\($0)" }))
    #expect(await transport.requests.count == 1)
}

@Test func quietHoursClockConversion() throws {
    for valid in ["00:00", "23:59", " 07:30 "] { #expect(PushQuietHours(start: valid, end: "12:00") != nil) }
    for invalid in ["24:00", "7:00", "07:60", "", "0730", "07-30", "٠٧:٣٠"] { #expect(PushQuietHours(start: invalid, end: "12:00") == nil) }
    let window = try #require(PushQuietHours(start: "23:00", end: "07:00"))
    #expect(window.startMinute == 1_380); #expect(window.endMinute == 420); #expect(window.isEffective)
    #expect(window.start == "23:00"); #expect(window.end == "07:00")
    #expect(PushQuietHours(startMinute: 0, endMinute: 1_439)?.end == "23:59")
    #expect(PushQuietHours(startMinute: 1_440, endMinute: 0) == nil); #expect(PushQuietHours(startMinute: 0, endMinute: -1) == nil)
    #expect(PushQuietHours.clock(minuteOfDay: 420) == "07:00"); #expect(PushQuietHours.clock(minuteOfDay: 1_440) == nil)
    #expect(PushQuietHours.minuteOfDay("09:05") == 545); #expect(PushQuietHours(start: "08:00", end: "08:00")?.isEffective == false)
}

@Test func updatePushSubscriptionPutsWholeObjectAndReturnsDevice() async throws {
    let reply = #"{"id":9,"platform":"ios","subscription":{"events":[],"min_severity":"P1","group_ids":[],"platforms":[],"quiet_hours":null}}"#
    let transport = ScriptedTransport { _ in okReply(reply) }
    let client = pushClient(transport)
    let device = try await client.updatePushSubscription(id: 9, PushSubscription(events: []))
    #expect(device.id == 9); #expect(device.subscription?.isPaused == true)
    let sent = try #require(await transport.requests.first)
    #expect(sent.httpMethod == "PUT"); #expect(sent.url?.path == "/api/v1/admin/push/devices/9/subscription")
    #expect(sent.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"events":[],"group_ids":[],"min_severity":"P1","platforms":[],"quiet_hours":null}"#)
    #expect(await thrownAPIError { _ = try await client.updatePushSubscription(id: 0, .default) }?.kind == .validation)
    #expect(await transport.requests.count == 1)
    let refused = ScriptedTransport { _ in errorReply(400, reason: "INVALID_PUSH_SUBSCRIPTION", extra: #","metadata":{"field":"events"}"#) }
    let error = try #require(await thrownAPIError { _ = try await pushClient(refused).updatePushSubscription(id: 9, .default) })
    #expect(error.reason == "INVALID_PUSH_SUBSCRIPTION"); #expect(error.metadata["field"] == "events")
    #expect(await refused.requests.count == 1)
}

@Test func testPushDevicePostsWithoutBody() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"delivered":true,"provider_status":200}"#) }
    let result = try await pushClient(transport).testPushDevice(id: 4)
    #expect(result == PushTestResult(delivered: true, providerStatus: 200))
    let sent = try #require(await transport.requests.first)
    #expect(sent.httpMethod == "POST"); #expect(sent.url?.path == "/api/v1/admin/push/devices/4/test"); #expect(sent.httpBody == nil)
    #expect(try await pushClient(ScriptedTransport { _ in okReply("{}") }).testPushDevice(id: 4) == PushTestResult(delivered: true, providerStatus: nil))
    let failed = ScriptedTransport { _ in
        errorReply(502, reason: "PUSH_DELIVERY_FAILED", extra: #","metadata":{"provider_reason":"BadDeviceToken","provider_status":400}"#)
    }
    let error = try #require(await thrownAPIError { _ = try await pushClient(failed).testPushDevice(id: 4) })
    #expect(error.metadata["provider_reason"] == "BadDeviceToken"); #expect(error.metadata["provider_status"] == "400")
    #expect(await failed.requests.count == 1)
}

// MARK: Site APNs settings (60 §7.2 / §7.4)

@Test func pushConfigDecodesWithDefaults() async throws {
    let full = #"""
    {"apns_enabled":true,"apns_team_id":"ABCDE12345","apns_key_id":"KEY1234567","apns_private_key_configured":true,"apns_topic":"com.example.sub2",
    "apns_environment":"sandbox","encryption_key_configured":true,"ready":true}
    """#
    let transport = ScriptedTransport { _ in okReply(full) }
    let config = try await pushClient(transport).pushConfig()
    #expect(config == PushAPNsConfig(enabled: true, teamID: "ABCDE12345", keyID: "KEY1234567", privateKeyConfigured: true,
                                     topic: "com.example.sub2", environment: .sandbox, encryptionKeyConfigured: true, ready: true))
    let get = try #require(await transport.requests.first)
    #expect(get.httpMethod == "GET"); #expect(get.url?.path == "/api/v1/admin/push/config")
    let empty = try JSONDecoder().decode(PushAPNsConfig.self, from: Data("{}".utf8))
    #expect(empty == PushAPNsConfig())
    #expect(empty.enabled == false); #expect(empty.ready == false); #expect(empty.environment == .production); #expect(empty.topic == nil)
    let odd = try JSONDecoder().decode(PushAPNsConfig.self, from: Data(#"{"apns_topic":"","apns_environment":"weird","apns_team_id":""}"#.utf8))
    #expect(odd.topic == nil); #expect(odd.environment == .production); #expect(odd.teamID == nil)
}

@Test func apnsConfigUpdateContainsOnlyChangedFields() throws {
    let current = PushAPNsConfig(enabled: true, teamID: "ABCDE12345", keyID: "KEY1234567", privateKeyConfigured: true, topic: "com.example.sub2", ready: true)
    func update(enabled: Bool = true, team: String = "ABCDE12345", key: String = "KEY1234567", privateKey: String? = nil,
                topic: String = "com.example.sub2", environment: PushAPNsEnvironment = .production) -> PushAPNsConfigUpdate {
        PushAPNsConfigUpdate(changesFrom: current, enabled: enabled, teamID: team, keyID: key, privateKey: privateKey, topic: topic, environment: environment)
    }
    #expect(update().isEmpty); #expect(try bytes(update()) == "{}")
    #expect(update(team: " abcde12345 ").isEmpty)
    #expect(try bytes(update(key: "NEWKEY1234")) == #"{"apns_key_id":"NEWKEY1234"}"#)
    #expect(try bytes(update(topic: " ")) == #"{"apns_topic":""}"#)
    #expect(try bytes(update(environment: .sandbox)) == #"{"apns_environment":"sandbox"}"#)
    #expect(try bytes(update(enabled: false)) == #"{"apns_enabled":false}"#)
    for blank in [nil, "", " \n "] {
        #expect(update(privateKey: blank).includesPrivateKey == false); #expect(update(privateKey: blank).isEmpty)
    }
    let pem = "-----BEGIN PRIVATE KEY-----\nMIGTAgEA\n-----END PRIVATE KEY-----\n"
    let withKey = update(privateKey: pem)
    #expect(withKey.includesPrivateKey); #expect(!withKey.isEmpty)
    #expect(try object(withKey) == ["apns_private_key": pem])
    let fresh = PushAPNsConfigUpdate(changesFrom: PushAPNsConfig(), enabled: false, teamID: "abcde12345", keyID: "", privateKey: nil, topic: "", environment: .production)
    #expect(try bytes(fresh) == #"{"apns_team_id":"ABCDE12345"}"#)
}

@Test func updatePushConfigPutsChangesAndDoesNotResendAfterStepUpRefusal() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"apns_enabled":false,"apns_environment":"sandbox","ready":false}"#) }
    let config = try await pushClient(transport).updatePushConfig(PushAPNsConfigUpdate(environment: .sandbox))
    #expect(config.environment == .sandbox); #expect(config.ready == false)
    let sent = try #require(await transport.requests.first)
    #expect(sent.httpMethod == "PUT"); #expect(sent.url?.path == "/api/v1/admin/push/config")
    #expect(sent.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"apns_environment":"sandbox"}"#)
    let stepUp = ScriptedTransport { _ in errorReply(403, reason: "STEP_UP_REQUIRED") }
    let refused = try #require(await thrownAPIError { _ = try await pushClient(stepUp, credential: stubTokens()).updatePushConfig(PushAPNsConfigUpdate(enabled: true)) })
    #expect(refused.reason == "STEP_UP_REQUIRED"); #expect(await stepUp.requests.count == 1)
    let invalid = ScriptedTransport { _ in errorReply(400, reason: "INVALID_APNS_CONFIG", extra: #","metadata":{"field":"apns_team_id"}"#) }
    let error = try #require(await thrownAPIError { _ = try await pushClient(invalid).updatePushConfig(PushAPNsConfigUpdate(teamID: "X")) })
    #expect(error.reason == "INVALID_APNS_CONFIG"); #expect(error.metadata["field"] == "apns_team_id")
}

private extension JSONEncoder {
    static var sorted: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder }
}
