import Foundation
import Sub2Core

/// 60 §1: the rows of the search tab's directory. Raw values are the `search.item.*` identifiers.
enum SearchDirectoryItem: String, CaseIterable, Sendable, Identifiable {
    case usage, errors, alerts
    case groups, analytics, redeem, proxies, announcements
    case interface, sites
    case webSettings, webPayments

    var id: Self { self }
    var title: String {
        switch self {
        case .usage: "使用记录"
        case .errors: "错误请求"
        case .alerts: "告警事件"
        case .groups: "分组"
        case .analytics: "统计分析"
        case .redeem: "兑换码"
        case .proxies: "代理"
        case .announcements: "公告"
        case .interface: "界面与模式"
        case .sites: "站点与凭据"
        case .webSettings: "系统设置"
        case .webPayments: "支付与套餐"
        }
    }
    /// Design icons list, octagon, bell, group, chart, gift, shield, megaphone, sliders, key, web.
    var systemImage: String {
        switch self {
        case .usage: "list.bullet"
        case .errors: "exclamationmark.octagon"
        case .alerts: "bell"
        case .groups: "square.stack.3d.up"
        case .analytics: "chart.xyaxis.line"
        case .redeem: "gift"
        case .proxies: "shield"
        case .announcements: "megaphone"
        case .interface: "slider.horizontal.3"
        case .sites: "key"
        case .webSettings, .webPayments: "safari"
        }
    }
}

/// Where a directory row goes (60 §1.1, §1.4).
enum SearchDirectoryDestination: Equatable, Sendable {
    case push(AppRoute)
    case select(TabIntent)
    /// Handed to Safari, which keeps the Web sign-in.
    case openURL(URL)
}

struct SearchDirectorySection: Equatable, Sendable, Identifiable {
    let title: String
    /// 壹, 贰…, counted over the sections still shown.
    let ordinal: String
    let items: [SearchDirectoryItem]
    var id: String { title }
}

enum SearchDirectory {
    private static let groups: [(title: String, items: [SearchDirectoryItem])] = [
        ("记录", [.usage, .errors, .alerts]),
        ("资源", [.groups, .analytics, .redeem, .proxies, .announcements]),
        ("设置", [.interface, .sites]),
        ("在 Web 中打开", [.webSettings, .webPayments])
    ]

    /// Until admin/me is known everything shows as for the site owner (60 §1.5).
    static func sections(me: AdminMe?) -> [SearchDirectorySection] {
        numbered(groups.map { (title: $0.title, items: $0.items.filter { isVisible($0, me: me) }) })
    }

    /// 60 §1.3. Errors and alerts stay while ops monitoring is off: their pages say so (60 §1.2). A missing
    /// `payment_enabled` (old server) keeps the payments row. Other rows show for vendors until vendors are supported (U01).
    static func isVisible(_ item: SearchDirectoryItem, me: AdminMe?) -> Bool {
        guard let me else { return true }
        let permissions = me.workspace?.permissions
        switch item {
        case .webPayments: return me.features.paymentEnabled != false
        case .redeem, .announcements: return me.workspace == nil
        case .proxies: return me.workspace == nil || permissions?.proxyManage == true || permissions?.accountManage == true
        default: return true
        }
    }

    /// Empty sections are dropped and the rest numbered again.
    static func numbered(_ groups: [(title: String, items: [SearchDirectoryItem])]) -> [SearchDirectorySection] {
        groups.filter { !$0.items.isEmpty }.enumerated().map { index, group in
            SearchDirectorySection(title: group.title, ordinal: ChineseOrdinal.text(index + 1), items: group.items)
        }
    }

    static func destination(for item: SearchDirectoryItem, siteURL: URL) -> SearchDirectoryDestination {
        switch item {
        case .usage: .push(.logs(LogsRoute(scope: .usage)))
        case .errors: .push(.logs(LogsRoute(scope: .errors)))
        case .alerts: .select(.monitor(segment: .alerts))
        case .groups: .push(.groups())
        // 40 §1.1: entered from the directory, the first visit shows the last seven days.
        case .analytics: .push(.analytics(range: .last7))
        case .redeem: .push(.redeem())
        case .proxies: .push(.proxies())
        case .announcements: .push(.announcements())
        case .interface: .push(.settings(focus: .interface))
        case .sites: .push(.settings(focus: .sites))
        case .webSettings: .openURL(siteURL.appending(path: "admin/settings"))
        case .webPayments: .openURL(siteURL.appending(path: "admin/orders/dashboard"))
        }
    }
}
