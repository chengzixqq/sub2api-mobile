import Foundation
import Sub2Core

// The app skeleton's navigation values (10 §0.7, U14). Every route of 10 §0.7-3, 20, 30, 40 §0.1, 50 and 60 §0.1 is
// defined here once; a page that is not rewritten yet maps to an existing page or the “即将推出” placeholder
// (NativeApp/Features/AppDestinations.swift).

/// 10 §0.7-1: “概览 · 账号 · 用户 · 监控” and the separate search tab (60 §1.1).
enum MainTab: String, Hashable, Sendable, CaseIterable {
    case today, accounts, users, monitor, search

    var title: String {
        switch self {
        case .today: "概览"
        case .accounts: "账号"
        case .users: "用户"
        case .monitor: "监控"
        case .search: "搜索"
        }
    }
    /// Design `TAB_DEFS`: home, server, people, pulse.
    var systemImage: String {
        switch self {
        case .today: "house"
        case .accounts: "server.rack"
        case .users: "person.2"
        case .monitor: "waveform.path.ecg"
        case .search: "magnifyingglass"
        }
    }
}

/// 10 §0.7-4: a jump to another tab; its root takes the intent once (`AppRouter.takeIntent(for:)`).
enum TabIntent: Hashable, Sendable {
    case today
    case accounts(filter: AccountsTabFilter? = nil, platform: String? = nil)
    case users
    case monitor(segment: MonitorSegment = .overview)
    case search

    var tab: MainTab {
        switch self {
        case .today: .today
        case .accounts: .accounts
        case .users: .users
        case .monitor: .monitor
        case .search: .search
        }
    }
}

// Route parameters; raw values follow each chapter's route spelling.

/// 10 §4–§6.
enum MonitorSegment: String, Hashable, Sendable, CaseIterable, Identifiable {
    case overview, channels, alerts
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "概况"
        case .channels: "渠道"
        case .alerts: "告警"
        }
    }
}
/// 20 §1.1.
enum AccountsTabFilter: String, Hashable, Sendable, CaseIterable { case needs, limited, paused }
/// 50 §1.3.
enum GroupListSegment: String, Hashable, Sendable, CaseIterable {
    case attention, normal, off
    var title: String {
        switch self {
        case .attention: "需处理"
        case .normal: "正常"
        case .off: "停用"
        }
    }
}
/// 20 §3.1: the section an account detail scrolls to.
enum AccountDetailFocus: String, Hashable, Sendable, CaseIterable { case basic, sched, cred, proxy, models, adv }
/// 30 §6–§8.
enum UserEditSegment: String, Hashable, Sendable, CaseIterable { case basic, access, keys }
/// 60 §3.1.
enum SettingsFocus: String, Hashable, Sendable, CaseIterable { case interface, sites }
/// 40 §0.1 `analytics`: the entry's default range, used only before the site remembers one.
enum AnalyticsEntryRange: String, Hashable, Sendable, CaseIterable { case today, last7 }
enum AnalyticsFocus: String, Hashable, Sendable, CaseIterable { case perf }
enum PerfMetric: String, Hashable, Sendable, CaseIterable { case rpm, tpm }
/// 40 §0.1 chart keys; `switch` is a Swift keyword, hence `accountSwitch`.
enum AnalyticsChartKey: String, Hashable, Sendable, CaseIterable {
    case billing, profit, tokens, userTrend, endpoints, reqType, perf
    case accountSwitch = "switch"
    case latency, errTrend, errDist, tokenSpeed
}
enum AnalyticsTopic: String, Hashable, Sendable, CaseIterable { case billing, usage, ops }
enum AnalyticsRankDimension: String, Hashable, Sendable, CaseIterable { case model, user, group }
/// 40 §0.1 `logs`: 使用记录 / 错误请求 / 上游错误.
enum LogScope: String, Hashable, Sendable, CaseIterable { case usage, errors, upstream }
/// 30 §3.
enum BalanceKeypadMode: String, Hashable, Sendable, CaseIterable { case topup, refund }

/// An object a route filters by: its id and, when known, the name to show before anything loads.
struct RouteObject: Hashable, Sendable {
    let id: Int
    var name: String?
}

/// 40 §0.1 `logs`.
struct LogsRoute: Hashable, Sendable {
    var scope: LogScope = .usage
    var account: RouteObject?
    var group: RouteObject?
    var user: RouteObject?
    var model: String?
    var modelSource: ModelSource = .requested
}

/// A row a route carries for the first screen. Routes compare by the instance, never by the data, so a path stays
/// Hashable whatever the value is.
struct RoutePreload<Value: Sendable>: Hashable, Sendable {
    let value: Value
    private let token = UUID()
    init(_ value: Value) { self.value = value }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.token == rhs.token }
    func hash(into hasher: inout Hasher) { hasher.combine(token) }
}

