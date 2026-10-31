import Foundation
import Testing
@testable import Sub2Core

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private func device(_ id: Int = 1, platform: PushPlatform? = .ios, rawPlatform: String? = nil, tokenHint: String? = nil, host: String? = nil,
                    name: String? = nil, enabled: Bool = true, reason: PushDisabledReason? = nil, success: Date? = nil,
                    error: String? = nil, errorAt: Date? = nil) -> PushDevice {
    PushDevice(id: id, platform: platform, rawPlatform: rawPlatform, tokenHint: tokenHint, endpointHost: host, deviceName: name, enabled: enabled,
               disabledReason: reason, lastSuccessAt: success, lastError: error, lastErrorAt: errorAt)
}
private func failure(_ status: Int, _ reason: String, _ metadata: [String: String] = [:], outcome: SecurityPromptOutcome? = nil) -> APIError {
    let base = APIError.server(status: status, envelope: ErrorEnvelope(reason: reason, metadata: metadata))
    return outcome.map(base.withSecurityOutcome) ?? base
}

// MARK: Local switch and settings row (60 §7.3, §3.3)

@Test func notReadyBannerAndLocalToggleAvailability() {
    let notReady = PushAPNsConfig(enabled: true, ready: false), ready = PushAPNsConfig(enabled: true, ready: true)
    #expect(PushPresentation.showsNotReadyBanner(notReady)); #expect(!PushPresentation.canEnableLocal(notReady))
    #expect(PushPresentation.notReadyBanner == "站点还没配好 APNs，本机收不到推送。可改用 Bark / ntfy / Webhook，或在下方配置 APNs。")
    #expect(PushPresentation.localToggleNeedsAPNs == "站点配好 APNs 后才能打开")
    #expect(!PushPresentation.showsNotReadyBanner(ready)); #expect(PushPresentation.canEnableLocal(ready))
    #expect(!PushPresentation.showsNotReadyBanner(nil)); #expect(PushPresentation.canEnableLocal(nil))
}

@Test func localStateAndSettingsRowTitles() {
    let devices = [device(3), device(4, enabled: false, reason: .unregistered)]
    #expect(PushPresentation.localState(registeredID: nil, devices: devices) == .off)
    #expect(PushPresentation.localState(registeredID: 3, devices: nil) == .on)
    #expect(PushPresentation.localState(registeredID: 3, devices: devices) == .on)
    #expect(PushPresentation.localState(registeredID: 4, devices: devices) == .disabled)
    #expect(PushPresentation.localState(registeredID: 9, devices: devices) == .off)
    #expect(PushPresentation.localDevice(registeredID: 4, in: devices)?.id == 4); #expect(PushPresentation.localDevice(registeredID: nil, in: devices) == nil)
    #expect(PushLocalState.off.settingsTitle == "未开启"); #expect(PushLocalState.on.settingsTitle == "已开启")
    #expect(PushLocalState.disabled.settingsTitle == "已停用")
    #expect(PushLocalState.on.isToggleOn); #expect(!PushLocalState.disabled.isToggleOn); #expect(!PushLocalState.off.isToggleOn)
    #expect(PushLocalState.on.canSendTest); #expect(PushLocalState.disabled.canSendTest); #expect(!PushLocalState.off.canSendTest)
}

@Test func statusLineForEnabledDevice() {
    #expect(PushPresentation.statusLine(device(success: at("2026-10-17T01:41:00Z")), timeZone: shanghai) == "已开启 · 上次送达 10/17 09:41")
    #expect(PushPresentation.statusLine(device(), timeZone: shanghai) == "已开启 · 还没有送达记录")
    #expect(PushPresentation.statusLine(device(success: at("2026-03-05T00:07:00Z")), timeZone: shanghai) == "已开启 · 上次送达 03/05 08:07")
}

@Test func statusLineForEachDisabledReason() {
    let texts: [(PushDisabledReason?, String)] = [
        (.unregistered, "设备令牌已失效，关掉再打开即可恢复"), (.badDeviceToken, "设备令牌无效"),
        (.topicMismatch, "App 的包名与站点 APNs 配置不符"), (.secretUndecryptable, "站点更换了加密密钥，关掉再打开即可恢复"),
        (.endpointGone, "已停用"), (.other("quota"), "已停用"), (nil, "已停用")
    ]
    for (reason, text) in texts {
        #expect(PushPresentation.disabledText(reason) == text)
        #expect(PushPresentation.statusLine(device(enabled: false, reason: reason, success: at("2026-10-17T01:41:00Z")), timeZone: shanghai) == text)
    }
}

