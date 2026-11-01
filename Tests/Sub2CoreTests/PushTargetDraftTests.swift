import Foundation
import Testing
@testable import Sub2Core

private func body(_ value: some Encodable) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]
}
private func failure(_ status: Int, _ reason: String?, _ metadata: [String: String] = [:], outcome: SecurityPromptOutcome? = nil) -> APIError {
    let base = APIError.server(status: status, envelope: ErrorEnvelope(reason: reason, metadata: metadata))
    return outcome.map(base.withSecurityOutcome) ?? base
}
private func everything(_ value: Any) -> String {
    var dumped = ""
    dump(value, to: &dumped)
    return [String(describing: value), String(reflecting: value), "\(value)", dumped].joined(separator: "\n")
}
private let pem = "-----BEGIN PRIVATE KEY-----\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49\nAwEHBG0wawIBAQQgFIXTUREKEY==\n-----END PRIVATE KEY-----"
private let lostConnection = APIError(kind: .transport, message: "无法连接站点")
private let notReady = PushAPNsConfig(encryptionKeyConfigured: true)
private let ready = PushAPNsConfig(enabled: true, teamID: "ABCDE12345", keyID: "KEY1234567", privateKeyConfigured: true,
                                   topic: "com.example.sub2", encryptionKeyConfigured: true, ready: true)

// MARK: 添加接收方式 (60 §7.4)

@Test func targetDraftDefaultsAndPlatforms() {
    let draft = PushTargetDraft()
    #expect(draft.platform == .bark); #expect(draft.barkEndpoint == "https://api.day.app"); #expect(draft.ntfyEndpoint == "https://ntfy.sh")
    #expect(draft.barkKey.isEmpty && draft.ntfyTopic.isEmpty && draft.ntfyAccessToken.isEmpty && draft.webhookURL.isEmpty)
    #expect(draft.webhookSecret.isEmpty && draft.name.isEmpty && !draft.needsSecretAgain && !draft.hasInput)
    #expect(PushTargetDraft.platforms == [.bark, .ntfy, .webhook])
    #expect(PushTargetDraft.platforms.map(PushTargetDraft.title) == ["Bark", "ntfy", "Webhook"])
    #expect(PushTargetDraft(platform: .ios).platform == .bark)
    #expect(PushTargetDraft.fields(for: .bark) == [.endpoint, .token, .name])
    #expect(PushTargetDraft.fields(for: .ntfy) == [.endpoint, .token, .secret, .name])
    #expect(PushTargetDraft.fields(for: .webhook) == [.endpoint, .secret, .name])
    #expect(PushTargetDraft.fields(for: .bark).map { PushTargetDraft.label($0, platform: .bark) } == ["服务器", "设备 Key", "名称（可选）"])
    #expect(PushTargetDraft.fields(for: .ntfy).map { PushTargetDraft.label($0, platform: .ntfy) } == ["服务器", "主题", "访问令牌（可选）", "名称（可选）"])
    #expect(PushTargetDraft.fields(for: .webhook).map { PushTargetDraft.label($0, platform: .webhook) } == ["URL", "签名密钥（可选）", "名称（可选）"])
    #expect(PushTargetDraft.placeholder(.token, platform: .bark) == "Bark App 里的设备 Key")
    #expect(PushTargetDraft.placeholder(.token, platform: .ntfy) == "字母、数字、- 和 _")
    #expect(PushTargetDraft.placeholder(.endpoint, platform: .webhook) == "https://")
}

@Test func barkDraftRequiresDeviceKey() throws {
    var draft = PushTargetDraft()
    #expect(draft.issues[.token] == "填写 Bark App 里的设备 Key")
    for bad in ["ab cd", "ab/cd", String(repeating: "k", count: 129)] {
        draft.barkKey = bad
        #expect(draft.issues[.token] == "设备 Key 只能包含字母、数字、- 和 _", "\(bad)")
    }
    draft.barkKey = " fixture_Key-123 "
    #expect(draft.issues.isEmpty); #expect(draft.isComplete); #expect(draft.hasInput)
    let fields = try body(draft.registration(timezone: "Asia/Shanghai"))
    #expect(Set(fields.keys) == ["platform", "endpoint", "token", "locale", "timezone"])
    #expect(fields["platform"] as? String == "bark"); #expect(fields["endpoint"] as? String == "https://api.day.app")
    #expect(fields["token"] as? String == "fixture_Key-123"); #expect(fields["timezone"] as? String == "Asia/Shanghai")
}

