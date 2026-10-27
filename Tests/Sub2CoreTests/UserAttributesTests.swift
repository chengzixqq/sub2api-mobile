import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func definitionJSON(id: Int, type: String, order: Int = 0, extra: String = "") -> String {
    "{\"id\":\(id),\"key\":\"k\(id)\",\"name\":\"属性\(id)\",\"description\":\"\",\"type\":\"\(type)\",\"options\":null,\"required\":false,"
        + "\"validation\":{},\"placeholder\":\"\",\"display_order\":\(order),\"enabled\":true,\"created_at\":\"2026-10-01T00:00:00Z\","
        + "\"updated_at\":\"2026-10-01T00:00:00Z\"\(extra)}"
}
private func attributesClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-key"), transport: transport, requestClock: .immediate)
}
private func queryItems(_ request: URLRequest?) -> [URLQueryItem] {
    request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
}

/// The backend's AttributeDefinitionResponse shape for every type (30 §5.2).
@Test func definitionsDecodeAllTypesAndDefaults() throws {
    for kind in UserAttributeDefinition.Kind.allCases {
        let definition = try JSONDecoder().decode(UserAttributeDefinition.self, from: Data(definitionJSON(id: 3, type: kind.rawValue).utf8))
        #expect(definition.kind == kind && definition.type == kind.rawValue)
        #expect(definition.options.isEmpty && definition.placeholder == nil && !definition.isRequired)
    }
    let select = #"{"id":4,"key":"region","name":"区域","type":"select","options":[{"value":"east","label":"华东"},{"value":"west","label":"华西"}],"required":true,"placeholder":"请选择","display_order":2}"#
    let region = try JSONDecoder().decode(UserAttributeDefinition.self, from: Data(select.utf8))
    #expect(region.key == "region" && region.name == "区域" && region.isRequired && region.placeholder == "请选择" && region.displayOrder == 2)
    #expect(region.options == [.init(value: "east", label: "华东"), .init(value: "west", label: "华西")])
    let bare = try JSONDecoder().decode(UserAttributeDefinition.self, from: Data(#"{"id":5,"name":"颜色","type":"color"}"#.utf8))
    #expect(bare.kind == nil && bare.type == "color" && bare.key == "" && !bare.isRequired && bare.placeholder == nil && bare.displayOrder == 0)
}

/// U28: multi_select and unknown types are shown, never written.
@Test func multiSelectAndUnknownTypesAreReadOnly() {
    let readOnly = UserAttributeDefinition.Kind.allCases.filter { UserAttributeDefinition(id: 1, key: "k", name: "n", type: $0.rawValue).isReadOnly }
    #expect(readOnly == [.multiSelect])
    #expect(UserAttributeDefinition(id: 1, key: "k", name: "n", type: "color").isReadOnly)
    let region = UserAttributeDefinition(id: 4, key: "region", name: "区域", type: "select", options: [.init(value: "east", label: "华东")])
    #expect(region.optionLabel(for: "east") == "华东" && region.optionLabel(for: "north") == nil)
}

@Test func definitionsRequestEnabledOnlyAndSortByDisplayOrder() async throws {
    let list = [definitionJSON(id: 2, type: "text", order: 3), definitionJSON(id: 9, type: "text", order: 1), definitionJSON(id: 4, type: "number", order: 1)]
    let transport = ScriptedTransport { _ in okReply("[\(list.joined(separator: ","))]") }
    let definitions = try await attributesClient(transport).userAttributeDefinitions()
    #expect(definitions.map(\.id) == [4, 9, 2])
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "GET" && request.url?.path == "/api/v1/admin/user-attributes")
    #expect(queryItems(request) == [URLQueryItem(name: "enabled", value: "true")])
}

@Test func userAttributesDecodeValues() async throws {
    let reply = #"[{"id":1,"user_id":24,"attribute_id":3,"value":"华东","created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-01T00:00:00Z"},{"id":2,"user_id":24,"attribute_id":5}]"#
    let transport = ScriptedTransport { _ in okReply(reply) }
    let client = attributesClient(transport)
    let values = try await client.userAttributes(userID: 24)
    #expect(values == [UserAttributeValue(attributeID: 3, value: "华东"), UserAttributeValue(attributeID: 5, value: "")])
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "GET" && request.url?.path == "/api/v1/admin/users/24/attributes")
    #expect(await thrownAPIError { _ = try await client.userAttributes(userID: 0) }?.kind == .validation)
    #expect(await transport.requests.count == 1)
}

/// 30 §5.4 step 6 / §6.4 step 5: string keys, sent once without a key.
@Test func updateSendsStringKeyedValuesOnce() async throws {
    let transport = ScriptedTransport { _ in okReply(#"[{"attribute_id":3,"value":"华东"},{"attribute_id":8,"value":""}]"#) }
    let saved = try await attributesClient(transport).updateUserAttributes(userID: 24, values: [3: "华东", 8: ""])
    #expect(saved == [UserAttributeValue(attributeID: 3, value: "华东"), UserAttributeValue(attributeID: 8, value: "")])
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "PUT" && request.url?.path == "/api/v1/admin/users/24/attributes")
    #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"values":{"3":"华东","8":""}}"#)
    #expect(sentHeader(request, "Idempotency-Key") == nil && sentHeader(request, "X-Request-ID") != nil)
    let failing = ScriptedTransport { _ in errorReply(500) }
    await #expect(throws: APIError.self) { _ = try await attributesClient(failing).updateUserAttributes(userID: 24, values: [3: "华东"]) }
    #expect(await failing.requests.count == 1)
}

@Test func emptyOrInvalidUpdateSendsNothing() async throws {
    let transport = ScriptedTransport { _ in okReply("[]") }
    let client = attributesClient(transport)
    #expect(await thrownAPIError { _ = try await client.updateUserAttributes(userID: 24, values: [:]) }?.kind == .validation)
    #expect(await thrownAPIError { _ = try await client.updateUserAttributes(userID: 24, values: [0: "x"]) }?.kind == .validation)
    #expect(await thrownAPIError { _ = try await client.updateUserAttributes(userID: 0, values: [3: "x"]) }?.kind == .validation)
    #expect(await transport.requests.isEmpty)
}

/// Only edited, writable, known definitions go out; a cleared value is "".
@Test func changesSendOnlyEditedEnabledValues() {
    let text = { (id: Int) in UserAttributeDefinition(id: id, key: "k\(id)", name: "属性\(id)", type: "text") }
    let definitions = [text(3), text(4), text(5), UserAttributeDefinition(id: 7, key: "k7", name: "标签", type: "multi_select")]
    let original = [3: "华东", 4: "x", 7: #"["a"]"#]
    let draft = [3: "华东 ", 4: "", 5: " 新 ", 7: "[]", 8: "孤儿"]
    #expect(UserAttributeEdits.changes(original: original, draft: draft, definitions: definitions) == [4: "", 5: "新"])
    #expect(UserAttributeEdits.changes(original: [:], draft: [3: "", 5: "值"], definitions: definitions) == [5: "值"])
    #expect(UserAttributeEdits.values([UserAttributeValue(attributeID: 3, value: "旧"), UserAttributeValue(attributeID: 3, value: "新")]) == [3: "新"])
}
