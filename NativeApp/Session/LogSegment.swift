import Foundation
import Sub2Core

/// Where one segment of the usage-record page stands (40 §6.5).
enum LogSegmentPhase: Equatable, Sendable {
    /// Not read in this window yet, or page 1 was cancelled before any row came (D18).
    case idle
    case loading(page: Int)
    case loaded
    case failed(page: Int)
    /// An error segment while ops monitoring is off: admin/me, the latest signal or a 404 OPS_DISABLED said so.
    case opsDisabled
    /// An auto refresh failed (S4-06): the rows stay, and 重试 polls again.
    case refreshFailed
}

/// What the page reads of a segment whatever its record type.
protocol LogSegmentStatus: Sendable {
    var phase: LogSegmentPhase { get }
    var nextPage: Int? { get }
    var window: LogTimeWindow? { get }
    var lastError: APIError? { get }
    var lastErrorAt: Date? { get }
    var hasRows: Bool { get }
}

/// One segment's rows and paging (40 §6.4). Every change returns a new value.
struct LogSegment<Record: IncrementalRecord & Decodable>: LogSegmentStatus {
    /// `limit` nil: 40 §6.6 trims only near the top (S4-06).
    let list: IncrementalList<Record>
    /// nil: no further page.
    let nextPage: Int?
    /// The window of the last full load.
    let window: LogTimeWindow?
    let phase: LogSegmentPhase
    let lastError: APIError?
    let lastErrorAt: Date?

    init(list: IncrementalList<Record> = IncrementalList(), nextPage: Int? = nil, window: LogTimeWindow? = nil,
         phase: LogSegmentPhase = .idle, lastError: APIError? = nil, lastErrorAt: Date? = nil) {
        self.list = list; self.nextPage = nextPage; self.window = window; self.phase = phase
        self.lastError = lastError; self.lastErrorAt = lastErrorAt
    }

    var rows: [Record] { list.items }
    var hasRows: Bool { !list.items.isEmpty }

    /// Page 1 takes the new window; the old rows stay until its reply lands.
    func starting(page: Int, window: LogTimeWindow) -> LogSegment {
        LogSegment(list: list, nextPage: nextPage, window: page == 1 ? window : self.window, phase: .loading(page: page),
                   lastError: lastError, lastErrorAt: lastErrorAt)
    }
    /// Page 1 replaces the rows; a later page joins them by id.
    func applying(_ reply: Page<Record>, page: Int) -> LogSegment {
        let merged = page == 1 ? list.reset(firstPage: reply.items) : list.appendingOlder(reply.items)
        return LogSegment(list: merged, nextPage: reply.hasMore ? page + 1 : nil, window: window, phase: .loaded)
    }
    /// The rows stay (40 §6.5). nil `error` is a read the 429 wait held back.
    func failing(page: Int, error: (any Error)?, at date: Date) -> LogSegment {
        LogSegment(list: list, nextPage: nextPage, window: window, phase: .failed(page: page), lastError: error as? APIError,
                   lastErrorAt: error == nil ? nil : date)
    }
    /// Cancelled: page 1 without rows reads again on the next appearance; nothing is recorded as failed.
    func interrupted(page: Int) -> LogSegment {
        LogSegment(list: list, nextPage: nextPage, window: window, phase: page == 1 && !hasRows ? .idle : .loaded,
                   lastError: lastError, lastErrorAt: lastErrorAt)
    }
    func opsOff() -> LogSegment { LogSegment(window: window, phase: .opsDisabled) }
    /// Only the rows change (S4-08b updates a row in place).
    func replacingList(_ list: IncrementalList<Record>) -> LogSegment {
        LogSegment(list: list, nextPage: nextPage, window: window, phase: phase, lastError: lastError, lastErrorAt: lastErrorAt)
    }

    // S4-06: an auto refresh (40 §6.6).

    /// A poll merged: the rows change and the last poll's failure goes.
    func refreshed(_ list: IncrementalList<Record>) -> LogSegment {
        let recovered = phase == .refreshFailed
        return LogSegment(list: list, nextPage: nextPage, window: window, phase: recovered ? .loaded : phase,
                          lastError: recovered ? nil : lastError, lastErrorAt: recovered ? nil : lastErrorAt)
    }
    /// The newest N rows stay, and “加载更多” reads the trim's page next.
    func trimmed(_ trim: LogTrim<Record>) -> LogSegment {
        LogSegment(list: trim.list, nextPage: trim.nextPage, window: window, phase: phase, lastError: lastError, lastErrorAt: lastErrorAt)
    }
    /// A poll with nothing to continue from read page 1 over `window`: it lands as page 1 does.
    func reloaded(_ reply: Page<Record>, window: LogTimeWindow) -> LogSegment {
        LogSegment(list: list, window: window).applying(reply, page: 1)
    }
    /// The rows stay, and the list's end says the poll failed.
    func refreshFailing(_ error: any Error, at date: Date) -> LogSegment {
        LogSegment(list: list, nextPage: nextPage, window: window, phase: .refreshFailed, lastError: error as? APIError, lastErrorAt: date)
    }
}
