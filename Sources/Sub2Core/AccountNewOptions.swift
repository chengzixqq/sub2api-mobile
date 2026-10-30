import Foundation

/// One choice of a grouped picker: the value sent and what the row says.
public struct AccountNewOption: Sendable, Equatable, Identifiable {
    public let value: String
    public let label: String
    public var id: String { value }
}

public struct AccountNewOptionGroup: Sendable, Equatable, Identifiable {
    public let title: String
    public let options: [AccountNewOption]
    public var id: String { title }
}

/// A shortcut address for one mode and protocol of a domestic provider (Web CN_BASE_URL_PRESETS).
public struct AccountNewEndpointPreset: Sendable, Equatable, Identifiable {
    public let platform: String
    public let mode: String
    public let apiProtocol: String
    public let label: String
    public let url: String
    public var id: String { url }
}

/// 20 §7.3 接入 · 端点 for a concrete protocol: the catalog's, a preset, or the admin's own.
public enum AccountNewEndpointChoice: Hashable, Sendable {
    case official
    case preset(String)
    case custom
}

/// Web CreateAccountModal's Bedrock Region list and VERTEX_LOCATION_OPTIONS, in its groups and order.
extension AccountNewDefaults {
    public static let bedrockRegionGroups: [AccountNewOptionGroup] = [
        group("美国", [("us-east-1", "弗吉尼亚北部"), ("us-east-2", "俄亥俄"), ("us-west-1", "加利福尼亚北部"), ("us-west-2", "俄勒冈"),
                     ("us-gov-east-1", "GovCloud 美国东部"), ("us-gov-west-1", "GovCloud 美国西部")]),
        group("欧洲", [("eu-west-1", "爱尔兰"), ("eu-west-2", "伦敦"), ("eu-west-3", "巴黎"), ("eu-central-1", "法兰克福"), ("eu-central-2", "苏黎世"),
                     ("eu-south-1", "米兰"), ("eu-south-2", "西班牙"), ("eu-north-1", "斯德哥尔摩")]),
        group("亚太", [("ap-northeast-1", "东京"), ("ap-northeast-2", "首尔"), ("ap-northeast-3", "大阪"), ("ap-south-1", "孟买"), ("ap-south-2", "海得拉巴"),
                     ("ap-southeast-1", "新加坡"), ("ap-southeast-2", "悉尼")]),
        group("加拿大", [("ca-central-1", "加拿大中部")]),
        group("南美", [("sa-east-1", "圣保罗")])
    ]
    public static let vertexLocationGroups: [AccountNewOptionGroup] = [
        group("常用", [("us-central1", "艾奥瓦"), ("global", nil), ("us", nil), ("eu", nil)]),
        group("美国", [("us-east1", "南卡罗来纳"), ("us-east4", "弗吉尼亚北部"), ("us-east5", "哥伦布"), ("us-south1", "达拉斯"), ("us-west1", "俄勒冈"),
                     ("us-west4", "拉斯维加斯")]),
        group("欧洲", [("europe-west1", "比利时"), ("europe-west2", "伦敦"), ("europe-west3", "法兰克福"), ("europe-west4", "荷兰"),
                     ("europe-west6", "苏黎世"), ("europe-west8", "米兰"), ("europe-west9", "巴黎")]),
        group("亚太", [("asia-east1", "中国台湾彰化"), ("asia-east2", "中国香港"), ("asia-northeast1", "东京"), ("asia-northeast3", "首尔"),
                     ("asia-south1", "孟买"), ("asia-southeast1", "新加坡"), ("australia-southeast1", "悉尼")])
    ]

    /// “us-east-1（弗吉尼亚北部）”, or the bare value.
    private static func group(_ title: String, _ items: [(String, String?)]) -> AccountNewOptionGroup {
        AccountNewOptionGroup(title: title, options: items.map { value, place in
            AccountNewOption(value: value, label: place.map { "\(value)（\($0)）" } ?? value)
        })
    }
}

