import Foundation

// 60 §2.3 “查看全部” pages (S6-21). The kinds, requests, rows and wording are GlobalSearch.swift's (S6-20).

/// One page of a kind's search, 20 a page. SearchHits has no page number, so this is the page that was asked for.
public struct SearchHitPage: Sendable {
    public let hits: [SearchHit]
    /// The envelope's total; nil when it has none.
    public let total: Int?
    public let page: Int
    public let hasMore: Bool

    public init(hits: [SearchHit], total: Int?, page: Int, hasMore: Bool) {
        self.hits = hits; self.total = total; self.page = page; self.hasMore = hasMore
    }
}

/// The rows a “查看全部” page has from page 1 on, each id once in the order it came.
public struct SearchResultsListSnapshot: Sendable {
    public let hits: [SearchHit]
    /// The latest page's total; a page without one keeps the last.
    public let total: Int?
    public let page: Int
    public let hasMore: Bool

    public init(_ first: SearchHitPage) {
        self.init(hits: first.hits, total: first.total, page: first.page, hasMore: first.hasMore)
    }
    private init(hits: [SearchHit], total: Int?, page: Int, hasMore: Bool) {
        self.hits = hits; self.total = total; self.page = page; self.hasMore = hasMore
    }

    /// Follows has_more alone, so envelopes without a total page too.
    public var nextPage: Int? { hasMore ? page + 1 : nil }

    /// Only the page after the last one joins; a row a moved page boundary brings again stays where it was.
    public func appending(_ next: SearchHitPage) -> SearchResultsListSnapshot {
        guard next.page == page + 1 else { return self }
        let shown = Set(hits.map(\.id))
        return SearchResultsListSnapshot(hits: hits + next.hits.filter { !shown.contains($0.id) }, total: next.total ?? total,
                                         page: next.page, hasMore: next.hasMore)
    }
}
