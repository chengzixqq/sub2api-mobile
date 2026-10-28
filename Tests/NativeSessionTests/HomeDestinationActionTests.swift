import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-10: 10 §1.1's go table for the overview's rows and cells, and the 「测试」 sheet's close.

private let grant = UUID(uuidString: "0A000000-0000-4000-8000-0000000000C1")!
private let goTable: [(HomeDestination, HomeDestinationAction)] = [
    (.analytics, .push(.analytics())),
    (.performanceTrend(.rpm), .push(.analytics(focus: .perf, metric: .rpm))),
    (.performanceTrend(.tpm), .push(.analytics(focus: .perf, metric: .tpm))),
    (.alert(id: 7), .push(.alert(id: 7))),
    (.alertsSegment, .select(.monitor(segment: .alerts))),
    (.account(id: 3), .push(.account(id: 3))),
    (.accountTest(id: 3), .present(.accountTest(id: 3))),
    (.limitedAccounts, .select(.accounts(filter: .limited))),
    (.group(id: 9), .push(.group(id: 9))),
    (.groupsAttention, .push(.groups(segment: .attention))),
    (.user(id: 5), .push(.user(id: 5))),
    (.redeemReconcile, .push(.redeem(reconcile: true))),
    (.compensation(userID: 5, pendingID: grant), .present(.redeemGrant(userID: 5, pendingID: grant))),
    (.retryAvailability, .refreshHome),
    (.retryAlerts, .refreshHome)
]

@Test(arguments: goTable.indices)
func homeDestinationsFollowTheOverviewGoTable(index: Int) {
    let (destination, action) = goTable[index]
    #expect(HomeDestinationAction(destination) == action)
}

@Test func goTableCoversEveryDestination() {
    // The 14 cases, performanceTrend once per metric.
    #expect(Set(goTable.map(\.0)).count == goTable.count && goTable.count == 15)
}

@MainActor @Test func openingAnActionOnlyChangesTheRouterOrRefreshes() {
    var refreshes = 0
    let router = AppRouter(selectedTab: .today)
    router.open(.push(.alert(id: 1))) { refreshes += 1 }
    #expect(router.path(for: .today) == [.alert(id: 1)] && refreshes == 0)

    router.open(.select(.monitor(segment: .alerts))) { refreshes += 1 }
    #expect(router.selectedTab == .monitor && router.pendingIntent == .monitor(segment: .alerts))
    #expect(router.path(for: .monitor).isEmpty && router.path(for: .today) == [.alert(id: 1)] && refreshes == 0)

    router.open(.present(.accountTest(id: 3))) { refreshes += 1 }
    #expect(router.presentedSheet == .accountTest(id: 3) && refreshes == 0)

    let before = (router.selectedTab, router.presentedSheet, router.path(for: .today), router.pendingIntent)
    router.open(.refreshHome) { refreshes += 1 }
    #expect(refreshes == 1)
    #expect(router.selectedTab == before.0 && router.presentedSheet == before.1 && router.path(for: .today) == before.2)
    #expect(router.pendingIntent == before.3)
}

@Test func accountTestSheetCloseIsDetectedOnce() {
    func closed(_ old: AppSheet?, _ new: AppSheet?, _ awaiting: Int?) -> Bool {
        HomeDestinationAction.accountTestClosed(from: old, to: new, awaiting: awaiting)
    }
    #expect(closed(.accountTest(id: 3), nil, 3))
    #expect(closed(.accountTest(id: 3), .addSite, 3))
    #expect(!closed(.accountTest(id: 3), .accountTest(id: 3), 3))
    #expect(!closed(nil, .accountTest(id: 3), 3))
    #expect(!closed(.accountTest(id: 4), nil, 3))
    #expect(!closed(.redeemGrant(userID: 1, pendingID: nil), nil, 3))
    #expect(!closed(.accountTest(id: 3), nil, nil))
}

/// S1-09's six cells go through the same table: 实际扣费 and the like to 统计分析, RPM / TPM to its performance trend.
@MainActor @Test func tickerDestinationsOpenAnalyticsRoutes() {
    let cells = HomePresentation.tickerCells(stats: nil, rates: nil, ratesSource: .home)
    let router = AppRouter(selectedTab: .today)
    for cell in cells { router.open(HomeDestinationAction(cell.destination)) {} }
    let expected: [AppRoute] = cells.map { cell in
        switch cell.kind {
        case .rpm: .analytics(focus: .perf, metric: .rpm)
        case .tpm: .analytics(focus: .perf, metric: .tpm)
        default: .analytics()
        }
    }
    #expect(router.path(for: .today) == expected && expected.count == 6)
}
