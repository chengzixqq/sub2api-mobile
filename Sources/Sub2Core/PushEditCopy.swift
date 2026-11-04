import Foundation

/// 60 §7.4 (S6-25): the wording of 添加接收方式 and 站点 APNs 配置. The Webhook signature line and the reason texts are the
/// spec's; the rest is ours (listed in the progress row). Reason texts stay in PushPresentation.
public enum PushEditCopy {
    // MARK: 添加接收方式

    public static let webhookSignatureNote = #"设置后请求带 X-Sub2-Signature: sha256=HMAC(secret, 时间戳 + "." + 正文)"#
    /// push_senders.go: the timestamp the signature covers is this header.
    public static let webhookTimestampNote = "时间戳为请求头 X-Sub2-Timestamp 的 Unix 秒"
    public static let targetSheetTitle = "添加接收方式"
    public static let add = "添加"
    public static let adding = "正在添加"
    public static let platformPicker = "接收方式"
    public static let insecureHTTPNote = "http 地址需站长打开 push_targets 配置，否则会被站点拒绝"
    /// Under the topic while the server is ntfy.sh (U-23).
    public static let ntfyPublicTopicNote = "公共服务器上的主题，谁知道名字谁就能订阅，告警内容会被别人看到。"
    public static let secretClearedNote = "提交后已清空，请重新填写；不需要就点“不设置”"
    public static let dropSecret = "不设置"
    public static let targetUnconfirmed = "没有收到结果，已刷新列表，请确认是否已添加"
    public static let fixFields = "还有内容需要修改"
    public static let secretTooLong = "最多 \(PushTargetDraft.maxSecretBytes) 字节"

    /// 201, or 200 for a target already registered, which the server enables again.
    public static func addedReceipt(name: String, created: Bool) -> String {
        created ? "已添加接收方式「\(name)」" : "这个接收方式已登记过，已重新启用「\(name)」"
    }

    // MARK: 站点 APNs 配置

    public static let save = "保存"
    public static let saving = "正在保存"
    public static let stepUpPurpose = "修改站点 APNs 配置"
    public static let enabledTitle = "启用 APNs 推送"
    public static let credentialsTitle = "凭据"
    public static let privateKeyTitle = "私钥"
    public static let deliveryTitle = "发送"
    public static let importKey = "导入 .p8 文件…"
    public static let pasteKeyPlaceholder = "或粘贴 .p8 文件的全部内容"
    public static let clearKey = "清除"
    public static let keepCurrentKey = "不更换私钥"
    public static let keyFileUnreadable = "这个文件不是 APNs 私钥（.p8）"
    public static let keyClearedNote = "私钥已在提交后清空，请重新导入或粘贴"
    /// As PushPresentation.apnsRows shows an empty Topic.
    public static let topicPlaceholder = "跟随 App 包名"
    public static let savedReceipt = "已保存站点 APNs 配置"
    public static let apnsUnconfirmed = "没有收到保存结果，已重新读取配置，请核对后再保存"

    // MARK: Both

    public static let discardTitle = "放弃修改？", discardConfirm = "放弃修改", keepEditing = "继续编辑"
    /// Over the form while the App is not active, so the App switcher's snapshot shows no address, key or private key.
    public static let privacyCover = "内容已隐藏"
}

extension PushTargetDraft {
    public static func title(_ platform: PushPlatform) -> String {
        switch platform {
        case .ntfy: "ntfy"
        case .webhook: "Webhook"
        case .bark, .ios: "Bark"
        }
    }
    public static func label(_ field: PushTargetField, platform: PushPlatform) -> String {
        switch (field, platform) {
        case (.endpoint, .webhook): "URL"
        case (.endpoint, _): "服务器"
        case (.token, .ntfy): "主题"
        case (.token, _): "设备 Key"
        case (.secret, .webhook): "签名密钥（可选）"
        case (.secret, _): "访问令牌（可选）"
        case (.name, _): "名称（可选）"
        }
    }
    public static func placeholder(_ field: PushTargetField, platform: PushPlatform) -> String {
        switch (field, platform) {
        case (.endpoint, .webhook): "https://"
        case (.endpoint, .ntfy): PushDeviceRegistration.defaultNtfyEndpoint
        case (.endpoint, _): PushDeviceRegistration.defaultBarkEndpoint
        case (.token, .ntfy): "字母、数字、- 和 _"
        case (.token, _): "Bark App 里的设备 Key"
        case (.secret, _): "不需要就留空"
        case (.name, _): "列表里显示的名字"
        }
    }
}
