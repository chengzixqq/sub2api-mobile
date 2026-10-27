import Foundation

/// One enabled custom attribute definition (`GET admin/user-attributes?enabled=true`, 30 §5.2).
public struct UserAttributeDefinition: Identifiable, Decodable, Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable { case text, textarea, number, email, url, date, select, multiSelect = "multi_select" }
    public struct Option: Decodable, Sendable, Equatable {
        public let value: String
        public let label: String
        public init(value: String, label: String) { self.value = value; self.label = label }
    }
    public let id: Int
    /// "" when the reply leaves it out.
    public let key: String
    public let name: String
    /// The server's value as sent; `kind` is nil for a type this App does not know.
    public let type: String
    public let options: [Option]
    public let isRequired: Bool
    /// nil when blank.
    public let placeholder: String?
    public let displayOrder: Int
    public var kind: Kind? { Kind(rawValue: type) }
    /// U28: multi_select and unknown types are shown as they are (“在 Web 端修改”), never required here and never written.
    public var isReadOnly: Bool { kind == nil || kind == .multiSelect }
    public func optionLabel(for value: String) -> String? { options.first { $0.value == value }?.label }

    public init(id: Int, key: String, name: String, type: String, options: [Option] = [], isRequired: Bool = false, placeholder: String? = nil,
                displayOrder: Int = 0) {
        self.id = id; self.key = key; self.name = name; self.type = type; self.options = options; self.isRequired = isRequired
        self.placeholder = placeholder.flatMap { $0.isEmpty ? nil : $0 }; self.displayOrder = displayOrder
    }
    enum CodingKeys: String, CodingKey { case id, key, name, type, options, required, placeholder; case displayOrder = "display_order" }
    /// id and name are required; anything else missing or malformed reads as its default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
        try self.init(id: c.decode(Int.self, forKey: .id), key: text(.key) ?? "", name: c.decode(String.self, forKey: .name), type: text(.type) ?? "",
                      options: (try? c.decodeIfPresent(LossyList<Option>.self, forKey: .options))?.items ?? [],
                      isRequired: (try? c.decodeIfPresent(Bool.self, forKey: .required)) ?? false, placeholder: text(.placeholder),
                      displayOrder: (try? c.decodeIfPresent(Int.self, forKey: .displayOrder)) ?? 0)
    }
}

/// One stored value (`GET admin/users/:id/attributes`).
public struct UserAttributeValue: Decodable, Sendable, Equatable {
    public let attributeID: Int
    public let value: String
    public init(attributeID: Int, value: String) { self.attributeID = attributeID; self.value = value }
    enum CodingKeys: String, CodingKey { case value; case attributeID = "attribute_id" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(attributeID: c.decode(Int.self, forKey: .attributeID), value: (try? c.decodeIfPresent(String.self, forKey: .value)) ?? "")
    }
}

public enum UserAttributeEdits {
    /// Attribute id → value; a repeated id keeps the later value.
    public static func values(_ list: [UserAttributeValue]) -> [Int: String] {
        Dictionary(list.map { ($0.attributeID, $0.value) }, uniquingKeysWith: { _, later in later })
    }
    /// 30 §6.4 step 5: only writable definitions in `definitions`, only values that differ after trimming; a cleared value is
    /// "". An id outside the enabled definitions would answer 404 ATTRIBUTE_DEFINITION_NOT_FOUND, so it is never sent.
    public static func changes(original: [Int: String], draft: [Int: String], definitions: [UserAttributeDefinition]) -> [Int: String] {
        var changes = [Int: String]()
        for definition in definitions where !definition.isReadOnly {
            guard let value = draft[definition.id]?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            if value != (original[definition.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) { changes[definition.id] = value }
        }
        return changes
    }
}

extension APIClient {
    /// The server returns every definition unless `enabled` is the literal "true". Sorted by display order, then id.
    public func userAttributeDefinitions() async throws -> [UserAttributeDefinition] {
        let list: LossyList<UserAttributeDefinition> = try await request("admin/user-attributes", query: [URLQueryItem(name: "enabled", value: "true")])
        return list.items.sorted { ($0.displayOrder, $0.id) < ($1.displayOrder, $1.id) }
    }
    public func userAttributes(userID: Int) async throws -> [UserAttributeValue] {
        let list: LossyList<UserAttributeValue> = try await request("admin/users/\(validID(userID))/attributes")
        return list.items
    }
    /// `{"values":{"<attribute_id>":"<value>"}}`, an ordinary write sent once (no idempotency on this route). Returns every
    /// value the server holds afterwards.
    public func updateUserAttributes(userID: Int, values: [Int: String]) async throws -> [UserAttributeValue] {
        let path = "admin/users/\(try validID(userID))/attributes"
        guard !values.isEmpty, values.keys.allSatisfy({ $0 > 0 }) else { throw APIError(kind: .validation, message: "无效的自定义属性。") }
        let body = try encode(["values": Dictionary(uniqueKeysWithValues: values.map { (String($0.key), $0.value) })])
        let list: LossyList<UserAttributeValue> = try await request(path, method: "PUT", body: body)
        return list.items
    }
}