@Test func ntfyTopicFormatAndOptionalAccessToken() throws {
    var draft = PushTargetDraft(platform: .ntfy)
    #expect(draft.issues[.token] == "填写主题")
    for bad in ["告警 主题", "a.b", String(repeating: "t", count: 65)] {
        draft.ntfyTopic = bad
        #expect(draft.issues[.token] == "主题只能包含字母、数字、- 和 _，最多 64 个", "\(bad)")
    }
    draft.ntfyTopic = "sub2_alerts-1"
    #expect(draft.issues.isEmpty)
    draft.ntfyAccessToken = "   "
    #expect(try body(draft.registration(timezone: "UTC"))["secret"] == nil)
    draft.ntfyAccessToken = " tk_fixture "
    let fields = try body(draft.registration(timezone: "UTC"))
    #expect(fields["secret"] as? String == "tk_fixture"); #expect(fields["token"] as? String == "sub2_alerts-1")
    #expect(fields["endpoint"] as? String == "https://ntfy.sh")
    draft.ntfyAccessToken = String(repeating: "x", count: 513)
    #expect(draft.issues[.secret] == "最多 512 字节")
    draft.ntfyAccessToken = String(repeating: "x", count: 512)
    #expect(draft.issues.isEmpty)
}

@Test func webhookURLMustBeAbsoluteAndSecretIsOptional() throws {
    var draft = PushTargetDraft(platform: .webhook)
    #expect(draft.issues[.endpoint] == "填写 Webhook URL")
    for bad in ["hooks.example.com", "ftp://hooks.example.com", "https://", "https://exa mple.com"] {
        draft.webhookURL = bad
        #expect(draft.issues[.endpoint] == "地址格式不对，要以 https:// 开头", "\(bad)")
    }
    draft.webhookURL = "https://hooks.example.com/sub2"
    #expect(draft.issues.isEmpty)
    let plain = try body(draft.registration(timezone: "Asia/Shanghai"))
    #expect(Set(plain.keys) == ["platform", "endpoint", "locale", "timezone"]); #expect(plain["platform"] as? String == "webhook")
    draft.webhookSecret = "fixture-secret"
    #expect(try body(draft.registration(timezone: "Asia/Shanghai"))["secret"] as? String == "fixture-secret")
    draft.webhookSecret = String(repeating: "密", count: 171)
    #expect(draft.issues[.secret] == "最多 512 字节")
}

@Test func endpointRulesForCustomServers() {
    var draft = PushTargetDraft()
    draft.barkKey = "fixturekey"
    draft.barkEndpoint = "  "
    #expect(draft.issues[.endpoint] == "填写服务器地址")
    draft.barkEndpoint = "https://bark.example.com/" + String(repeating: "a", count: 2049 - 25)
    #expect(draft.barkEndpoint.utf8.count == 2049); #expect(draft.issues[.endpoint] == "地址太长")
    draft.barkEndpoint = "https://bark.example.com/"
    #expect(draft.issues.isEmpty); #expect(!draft.usesInsecureHTTP)
    draft.barkEndpoint = "https://bark.example.com:8443"
    #expect(draft.issues.isEmpty)
    draft.platform = .ntfy
    draft.ntfyTopic = "alerts"
    draft.ntfyEndpoint = "http://ntfy.example.com"
    #expect(draft.issues.isEmpty); #expect(draft.usesInsecureHTTP)
    draft.ntfyEndpoint = ""
    #expect(draft.issues[.endpoint] == "填写服务器地址")
    draft.platform = .bark
    #expect(draft.issues.isEmpty); #expect(!draft.usesInsecureHTTP)
}

