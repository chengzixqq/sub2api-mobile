import Foundation
import Observation
import Sub2Core

/// 40 §7.2's three reads: the usage record by request ID, the error-log detail and the retry chain. RequestDetailView picks
/// the site or, under `-ui-testing`, LogFixtures+Detail (`RequestDetailSource.app`).
struct RequestDetailSource: Sendable {
    let usageRecord: @Sendable (_ filter: RequestLogFilter) async throws -> UsageRequestRecord?
    let errorDetail: @Sendable (_ id: Int, _ kind: ErrorLogKind) async throws -> RequestErrorDetail
    let attempts: @Sendable (_ id: String, _ around: Date?) async throws -> RequestAttempts

    /// R19's methods; the usage lookup sends `key_view=masked` only with the site's `api_keys.masked_view` (S4D1-06).
    static func live(_ client: APIClient, site: SiteSession) -> RequestDetailSource {
        let masked = site.has(.apiKeysMaskedView)
        return RequestDetailSource(usageRecord: { try await client.requestRecords(page: 1, filter: $0, maskedView: masked).items.first },
                                   errorDetail: { try await client.errorDetail(id: $0, kind: $1) },
                                   attempts: { try await client.requestAttempts(id: $0, around: $1) })
    }
}

extension RequestRoute {
    /// nil for the usage record, the success look.
    var errorKind: ErrorLogKind? {
        guard case .error(_, let kind, _) = self else { return nil }
        return kind
    }
    /// The list row an error route carries; the account detail's entry carries none.
    var initialErrorRow: RequestErrorRecord? {
        guard case .error(_, _, let initial) = self else { return nil }
        return initial?.value
    }
}

/// 40 §7: one request. A row the route carries is drawn at once and the error-log detail and the retry chain fill it in, read side
/// by side; without a row the detail comes first and names the chain. Only a request ID is looked up in the usage records once.
/// Reads on entry, pull, return to the foreground and retry; never polls. With ops monitoring off nothing goes to ops (00 §0.3).
/// A reply for an older load or another session is dropped.
@MainActor @Observable
final class RequestDetailModel {
    /// The whole page: `.loading` only while there is no row; `.gone` when the request ID finds nothing or the detail answers
    /// 404 OPS_ERROR_NOT_FOUND; `.opsDisabled` and `.failed` only without a row.
    enum Page: Equatable, Sendable { case loading, content, gone, opsDisabled, failed }
    enum Attempts: Equatable, Sendable {
        case hidden, loading, chain(RequestAttempts), fallback(rows: [AttemptRow], dropped: Int), unavailable
    }

    let route: RequestRoute
    private(set) var page: Page
    private(set) var usage: UsageRequestRecord?
    /// The row first, then the detail's record.
    private(set) var record: RequestErrorRecord?
    /// Ops monitoring off, as the switch says or the detail answered, is `.disabled(reason: "OPS_DISABLED")`.
    private(set) var detail: BlockState<RequestErrorDetail> = .idle
    private(set) var detailError: APIError?
    private(set) var detailRefresh = BlockRefresh()
    private(set) var pageError: APIError?
    private(set) var attempts: Attempts = .hidden
    /// Grows with every detail that arrives (entry, pull, foreground, retry); S4-08b follows it (S4D2a-08).
    private(set) var detailRevision = 0
    /// A load ran to its end, so returning to the page reads nothing until the reason to read changes.
    private(set) var hasLoaded = false

    @ObservationIgnored private let source: RequestDetailSource
    @ObservationIgnored private let attemptsSupported: Bool
    @ObservationIgnored private let isOpsEnabled: @MainActor () -> Bool
    @ObservationIgnored private let isCurrent: @MainActor @Sendable () -> Bool
    @ObservationIgnored private let onOpsResponse: @MainActor ((any Error)?) async -> Void
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Changes with every load; a reply carrying an older one is dropped.
    @ObservationIgnored private var ticket = UUID()

