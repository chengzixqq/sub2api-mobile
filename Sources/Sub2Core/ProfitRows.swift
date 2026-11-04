import Foundation

/// One bucket of 利润明细, in whole cents. nil where the account cost of a degraded segment could not be read.
public struct ProfitRow: Equatable, Sendable {
    public let actual: Decimal?
    public let accountCost: Decimal?
    public let profit: Decimal?
}

/// 40 §1.4 分段取整: actual takes its `usage/stats` total rounded to cents and profit the totals' difference rounded to cents, the
/// way the overview and the profit card show it (40 §0.2: today's profit equals the overview's); account cost takes what lies between
/// them, which can be a cent off its own rounded total (round(A) − round(C) ≠ round(A − C) about one time in four). Each column is
/// split over the buckets by their raw values with the largest remainder method, so every column adds up to its total and every row's
/// profit is its actual minus its cost. A column whose total or any row is missing is rounded row by row instead (`isReconciled` false).
public struct ProfitRows: Equatable, Sendable {
    public let rows: [ProfitRow]
    public let totalActual: Decimal?
    public let totalAccountCost: Decimal?
    public let totalProfit: Decimal?
    /// Each column adds up to its total.
    public let isReconciled: Bool

    /// `actual` and `accountCost` are the trend's buckets in order (`accountCost[i]` nil for a failed segment); the totals come from
    /// `usage/stats` over the same range.
    public init(actual: [Decimal], accountCost: [Decimal?], totalActual: Decimal?, totalAccountCost: Decimal?) {
        let costs = actual.indices.map { accountCost.indices.contains($0) ? accountCost[$0] : nil }
        let actualTotal = totalActual.map { DisplayFormat.rounded($0, digits: 2) }
        let profitTotal = totalActual.flatMap { actual in totalAccountCost.map { DisplayFormat.rounded(actual - $0, digits: 2) } }
        let costTotal = actualTotal.flatMap { actual in profitTotal.map { actual - $0 } }
            ?? totalAccountCost.map { DisplayFormat.rounded($0, digits: 2) }
        let actualColumn = Self.column(actual.map(Optional.some), total: actualTotal)
        let costColumn = Self.column(costs, total: costTotal)
        rows = zip(actualColumn.values, costColumn.values).map { actual, cost in
            ProfitRow(actual: actual, accountCost: cost, profit: actual.flatMap { value in cost.map { value - $0 } })
        }
        self.totalActual = actualTotal
        self.totalAccountCost = costTotal
        totalProfit = profitTotal
        isReconciled = actualColumn.isReconciled && costColumn.isReconciled
    }

    /// Largest remainder (Hamilton): each weight's share of `totalCents` rounded down, the cents left over going to the largest
    /// remainders, ties to the earlier bucket. nil when it cannot be split: a negative total or weight, or a total over all-zero weights.
    static func allocate(totalCents: Decimal, weights: [Decimal]) -> [Decimal]? {
        let total = DisplayFormat.rounded(totalCents, digits: 0)
        guard total >= 0, weights.allSatisfy({ $0 >= 0 }) else { return nil }
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return total == 0 ? [Decimal](repeating: 0, count: weights.count) : nil }
        let shares = weights.map { total * $0 / sum }
        var cents = shares.map { decimalRound($0, digits: 0, .down) }
        // Remainders are compared at ten digits so that equal shares tie however Decimal division ends them.
        let remainders = zip(shares, cents).map { decimalRound($0 - $1, digits: 10, .plain) }
        let leftover = NSDecimalNumber(decimal: total - cents.reduce(0, +)).intValue
        let order = remainders.indices.sorted { remainders[$0] != remainders[$1] ? remainders[$0] > remainders[$1] : $0 < $1 }
        for index in order.prefix(max(0, leftover)) { cents[index] += 1 }
        return cents
    }

    private static func column(_ values: [Decimal?], total: Decimal?) -> (values: [Decimal?], isReconciled: Bool) {
        let present = values.compactMap { $0 }
        if let total, present.count == values.count, let cents = allocate(totalCents: total * 100, weights: present) {
            return (cents.map { Optional($0 / 100) }, true)
        }
        return (values.map { $0.map { DisplayFormat.rounded($0, digits: 2) } }, false)
    }

    private static func decimalRound(_ value: Decimal, digits: Int, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var source = value, result = Decimal()
        NSDecimalRound(&result, &source, digits, mode)
        return result
    }
}
