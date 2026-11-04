import Foundation
import Testing
@testable import Sub2Core

// S1-09: the overview's whole-page state, the subtitle's refresh status and the six cells' rows (10 §0.1, §1.3.1, §1.3.2, §1.5).

private let at = Date(timeIntervalSince1970: 1_800_000_000)
private let fresh = HomeBlockPhase.value(updateFailed: false)
private let stale = HomeBlockPhase.value(updateFailed: true)
private func seven(_ phase: HomeBlockPhase) -> [HomeBlockPhase] { Array(repeating: phase, count: 7) }

@Test func vendorWinsOverEveryOtherState() {
    for sections in [seven(fresh), seven(.placeholder), seven(.failed), []] {
        #expect(HomeScreenState.resolve(isVendor: true, sections: sections, requestFailed: false) == .vendorPlaceholder)
        #expect(HomeScreenState.resolve(isVendor: true, sections: sections, requestFailed: true) == .vendorPlaceholder)
    }
}

@Test func placeholderSectionsShowSkeleton() {
    #expect(HomeScreenState.resolve(isVendor: false, sections: seven(.placeholder), requestFailed: false) == .skeleton)
    #expect(HomeScreenState.resolve(isVendor: false, sections: [], requestFailed: false) == .skeleton)
    // The fallback lands block by block: a failed block waits for the others still on their way.
    #expect(HomeScreenState.resolve(isVendor: false, sections: [.failed, .placeholder, .disabled], requestFailed: false) == .skeleton)
}

@Test func allFailedWithoutValuesShowsUnreachable() {
    #expect(HomeScreenState.resolve(isVendor: false, sections: seven(.failed), requestFailed: false) == .unreachable)
    #expect(HomeScreenState.resolve(isVendor: false, sections: [.failed, .disabled, .failed], requestFailed: false) == .unreachable)
    // Home itself failed (a 5xx) before any block had a value: the blocks are still idle.
    #expect(HomeScreenState.resolve(isVendor: false, sections: seven(.placeholder), requestFailed: true) == .unreachable)
}

@Test func anyValueShowsContentEvenWhenOthersFailed() {
    #expect(HomeScreenState.resolve(isVendor: false, sections: [stale] + seven(.failed), requestFailed: true) == .content)
    #expect(HomeScreenState.resolve(isVendor: false, sections: [fresh, .placeholder], requestFailed: false) == .content)
    #expect(HomeScreenState.resolve(isVendor: false, sections: seven(.disabled), requestFailed: false) == .content)
}

@Test func refreshStatusMatchesSubtitleRules() {
    #expect(HomeScreenState.refreshStatus(sections: seven(.placeholder), lastFullSuccessAt: nil, requestFailed: false) == .loading)
    #expect(HomeScreenState.refreshStatus(sections: [fresh, .failed], lastFullSuccessAt: at, requestFailed: false) == .partial)
    #expect(HomeScreenState.refreshStatus(sections: [fresh, stale], lastFullSuccessAt: at, requestFailed: false) == .partial)
    // 10 §1.5: a whole-home failure keeps the earlier values and says 部分数据未更新.
    #expect(HomeScreenState.refreshStatus(sections: seven(fresh), lastFullSuccessAt: at, requestFailed: true) == .partial)
    #expect(HomeScreenState.refreshStatus(sections: seven(fresh) + [.disabled], lastFullSuccessAt: at, requestFailed: false) == .updated(at: at))
    #expect(HomeScreenState.refreshStatus(sections: seven(fresh), lastFullSuccessAt: nil, requestFailed: false) == .loading)
}

@Test func blockDisplayMapsToHomePhase() {
    #expect(BlockState<Int>.idle.display.homePhase == .placeholder)
    #expect(BlockState<Int>.loading(previous: nil, at: nil).display.homePhase == .placeholder)
    #expect(BlockState.loading(previous: 1, at: at).display.homePhase == fresh)
    #expect(BlockState.loaded(1, at: at).display.homePhase == fresh)
    #expect(BlockState.failed(reason: HomeBlockText.failed, previous: 1, at: at).display.homePhase == stale)
    #expect(BlockState<Int>.failed(reason: HomeBlockText.timedOut, previous: nil, at: nil).display.homePhase == .failed)
    #expect(BlockState<Int>.disabled(reason: "OPS_DISABLED").display.homePhase == .disabled)
}

@Test func homeBlocksListEverySectionPhase() {
    var blocks = HomeBlocks()
    #expect(blocks.phases == seven(.placeholder))
    blocks.stats = .loaded(HomeStats(todayRequests: 1), at: at)
    blocks.ops = .disabled(reason: "OPS_DISABLED")
    blocks.channels = .failed(reason: HomeBlockText.failed, previous: nil, at: nil)
    #expect(blocks.phases == [fresh, .placeholder, .placeholder, .disabled, .placeholder, .placeholder, .failed])
}

@Test func tickerLayoutKeepsOrderInThreeOrTwoColumns() {
    #expect(HomeTickerLayout.columnCount(isAccessibilitySize: false) == 3)
    #expect(HomeTickerLayout.columnCount(isAccessibilitySize: true) == 2)
    #expect(HomeTickerLayout.rows([0, 1, 2, 3, 4, 5], columns: 3) == [[0, 1, 2], [3, 4, 5]])
    #expect(HomeTickerLayout.rows([0, 1, 2, 3, 4, 5], columns: 2) == [[0, 1], [2, 3], [4, 5]])
    #expect(HomeTickerLayout.rows([0, 1, 2, 3, 4], columns: 3) == [[0, 1, 2], [3, 4]])
    #expect(HomeTickerLayout.rows([Int](), columns: 3) == [])
    #expect(HomeTickerLayout.rows([0, 1], columns: 0) == [[0], [1]])
}

@Test func tickerCellsStaySkeletonUntilTheirOwnBlockLands() {
    // The fallback lands block by block (S1-07): the rates can be in while today's figures are still on their way.
    #expect(HomeTickerLayout.placeholders(stats: .placeholder, rates: fresh) == [.actualCost, .requests, .profit])
    #expect(HomeTickerLayout.placeholders(stats: fresh, rates: .placeholder) == [.errorRate, .rpm, .tpm])
    #expect(HomeTickerLayout.placeholders(stats: .placeholder, rates: .placeholder) == Set(HomeTickerKind.allCases))
    // A value, a failure (“—”) or a switched-off block is no longer loading.
    for phase in [fresh, stale, .failed, .disabled] {
        #expect(HomeTickerLayout.placeholders(stats: phase, rates: phase).isEmpty)
    }
}