extension AccountNewCatalog {
    /// Web CN_BASE_URL_PRESETS (credentialsBuilder.ts).
    private static let allEndpointPresets: [AccountNewEndpointPreset] = [
        preset("kimi", "payg", "chat_completions", "Moonshot", "https://api.moonshot.cn/v1"),
        preset("kimi", "payg", "anthropic", "Moonshot Anthropic", "https://api.moonshot.cn/anthropic"),
        preset("kimi", "payg", "responses", "Moonshot Responses", "https://api.moonshot.cn/v1"),
        preset("kimi", "coding", "chat_completions", "Kimi For Coding", "https://api.kimi.com/coding/v1"),
        preset("kimi", "coding", "anthropic", "Kimi Coding Anthropic", "https://api.kimi.com/coding"),
        preset("kimi", "coding", "responses", "Kimi Coding Responses", "https://api.kimi.com/coding/v1"),
        preset("zhipu", "payg", "chat_completions", "GLM PaaS", "https://open.bigmodel.cn/api/paas/v4"),
        preset("zhipu", "payg", "anthropic", "GLM Anthropic", "https://open.bigmodel.cn/api/anthropic"),
        preset("zhipu", "coding", "chat_completions", "GLM Coding", "https://open.bigmodel.cn/api/coding/paas/v4"),
        preset("zhipu", "coding", "anthropic", "GLM Coding Anthropic", "https://open.bigmodel.cn/api/anthropic"),
        preset("deepseek", "payg", "chat_completions", "DeepSeek", "https://api.deepseek.com"),
        preset("deepseek", "payg", "anthropic", "DeepSeek Anthropic", "https://api.deepseek.com/anthropic"),
        preset("deepseek", "payg", "responses", "DeepSeek Responses", "https://api.deepseek.com"),
        preset("minimax", "payg", "chat_completions", "MiniMax CN", "https://api.minimaxi.com/v1"),
        preset("minimax", "payg", "anthropic", "MiniMax CN Anthropic", "https://api.minimaxi.com/anthropic"),
        preset("minimax", "payg", "responses", "MiniMax CN Responses", "https://api.minimaxi.com/v1"),
        preset("minimax", "payg", "chat_completions", "MiniMax Intl", "https://api.minimax.io/v1"),
        preset("minimax", "payg", "anthropic", "MiniMax Intl Anthropic", "https://api.minimax.io/anthropic"),
        preset("minimax", "payg", "responses", "MiniMax Intl Responses", "https://api.minimax.io/v1"),
        preset("minimax", "coding", "chat_completions", "MiniMax Coding CN", "https://api.minimaxi.com/v1"),
        preset("minimax", "coding", "anthropic", "MiniMax Coding CN Anthropic", "https://api.minimaxi.com/anthropic"),
        preset("minimax", "coding", "responses", "MiniMax Coding CN Responses", "https://api.minimaxi.com/v1"),
        preset("minimax", "coding", "chat_completions", "MiniMax Coding Intl", "https://api.minimax.io/v1"),
        preset("minimax", "coding", "anthropic", "MiniMax Coding Intl Anthropic", "https://api.minimax.io/anthropic"),
        preset("minimax", "coding", "responses", "MiniMax Coding Intl Responses", "https://api.minimax.io/v1")
    ]

    /// The presets of this platform, mode and protocol other than the catalog's own address, each address once.
    public static func endpointPresets(platform: String, mode: String, apiProtocol: String, official: String?) -> [AccountNewEndpointPreset] {
        var seen = Set(official.map { [$0] } ?? [])
        return allEndpointPresets.filter { $0.platform == platform && $0.mode == mode && $0.apiProtocol == apiProtocol && seen.insert($0.url).inserted }
    }

    private static func preset(_ platform: String, _ mode: String, _ apiProtocol: String, _ label: String, _ url: String) -> AccountNewEndpointPreset {
        AccountNewEndpointPreset(platform: platform, mode: mode, apiProtocol: apiProtocol, label: label, url: url)
    }
}

extension AccountNewDraft {
    /// A concrete protocol's 端点 candidates after the catalog's (20 §7.3); [] for 自适应 and for other methods.
    public var endpointPresets: [AccountNewEndpointPreset] {
        guard let platform, let method, case .multiProtocol(let mode) = method.kind, let apiProtocol = effectiveProtocol,
              apiProtocol != AccountProtocolEndpoints.adaptive else { return [] }
        return AccountNewCatalog.endpointPresets(platform: platform, mode: mode.mode, apiProtocol: apiProtocol,
                                                 official: method.officialEndpoint(for: apiProtocol))
    }
    /// The 端点 picker: a preset of another protocol or mode reads as the catalog's.
    public var endpointChoice: AccountNewEndpointChoice {
        get {
            if usesCustomEndpoint { return .custom }
            guard let presetEndpoint, endpointPresets.contains(where: { $0.url == presetEndpoint }) else { return .official }
            return .preset(presetEndpoint)
        }
        set {
            usesCustomEndpoint = newValue == .custom
            if case .preset(let url) = newValue { presetEndpoint = url } else { presetEndpoint = nil }
        }
    }
    /// What a concrete protocol sends as `base_url`.
    func concreteEndpoint(_ method: AccountNewMethod, apiProtocol: String) -> String? {
        if customEndpointInUse { return customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines) }
        if case .preset(let url) = endpointChoice { return url }
        return method.officialEndpoint(for: apiProtocol)
    }
}
