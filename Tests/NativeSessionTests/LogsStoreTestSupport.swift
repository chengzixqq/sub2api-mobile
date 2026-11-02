import Foundation
import Sub2Core
@testable import NativeSessionSupport

// LogsStoreStateTests' read stub, clock and pages, kept apart so that file stays under 800 lines (S4-20).

/// Records every read and answers through closures; `call` counts every read from 1, whatever the segment.
actor LogsStub {
    struct Read: Sendable {
        let page: Int
        let filter: RequestLogFilter
        let kind: ErrorLogKind?
    }
    typealias UsageHandler = @Sendable (_ call: Int, _ read: Read) async throws -> Page<UsageRequestRecord>
    typealias ErrorHandler = @Sendable (_ call: Int, _ read: Read) async throws -> Page<RequestErrorRecord>
    private let onUsage: UsageHandler
    private let onErrors: ErrorHandler
    private(set) var reads: [Read] = []

    init(usage: @escaping UsageHandler = { _, read in usagePage([], page: read.page) },
         errors: @escaping ErrorHandler = { _, read in errorPage([], page: read.page) }) {
        onUsage = usage; onErrors = errors
    }
    func usage(_ page: Int, _ filter: RequestLogFilter) async throws -> Page<UsageRequestRecord> {
        let read = Read(page: page, filter: filter, kind: nil)
        reads.append(read)
        return try await onUsage(reads.count, read)
    }
    func errors(_ page: Int, _ filter: RequestLogFilter, _ kind: ErrorLogKind) async throws -> Page<RequestErrorRecord> {
        let read = Read(page: page, filter: filter, kind: kind)
        reads.append(read)
        return try await onErrors(reads.count, read)
    }
    nonisolated var source: LogsSource {
        LogsSource(usage: { try await self.usage($0, $1) }, errors: { try await self.errors($0, $1, $2) })
    }
}

/// The store's clock, session flag, ops switch and what it reported to LiveOpsStore (“nil” for a success).
@MainActor final class LogsStoreHarness {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Server minus phone time, as ServerClock keeps it; `phone` moves with `now`.
    var serverOffset: TimeInterval = 0
    var phone: Date { now.addingTimeInterval(-serverOffset) }
    var isCurrent = true
    var opsOff = false
    private(set) var reports: [String] = []
    let generation = UUID()

    func store(_ route: LogsRoute = LogsRoute(), stub: LogsStub, legacyServer: Bool = false,
               counts: LogCountSource = .unavailable) -> LogsStoreState {
        LogsStoreState(route: route, generation: generation, source: stub.source, timeZone: liveOpsZone, legacyServer: legacyServer,
                       supportsModelSource: true, isCurrent: { self.isCurrent }, now: { self.now }, phoneNow: { self.phone },
                       opsDisabled: { self.opsOff },
                       reportOps: { error in self.reports.append(error.map { ($0 as? APIError)?.reason ?? "other" } ?? "nil") },
                       countSource: counts)
    }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    func lastDay() -> LogTimeWindow { .range(now.addingTimeInterval(-86_400), now) }
}

func usagePage(_ records: [UsageRequestRecord], page: Int = 1, hasMore: Bool = false) -> Page<UsageRequestRecord> {
    Page(items: records, total: nil, page: page, pageSize: 100, pages: nil, hasMore: hasMore)
}
/// Like `ops/upstream-errors`: no `has_more`, so `page < pages` decides.
func errorPage(_ records: [RequestErrorRecord], page: Int = 1, pages: Int = 1) -> Page<RequestErrorRecord> {
    Page(items: records, total: records.count, page: page, pageSize: 100, pages: pages)
}
