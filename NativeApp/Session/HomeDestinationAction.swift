import Foundation
import Sub2Core

/// 10 §1.1's go table, the one map from where an overview row or cell leads (Sub2Core's HomeDestination) to the App's routes:
/// push onto the current tab, switch tabs with an intent, present a sheet, or read home again past the server cache. The six
/// cells (S1-09), the 待处理 rows (S1-10) and the calm layout (S1-11) all open through it.
enum HomeDestinationAction: Equatable, Sendable {
    case push(AppRoute)
    case select(TabIntent)
    case present(AppSheet)
    case refreshHome

    init(_ destination: HomeDestination) {
        self = switch destination {
        case .analytics: .push(.analytics())
        case .performanceTrend(let metric): .push(.analytics(focus: .perf, metric: PerfMetric(rawValue: metric.rawValue) ?? .rpm))
        case .alert(let id): .push(.alert(id: id))
        case .alertsSegment: .select(.monitor(segment: .alerts))
        case .account(let id): .push(.account(id: id))
        case .accountTest(let id): .present(.accountTest(id: id))
        case .limitedAccounts: .select(.accounts(filter: .limited))
        case .group(let id): .push(.group(id: id))
        case .groupsAttention: .push(.groups(segment: .attention))
        case .user(let id): .push(.user(id: id))
        case .redeemReconcile: .push(.redeem(reconcile: true))
        // R02: the record may belong to an earlier login of this address; the sheet checks it with the current identity.
        case .compensation(let userID, let pendingID): .present(.redeemGrant(userID: userID, pendingID: pendingID))
        case .retryAvailability, .retryAlerts: .refreshHome
        }
    }

    /// 10 §1.4: the 「测试」 sheet opened for `accountID` went away, whether closed or replaced (a tab switch closes it too).
    static func accountTestClosed(from old: AppSheet?, to new: AppSheet?, awaiting accountID: Int?) -> Bool {
        guard let accountID, old == .accountTest(id: accountID) else { return false }
        return new != old
    }
}

extension AppRouter {
    /// `refreshHome` is the page's read past the server cache.
    func open(_ action: HomeDestinationAction, refreshHome: () -> Void) {
        switch action {
        case .push(let route): push(route)
        case .select(let intent): select(intent)
        case .present(let sheet): present(sheet)
        case .refreshHome: refreshHome()
        }
    }
}