    /// `attemptsSupported` is `ops.request_attempts`; `onOpsResponse` hands each ops read's outcome to LiveOpsStore (S1D1-02).
    init(route: RequestRoute, source: RequestDetailSource, attemptsSupported: Bool, isOpsEnabled: @escaping @MainActor () -> Bool,
         isCurrent: @escaping @MainActor @Sendable () -> Bool, onOpsResponse: @escaping @MainActor ((any Error)?) async -> Void = { _ in },
         now: @escaping @MainActor () -> Date = { Date() }) {
        self.route = route; self.source = source; self.attemptsSupported = attemptsSupported; self.isOpsEnabled = isOpsEnabled
        self.isCurrent = isCurrent; self.onOpsResponse = onOpsResponse; self.now = now
        switch route {
        case .usage(let preload): usage = preload.value; page = .content
        case .usageRequestID: page = .loading
        case .error(_, _, let initial): record = initial?.value; page = initial == nil ? .loading : .content
        }
    }

    var kind: ErrorLogKind? { route.errorKind }
    var style: RequestDetailStyle {
        guard let kind else { return .success }
        return RequestDetailPresentation.style(kind: kind, statusCode: record?.statusCode)
    }
    var chain: RequestAttempts? {
        guard case .chain(let chain) = attempts else { return nil }
        return chain
    }
    var attemptRows: [AttemptRow] {
        switch attempts {
        case .chain(let chain): RequestDetailPresentation.attemptRows(chain)
        case .fallback(let rows, _): rows
        case .hidden, .loading, .unavailable: []
        }
    }
    /// The failed looks keep the section while it loads or says it could not get the chain; the success shows two tries or more.
    var showsAttempts: Bool {
        switch attempts {
        case .hidden: false
        case .loading, .unavailable: style != .success
        case .chain, .fallback: RequestDetailPresentation.showsAttempts(style: style, count: attemptRows.count)
        }
    }
    var attemptsMeta: String? {
        let count = attemptRows.count
        guard count > 0 else { return nil }
        let code = chain?.clientStatusCode ?? (style == .success ? 200 : record?.statusCode)
        return RequestDetailPresentation.attemptsMeta(count: count, clientStatusCode: code)
    }
    var droppedNote: String? {
        switch attempts {
        case .chain(let chain): RequestDetailPresentation.droppedNote(chain.droppedEarlierAttempts)
        case .fallback(_, let dropped): RequestDetailPresentation.droppedNote(dropped)
        case .hidden, .loading, .unavailable: nil
        }
    }
    var sections: [RequestDetailSection] { RequestDetailLayout.sections(style: style, showsAttempts: showsAttempts) }

    // MARK: - Loading

    /// Entry, pull, foreground and retry: each takes a new ticket. A gone record stays gone.
    func load() async {
        guard isCurrent(), page != .gone else { return }
        let ticket = UUID()
        self.ticket = ticket
        switch route {
        case .usage, .usageRequestID: await loadUsage(ticket)
        case .error(let id, let kind, _): await loadError(id: id, kind: kind, ticket: ticket)
        }
        if ticket == self.ticket, !Task.isCancelled { hasLoaded = true }
    }

