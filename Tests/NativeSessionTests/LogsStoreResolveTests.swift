import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 40 §7.4 (S4-08b): a request detail's 标记已处理 changes the row in place; LogsStoreStateTests.swift is past 800 lines.

/// Both error lists answer the same rows (one table, 40 §7.2) with a next page; every read is counted.
private actor ResolveListStub {
    private(set) var reads = 0
    private let rows: [RequestErrorRecord]
    init(rows: [RequestErrorRecord]) { self.rows = rows }
    func usage(_ page: Int) -> Page<UsageRequestRecord> {
        reads += 1
        return Page(items: [], total: nil, page: page, pageSize: 100, pages: nil, hasMore: false)
    }
    func errors(_ page: Int) -> Page<RequestErrorRecord> {
        reads += 1
        return Page(items: rows, total: nil, page: page, pageSize: 100, pages: nil, hasMore: true)
    }
    nonisolated var source: LogsSource {
        LogsSource(usage: { page, _ in await self.usage(page) }, errors: { page, _, _ in await self.errors(page) })
    }
}

private func resolveListRow(_ id: Int, at createdAt: Date) throws -> RequestErrorRecord {
    let json = """
    {"id":\(id),"created_at":"\(ServerTime.utcTimestamp(createdAt))","request_id":"req-\(id)","phase":"upstream","type":"upstream_error",
     "status_code":502,"platform":"openai","model":"gpt-4.1","resolved":false,"message":"Upstream error","account_id":4}
    """
    return try JSONDecoder().decode(RequestErrorRecord.self, from: Data(json.utf8))
}

@MainActor @Test func resolvedRecordChangesBothErrorSegmentsInPlace() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let rows = [try resolveListRow(6, at: now.addingTimeInterval(-60)), try resolveListRow(5, at: now.addingTimeInterval(-120))]
    let list = ResolveListStub(rows: rows)
    let store = LogsStoreState(route: LogsRoute(scope: .errors), generation: UUID(), source: list.source, timeZone: liveOpsZone,
                               legacyServer: false, supportsModelSource: true, isCurrent: { true }, now: { now }, phoneNow: { now })
    await store.appeared()
    await store.select(.upstream)
    let reads = await list.reads
    #expect(store.errors.nextPage == 2 && store.upstream.nextPage == 2)

    store.applyResolved(rows[1].settingResolved(true))

    #expect(store.errors.rows.map(\.id) == [6, 5] && store.errors.rows.map(\.resolved) == [false, true])
    #expect(store.upstream.rows.map(\.id) == [6, 5] && store.upstream.rows.map(\.resolved) == [false, true])
    #expect(store.errors.nextPage == 2 && store.upstream.nextPage == 2 && store.errors.phase == .loaded && store.upstream.phase == .loaded)
    #expect(store.usage.rows.isEmpty && store.sections.flatMap(\.rows).map(\.id) == [6, 5])
    #expect(await list.reads == reads)
    let route = store.requestRoute(for: LogRowPresentation(rows[1], kind: .upstream, timeZone: liveOpsZone))
    guard case .error(5, .upstream, let initial?)? = route else { Issue.record("no route: \(String(describing: route))"); return }
    #expect(initial.value.resolved)

    store.applyResolved(try resolveListRow(99, at: now))
    #expect(store.upstream.rows.map(\.resolved) == [false, true])
    #expect(await list.reads == reads)
}