@Test func statusLineAppendsRecentFailureUnlessOlderThanSuccess() {
    let success = at("2026-10-17T01:00:00Z"), later = at("2026-10-17T02:00:00Z"), earlier = at("2026-10-17T00:00:00Z")
    let error = "HTTP 410: Unregistered"
    #expect(PushPresentation.statusLine(device(success: success, error: error, errorAt: later), timeZone: shanghai)
            == "已开启 · 上次送达 10/17 09:00 · 最近失败：HTTP 410: Unregistered")
    #expect(PushPresentation.statusLine(device(success: success, error: error, errorAt: earlier), timeZone: shanghai) == "已开启 · 上次送达 10/17 09:00")
    #expect(PushPresentation.statusLine(device(success: success, error: error), timeZone: shanghai).hasSuffix(" · 最近失败：HTTP 410: Unregistered"))
    #expect(PushPresentation.statusLine(device(error: error, errorAt: later), timeZone: shanghai) == "已开启 · 还没有送达记录 · 最近失败：HTTP 410: Unregistered")
    #expect(PushPresentation.statusLine(device(enabled: false, reason: .unregistered, error: error, errorAt: later), timeZone: shanghai)
            == "设备令牌已失效，关掉再打开即可恢复 · 最近失败：HTTP 410: Unregistered")
    #expect(PushPresentation.statusLine(device(error: "  ", errorAt: later), timeZone: shanghai) == "已开启 · 还没有送达记录")
    #expect(PushPresentation.statusLine(device(error: "line\none", errorAt: later), timeZone: shanghai).hasSuffix("最近失败：line one"))
}

// MARK: Subscription summary (60 §7.3)

@Test func subscriptionSummaryRows() {
    #expect(PushEvent.allCases.map(PushPresentation.eventTitle) == ["告警触发", "告警恢复", "账号出错", "账号测试完成"])
    #expect(PushPresentation.pausedNote == "已暂停推送")
    #expect(PushPresentation.severitySummary(.p1) == "P1 及以上"); #expect(PushSeverity.allCases.map(PushPresentation.severityTitle) == ["P0", "P1", "P2", "P3"])
    #expect(PushPresentation.platformScope([]) == "全部平台"); #expect(PushPresentation.platformScope(["anthropic", "openai"]) == "Anthropic、OpenAI")
    #expect(PushPresentation.platformScope(["newplat"]) == "newplat")
    #expect(PushPresentation.platformScope(["zhipu"], name: { "目录:" + $0 }) == "目录:zhipu")
    let names = [1: "高级组", 2: "默认组", 3: "测试组"]
    #expect(PushPresentation.groupScope([], name: { names[$0] }) == "全部分组")
    #expect(PushPresentation.groupScope([1], name: { names[$0] }) == "高级组")
    #expect(PushPresentation.groupScope([1, 2, 3], name: { names[$0] }) == "高级组 等 3 个")
    #expect(PushPresentation.groupScope([7], name: { names[$0] }) == "分组 #7")
    #expect(PushPresentation.groupScope([7, 1], name: { names[$0] }) == "分组 #7 等 2 个")
    #expect(PushPresentation.groupScopeNote == "全站告警不受范围限制")
}

@Test func quietHoursNoteAndFooter() {
    #expect(PushPresentation.quietHoursNote(timezone: "Asia/Shanghai") == "按本机时区 Asia/Shanghai；时段内的事件不补推")
    #expect(PushPresentation.quietHoursNote(timezone: nil) == "按 UTC 时区；时段内的事件不补推")
    #expect(PushPresentation.quietHoursNote(timezone: " ") == "按 UTC 时区；时段内的事件不补推")
    #expect(PushPresentation.footer == "同一账号出错 30 分钟内最多推一次；推送最多晚约 15 秒；测试完成只推给发起测试的人。")
}

// MARK: Other targets (60 §7.3)

@Test func otherTargetRows() {
    let devices = [device(1, tokenHint: "a3f0", name: "本机"), device(2, tokenHint: "a3f0", name: "另一台 iPhone"),
                   device(3, platform: .ntfy, host: "ntfy.sh", name: " "), device(4, platform: .bark, host: "api.day.app", name: "我的 Bark"),
                   device(5, platform: .webhook, host: "hooks.example.com", enabled: false, reason: .endpointGone), device(6, tokenHint: nil),
                   device(7, platform: nil, rawPlatform: "apns2")]
    let rows = PushPresentation.otherTargets(devices, localID: 1)
    #expect(rows.map(\.id) == [2, 3, 4, 5, 6, 7])
    #expect(rows.map(\.title) == ["另一台 iPhone", "ntfy.sh", "我的 Bark", "hooks.example.com", "iOS", "apns2"])
    #expect(rows.map(\.subtitle) == ["iOS · …a3f0", "ntfy · ntfy.sh", "Bark · api.day.app", "Webhook · hooks.example.com", "iOS", "apns2"])
    #expect(rows.map(\.isDisabled) == [false, false, false, true, false, false])
    #expect(rows.map(\.symbolName) == ["iphone", "bell.badge", "app.badge", "link", "iphone", "bell"])
    #expect(PushPresentation.otherTargets(devices, localID: nil).count == 7)
    #expect(PushPresentation.targetName(device(8, platform: nil)) == "—"); #expect(PushPresentation.disabledBadge == "已停用")
}

