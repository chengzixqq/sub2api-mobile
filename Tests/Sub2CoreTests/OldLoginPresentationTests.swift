import Foundation
import Testing
@testable import Sub2Core

// S6-26 ⑥ (C-26, D17, S6D2a-04): older logins of the site list and where the login page's pending rows lead.

private func site(_ name: String, _ url: String, id: UUID = UUID()) -> ServerProfile {
    ServerProfile(id: id, name: name, baseURL: URL(string: url)!, authentication: .password)
}

@Test func rootActionSignsInAtASavedSiteOfTheRecordAddress() {
    let archived = site("设置站点", "https://Settings.example.invalid:443")
    let settings = site("设置站点", "https://settings.example.invalid")
    let other = site("其他站点", "https://other.example.invalid")
    #expect(OldLoginPresentation.rootAction(recordSite: archived, saved: [other, settings], withoutCredential: [settings.id], reusable: [])
            == .signIn(settings))

    let first = site("甲", "https://settings.example.invalid"), second = site("乙", "https://settings.example.invalid")
    // One has a credential: that one.
    #expect(OldLoginPresentation.rootAction(recordSite: archived, saved: [first, second], withoutCredential: [second.id], reusable: [])
            == .signIn(first))
    // Neither has one: the one without records keeps its id when signed in again.
    #expect(OldLoginPresentation.rootAction(recordSite: archived, saved: [first, second], withoutCredential: [first.id, second.id],
                                            reusable: [first.id]) == .signIn(first))
    // Neither: the later one.
    #expect(OldLoginPresentation.rootAction(recordSite: archived, saved: [first, second], withoutCredential: [first.id, second.id], reusable: [])
            == .signIn(second))
    // Both have credentials: the later one.
    #expect(OldLoginPresentation.rootAction(recordSite: archived, saved: [first, second], withoutCredential: [], reusable: []) == .signIn(second))
}

@Test func rootActionOpensTheOriginalSiteOnlyForAnotherAddress() throws {
    let old = site("旧站点", "https://old.example.invalid")
    let settings = site("设置站点", "https://settings.example.invalid")
    #expect(OldLoginPresentation.rootAction(recordSite: old, saved: [settings], withoutCredential: [], reusable: [])
            == .openOriginalSite(try #require(URL(string: "https://old.example.invalid"))))
    #expect(OldLoginPresentation.rootAction(recordSite: nil, saved: [settings], withoutCredential: [], reusable: []) == .none)
}

@Test func oldLoginsMapOnlyClearedSitesWithRecords() {
    let a1 = site("设置站点", "https://settings.example.invalid"), a2 = site("设置站点", "https://SETTINGS.example.invalid:443")
    let b = site("旧站点", "https://old.example.invalid")
    let saved = [a1, b, a2]
    #expect(OldLoginPresentation.oldLogins(saved: saved, activeID: a2.id, withRecords: [a1.id, b.id], withoutCredential: [a1.id, b.id], reusable: [])
            == [a1.id: a2])
    // A credential, no records, no other site at the address, or itself connected: not an older login.
    #expect(OldLoginPresentation.oldLogins(saved: saved, activeID: a2.id, withRecords: [a1.id], withoutCredential: [], reusable: []).isEmpty)
    #expect(OldLoginPresentation.oldLogins(saved: saved, activeID: a2.id, withRecords: [], withoutCredential: [a1.id], reusable: []).isEmpty)
    #expect(OldLoginPresentation.oldLogins(saved: [a1, b], activeID: b.id, withRecords: [a1.id], withoutCredential: [a1.id], reusable: []).isEmpty)
    #expect(OldLoginPresentation.oldLogins(saved: saved, activeID: a1.id, withRecords: [a1.id], withoutCredential: [a1.id], reusable: []).isEmpty)
}

@Test func oldLoginTargetPrefersCurrentThenCredentialThenReusable() {
    let a1 = site("旧登录", "https://settings.example.invalid"), a2 = site("有凭据", "https://settings.example.invalid")
    let a3 = site("当前", "https://settings.example.invalid")
    let saved = [a1, a2, a3]
    #expect(OldLoginPresentation.oldLogins(saved: saved, activeID: a3.id, withRecords: [a1.id], withoutCredential: [a1.id], reusable: [])[a1.id] == a3)
    #expect(OldLoginPresentation.oldLogins(saved: saved, activeID: nil, withRecords: [a1.id], withoutCredential: [a1.id, a3.id], reusable: [])[a1.id] == a2)
    let pair = [a1, a2]
    #expect(OldLoginPresentation.oldLogins(saved: pair, activeID: nil, withRecords: [a1.id], withoutCredential: [a1.id, a2.id], reusable: [a2.id])[a1.id] == a2)
    #expect(OldLoginPresentation.oldLogins(saved: pair, activeID: nil, withRecords: [a1.id, a2.id], withoutCredential: [a1.id, a2.id], reusable: []).isEmpty)
}

@Test func oldLoginCopy() {
    let target = site("设置站点", "https://settings.example.invalid")
    #expect(OldLoginPresentation.rowNote(target: target, isActive: true) == "旧登录 · 记录在下方“待核对”里核对")
    #expect(OldLoginPresentation.rowNote(target: target, isActive: false) == "旧登录 · 切换到「设置站点」后在“待核对”里核对")
    #expect(OldLoginPresentation.signInTitle(target) == "登录「设置站点」后核对")
    #expect(OldLoginPresentation.rootSectionTitle == "待核对")
    #expect(OldLoginPresentation.rootFootnote
            == "以下写入保留原操作编号，结果还没确认。登录同一地址的站点后在“设置 → 待核对”里核对；地址已不在站点列表里的，请在原站点 Web 后台核对，勿新建重复操作。")
}

// U-24: switching to a saved site without a credential (site menu, settings, push) follows its older-login lead.

@Test func switchActionStaysSwitchesOrSignsIn() {
    let current = site("设置站点", "https://settings.example.invalid"), other = site("设置站点", "https://settings.example.invalid")
    #expect(OldLoginPresentation.switchAction(lead: current, activeID: current.id) == .stay)
    #expect(OldLoginPresentation.switchAction(lead: other, activeID: current.id) == .switchTo(other))
    #expect(OldLoginPresentation.switchAction(lead: other, activeID: nil) == .switchTo(other))
    #expect(OldLoginPresentation.switchAction(lead: nil, activeID: current.id) == .signIn)
    #expect(OldLoginPresentation.switchAction(lead: nil, activeID: nil) == .signIn)
}

@Test func stayReceiptNamesTheOlderLogin() {
    #expect(OldLoginPresentation.stayReceipt(name: "设置站点") == "「设置站点」是旧登录 · 记录在“设置 → 待核对”里核对")
}
