import Foundation
import Testing
@testable import Sub2Core

private func account(platform: String = "anthropic", type: String = "oauth", _ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":3,"name":"测试账号","platform":"\#(platform)","type":"\#(type)","status":"active","schedulable":true"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func entry(_ from: String, _ to: String? = nil) -> AccountModelMapping.Entry { .init(from: from, to: to ?? from) }
private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

// MARK: - Reading

@Test func mappingReadsStringEntriesSortedByRequestModel() {
    let credentials: JSONValue = ["model_mapping": ["b": "b", "a": "x", "n": 1, "": "y", "c": " ", " d ": "z"]]
    #expect(AccountModelMapping(credentials: credentials).entries == [entry(" d ", "z"), entry("a", "x"), entry("b")])
}

@Test(arguments: [nil, [:], ["model_mapping": [:]], ["model_mapping": "gpt-5"], ["model_mapping": ["gpt-5"]], ["model_mapping": .null]] as [JSONValue?])
func missingOrMalformedMappingMeansAllModels(credentials: JSONValue?) {
    let mapping = AccountModelMapping(credentials: credentials)
    #expect(mapping.isEmpty && mapping.summary == "未限制")
    #expect(AccountModelMapping.emptyText == "支持所有模型")
}

@Test func summaryCountsEntriesWithGrouping() {
    #expect(AccountModelMapping(entries: [entry("a"), entry("b"), entry("c")]).summary == "只调度这 3 个")
    #expect(AccountModelMapping(entries: [entry("a")]).summary == "只调度这 1 个")
    #expect(AccountModelMapping(entries: (0..<1_234).map { entry("m\($0)") }).summary == "只调度这 1,234 个")
}

@Test func passthroughEntryForwardsTheRequestedModel() {
    #expect(entry("gpt-5").isPassthrough && !entry("claude-opus-4-1", "claude-opus-4").isPassthrough)
    #expect(AccountModelMapping.passthroughText == "原样转发")
}

// MARK: - Editing

@Test func addingModelsAppendsSelfMappingsSkippingExistingAndWildcards() {
    let mapping = AccountModelMapping(entries: [entry("gpt-5")]).adding(models: [" gpt-4.1 ", "gpt-5", "gpt-4*", " "])
    #expect(mapping.entries == [entry("gpt-5"), entry("gpt-4.1")])
}

@Test func togglingAModelAddsOrRemovesItsRowIncludingAMapping() {
    let added = AccountModelMapping().toggling(model: "gpt-4o")
    #expect(added.entries == [entry("gpt-4o")])
    #expect(added.toggling(model: "gpt-4o").isEmpty)
    let mapped = AccountModelMapping(entries: [entry("claude-opus-4-1", "claude-opus-4"), entry("claude-opus-4")])
    #expect(mapped.toggling(model: "claude-opus-4-1").entries == [entry("claude-opus-4")])
    #expect(mapped.removing(from: "claude-opus-4").entries == [entry("claude-opus-4-1", "claude-opus-4")])
}

struct MappingValidationCase: Sendable, CustomTestStringConvertible {
    let from: String, to: String, error: AccountModelMappingError?, message: String?
    var testDescription: String { "\(from) → \(to)" }
}
private let mappingValidationCases: [MappingValidationCase] = [
    .init(from: "gpt-*-mini", to: "x", error: .wildcardNotAtEnd, message: "通配符 * 只能放在末尾"),
    .init(from: "gpt-**", to: "x", error: .wildcardNotAtEnd, message: "通配符 * 只能放在末尾"),
    .init(from: "gpt-*-mini", to: "", error: .wildcardNotAtEnd, message: "通配符 * 只能放在末尾"),
    .init(from: "gpt-4*", to: "gpt-4*", error: .wildcardInTarget, message: "实际模型不能用通配符"),
    .init(from: " gpt-5 ", to: "gpt-5.1", error: .duplicate, message: "这个请求模型已在列表里"),
    .init(from: "  ", to: "x", error: .emptyFrom, message: nil),
    .init(from: "x", to: " ", error: .emptyTo, message: nil),
    .init(from: " claude-3-5-sonnet-* ", to: " claude-sonnet-4-5 ", error: nil, message: nil),
    .init(from: "*", to: "gpt-5-mini", error: nil, message: nil)
]
@Test(arguments: mappingValidationCases)
func mappingValidationTable(_ entry: MappingValidationCase) {
    let existing = AccountModelMapping(entries: [.init(from: "gpt-5", to: "gpt-5")])
    let error = AccountModelMapping.validate(from: entry.from, to: entry.to, existing: existing)
    #expect(error == entry.error)
    #expect(error?.message == entry.message)
}

@Test func addingAValidMappingAppendsItTrimmedAndAnInvalidOneThrows() throws {
    let base = AccountModelMapping(entries: [entry("gpt-5")])
    #expect(try base.adding(from: " gpt-4-* ", to: "gpt-4.1 ").entries == [entry("gpt-5"), entry("gpt-4-*", "gpt-4.1")])
    #expect(throws: AccountModelMappingError.wildcardNotAtEnd) { try base.adding(from: "gpt-*-x", to: "gpt-4.1") }
    #expect(throws: AccountModelMappingError.duplicate) { try base.adding(from: "gpt-5", to: "gpt-4.1") }
    #expect(base.entries == [entry("gpt-5")])
}

@Test func sameTableIgnoresOrder() throws {
    let one = AccountModelMapping(entries: [entry("a"), entry("b", "x")])
    #expect(one.sameTable(as: AccountModelMapping(entries: [entry("b", "x"), entry("a")])))
    #expect(!one.sameTable(as: AccountModelMapping(entries: [entry("a"), entry("b", "y")])))
    var draft = AccountModelsDraft(account: try account(#""credentials":{"model_mapping":{"a":"a","b":"x"}}"#))
    draft.mapping = AccountModelMapping(entries: [entry("b", "x"), entry("a")])
    #expect(!draft.hasChanges && draft.changedFieldNames.isEmpty && !draft.patch().hasChanges && draft.change() == nil)
}

// MARK: - Saving

@Test func patchWritesTheWholeTableOrNull() throws {
    var draft = AccountModelsDraft(account: try account(#""credentials":{"model_mapping":{"gpt-5":"gpt-5"}}"#))
    draft.mapping = try draft.mapping.adding(from: "gpt-4-*", to: "gpt-4.1")
    #expect(text(try draft.patch().requestBody()) == #"{"credentials_patch":{"model_mapping":{"gpt-4-*":"gpt-4.1","gpt-5":"gpt-5"}}}"#)
    draft.mapping = AccountModelMapping()
    #expect(text(try draft.patch().requestBody()) == #"{"credentials_patch":{"model_mapping":null}}"#)
}

@Test func modelsDraftReportsTheChangeAndUndoesToTheStoredTable() throws {
    var draft = AccountModelsDraft(account: try account(#""credentials":{"model_mapping":{"a":"a"},"base_url":"https://relay.example.invalid"}"#))
    draft.mapping = draft.mapping.adding(models: ["b"])
    let change = try #require(draft.change())
    #expect(change.fieldNames == ["模型"] && AccountModelsDraft.fieldName == "模型")
    #expect(change.request.credentialsPatch == ["model_mapping": .set(["a": "a", "b": "b"])])
    #expect(change.request.extraPatch.isEmpty && change.undo?.credentialsPatch == ["model_mapping": .set(["a": "a"])])
    draft.mapping = AccountModelMapping()
    #expect(draft.patch().credentialsPatch == ["model_mapping": .delete] && draft.undoPatch().credentialsPatch == ["model_mapping": .set(["a": "a"])])

    var fresh = AccountModelsDraft(account: try account())
    fresh.mapping = fresh.mapping.adding(models: ["a"])
    #expect(fresh.undoPatch().credentialsPatch == ["model_mapping": .delete])
}

// MARK: - Badges and the passthrough note

@Test func limitBadgeMatchesTheMappedTargetModel() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let limits = [AccountModelRateLimit(model: "claude-opus-4", resetAt: now.addingTimeInterval(720)),
                  AccountModelRateLimit(model: "claude-haiku-4-5", resetAt: now.addingTimeInterval(-1)),
                  AccountModelRateLimit(model: "gpt-5", resetAt: now.addingTimeInterval(3_900)),
                  AccountModelRateLimit(model: "o4-mini", resetAt: now.addingTimeInterval(20))]
    #expect(AccountModelMapping.limitBadge(for: entry("claude-opus-4-1", "claude-opus-4"), limits: limits, now: now) == "限流 12 分钟")
    #expect(AccountModelMapping.limitBadge(for: entry("claude-opus-4"), limits: limits, now: now) == "限流 12 分钟")
    #expect(AccountModelMapping.limitBadge(for: entry("claude-opus-4", "claude-sonnet-4"), limits: limits, now: now) == nil)
    #expect(AccountModelMapping.limitBadge(for: entry("claude-haiku-4-5"), limits: limits, now: now) == nil)
    #expect(AccountModelMapping.limitBadge(for: entry("gpt-5"), limits: limits, now: now) == "限流 1 小时 5 分钟")
    #expect(AccountModelMapping.limitBadge(for: entry("o4-mini"), limits: limits, now: now) == "限流 1 分钟")
}

/// Backend IsOpenAIPassthroughEnabled: the new key decides when it is a boolean, the old OAuth key otherwise; OpenAI only.
@Test func passthroughReadsTheCurrentKeyThenTheLegacyOneForOpenAIOnly() throws {
    #expect(AccountModelMapping.passthroughEnabled(try account(platform: "openai", type: "apikey", #""extra":{"openai_passthrough":true}"#)))
    #expect(AccountModelMapping.passthroughEnabled(try account(platform: "openai", #""extra":{"openai_oauth_passthrough":true}"#)))
    #expect(!AccountModelMapping.passthroughEnabled(try account(platform: "openai", #""extra":{"openai_passthrough":false,"openai_oauth_passthrough":true}"#)))
    #expect(!AccountModelMapping.passthroughEnabled(try account(#""extra":{"openai_passthrough":true}"#)))
    #expect(!AccountModelMapping.passthroughEnabled(try account(platform: "openai", #""extra":{"openai_passthrough":"true"}"#)))
    #expect(!AccountModelMapping.passthroughEnabled(try account(platform: "openai")))
    #expect(AccountModelMapping.passthroughNote == "已开启自动透传，模型限制不生效")
}
