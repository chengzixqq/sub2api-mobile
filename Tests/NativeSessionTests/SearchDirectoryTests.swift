import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private func vendor(_ permissions: AdminMe.WorkspacePermissions?) -> AdminMe {
    AdminMe(workspace: .init(id: 3, name: "代运营", permissions: permissions))
}
private func items(_ me: AdminMe?) -> [[SearchDirectoryItem]] { SearchDirectory.sections(me: me).map(\.items) }

@Test func unknownIdentityShowsWholeDirectoryInOrder() {
    let sections = SearchDirectory.sections(me: nil)
    #expect(sections.map(\.title) == ["记录", "资源", "设置", "在 Web 中打开"])
    #expect(sections.map(\.ordinal) == ["壹", "贰", "叁", "肆"])
    #expect(sections.map(\.items) == [
        [.usage, .errors, .alerts], [.groups, .analytics, .redeem, .proxies, .announcements], [.interface, .sites], [.webSettings, .webPayments]
    ])
    #expect(SearchDirectoryItem.allCases.map(\.title) == [
        "使用记录", "错误请求", "告警事件", "分组", "统计分析", "兑换码", "代理", "公告", "界面与模式", "站点与凭据", "系统设置", "支付与套餐"
    ])
    #expect(SearchDirectoryItem.allCases.allSatisfy { !$0.systemImage.isEmpty })
    #expect(items(AdminMe()) == items(nil))
}

@Test func paymentDisabledHidesOnlyPaymentsRow() {
    let me = AdminMe(features: .init(paymentEnabled: false))
    #expect(items(me) == Array(items(nil).prefix(3)) + [[.webSettings]])
    #expect(!SearchDirectory.isVisible(.webPayments, me: me))
}

@Test func missingPaymentFlagKeepsPaymentsRow() {
    #expect(SearchDirectory.isVisible(.webPayments, me: AdminMe()))
    #expect(SearchDirectory.isVisible(.webPayments, me: AdminMe(features: .init(paymentEnabled: true))))
    #expect(SearchDirectory.isVisible(.webPayments, me: nil))
}

@Test func opsDisabledStillListsErrorsAndAlerts() {
    let me = AdminMe(features: .init(opsMonitoringEnabled: false, opsMonitoringDisabledReason: "setting_off"))
    #expect(items(me).first == [.usage, .errors, .alerts])
}

@Test func vendorHidesRedeemAndAnnouncements() {
    let none = AdminMe.WorkspacePermissions(accountManage: false, groupOps: false, groupBilling: false, proxyManage: false, monitorView: false)
    let sections = SearchDirectory.sections(me: vendor(none))
    #expect(sections[1].items == [.groups, .analytics])
    #expect(sections.map(\.ordinal) == ["壹", "贰", "叁", "肆"])
}

@Test func vendorSeesProxiesOnlyWithProxyOrAccountPermission() {
    #expect(SearchDirectory.isVisible(.proxies, me: vendor(.init(proxyManage: true))))
    #expect(SearchDirectory.isVisible(.proxies, me: vendor(.init(accountManage: true))))
    #expect(!SearchDirectory.isVisible(.proxies, me: vendor(.init(accountManage: false, proxyManage: false))))
    #expect(!SearchDirectory.isVisible(.proxies, me: vendor(nil)))
    #expect(SearchDirectory.isVisible(.proxies, me: AdminMe()))
    #expect(SearchDirectory.isVisible(.redeem, me: AdminMe()) && SearchDirectory.isVisible(.announcements, me: AdminMe()))
}

@Test func emptySectionsDropAndOrdinalsRenumber() {
    let sections = SearchDirectory.numbered([(title: "A", items: [.usage]), (title: "B", items: []), (title: "C", items: [.sites])])
    #expect(sections.map(\.title) == ["A", "C"])
    #expect(sections.map(\.ordinal) == ["壹", "贰"])
    #expect(sections.map(\.id) == ["A", "C"])
}

@Test func destinationsFollowDirectoryTable() {
    let site = URL(string: "https://a.example.com")!
    let expected: [(SearchDirectoryItem, SearchDirectoryDestination)] = [
        (.usage, .push(.logs(LogsRoute(scope: .usage)))),
        (.errors, .push(.logs(LogsRoute(scope: .errors)))),
        (.alerts, .select(.monitor(segment: .alerts))),
        (.groups, .push(.groups())),
        (.analytics, .push(.analytics(range: .last7))),
        (.redeem, .push(.redeem())),
        (.proxies, .push(.proxies())),
        (.announcements, .push(.announcements())),
        (.interface, .push(.settings(focus: .interface))),
        (.sites, .push(.settings(focus: .sites)))
    ]
    for (item, destination) in expected { #expect(SearchDirectory.destination(for: item, siteURL: site) == destination, "\(item)") }
}

@Test func webDestinationsUseSiteOrigin() {
    let site = URL(string: "https://a.example.com")!
    #expect(SearchDirectory.destination(for: .webSettings, siteURL: site) == .openURL(URL(string: "https://a.example.com/admin/settings")!))
    #expect(SearchDirectory.destination(for: .webPayments, siteURL: site) == .openURL(URL(string: "https://a.example.com/admin/orders/dashboard")!))
    let port = URL(string: "https://b.example.com:8443")!
    #expect(SearchDirectory.destination(for: .webSettings, siteURL: port) == .openURL(URL(string: "https://b.example.com:8443/admin/settings")!))
}
