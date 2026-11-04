import Foundation
import Testing
@testable import Sub2Core

@Test func chineseOrdinalsOneThroughTen() {
    #expect((1...10).map(ChineseOrdinal.text) == ["壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖", "拾"])
    #expect(ChineseOrdinal.text(0) == "0")
    #expect(ChineseOrdinal.text(11) == "11")
    #expect(ChineseOrdinal.text(-1) == "-1")
}

@Test func searchResultKindAndModelSourceValues() {
    #expect(SearchResultKind.allCases == [.accounts, .users, .groups, .proxies])
    #expect(SearchResultKind.allCases.map(\.title) == ["账号", "用户", "分组", "代理"])
    // backend usagestats.ModelSource* (usage_log_types.go)
    #expect(ModelSource.allCases.map(\.rawValue) == ["requested", "upstream", "mapping"])
}
