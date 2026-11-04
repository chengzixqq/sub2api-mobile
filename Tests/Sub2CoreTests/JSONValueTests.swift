import Foundation
import Testing
@testable import Sub2Core

private func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

@Test func decodesEveryKindAndRoundTripsThroughJSON() throws {
    let decoded = try json(#"{"n":null,"b":true,"i":42,"s":"x","a":[1,"2",false,null],"o":{"k":{"z":[]}}}"#)
    let expected = JSONValue.object([
        "n": .null, "b": .bool(true), "i": .number(42), "s": .string("x"),
        "a": .array([.number(1), .string("2"), .bool(false), .null]),
        "o": .object(["k": .object(["z": .array([])])])
    ])
    #expect(decoded == expected)
    let encoded = try JSONEncoder().encode(decoded)
    #expect(try JSONDecoder().decode(JSONValue.self, from: encoded) == decoded)
    #expect(try json("1") == .number(1))
    #expect(try json("true") == .bool(true))
    #expect(try json(#""1.5""#) == .string("1.5"))
    #expect(try json("0") != .bool(false))
}

@Test func numbersKeepServerPrecision() throws {
    let decoded = try json(#"{"d":12.34567890123456789,"big":9007199254740993,"tenth":0.1,"half":1.5,"neg":-3}"#)
    #expect(decoded["d"]?.decimalValue == Decimal(string: "12.34567890123456789"))
    #expect(decoded["big"]?.intValue == 9_007_199_254_740_993)
    let text = String(decoding: try decoded.jsonData(), as: UTF8.self)
    #expect(text.contains("12.34567890123456789"))
    #expect(text.contains(#""tenth":0.1"#) && !text.contains("0.1000000000000000055"))
    #expect(decoded["half"]?.intValue == nil)
    #expect(decoded["neg"]?.intValue == -3)
}

@Test func objectKeysEncodeSortedAndBytesAreStable() throws {
    let value: JSONValue = ["b": 1, "a": ["d": 2, "c": 3], "list": [3, 1, 2]]
    let first = try value.jsonData()
    #expect(String(decoding: first, as: UTF8.self) == #"{"a":{"c":3,"d":2},"b":1,"list":[3,1,2]}"#)
    #expect(try value.jsonData() == first)
    #expect(try JSONValue(encoding: value).jsonData() == first)
}

@Test func explicitNullDiffersFromMissingKey() throws {
    let decoded = try json(#"{"a":null}"#)
    #expect(decoded["a"] == .null)
    #expect(decoded["a"]?.isNull == true)
    #expect(decoded["b"] == nil)
    #expect(JSONValue.string("a")["a"] == nil)
    #expect(JSONValue.array([.null])["a"] == nil)
    #expect(!JSONValue.bool(false).isNull)
}

@Test func accessorsReturnNilOnTypeMismatch() {
    let values: [JSONValue] = [.null, .bool(true), .number(1), .string("1"), .array([]), .object([:])]
    #expect(values.compactMap(\.stringValue) == ["1"])
    #expect(values.compactMap(\.boolValue) == [true])
    #expect(values.compactMap(\.decimalValue) == [1])
    #expect(values.compactMap(\.intValue) == [1])
    #expect(values.compactMap(\.objectValue).count == 1)
    #expect(values.compactMap(\.arrayValue).count == 1)
    #expect(values.filter(\.isNull).count == 1)
}

@Test func convertsToAndFromTypedValues() throws {
    let raw = #"{"status":"ok","fresh_until":"2026-10-15T02:00:00Z","data":{"effective_rate_multiplier":1.234567890123456789,"observed_at":"2026-10-15T00:00:00Z"}}"#
    let probe = try JSONDecoder().decode(AccountBillingProbe.self, from: Data(raw.utf8))
    let converted = try JSONValue(encoding: probe).decode(AccountBillingProbe.self)
    let observedNow = Date(timeIntervalSince1970: 1_792_026_000)
    #expect(converted.historicalMultiplier(at: observedNow) == Decimal(string: "1.234567890123456789"))
    #expect(converted.historicalMultiplier(at: observedNow) == probe.historicalMultiplier(at: observedNow))
    #expect(throws: DecodingError.self) { _ = try JSONValue.string("x").decode(AccountBillingProbe.self) }
}
