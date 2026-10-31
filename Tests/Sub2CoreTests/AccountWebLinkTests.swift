import Foundation
import Testing
@testable import Sub2Core

private let root = URL(string: "https://sub2.example.com")!

@Test func deepLinkCarriesIDAndEncodedName() throws {
    let link = try #require(AccountWebLink.make(siteRoot: root, accountID: 7, name: "Claude-官方-01", supportsDeepLink: true))
    #expect(link.kind == .editor)
    #expect(link.url.absoluteString == "https://sub2.example.com/admin/accounts?edit=7&search=Claude-%E5%AE%98%E6%96%B9-01")
    #expect(link.copiedName == nil)
    #expect(link.receipt == "已在浏览器打开「Claude-官方-01」的编辑页")
}

@Test func reservedCharactersCannotInjectParameters() throws {
    let link = try #require(AccountWebLink.make(siteRoot: root, accountID: 7, name: "a+b&edit=9#x%y z/?~._-", supportsDeepLink: true))
    #expect(link.url.absoluteString.hasSuffix("?edit=7&search=a%2Bb%26edit%3D9%23x%25y%20z%2F%3F~._-"))
    let items = try #require(URLComponents(url: link.url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.map(\.name) == ["edit", "search"])
    #expect(items.first?.value == "7" && items.last?.value == "a+b&edit=9#x%y z/?~._-")
}

@Test func truncatesToHundredUTF8BytesWithoutSplitting() {
    let family = "👨‍👩‍👧"
    let cases: [(String, String)] = [
        (String(repeating: "a", count: 120), String(repeating: "a", count: 100)),
        (String(repeating: "中", count: 40), String(repeating: "中", count: 33)),
        ("a" + String(repeating: "😀", count: 30), "a" + String(repeating: "😀", count: 24)),
        (String(repeating: family, count: 6), String(repeating: family, count: 5)),
        (String(repeating: "b", count: 100), String(repeating: "b", count: 100))
    ]
    for (input, expected) in cases {
        let cut = AccountWebLink.truncatedUTF8(input, maxBytes: AccountWebLink.searchByteLimit)
        #expect(cut == expected)
        #expect(cut.utf8.count <= 100 && input.hasPrefix(cut))
    }
}

@Test func trimsBeforeTruncating() throws {
    let link = try #require(AccountWebLink.make(siteRoot: root, accountID: 7, name: "  主力 01\n", supportsDeepLink: true))
    #expect(link.url.absoluteString.hasSuffix("search=%E4%B8%BB%E5%8A%9B%2001"))
    #expect(link.receipt == "已在浏览器打开「主力 01」的编辑页")
}

@Test func fallbackOpensListAndCopiesFullName() throws {
    let long = String(repeating: "长", count: 50)
    let link = try #require(AccountWebLink.make(siteRoot: root, accountID: 7, name: long, supportsDeepLink: false))
    #expect(link.kind == .accountList)
    #expect(link.url.absoluteString == "https://sub2.example.com/admin/accounts")
    #expect(link.copiedName == long)
    #expect(link.receipt == "已打开 Web 账号管理 · 已复制「\(long)」，可直接搜索")
}

@Test func webLinkEdgeCases() throws {
    let slashed = URL(string: "https://sub2.example.com/")!
    let link = try #require(AccountWebLink.make(siteRoot: slashed, accountID: 7, name: "x", supportsDeepLink: true))
    #expect(link.url.absoluteString == "https://sub2.example.com/admin/accounts?edit=7&search=x")
    #expect(AccountWebLink.make(siteRoot: root, accountID: 0, name: "x", supportsDeepLink: true) == nil)
    #expect(AccountWebLink.make(siteRoot: root, accountID: -3, name: "x", supportsDeepLink: false) == nil)
    let blank = try #require(AccountWebLink.make(siteRoot: root, accountID: 7, name: "  ", supportsDeepLink: true))
    #expect(blank.url.absoluteString == "https://sub2.example.com/admin/accounts?edit=7")
    #expect(blank.receipt == "已在浏览器打开账号 #7 的编辑页")
    let unnamed = try #require(AccountWebLink.make(siteRoot: root, accountID: 7, name: nil, supportsDeepLink: false))
    #expect(unnamed.copiedName == nil && unnamed.receipt == "已打开 Web 账号管理")
}
