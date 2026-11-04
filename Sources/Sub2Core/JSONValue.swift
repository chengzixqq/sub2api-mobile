import Foundation

/// Any JSON value. Numbers are kept as Decimal, never through Double, so a value comes back exactly (the spelling does not:
/// 1.10 reads back as 1.1). Object keys are written in sorted order and `jsonData()` gives the same bytes for equal values.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        // Bool is tried before Decimal: JSONDecoder never reads a number as Bool or `true` as a number.
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Decimal.self) { self = .number(value) }
        else if let value = try? c.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? c.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value.") }
    }
    public func encode(to encoder: any Encoder) throws {
        if case .object(let fields) = self {
            var c = encoder.container(keyedBy: ObjectKey.self)
            for (key, value) in fields.sorted(by: { $0.key < $1.key }) { try c.encode(value, forKey: ObjectKey(key)) }
            return
        }
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let values): try c.encode(values)
        case .object: break
        }
    }
    private struct ObjectKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Converts a typed value through its JSON form.
    public init<T: Encodable>(encoding value: T) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
    public func decode<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: jsonData()) }
    /// Sorted keys: equal values always give the same request bytes.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(self)
    }

    /// Objects only; a missing key is nil, an explicit null is `.null`.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let fields) = self else { return nil }
        return fields[key]
    }
    public var isNull: Bool { self == .null }
    public var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    public var boolValue: Bool? { if case .bool(let value) = self { value } else { nil } }
    public var decimalValue: Decimal? { if case .number(let value) = self { value } else { nil } }
    /// Whole numbers within Int's range, converted exactly.
    public var intValue: Int? {
        guard case .number(var value) = self, value.hasAtMostFractionDigits(0) else { return nil }
        var whole = Decimal()
        NSDecimalRound(&whole, &value, 0, .plain)
        return Int(whole.description)
    }
    public var objectValue: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    public var arrayValue: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Decimal(value)) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}
