import Foundation
import Testing
@testable import Sub2Core

private func amount(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func amounts(_ raws: [String]) -> [Decimal] { raws.map(amount) }
private func column(_ raws: [String?]) -> [Decimal?] { raws.map { $0.map(amount) } }
private func isCents(_ value: Decimal?) -> Bool { value.map { $0 == DisplayFormat.rounded($0, digits: 2) } ?? false }

@Test func profitRowsSplitTotalsToCentsByLargestRemainder() {
    let rows = ProfitRows(actual: amounts(["1.234", "2.345", "3.456"]), accountCost: column(["1.006", "2.004", "2.09"]),
                          totalActual: amount("7.04"), totalAccountCost: amount("5.10"))
    #expect(rows.rows.map(\.actual) == column(["1.23", "2.35", "3.46"]))
    #expect(rows.rows.map(\.accountCost) == column(["1.01", "2.00", "2.09"]))
    #expect(rows.rows.map(\.profit) == column(["0.22", "0.35", "1.37"]))
    #expect(rows.totalActual == amount("7.04") && rows.totalAccountCost == amount("5.1") && rows.totalProfit == amount("1.94"))
    #expect(rows.isReconciled)
}

@Test func profitRowsAllocateBreaksTiesByTheEarlierBucket() {
    #expect(ProfitRows.allocate(totalCents: 3, weights: [1, 1, 1, 1]) == [1, 1, 1, 0])
    #expect(ProfitRows.allocate(totalCents: 100, weights: [1, 1, 1]) == [34, 33, 33])
    #expect(ProfitRows.allocate(totalCents: 0, weights: [0, 0]) == [0, 0])
    #expect(ProfitRows.allocate(totalCents: 5, weights: [0, 0]) == nil)
    #expect(ProfitRows.allocate(totalCents: 5, weights: [1, -1, 2]) == nil)
    #expect(ProfitRows.allocate(totalCents: -5, weights: [1, 2]) == nil)
    #expect(ProfitRows.allocate(totalCents: 7, weights: []) == nil)
    #expect(ProfitRows.allocate(totalCents: 0, weights: []) == [])
}

@Test func profitRowsKeepEveryColumnEqualToItsTotal() {
    let actual = (0..<30).map { amount("0.1237") * Decimal($0) + amount("0.0049") }
    let cost = (0..<30).map { amount("0.0611") * Decimal($0 % 7) + amount("0.003") }
    // Raw sums 53.9565 and 5.2835; the stats totals differ a little from the trend, as a newer read would.
    let rows = ProfitRows(actual: actual, accountCost: cost.map(Optional.some), totalActual: amount("53.9699"),
                          totalAccountCost: amount("5.2763"))
    #expect(rows.totalActual == amount("53.97") && rows.totalAccountCost == amount("5.28") && rows.totalProfit == amount("48.69"))
    #expect(rows.rows.compactMap(\.actual).reduce(0, +) == amount("53.97"))
    #expect(rows.rows.compactMap(\.accountCost).reduce(0, +) == amount("5.28"))
    #expect(rows.rows.compactMap(\.profit).reduce(0, +) == amount("48.69"))
    #expect(rows.rows.count == 30 && rows.isReconciled)
    #expect(rows.rows.allSatisfy { isCents($0.actual) && isCents($0.accountCost) && isCents($0.profit) })
    let half = ProfitRows(actual: amounts(["4.115", "8.23"]), accountCost: column(["1", "2"]), totalActual: amount("12.345"),
                          totalAccountCost: amount("3.004"))
    // 12.345 − 3.004 = 9.341 shows as $9.34, so the cost column takes 12.35 − 9.34 = 3.01 rather than its own rounded 3.00.
    #expect(half.totalActual == amount("12.35") && half.totalAccountCost == amount("3.01") && half.totalProfit == amount("9.34"))
    #expect(half.rows.map(\.actual) == column(["4.12", "8.23"]) && half.rows.map(\.accountCost) == column(["1", "2.01"]))
}

@Test func profitRowsKeepLossesAndLeaveMissingCostsBlank() {
    let loss = ProfitRows(actual: amounts(["1", "2"]), accountCost: column(["3", "0.5"]), totalActual: amount("3"), totalAccountCost: amount("3.5"))
    #expect(loss.rows.map(\.profit) == column(["-2", "1.5"]) && loss.totalProfit == amount("-0.5") && loss.isReconciled)

    let degraded = ProfitRows(actual: amounts(["1.004", "2.006"]), accountCost: column(["0.504", nil]), totalActual: amount("3.01"),
                              totalAccountCost: amount("0.5"))
    #expect(degraded.rows.map(\.actual) == column(["1.00", "2.01"]))
    #expect(degraded.rows.map(\.accountCost) == column(["0.50", nil]) && degraded.rows.map(\.profit) == column(["0.50", nil]))
    #expect(degraded.totalAccountCost == amount("0.5") && degraded.totalProfit == amount("2.51") && !degraded.isReconciled)

    let oldServer = ProfitRows(actual: amounts(["1.006", "2"]), accountCost: [nil, nil], totalActual: amount("3.01"), totalAccountCost: nil)
    #expect(oldServer.rows.map(\.actual) == column(["1.01", "2.00"]))
    #expect(oldServer.rows.map(\.accountCost) == [nil, nil] && oldServer.rows.map(\.profit) == [nil, nil])
    #expect(oldServer.totalAccountCost == nil && oldServer.totalProfit == nil && !oldServer.isReconciled)

    let unreadTotal = ProfitRows(actual: amounts(["1.006"]), accountCost: column(["0.5"]), totalActual: nil, totalAccountCost: amount("0.5"))
    #expect(unreadTotal.rows.map(\.actual) == column(["1.01"]) && unreadTotal.totalActual == nil && unreadTotal.totalProfit == nil)
    #expect(!unreadTotal.isReconciled)

    let silent = ProfitRows(actual: [0, 0], accountCost: [0, 0], totalActual: amount("1"), totalAccountCost: 0)
    #expect(silent.rows.map(\.actual) == column(["0", "0"]) && !silent.isReconciled)
    let empty = ProfitRows(actual: [0, 0], accountCost: [0, 0], totalActual: 0, totalAccountCost: 0)
    #expect(empty.isReconciled && empty.totalProfit == 0 && empty.rows.map(\.profit) == column(["0", "0"]))
}

@Test func profitRowsTotalProfitIsTheOverviewsRoundedDifference() {
    // 128.454 − 40.236 = 88.218: the overview and the profit card show $88.22, where 128.45 − 40.24 would give $88.21.
    let rows = ProfitRows(actual: amounts(["100.2", "28.254"]), accountCost: column(["20.118", "20.118"]),
                          totalActual: amount("128.454"), totalAccountCost: amount("40.236"))
    let overview = HomePresentation.profit(actual: amount("128.454"), account: amount("40.236"))
    #expect(rows.totalProfit == amount("88.22") && DisplayFormat.money(rows.totalProfit) == DisplayFormat.money(overview))
    #expect(rows.totalActual == amount("128.45") && rows.totalAccountCost == amount("40.23") && rows.isReconciled)
    #expect(rows.rows.map(\.actual) == column(["100.2", "28.25"]) && rows.rows.map(\.accountCost) == column(["20.12", "20.11"]))
    #expect(rows.rows.map(\.profit) == column(["80.08", "8.14"]))
    #expect(rows.rows.compactMap(\.profit).reduce(0, +) == amount("88.22"))
}
