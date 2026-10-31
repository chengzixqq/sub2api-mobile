import Foundation
import Testing
@testable import Sub2Core

private let catalog = MetaCatalog.builtin

private func keyed(_ platform: String, _ methodID: String) throws -> AccountNewDraft {
    let methods = AccountNewCatalog.methods(for: platform, in: catalog)
    var draft = AccountNewDraft().switchingPlatform(to: platform, methods: methods, suggestedName: "\(platform)-01")
        .switchingMethod(to: try #require(methods.first { $0.id == methodID }))
    draft.apiKey = "sk-options-fixture"
    return draft
}

@Test func bedrockRegionsFollowTheWebList() {
    let groups = AccountNewDefaults.bedrockRegionGroups
    #expect(groups.map(\.title) == ["美国", "欧洲", "亚太", "加拿大", "南美"])
    let values = groups.flatMap(\.options).map(\.value)
    #expect(values.count == 23 && Set(values).count == values.count)
    for region in ["us-east-1", "us-east-2", "us-west-1", "us-gov-west-1", "eu-central-1", "eu-north-1", "ap-southeast-1", "ap-south-2",
                   "ca-central-1", "sa-east-1"] {
        #expect(values.contains(region), "\(region)")
    }
    #expect(values.first == AccountNewDefaults.bedrockRegion)
    #expect(groups[0].options[0].label == "us-east-1（弗吉尼亚北部）")
}

@Test func vertexLocationsFollowTheWebList() {
    let groups = AccountNewDefaults.vertexLocationGroups
    #expect(groups.map(\.title) == ["常用", "美国", "欧洲", "亚太"])
    let values = groups.flatMap(\.options).map(\.value)
    #expect(values.count == 24 && Set(values).count == values.count)
    #expect(groups[0].options.map(\.value) == ["us-central1", "global", "us", "eu"])
    for location in ["us-east5", "us-west4", "europe-west4", "europe-west9", "asia-northeast1", "australia-southeast1"] {
        #expect(values.contains(location), "\(location)")
    }
    #expect(values.contains(AccountNewDefaults.vertexLocation))
}

@Test func endpointPresetsOfferTheModesOtherAddresses() throws {
    var minimax = try keyed("minimax", "mode.payg")
    #expect(minimax.endpointPresets.isEmpty, "自适应 has no endpoint picker")
    minimax.apiProtocol = "chat_completions"
    #expect(minimax.endpointPresets.map(\.url) == ["https://api.minimax.io/v1"], "the catalog's own address is not repeated")
    #expect(minimax.endpointPresets.map(\.label) == ["MiniMax Intl"])
    #expect(minimax.endpointChoice == .official)
    #expect(try minimax.builtCredentials().credentials["base_url"] == "https://api.minimaxi.com/v1")

    minimax.endpointChoice = .preset("https://api.minimax.io/v1")
    #expect(minimax.endpointChoice == .preset("https://api.minimax.io/v1") && !minimax.usesCustomEndpoint)
    #expect(try minimax.builtCredentials().credentials["base_url"] == "https://api.minimax.io/v1")
    #expect(minimax.missing(in: catalog).isEmpty && minimax.issues.isEmpty)

    minimax.apiProtocol = "anthropic"
    #expect(minimax.endpointPresets.map(\.url) == ["https://api.minimax.io/anthropic"])
    #expect(minimax.endpointChoice == .official, "a preset of another protocol does not carry over")
    #expect(try minimax.builtCredentials().credentials["base_url"] == "https://api.minimaxi.com/anthropic")

    minimax.endpointChoice = .custom
    minimax.customEndpoint = "https://relay.example.invalid/anthropic"
    #expect(minimax.endpointChoice == .custom && minimax.usesCustomEndpoint)
    #expect(try minimax.builtCredentials().credentials["base_url"] == "https://relay.example.invalid/anthropic")
    minimax.endpointChoice = .official
    #expect(!minimax.usesCustomEndpoint && minimax.presetEndpoint == nil)

    var coding = try keyed("minimax", "mode.coding")
    coding.apiProtocol = "responses"
    #expect(coding.endpointPresets.map(\.label) == ["MiniMax Coding Intl Responses"])
    var kimi = try keyed("kimi", "mode.payg")
    kimi.apiProtocol = "chat_completions"
    #expect(kimi.endpointPresets.isEmpty)
    #expect(try keyed("cline", "mode.payg").endpointPresets.isEmpty)
}

@Test func switchingMethodDropsThePreset() throws {
    var payg = try keyed("minimax", "mode.payg")
    payg.apiProtocol = "chat_completions"
    payg.endpointChoice = .preset("https://api.minimax.io/v1")
    let methods = AccountNewCatalog.methods(for: "minimax", in: catalog)
    let coding = payg.switchingMethod(to: try #require(methods.first { $0.id == "mode.coding" }))
    #expect(coding.presetEndpoint == nil && coding.endpointChoice == .official)
}