    private func loadUsage(_ ticket: UUID) async {
        if usage == nil, case .usageRequestID(let requestID) = route {
            guard await lookUpUsage(requestID, ticket: ticket) else { return }
        }
        guard let usage else { return }
        await readSuccessChain(usage, ticket: ticket)
    }
    /// Page 1 of one row with no time (40 §7.2); found once, it is not looked up again.
    private func lookUpUsage(_ requestID: String, ticket: UUID) async -> Bool {
        page = .loading
        let source = source, filter = RequestLogFilter(time: .none, requestID: requestID, pageSize: 1)
        let result = await Self.capture { try await source.usageRecord(filter) }
        guard ticket == self.ticket, isCurrent() else { return false }
        switch result {
        case .success(let found?):
            usage = found; pageError = nil; page = .content
            return true
        case .success(nil): page = .gone
        case .failure(let error) where error is CancellationError: break
        case .failure(let error): pageError = error as? APIError; page = .failed
        }
        return false
    }
    /// The success look reads the chain with the capability, ops on and an id the route takes, and shows no placeholder: most
    /// requests have one try. Any failure hides the section; there is no fallback without upstream events.
    private func readSuccessChain(_ usage: UsageRequestRecord, ticket: UUID) async {
        guard attemptsSupported, isOpsEnabled(), let id = RequestDetailPresentation.attemptsID(forUsage: usage) else {
            attempts = .hidden
            return
        }
        let read = await Self.readChain(source, id: id, around: ServerTime.parseTimestamp(usage.createdAt))
        guard ticket == self.ticket, isCurrent() else { return }
        switch read {
        case .chain(let chain)?:
            attempts = .chain(chain)
            await onOpsResponse(nil)
        case .failed(.opsDisabled, let error)?:
            attempts = .hidden
            await onOpsResponse(error)
        case .failed?, nil: attempts = .hidden
        case .cancelled?: break
        }
    }

    private func loadError(id: Int, kind: ErrorLogKind, ticket: UUID) async {
        guard isOpsEnabled() else { return showOpsOff() }
        guard detailRefresh.allowsRequest(at: now()) else { return }
        let source = source, row = record, previous = attempts
        let earlyID = row.flatMap { chainID($0) }, around = row.flatMap { ServerTime.parseTimestamp($0.createdAt) }
        if row == nil { page = .loading } else if earlyID != nil, !previous.isFilled { attempts = .loading }
        detail = detail.withLoading()
        async let early = Self.readChain(source, id: earlyID, around: around)
        let result = await Self.capture { try await source.errorDetail(id, kind) }
        var read = await early
        guard ticket == self.ticket, isCurrent() else { return }
        let proceeds = applyDetail(result, previous: previous)
        await report(result)
        guard proceeds, ticket == self.ticket, isCurrent() else { return }
        if row == nil, let fresh = detail.value, let lateID = chainID(fresh.record) {
            attempts = .loading
            read = await Self.readChain(source, id: lateID, around: ServerTime.parseTimestamp(fresh.record.createdAt))
            guard ticket == self.ticket, isCurrent() else { return }
        }
        await applyChain(read, previous: previous, ticket: ticket)
    }
    /// Whether the chain still matters: not after the record went, ops turned out off, the read was cancelled, or a page
    /// without a row failed.
    private func applyDetail(_ result: Result<RequestErrorDetail, any Error>, previous: Attempts) -> Bool {
        switch result {
        case .success(let fresh):
            record = fresh.record; detail = .loaded(fresh, at: now()); detailError = nil
            detailRefresh = detailRefresh.recordingSuccess(); detailRevision += 1; pageError = nil; page = .content
            return true
        case .failure(let error) where error is CancellationError:
            detail = detail.withCancelledLoad(); attempts = previous
            return false
        case .failure(let error) where Self.isGone(error):
            detail = .idle; attempts = .hidden; page = .gone
            return false
        case .failure(let error) where AccountUpstreamErrors.isOpsDisabled(error):
            showOpsOff()
            return false
        case .failure(let error):
            detail = detail.withFailure(error.localizedDescription); detailError = error as? APIError
            detailRefresh = detailRefresh.recordingFailure(error, at: now())
            guard record == nil else { return true }
            pageError = error as? APIError; page = .failed; attempts = previous
            return false
        }
    }
    /// The chain, or 40 §7.2's fallback when it could not be read.
    private func applyChain(_ read: RequestChainRead?, previous: Attempts, ticket: UUID) async {
        switch read {
        case .chain(let chain)?:
            attempts = .chain(chain)
            await onOpsResponse(nil)
        case .failed(.opsDisabled, let error)?:
            attempts = .hidden
            await onOpsResponse(error)
        case .cancelled?: attempts = previous
        case .failed?, nil: await fallback(ticket: ticket)
        }
    }
    /// The detail's `upstream_errors`, with the client's success for a recovered request; ops off hides the section, and without
    /// any detail it says it could not get the chain (40 §7.5).
    private func fallback(ticket: UUID) async {
        guard detail.disabledReason == nil else { attempts = .hidden; return }
        guard let fresh = detail.value else { attempts = .unavailable; return }
        let recovered = style == .recovered
        var success: UsageRequestRecord?
        if recovered, let filter = RequestDetailPresentation.fallbackSuccessFilter(clientRequestID: fresh.record.clientRequestID) {
            let source = source
            let found = await Self.capture { try await source.usageRecord(filter) }
            guard ticket == self.ticket, isCurrent() else { return }
            if case .failure(let error) = found, error is CancellationError { return }
            success = try? found.get()
        }
        let rows = RequestDetailPresentation.fallbackRows(events: fresh.upstreamEvents, success: success, clientSucceeded: recovered)
        attempts = rows.isEmpty ? .hidden : .fallback(rows: rows, dropped: RequestDetailPresentation.fallbackDropped(fresh.upstreamEvents))
    }

