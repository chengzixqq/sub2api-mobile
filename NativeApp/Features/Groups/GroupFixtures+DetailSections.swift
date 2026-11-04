import Foundation
import Sub2Core

/// 50 §2 `-ui-testing` (S5-07, X44): the group detail's 贰 on the fixture site. Capacity is counted like the backend from the
/// session's demo accounts, so member writes and account actions change it; usage-summary is the list's (S5-04) and
/// `-ui-group-usage-failure` fails dashboard/groups with it. The banner and the two 24-hour counts are not replaced: they come
/// through LiveOpsStore from LiveOpsFixtures (#41 on 标准组, 37 / 9 errors), so a resolve in the alert detail ends the banner.
/// `-ui-group-detail-blocks-failure-after-first` fails every read of 贰 and the banner after its first (S5-高-3); the U-11 review's
/// two arguments make the later reads hang or answer 429.
extension GroupFixtures {
    /// DEMO.groups[].todayStats (requests, tokens, account cost); a group not listed had no request today.
    static let todayUsage: [Int: GroupTodayUsage] = [
        1: today(10_194, 62_940_000, "370.27"), 2: today(5_500, 20_700_000, "82.4"), 3: today(980, 4_600_000, "14.1"),
        5: today(576, 3_560_000, "20.93"), 6: today(152, 900_000, "4.8"), 7: today(290, 1_400_000, "8.38"), 8: today(512, 2_300_000, "11.2")
    ]

    /// The backend's getGroupCapacity: the members that can be scheduled now, Σ concurrency, Σ max_sessions and Σ base_rpm of
    /// those above 0, with their current use. A stopped group has no row; an unknown one is 404 GROUP_NOT_FOUND.
    static func capacity(groupID: Int, groups: [AdminGroup], accounts: [UpstreamAccount], now: Date) throws -> [GroupCapacitySummary] {
        guard let group = groups.first(where: { $0.id == groupID }) else { throw APIError.server(status: 404, reason: "GROUP_NOT_FOUND") }
        guard group.status == "active" else { return [] }
        let members = accounts.filter { $0.groupIDs.contains(groupID) && AccountDisplayState($0, now: now).state == .available }
        let sessions = members.filter { ($0.maxSessions ?? 0) > 0 }, rpm = members.filter { ($0.baseRPM ?? 0) > 0 }
        return [GroupCapacitySummary(groupID: groupID, concurrencyUsed: sum(members, \.currentConcurrency), concurrencyMax: sum(members, \.concurrency),
                                     sessionsUsed: sum(sessions, \.activeSessions), sessionsMax: sum(sessions, \.maxSessions),
                                     rpmUsed: sum(rpm, \.currentRPM), rpmMax: sum(rpm, \.baseRPM))]
    }

    static func detailSectionsSource(_ app: AppModel, arguments: [String] = ProcessInfo.processInfo.arguments) -> GroupDetailSectionsSource {
        let live = GroupDetailSectionsSource.live(app)
        let reads = DetailReads(arguments: arguments)
        return GroupDetailSectionsSource(
            capacity: { [weak app] id in
                try await reads.check(.capacity)
                guard let context = app?.groupStore?.fixtureContext else { throw CancellationError() }
                return try Self.capacity(groupID: id, groups: context.fixtures.groups, accounts: context.accounts, now: context.now).first
            },
            usageSummary: { [weak app] in
                try await reads.check(.usage)
                guard let fixtures = app?.groupStore?.fixtures else { throw CancellationError() }
                return try await fixtures.usageSummary()
            },
            todayUsage: { id in
                try await reads.check(.todayUsage)
                if arguments.contains(Argument.usageFailure) { throw APIError.server(status: 502, reason: nil) }
                return Self.todayUsage[id] ?? .zero
            },
            firingAlert: { id in
                try await reads.check(.alert)
                return try await live.firingAlert(id)
            },
            errorCount: live.errorCount)
    }

    private static func today(_ requests: Int, _ tokens: Int, _ cost: String) -> GroupTodayUsage {
        GroupTodayUsage(requests: requests, totalTokens: tokens, accountCost: Decimal(string: cost))
    }
    private static func sum(_ accounts: [UpstreamAccount], _ value: KeyPath<UpstreamAccount, Int?>) -> Int {
        accounts.reduce(0) { $0 + ($1[keyPath: value] ?? 0) }
    }
}

extension GroupFixtures.Argument {
    /// On the group detail, the first read of capacity, usage-summary, dashboard/groups and the banner works; later ones answer
    /// 502. Counted per page; entering takes the list's usage-summary, so the detail's own fails from its second read.
    static let detailBlocksFailureAfterFirst = "-ui-group-detail-blocks-failure-after-first"
    /// The second read of capacity, dashboard/groups and the banner answers 502 and later ones hang (a retry that is slow to
    /// answer); usage-summary always works.
    static let detailBlocksFailureThenSlow = "-ui-group-detail-blocks-failure-then-slow"
    /// The second read of dashboard/groups and the banner answers 429 (retry_after `DetailReads.throttledWait`); every other read works.
    static let detailBlocksThrottledAfterFirst = "-ui-group-detail-blocks-throttled-after-first"
}

/// One detail page's reads per block under the `-ui-group-detail-blocks-…` arguments.
@MainActor private final class DetailReads {
    private enum Later { case works, fail, failThenHang, throttle }
    /// Long enough for a test to look at the 429 countdown, short enough to see the resend after it.
    static let throttledWait = 20
    private static let hang: Duration = .seconds(300)
    private let later: Later
    private var counts: [GroupDetailBlock: Int] = [:]

    init(arguments: [String]) { later = Self.later(arguments) }

    private static func later(_ arguments: [String]) -> Later {
        if arguments.contains(GroupFixtures.Argument.detailBlocksFailureAfterFirst) { return .fail }
        if arguments.contains(GroupFixtures.Argument.detailBlocksFailureThenSlow) { return .failThenHang }
        if arguments.contains(GroupFixtures.Argument.detailBlocksThrottledAfterFirst) { return .throttle }
        return .works
    }

    /// Counts a read of `block` and answers the later ones as the argument says.
    func check(_ block: GroupDetailBlock) async throws {
        guard later != .works else { return }
        counts[block, default: 0] += 1
        let read = counts[block, default: 0]
        guard read > 1 else { return }
        switch later {
        case .works: return
        case .fail: throw APIError.server(status: 502, reason: nil)
        case .failThenHang:
            guard block != .usage else { return }
            if read > 2 { try await Task.sleep(for: Self.hang) }
            throw APIError.server(status: 502, reason: nil)
        case .throttle:
            guard read == 2, block == .todayUsage || block == .alert else { return }
            throw APIError.server(status: 429, envelope: nil, retryAfter: Self.throttledWait)
        }
    }
}