@Test func nameIsOptionalTrimmedAndCapped() throws {
    var draft = PushTargetDraft()
    draft.barkKey = "fixturekey"
    #expect(try body(draft.registration(timezone: "UTC"))["device_name"] == nil)
    draft.name = "  值班手机 "
    #expect(try body(draft.registration(timezone: "UTC"))["device_name"] as? String == "值班手机")
    draft.name = String(repeating: "名", count: 64)
    #expect(draft.issues.isEmpty)
    draft.name = String(repeating: "名", count: 65)
    #expect(draft.issues[.name] == "名称最多 64 个字")
}

@Test func issuesFollowSelectedPlatformAndKeepOtherFields() {
    var draft = PushTargetDraft()
    draft.barkKey = "bad key"
    draft.platform = .ntfy
    draft.ntfyTopic = "alerts"
    #expect(draft.issues.isEmpty)
    draft.platform = .bark
    #expect(draft.barkKey == "bad key"); #expect(draft.ntfyTopic == "alerts")
    #expect(draft.issues[.token] == "设备 Key 只能包含字母、数字、- 和 _")
}

@Test func registrationThrowsWhileIssuesRemain() throws {
    var draft = PushTargetDraft(platform: .ntfy)
    #expect(!draft.isComplete)
    #expect(throws: APIError.self) { _ = try draft.registration(timezone: "UTC") }
    do { _ = try draft.registration(timezone: "UTC") } catch let error as APIError {
        #expect(error.kind == .validation); #expect(error.localizedDescription == "还有内容需要修改")
    }
    draft.ntfyTopic = "alerts"
    _ = try draft.registration(timezone: "UTC")
}

@Test func submittedSecretIsClearedAndMustBeReentered() throws {
    var draft = PushTargetDraft(platform: .webhook)
    draft.webhookURL = "https://hooks.example.com/sub2"; draft.name = "值班 Webhook"; draft.webhookSecret = "fixture-secret"
    draft.didSubmit(try draft.registration(timezone: "UTC"))
    #expect(draft.webhookSecret.isEmpty); #expect(draft.webhookURL == "https://hooks.example.com/sub2"); #expect(draft.name == "值班 Webhook")
    #expect(draft.needsSecretAgain); #expect(draft.issues[.secret] == "提交后已清空，请重新填写；不需要就点“不设置”")
    draft.webhookSecret = "fixture-secret"
    #expect(draft.issues.isEmpty)
    draft.webhookSecret = ""
    draft.dropSecret()
    #expect(draft.issues.isEmpty); #expect(!draft.needsSecretAgain)
    #expect(try body(draft.registration(timezone: "UTC"))["secret"] == nil)
    draft.didSubmit(try draft.registration(timezone: "UTC"))
    #expect(!draft.needsSecretAgain)

    var ntfy = PushTargetDraft(platform: .ntfy)
    ntfy.ntfyTopic = "alerts"; ntfy.ntfyAccessToken = "tk_fixture"
    ntfy.didSubmit(try ntfy.registration(timezone: "UTC"))
    #expect(ntfy.ntfyAccessToken.isEmpty); #expect(ntfy.ntfyTopic == "alerts"); #expect(ntfy.issues[.secret] != nil)
}

@Test func targetDraftDescriptionRedactsEverythingButPlatform() {
    var draft = PushTargetDraft(platform: .webhook)
    draft.barkEndpoint = "https://bark.secret-host.example"; draft.barkKey = "barkSecretKey9"
    draft.ntfyTopic = "secretTopic77"; draft.ntfyAccessToken = "tk_secretToken"
    draft.webhookURL = "https://hooks.example.com/peer-token-abc"; draft.webhookSecret = "hmacSecret42"; draft.name = "值班"
    let text = everything(draft)
    for secret in ["secret-host", "barkSecretKey9", "secretTopic77", "tk_secretToken", "peer-token-abc", "hooks.example.com", "hmacSecret42", "ntfy.sh",
                   "api.day.app"] {
        #expect(!text.contains(secret), "\(secret)")
    }
    #expect(text.contains("<redacted>")); #expect(text.contains("webhook"))
}