@Test func addTargetHiddenForReadOnlyToken() {
    #expect(!PushPresentation.showsAddTarget(isReadOnlyToken: true)); #expect(PushPresentation.showsAddTarget(isReadOnlyToken: false))
    #expect(PushPresentation.addTarget == "+ 添加其他接收方式")
}

// MARK: Site APNs settings (60 §7.3)

@Test func apnsConfigRows() {
    let ready = PushPresentation.apnsRows(PushAPNsConfig(enabled: true, teamID: "ABCDE12345", keyID: "KEY1234567", privateKeyConfigured: true,
                                                         topic: "com.example.sub2", environment: .sandbox, ready: true))
    #expect(ready == PushAPNsConfigRows(teamID: "ABCDE12345", keyID: "KEY1234567", privateKey: "已配置", topic: "com.example.sub2",
                                        environment: "sandbox", status: "可用", statusTone: .ok))
    let empty = PushPresentation.apnsRows(PushAPNsConfig())
    #expect(empty == PushAPNsConfigRows(teamID: "—", keyID: "—", privateKey: "未配置", topic: "跟随 App 包名", environment: "production",
                                        status: "未就绪", statusTone: .caution))
}

@Test func apnsEditabilityConditions() {
    typealias Security = AdminMe.Security
    let off = Security(stepUpEnabled: false), available = Security(stepUpEnabled: true, stepUpAvailable: true)
    let unavailable = Security(totpEnabled: false, stepUpEnabled: true, stepUpAvailable: false)
    #expect(PushPresentation.apnsEditability(isReadOnlyToken: true, security: off, authMethod: .adminAccessToken) == .disabled("只读令牌"))
    #expect(PushPresentation.apnsEditability(isReadOnlyToken: false, security: off, authMethod: .adminAPIKey) == .available)
    #expect(PushPresentation.apnsEditability(isReadOnlyToken: false, security: available, authMethod: .jwt) == .available)
    for method in [AdminAuthMethod.adminAPIKey, .adminAccessToken] {
        #expect(PushPresentation.apnsEditability(isReadOnlyToken: false, security: unavailable, authMethod: method)
                == .disabled("站点开启了二次验证，需要邮箱和密码登录才能修改"))
    }
    #expect(PushPresentation.apnsEditability(isReadOnlyToken: false, security: unavailable, authMethod: .jwt) == .disabled("需要先在 Web 端开启二次验证"))
    #expect(PushPresentation.apnsEditability(isReadOnlyToken: false, security: Security(), authMethod: .jwt).isAvailable)
    #expect(PushAPNsEditability.disabled("只读令牌").note == "只读令牌"); #expect(PushAPNsEditability.available.note == nil)
}

// MARK: Failure wording (60 §7.4)

@Test func registerFailureMessages() {
    let notAllowed = "地址不被允许：默认只接受公网 https 地址（局域网或 http 需站长打开 push_targets 配置）"
    #expect(PushPresentation.failureMessage(failure(400, "INVALID_PUSH_TARGET", ["field": "endpoint"])) == notAllowed)
    #expect(PushPresentation.failureMessage(failure(400, "INVALID_PUSH_TARGET")) == notAllowed)
    for field in ["bundle_id", "timezone", "environment", "body"] {
        #expect(PushPresentation.failureMessage(failure(400, "INVALID_PUSH_TARGET", ["field": field])) == "请求参数有误（错误码 INVALID_PUSH_TARGET）")
    }
    #expect(PushPresentation.failureMessage(failure(400, "INVALID_PUSH_TOKEN", ["field": "token"])) == "设备 Key / 主题格式不对")
    #expect(PushPresentation.failureMessage(failure(400, "INVALID_PUSH_TOKEN", ["field": "apns_token"])) == "请求参数有误（错误码 INVALID_PUSH_TOKEN）")
    #expect(PushPresentation.failureMessage(failure(409, "PUSH_TARGET_IN_USE")) == "这个接收地址已由另一位管理员登记")
    #expect(PushPresentation.failureMessage(failure(409, "PUSH_DEVICE_LIMIT_REACHED", ["max": "20"])) == "最多 20 个推送目标，先删除不用的")
    #expect(PushPresentation.failureMessage(failure(409, "PUSH_DEVICE_LIMIT_REACHED")) == "最多 20 个推送目标，先删除不用的")
    #expect(PushPresentation.failureMessage(failure(409, "PUSH_DEVICE_LIMIT_REACHED", ["max": "30"])) == "最多 30 个推送目标，先删除不用的")
    #expect(PushPresentation.failureMessage(failure(403, "ACCESS_TOKEN_READ_ONLY", ["field": "platform"])) == "只读令牌只能登记本机推送")
    #expect(PushPresentation.failureMessage(failure(403, "ACCESS_TOKEN_READ_ONLY")) == "当前管理访问令牌只读，不能执行此操作")
    #expect(PushPresentation.failureMessage(failure(429, "RATE_LIMITED")) == failure(429, "RATE_LIMITED").localizedDescription)
    #expect(PushPresentation.failureMessage(APIError.invalidResponse) == APIError.invalidResponse.localizedDescription)
    #expect(PushPresentation.failureMessage(URLError(.timedOut)) == URLError(.timedOut).localizedDescription)
}