    private func showOpsOff() {
        detail = .disabled(reason: AccountUpstreamErrors.opsDisabledReason); attempts = .hidden
        if record == nil { page = .opsDisabled }
    }
    /// A detail that arrived says ops is on, a 404 OPS_DISABLED that it is off; other failures say nothing about the switch.
    private func report(_ result: Result<RequestErrorDetail, any Error>) async {
        switch result {
        case .success: await onOpsResponse(nil)
        case .failure(let error) where AccountUpstreamErrors.isOpsDisabled(error): await onOpsResponse(error)
        case .failure: break
        }
    }
    private func chainID(_ record: RequestErrorRecord) -> String? {
        attemptsSupported ? RequestDetailPresentation.attemptsID(forError: record) : nil
    }

    /// One read, and after 409 one more with the id nearest the row's time when it differs and the route takes it; anything
    /// after that reads as `.useFallback`, never a third request.
    private nonisolated static func readChain(_ source: RequestDetailSource, id: String?, around: Date?) async -> RequestChainRead? {
        guard let id else { return nil }
        let first = await readOnce(source, id: id, around: around)
        guard case .failed(.ambiguous(let ambiguous), let error) = first else { return first }
        guard let closest = ambiguous.closest(to: around), closest != id, RequestAttemptsLookup.isQueryable(closest) else {
            return .failed(.useFallback, error)
        }
        let second = await readOnce(source, id: closest, around: around)
        if case .failed(.ambiguous, let again) = second { return .failed(.useFallback, again) }
        return second
    }
    private nonisolated static func readOnce(_ source: RequestDetailSource, id: String, around: Date?) async -> RequestChainRead {
        do { return .chain(try await source.attempts(id, around)) } catch is CancellationError { return .cancelled } catch {
            return .failed(AttemptsFailure(error), error)
        }
    }
    private static func isGone(_ error: any Error) -> Bool {
        guard let error = error as? APIError else { return false }
        return error.statusCode == 404 && error.reason == "OPS_ERROR_NOT_FOUND"
    }
    private nonisolated static func capture<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}

/// How one chain read ended.
private enum RequestChainRead: Sendable {
    case chain(RequestAttempts)
    case failed(AttemptsFailure, (any Error)?)
    case cancelled
}

private extension RequestDetailModel.Attempts {
    /// A chain or fallback already shown stays while a refresh reads it again.
    var isFilled: Bool {
        switch self {
        case .chain, .fallback: true
        case .hidden, .loading, .unavailable: false
        }
    }
}