@Test func targetFailureClassification() {
    let address = "地址不被允许：默认只接受公网 https 地址（局域网或 http 需站长打开 push_targets 配置）"
    #expect(PushTargetFailure.classify(failure(400, "INVALID_PUSH_TARGET", ["field": "endpoint"])) == .field(.endpoint, address))
    #expect(PushTargetFailure.classify(failure(400, "INVALID_PUSH_TARGET")) == .field(.endpoint, address))
    #expect(PushTargetFailure.classify(failure(400, "INVALID_PUSH_TARGET", ["field": "secret"])) == .field(.secret, "最多 512 字节"))
    for field in ["timezone", "platform", "body"] {
        #expect(PushTargetFailure.classify(failure(400, "INVALID_PUSH_TARGET", ["field": field])) == .form("请求参数有误（错误码 INVALID_PUSH_TARGET）"))
    }
    #expect(PushTargetFailure.classify(failure(400, "INVALID_PUSH_TOKEN", ["field": "token"])) == .field(.token, "设备 Key / 主题格式不对"))
    #expect(PushTargetFailure.classify(failure(409, "PUSH_TARGET_IN_USE")) == .form("这个接收地址已由另一位管理员登记"))
    #expect(PushTargetFailure.classify(failure(409, "PUSH_DEVICE_LIMIT_REACHED", ["max": "20"])) == .form("最多 20 个推送目标，先删除不用的"))
    #expect(PushTargetFailure.classify(failure(403, "ACCESS_TOKEN_READ_ONLY", ["field": "platform"], outcome: .blocked))
            == .form("只读令牌只能登记本机推送"))
    #expect(PushTargetFailure.classify(failure(423, "ADMIN_COMPLIANCE_REQUIRED", outcome: .passed)) == .form("合规确认已完成，请重新确认后发送"))
    #expect(PushTargetFailure.classify(failure(423, "ADMIN_COMPLIANCE_REQUIRED", outcome: .cancelled)) == .cancelled)
    #expect(PushTargetFailure.classify(CancellationError()) == .cancelled)
    let unconfirmed = PushTargetFailure.unconfirmed("没有收到结果，已刷新列表，请确认是否已添加")
    for error in [lostConnection, .invalidResponse, failure(408, nil), failure(502, nil), failure(504, nil), failure(503, nil),
                  APIError.server(status: 503, envelope: nil)] {
        #expect(PushTargetFailure.classify(error) == unconfirmed, "\(error.statusCode ?? 0)")
    }
    #expect(PushTargetFailure.classify(APIError.refreshDeferred) == .form(APIError.refreshDeferred.localizedDescription))
}

// MARK: 编辑站点 APNs 配置 (60 §7.4)

@Test func apnsDraftStartsFromConfigWithoutChanges() {
    let draft = APNsConfigDraft(config: ready)
    #expect(draft.enabled); #expect(draft.teamID == "ABCDE12345"); #expect(draft.keyID == "KEY1234567"); #expect(draft.topic == "com.example.sub2")
    #expect(draft.environment == .production); #expect(draft.privateKey.isEmpty); #expect(!draft.hasChanges); #expect(draft.update.isEmpty)
    #expect(draft.issues.isEmpty); #expect(draft.privateKeyStatus == "已配置（不更换就不用填）")
    let empty = APNsConfigDraft(config: notReady)
    #expect(empty.topic.isEmpty && empty.teamID.isEmpty); #expect(empty.privateKeyStatus == "未配置")
    var pasted = empty
    pasted.setPrivateKey(pem)
    #expect(pasted.privateKeyStatus == "已读取新私钥，保存时上传")
}

