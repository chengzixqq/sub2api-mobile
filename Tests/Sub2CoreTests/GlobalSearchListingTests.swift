import Foundation
import Testing
@testable import Sub2Core

// 60 §2.3 “查看全部”: the rows a page has loaded, page after page (S6-21).

private func users(_ ids: ClosedRange<Int>) -> [SearchHit] { ids.map { .user(AdminUser(id: $0, email: "user\($0)@example.invalid")) } }
private func page(_ ids: ClosedRange<Int>, total: Int?, page: Int, hasMore: Bool) -> SearchHitPage {
    SearchHitPage(hits: users(ids), total: total, page: page, hasMore: hasMore)
}

@Test func snapshotAppendsNextPageDedupedInOrder() {
    let first = SearchResultsListSnapshot(page(1...20, total: 26, page: 1, hasMore: true))
    #expect(first.hits.map(\.id) == (1...20).map { "user-\($0)" })
    #expect(first.page == 1)
    #expect(first.nextPage == 2)

    // The boundary moved by one: user 20 comes again on page 2 and stays where it was.
    let both = first.appending(page(20...26, total: 27, page: 2, hasMore: false))
    #expect(both.hits.map(\.id) == (1...26).map { "user-\($0)" })
    #expect(both.page == 2)
    #expect(both.hasMore == false)
    #expect(both.nextPage == nil)
    #expect(both.total == 27)
}

@Test func snapshotIgnoresStaleOrRepeatedPage() {
    let first = SearchResultsListSnapshot(page(1...20, total: 26, page: 1, hasMore: true))
    let second = first.appending(page(21...26, total: 26, page: 2, hasMore: false))

    let again = second.appending(page(1...20, total: 30, page: 1, hasMore: true))
    #expect(again.hits.map(\.id) == second.hits.map(\.id))
    #expect(again.page == 2)
    #expect(again.total == 26)
    let repeated = second.appending(page(21...26, total: 30, page: 2, hasMore: true))
    #expect(repeated.hits.count == 26)
    #expect(repeated.hasMore == false)
    let skipped = first.appending(page(41...45, total: 45, page: 3, hasMore: false))
    #expect(skipped.hits.count == 20)
    #expect(skipped.page == 1)

    // Usage-like envelopes carry no total: the next page follows has_more alone, and a missing total keeps the last one.
    let untotalled = SearchResultsListSnapshot(page(1...20, total: nil, page: 1, hasMore: true))
    #expect(untotalled.total == nil)
    #expect(untotalled.nextPage == 2)
    #expect(first.appending(page(21...26, total: nil, page: 2, hasMore: false)).total == 26)
}
