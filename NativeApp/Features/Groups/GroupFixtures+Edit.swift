import Foundation
import Sub2Core

/// 50 §3 `-ui-testing` (S5-10, X44): the group sheet's fixture server is strict about what a PUT carries, so a sheet that sends a
/// field it did not change is caught. New groups and the first lost write come from GroupFixtures and GroupFixtures+Actions.
extension GroupFixtures {
    /// Every field the request carries differs from the group; platform and billing type are never sent (50 §3.4 编辑 1).
    static func sendsOnlyChanges(_ request: GroupUpdateRequest, current: AdminGroup) -> Bool {
        guard request.subscriptionType == nil else { return false }
        let unchanged: [Bool?] = [
            request.name.map { $0 == current.name },
            request.description.map { $0 == (current.description ?? "") },
            request.rateMultiplier.map { $0 == current.rateMultiplier },
            request.isExclusive.map { $0 == (current.isExclusive ?? false) },
            request.status.map { $0 == current.status },
            request.rpmLimit.map { $0 == (current.rpmLimit ?? 0) },
            request.dailyLimitUSD.map { same($0, current.dailyLimitUSD) },
            request.weeklyLimitUSD.map { same($0, current.weeklyLimitUSD) },
            request.monthlyLimitUSD.map { same($0, current.monthlyLimitUSD) }
        ]
        return !unchanged.contains(true)
    }

    private static func same(_ change: GroupLimitChange, _ value: Decimal?) -> Bool {
        switch change {
        case .unlimited: value == nil
        case .amount(let amount): value == amount
        }
    }
}