@Test func apnsTeamAndKeyIDFormat() throws {
    var draft = APNsConfigDraft(config: ready)
    draft.teamID = " abcde12345 "
    #expect(draft.issues.isEmpty); #expect(!draft.hasChanges)
    for bad in ["ABCDE1234", "ABCDE123456", "ABCDE-1234"] {
        draft.teamID = bad
        #expect(draft.issues[.teamID] == "Team ID 应为 10 位大写字母或数字", "\(bad)")
    }
    draft.teamID = "ABCDE12345"; draft.keyID = "KEY12345"
    #expect(draft.issues[.keyID] == "Key ID 应为 10 位大写字母或数字")
    var off = APNsConfigDraft(config: PushAPNsConfig(teamID: "ABCDE12345", encryptionKeyConfigured: true))
    off.teamID = ""
    #expect(off.issues.isEmpty); #expect(try body(off.update)["apns_team_id"] as? String == "")
}

@Test func apnsTopicMustBeBundleID() throws {
    var draft = APNsConfigDraft(config: ready)
    for bad in ["com example", ".com.example"] {
        draft.topic = bad
        #expect(draft.issues[.topic] == "Topic 应为 App 的包名（Bundle ID）", "\(bad)")
    }
    draft.topic = "com.example.sub2-beta"
    #expect(draft.issues.isEmpty)
    draft.topic = ""
    #expect(draft.issues.isEmpty); #expect(try body(draft.update)["apns_topic"] as? String == "")
}

@Test func apnsEnablingNeedsTeamKeyAndPrivateKey() {
    var draft = APNsConfigDraft(config: notReady)
    draft.enabled = true
    #expect(draft.issues[.enabled] == "启用需要 Team ID、Key ID 与私钥")
    draft.teamID = "ABCDE12345"; draft.keyID = "KEY1234567"
    #expect(draft.issues[.enabled] != nil)
    draft.setPrivateKey(pem)
    #expect(draft.issues.isEmpty)
    var configured = APNsConfigDraft(config: PushAPNsConfig(privateKeyConfigured: true, encryptionKeyConfigured: true))
    configured.enabled = true; configured.teamID = "ABCDE12345"; configured.keyID = "KEY1234567"
    #expect(configured.issues.isEmpty)
    var cleared = APNsConfigDraft(config: ready)
    cleared.teamID = ""
    #expect(cleared.issues[.enabled] == "启用需要 Team ID、Key ID 与私钥"); #expect(cleared.issues[.teamID] == nil)
}

@Test func privateKeyPEMShape() {
    #expect(APNsConfigDraft.isPrivateKeyPEM(pem))
    #expect(APNsConfigDraft.isPrivateKeyPEM("  \r\n" + pem.replacingOccurrences(of: "\n", with: "\r\n") + "\n"))
    #expect(APNsConfigDraft.isPrivateKeyPEM("-----BEGIN EC PRIVATE KEY-----\nMHcCAQEEIFIXTURE\n-----END EC PRIVATE KEY-----"))
    for bad in ["-----BEGIN PRIVATE KEY-----\nMIGHAgEA",
                "-----BEGIN PRIVATE KEY-----\nMIGHAgEA\n-----END EC PRIVATE KEY-----",
                "-----BEGIN PUBLIC KEY-----\nMIGHAgEA\n-----END PUBLIC KEY-----",
                "-----BEGIN RSA PRIVATE KEY-----\nMIGHAgEA\n-----END RSA PRIVATE KEY-----",
                "-----BEGIN PRIVATE KEY-----\n\n-----END PRIVATE KEY-----",
                "-----BEGIN PRIVATE KEY-----\nMIGH!AgEA\n-----END PRIVATE KEY-----",
                "-----BEGIN PRIVATE KEY-----\n私钥\n-----END PRIVATE KEY-----"] {
        #expect(!APNsConfigDraft.isPrivateKeyPEM(bad), "\(bad)")
    }
    var draft = APNsConfigDraft(config: ready)
    draft.setPrivateKey("-----BEGIN PRIVATE KEY-----\nMIGHAgEA")
    #expect(draft.issues[.privateKey] == "私钥应为 APNs 的 .p8（P-256）文件内容")
}

