import Foundation
import Testing
@testable import Sub2Core

// S1-08: what a block shows beside its title and in its failure row (10 §0.5, §1.5; 00 §2.7.2).

private let t = Date(timeIntervalSince1970: 1_800_000_000)
private let rateLimited = APIError.server(status: 429, envelope: ErrorEnvelope(reason: "RATE_LIMITED"), retryAfter: 30)
private let compliance = APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED")

@Test func accessoryShowsRefreshingOnlyWithPreviousValue() {
    #expect(BlockStatusPresentation.accessory(for: BlockState.loading(previous: 5, at: t), refresh: BlockRefresh(), at: t) == .refreshing)
    #expect(BlockStatusPresentation.accessory(for: BlockState<Int>.loading(previous: nil, at: nil), refresh: BlockRefresh(), at: t) == .none)
}

@Test func accessoryShowsUpdateFailedWhenRefreshFailsWithValue() {
    #expect(BlockStatusPresentation.accessory(for: BlockState.failed(reason: "站点暂时不可用", previous: 5, at: t), refresh: BlockRefresh(), at: t)
        == .updateFailed)
    #expect(BlockStatusPresentation.accessory(for: BlockState<Int>.failed(reason: "站点暂时不可用", previous: nil, at: nil), refresh: BlockRefresh(), at: t)
        == .none)
}

@Test func accessoryShowsTimedOutForTimeoutReason() {
    let timedOut = BlockState.failed(reason: BlockStatusPresentation.timedOut, previous: 5, at: t)
    #expect(BlockStatusPresentation.timedOut == HomeBlockText.timedOut && BlockStatusPresentation.loadFailed == HomeBlockText.failed)
    #expect(BlockStatusPresentation.accessory(for: timedOut, refresh: BlockRefresh(), at: t) == .timedOut)
    #expect(BlockStatusPresentation.failureTitle(for: BlockState<Int>.failed(reason: HomeBlockText.timedOut, previous: nil, at: nil)) == "加载超时")
    #expect(BlockStatusPresentation.failureTitle(for: BlockState<Int>.failed(reason: "站点暂时不可用", previous: nil, at: nil)) == "加载失败")
    #expect(BlockStatusPresentation.failureTitle(for: BlockState<Int>.idle) == "加载失败")
}

@Test func accessoryCountsDownDuring429WaitThenFallsBack() {
    let refresh = BlockRefresh().recordingFailure(rateLimited, at: t)
    let state = BlockState.failed(reason: rateLimited.localizedDescription, previous: 5, at: t)
    #expect(BlockStatusPresentation.accessory(for: state, refresh: refresh, at: t) == .throttled("请求过于频繁，30 秒后自动重试"))
    #expect(BlockStatusPresentation.accessory(for: state, refresh: refresh, at: t.addingTimeInterval(12.3)) == .throttled("请求过于频繁，18 秒后自动重试"))
    #expect(BlockStatusPresentation.accessory(for: state, refresh: refresh, at: t.addingTimeInterval(30)) == .updateFailed)
    // The whole home request waits while its blocks keep their last value.
    #expect(BlockStatusPresentation.accessory(for: BlockState.loaded(5, at: t), refresh: refresh, at: t) == .throttled("请求过于频繁，30 秒后自动重试"))
}

@Test func accessoryIsNoneWithoutValueOrWhenLoadedOrDisabled() {
    #expect(BlockStatusPresentation.accessory(for: BlockState<Int>.idle, refresh: BlockRefresh(), at: t) == .none)
    #expect(BlockStatusPresentation.accessory(for: BlockState.loaded(5, at: t), refresh: BlockRefresh(), at: t) == .none)
    #expect(BlockStatusPresentation.accessory(for: BlockState<Int>.disabled(reason: "OPS_DISABLED"), refresh: BlockRefresh(), at: t) == .none)
}

@Test func failureRowRetryOutsideWaitAndWaitingDuring429() {
    let failure = APIError.server(status: 500, reason: "INTERNAL_ERROR")
    #expect(BlockStatusPresentation.failureRow(title: "每小时数据加载失败", error: failure, refresh: BlockRefresh(), at: t)
        == .init(text: "每小时数据加载失败", action: .retry))
    let waiting = BlockRefresh().recordingFailure(rateLimited, at: t)
    #expect(BlockStatusPresentation.failureRow(title: "加载失败", error: rateLimited, refresh: waiting, at: t.addingTimeInterval(5))
        == .init(text: "请求过于频繁，25 秒后自动重试", action: .waiting))
    #expect(BlockStatusPresentation.failureRow(title: "加载失败", error: rateLimited, refresh: waiting, at: t.addingTimeInterval(30))
        == .init(text: "加载失败", action: .retry))
}

@Test func failureRowOffersComplianceFor423UntilPassed() {
    #expect(BlockStatusPresentation.needsCompliance(compliance))
    #expect(BlockStatusPresentation.failureRow(title: "加载失败", error: compliance, refresh: BlockRefresh(), at: t)
        == .init(text: "需要先完成管理员合规确认", action: .completeCompliance))
    let passed = compliance.withSecurityOutcome(.passed)
    #expect(!BlockStatusPresentation.needsCompliance(passed))
    #expect(BlockStatusPresentation.failureRow(title: "加载失败", error: passed, refresh: BlockRefresh(), at: t).action == .retry)
    #expect(!BlockStatusPresentation.needsCompliance(APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")))
    #expect(!BlockStatusPresentation.needsCompliance(APIError.server(status: 500, reason: nil)))
    #expect(!BlockStatusPresentation.needsCompliance(nil))
}