@Test func testFailureMessages() {
    #expect(PushPresentation.failureMessage(failure(503, "PUSH_NOT_CONFIGURED")) == "站点没有配好 APNs")
    func delivery(_ metadata: [String: String]) -> String { PushPresentation.failureMessage(failure(502, "PUSH_DELIVERY_FAILED", metadata)) }
    #expect(delivery(["provider_reason": "BadDeviceToken", "provider_status": "400"]) == "推送服务没有接受：BadDeviceToken（400）")
    #expect(delivery(["provider_reason": "secret_undecryptable", "provider_status": "0"]) == "推送服务没有接受：secret_undecryptable")
    #expect(delivery(["provider_status": "410"]) == "推送服务没有接受（410）")
    #expect(delivery([:]) == "推送服务没有接受")
    #expect(delivery(["provider_reason": "bad\r\ntoken\u{7}", "provider_status": "x"]) == "推送服务没有接受：bad token")
    #expect(delivery(["provider_reason": String(repeating: "长", count: 200)]) == "推送服务没有接受：" + String(repeating: "长", count: 120))
    #expect(PushPresentation.failureMessage(failure(404, "PUSH_DEVICE_NOT_FOUND")) == "对象不存在或已删除")
    #expect(PushPresentation.testSent == "已发送测试推送，请看通知"); #expect(PushPresentation.sendTest == "发送测试推送")
}

@Test func apnsConfigFailureMapsFields() {
    let expected: [(String, PushAPNsField, String)] = [
        ("apns_enabled", .enabled, "启用需要 Team ID、Key ID 与私钥"), ("apns_team_id", .teamID, "Team ID 应为 10 位大写字母或数字"),
        ("apns_key_id", .keyID, "Key ID 应为 10 位大写字母或数字"), ("apns_private_key", .privateKey, "私钥应为 APNs 的 .p8（P-256）文件内容"),
        ("apns_topic", .topic, "Topic 应为 App 的包名（Bundle ID）"), ("apns_environment", .environment, "环境只能是 production 或 sandbox")
    ]
    for (raw, field, text) in expected {
        #expect(PushPresentation.apnsConfigFailure(failure(400, "INVALID_APNS_CONFIG", ["field": raw])) == PushFieldFailure(field: field, message: text))
    }
    let parameter = PushFieldFailure(field: nil, message: "请求参数有误（错误码 INVALID_APNS_CONFIG）")
    #expect(PushPresentation.apnsConfigFailure(failure(400, "INVALID_APNS_CONFIG", ["field": "body"])) == parameter)
    #expect(PushPresentation.apnsConfigFailure(failure(400, "INVALID_APNS_CONFIG")) == parameter)
    #expect(PushPresentation.apnsConfigFailure(failure(400, "SECRET_ENCRYPTION_KEY_NOT_CONFIGURED"))
            == PushFieldFailure(field: .privateKey, message: "站点没有配置固定的 TOTP_ENCRYPTION_KEY，私钥不能保存"))
    #expect(PushPresentation.encryptionKeyMissing == "站点没有配置固定的 TOTP_ENCRYPTION_KEY，私钥不能保存")
    #expect(PushPresentation.apnsConfigFailure(failure(403, "STEP_UP_REQUIRED", outcome: .passed))
            == PushFieldFailure(field: nil, message: "二次验证已通过，请重新确认后发送"))
}

@Test func fixedCopyMatchesSpec() {
    #expect(PushPresentation.systemPermissionDenied == "系统设置里关闭了通知 · 去设置")
    #expect(PushPresentation.loadFailed == "加载失败 · 重试")
    #expect(PushPresentation.pendingDeletionNotice == "有设备未能从站点移除，可在 Web 删除")
    #expect(PushPresentation.buildWithoutPush == "这个 App 构建没有开启推送能力；APNs 只适用于用站点同一 Apple Team 的 p8 私钥构建的 App。可改用 Bark / ntfy / Webhook。")
}