@Test func privateKeyFromFileData() {
    #expect(APNsConfigDraft.privateKey(fromFile: Data(("\u{FEFF}" + pem + "\n").utf8)) == pem)
    #expect(APNsConfigDraft.privateKey(fromFile: Data([0xFF, 0xFE, 0x00, 0x2D])) == nil)
    #expect(APNsConfigDraft.privateKey(fromFile: Data("not a key".utf8)) == nil)
    let padded = pem + String(repeating: " ", count: APNsConfigDraft.maxPrivateKeyBytes)
    #expect(APNsConfigDraft.privateKey(fromFile: Data(padded.utf8)) == nil)
}

@Test func privateKeyNeedsEncryptionKey() {
    var draft = APNsConfigDraft(config: PushAPNsConfig(encryptionKeyConfigured: false))
    #expect(!draft.canEditPrivateKey)
    draft.setPrivateKey(pem)
    #expect(draft.issues[.privateKey] == "站点没有配置固定的 TOTP_ENCRYPTION_KEY，私钥不能保存")
    #expect(APNsConfigDraft(config: ready).canEditPrivateKey)
}

@Test func privateKeyEditorCollapsesOnceRecognized() throws {
    var draft = APNsConfigDraft(config: ready)
    #expect(draft.acceptsPrivateKeyInput)
    draft.setPrivateKey(pem)
    #expect(!draft.acceptsPrivateKeyInput)
    draft.setPrivateKey("-----BEGIN PRIVATE KEY-----\nMIG")
    #expect(draft.acceptsPrivateKeyInput)
    #expect(!APNsConfigDraft(config: PushAPNsConfig(encryptionKeyConfigured: false)).acceptsPrivateKeyInput)
    draft.setPrivateKey(pem)
    draft.didSubmit(draft.update)
    #expect(draft.acceptsPrivateKeyInput)
}

@Test func apnsUpdateSendsOnlyChangedFields() throws {
    var draft = APNsConfigDraft(config: ready)
    draft.environment = .sandbox
    #expect(String(decoding: try JSONEncoder().encode(draft.update), as: UTF8.self) == #"{"apns_environment":"sandbox"}"#)
    draft.environment = .production; draft.topic = "com.example.other"
    #expect(Set(try body(draft.update).keys) == ["apns_topic"]); #expect(!draft.update.includesPrivateKey)
    draft.topic = "com.example.sub2"
    draft.setPrivateKey(pem)
    #expect(try body(draft.update)["apns_private_key"] as? String == pem); #expect(draft.update.includesPrivateKey)
    draft.clearPrivateKey()
    #expect(!draft.hasChanges)
}

@Test func submittedPrivateKeyIsClearedAndFlagged() {
    var draft = APNsConfigDraft(config: ready)
    draft.setPrivateKey(pem)
    draft.didSubmit(draft.update)
    #expect(draft.privateKey.isEmpty); #expect(draft.needsPrivateKeyAgain); #expect(!draft.update.includesPrivateKey)
    #expect(draft.issues[.privateKey] == "私钥已在提交后清空，请重新导入或粘贴")
    var replaced = draft
    replaced.setPrivateKey(pem)
    #expect(replaced.issues.isEmpty)
    draft.keepCurrentPrivateKey()
    #expect(draft.issues.isEmpty); #expect(!draft.needsPrivateKeyAgain)
    draft.environment = .sandbox
    draft.didSubmit(draft.update)
    #expect(!draft.needsPrivateKeyAgain)
}