/// 40 §0.1 `request`.
enum RequestRoute: Hashable, Sendable {
    case usage(RoutePreload<UsageRequestRecord>)
    case usageRequestID(String)
    case error(id: Int, kind: ErrorLogKind, initial: RoutePreload<RequestErrorRecord>? = nil)
}

/// Pushed onto the current tab's stack (10 §0.7-2).
enum AppRoute: Hashable, Sendable {
    // 10
    case alert(id: Int)
    // 20
    case account(id: Int, focus: AccountDetailFocus? = nil)
    case accountScheduledTests(accountID: Int)
    // 30
    case user(id: Int)
    case userLedger(userID: Int)
    case userNew
    case userEdit(id: Int, segment: UserEditSegment = .basic)
    // 40
    case analytics(range: AnalyticsEntryRange = .today, focus: AnalyticsFocus? = nil, metric: PerfMetric? = nil)
    case analyticsMore(chart: AnalyticsChartKey? = nil, topic: AnalyticsTopic? = nil)
    case analyticsChart(AnalyticsChartKey)
    case analyticsRank(AnalyticsRankDimension)
    case analyticsModel(model: String, source: ModelSource = .requested)
    case logs(LogsRoute)
    case request(RequestRoute)
    // 50; the batch result gains its items when stage 5 defines them.
    case groups(segment: GroupListSegment? = nil)
    case group(id: Int)
    case groupBatch(groupID: Int, name: String)
    case groupKeys(groupID: Int)
    case groupSubscriptions(groupID: Int)
    // 60
    case searchResults(kind: SearchResultKind, query: String)
    case settings(focus: SettingsFocus = .interface)
    case sessions
    case accessTokens
    case push
    case pushTarget(id: Int)
    case redeem(open: Int? = nil, query: String? = nil, status: String? = nil, type: String? = nil, reconcile: Bool = false)
    case proxies(filter: String? = nil)
    case proxyDetail(id: Int)
    case proxyFallbackAccounts(proxyID: Int)
    case announcements(segment: String? = nil)
    case announcementDetail(id: Int)
    case announcementReads(announcementID: Int)

    /// The navigation title of the page, used by the placeholder until the page is written.
    var placeholderTitle: String {
        switch self {
        case .alert: "告警详情"
        case .account: "账号详情"
        case .accountScheduledTests: "定时测试"
        case .user: "用户详情"
        case .userLedger: "充值与调整记录"
        case .userNew: "新建用户"
        case .userEdit: "编辑用户"
        case .analytics: "统计分析"
        case .analyticsMore: "更多图表"
        case .analyticsChart: "图表"
        case .analyticsRank: "全部排行"
        case .analyticsModel(let model, _): model
        case .logs: "使用记录"
        case .request: "请求详情"
        case .groups: "分组"
        case .group: "分组详情"
        case .groupBatch: "逐项结果"
        case .groupKeys: "API 密钥"
        case .groupSubscriptions: "订阅"
        case .searchResults(let kind, _): kind.title
        case .settings: "设置"
        case .sessions: "登录设备"
        case .accessTokens: "管理访问令牌"
        case .push: "推送通知"
        case .pushTarget: "接收方式"
        case .redeem: "兑换码"
        case .proxies: "代理"
        case .proxyDetail: "代理详情"
        case .proxyFallbackAccounts: "被改走的账号"
        case .announcements: "公告"
        case .announcementDetail: "公告详情"
        case .announcementReads: "已读情况"
        }
    }
}

/// Sheets presented over the tabs (`AppRouter.present(_:)`).
enum AppSheet: Hashable, Sendable, Identifiable {
    case addSite
    case accountNew
    case accountTest(id: Int)
    case balanceKeypad(userID: Int, mode: BalanceKeypadMode)
    case groupEdit(id: Int?)
    case groupPick(groupID: Int)
    case redeemEdit(id: Int)
    case redeemGenerate
    case redeemReconcile(batchID: UUID)
    case redeemGrant(userID: Int, pendingID: UUID?)
    case proxyEdit(id: Int?)
    case announcementEdit(id: Int?)

    var id: Self { self }
    var placeholderTitle: String {
        switch self {
        case .addSite: "添加站点"
        case .accountNew: "新建账号"
        case .accountTest: "测试连接"
        case .balanceKeypad(_, let mode): mode == .topup ? "充值" : "退款"
        case .groupEdit(let id): id == nil ? "新建分组" : "编辑分组"
        case .groupPick: "添加账号"
        case .redeemEdit: "编辑兑换码"
        case .redeemGenerate: "生成兑换码"
        case .redeemReconcile: "核对结果"
        case .redeemGrant: "发放兑换码（补偿）"
        case .proxyEdit(let id): id == nil ? "添加代理" : "编辑代理"
        case .announcementEdit(let id): id == nil ? "新建公告" : "编辑公告"
        }
    }
}
