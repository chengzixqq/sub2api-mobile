import Foundation
import Testing
@testable import Sub2Core

// This test intentionally uses only the original DashboardStats API so the same
// source can demonstrate the old decoder losing fields, and the fix preserving them.
private struct OverviewWireProjection: Decodable {
    let today_actual_cost: Decimal?
    let today_account_cost: Decimal?
    let total_actual_cost: Decimal?
    let total_account_cost: Decimal?
    let total_tokens: Int?
    let average_duration_ms: Double?
}

@Test func overviewRegressionPreservesActualAccountCostTokensAndPerformance() throws {
    let source = #"{"today_requests":12,"today_tokens":1234567,"today_cost":"99.99","today_actual_cost":"12.34567891","today_account_cost":"4.56789123","total_actual_cost":"1234.56789123","total_account_cost":"456.78912345","total_tokens":9876543210,"average_duration_ms":1250.25,"total_users":8,"total_accounts":3,"error_accounts":1,"rpm":1234,"tpm":987654}"#
    let stats = try JSONDecoder().decode(DashboardStats.self, from: Data(source.utf8))
    let roundTrip = try JSONEncoder().encode(stats)
    let fields = try JSONDecoder().decode(OverviewWireProjection.self, from: roundTrip)
    #expect(fields.today_actual_cost == Decimal(string: "12.34567891"))
    #expect(fields.today_account_cost == Decimal(string: "4.56789123"))
    #expect(fields.total_actual_cost == Decimal(string: "1234.56789123"))
    #expect(fields.total_account_cost == Decimal(string: "456.78912345"))
    #expect(fields.total_tokens == 9_876_543_210)
    #expect(fields.average_duration_ms == 1250.25)
    let actual = fields.today_actual_cost.map { NSDecimalNumber(decimal: $0).stringValue } ?? "unavailable"
    let account = fields.today_account_cost.map { NSDecimalNumber(decimal: $0).stringValue } ?? "unavailable"
    let tokens = fields.total_tokens.map { String($0) } ?? "unavailable"
    let duration = fields.average_duration_ms.map { String($0) } ?? "unavailable"
    print("OVERVIEW_REGRESSION actual=\(actual) account_cost=\(account) total_tokens=\(tokens) average_duration_ms=\(duration)")
}