@Test func apnsDraftDescriptionRedactsPrivateKey() {
    var draft = APNsConfigDraft(config: ready)
    draft.setPrivateKey(pem)
    let text = everything(draft)
    for piece in ["BEGIN", "MIGHAgEA", "FIXTUREKEY", "PRIVATE KEY"] { #expect(!text.contains(piece), "\(piece)") }
    #expect(text.contains("<redacted>")); #expect(text.contains("ABCDE12345"))
}

@Test func apnsFailureClassification() {
    #expect(APNsConfigFailure.classify(failure(403, "STEP_UP_REQUIRED", outcome: .passed)) == .reconfirm("二次验证已通过，请重新确认后发送"))
    #expect(APNsConfigFailure.classify(failure(423, "ADMIN_COMPLIANCE_REQUIRED", outcome: .passed)) == .reconfirm("合规确认已完成，请重新确认后发送"))
    #expect(APNsConfigFailure.classify(failure(403, "STEP_UP_REQUIRED", outcome: .cancelled)) == .cancelled)
    #expect(APNsConfigFailure.classify(failure(423, "ADMIN_COMPLIANCE_REQUIRED", outcome: .cancelled)) == .cancelled)
    #expect(APNsConfigFailure.classify(CancellationError()) == .cancelled)
    #expect(APNsConfigFailure.classify(failure(403, "STEP_UP_ADMIN_API_KEY_FORBIDDEN", outcome: .blocked))
            == .staleSecurity("该操作需要账号登录（Admin Key 与管理访问令牌不能二次验证）"))
    #expect(APNsConfigFailure.classify(failure(403, "STEP_UP_TOTP_NOT_ENABLED", outcome: .blocked)) == .staleSecurity("需要先在 Web 端开启二次验证"))
    // The notice swiped away still means admin/me is out of date.
    #expect(APNsConfigFailure.classify(failure(403, "STEP_UP_TOTP_NOT_ENABLED", outcome: .cancelled)) == .staleSecurity("需要先在 Web 端开启二次验证"))
    #expect(APNsConfigFailure.classify(failure(503, "STEP_UP_UNAVAILABLE", outcome: .blocked)) == .form("二次验证服务暂时不可用"))
    #expect(APNsConfigFailure.classify(failure(403, "ACCESS_TOKEN_READ_ONLY", outcome: .blocked)) == .form("当前管理访问令牌只读，不能执行此操作"))
    for field in PushAPNsField.allCases {
        #expect(APNsConfigFailure.classify(failure(400, "INVALID_APNS_CONFIG", ["field": field.rawValue])) == .field(field, field.invalidMessage))
    }
    #expect(APNsConfigFailure.classify(failure(400, "INVALID_APNS_CONFIG", ["field": "body"])) == .form("请求参数有误（错误码 INVALID_APNS_CONFIG）"))
    #expect(APNsConfigFailure.classify(failure(400, "INVALID_APNS_CONFIG")) == .form("请求参数有误（错误码 INVALID_APNS_CONFIG）"))
    #expect(APNsConfigFailure.classify(failure(400, "SECRET_ENCRYPTION_KEY_NOT_CONFIGURED"))
            == .field(.privateKey, "站点没有配置固定的 TOTP_ENCRYPTION_KEY，私钥不能保存"))
    let denied = failure(403, "WORKSPACE_PERMISSION_DENIED")
    #expect(APNsConfigFailure.classify(denied) == .form(denied.localizedDescription))
    let unconfirmed = APNsConfigFailure.unconfirmed("没有收到保存结果，已重新读取配置，请核对后再保存")
    for error in [lostConnection, .invalidResponse, failure(408, nil), failure(502, nil), failure(504, nil), failure(503, nil)] {
        #expect(APNsConfigFailure.classify(error) == unconfirmed, "\(error.statusCode ?? 0)")
    }
}

@Test func editCopyMatchesSpec() {
    #expect(PushEditCopy.webhookSignatureNote == #"设置后请求带 X-Sub2-Signature: sha256=HMAC(secret, 时间戳 + "." + 正文)"#)
    #expect(PushEditCopy.addedReceipt(name: "值班 Webhook", created: true) == "已添加接收方式「值班 Webhook」")
    #expect(PushEditCopy.addedReceipt(name: "值班 Webhook", created: false) == "这个接收方式已登记过，已重新启用「值班 Webhook」")
    #expect(PushEditCopy.stepUpPurpose == "修改站点 APNs 配置")
    #expect(PushEditCopy.topicPlaceholder == PushPresentation.apnsRows(PushAPNsConfig()).topic)
}
