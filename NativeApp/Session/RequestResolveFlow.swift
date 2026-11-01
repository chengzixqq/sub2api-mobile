import Foundation
import Observation
import os
import Sub2Core

/// 40 §7.4's write, and the detail read the page also uses, for the read-back (S4D2a-08). RequestResolveControls picks the site
/// or, under `-ui-testing`, LogFixtures+Detail.
struct RequestResolveSource: Sendable {
    let setResolved: @Sendable (_ id: Int, _ kind: ErrorLogKind, _ resolved: Bool) async throws -> Void
    let errorDetail: @Sendable (_ id: Int, _ kind: ErrorLogKind) async throws -> RequestErrorDetail

    init(detail: RequestDetailSource, setResolved: @escaping @Sendable (_ id: Int, _ kind: ErrorLogKind, _ resolved: Bool) async throws -> Void) {
        self.setResolved = setResolved
        errorDetail = detail.errorDetail
    }
    /// R19's `setErrorResolved` (no Idempotency-Key, never resent on its own) and the page's own detail read.
    static func live(_ client: APIClient, site: SiteSession) -> RequestResolveSource {
        RequestResolveSource(detail: .live(client, site: site)) { try await client.setErrorResolved(id: $0, kind: $1, resolved: $2) }
    }
}

/// 40 §7.4 标记已处理 of a failed request. The button changes at once; marking says “已标记为已处理” with 撤销 (which sends
/// resolved=false), taking it back says nothing (the decided design). One write at a time: taps meanwhile only change what is
/// wanted, and the running write sends the last of them next. A write that got no answer is never sent again: the detail read
/// back decides (00 §2.4). A refusal puts the server's value back with its words; 404 OPS_ERROR_NOT_FOUND greys the button for
/// good. A read-only token sends nothing and changes nothing (S4D1-13). When the server's value moved, `onSettled` updates the
/// list rows in place. A result for an ended session is dropped.
@MainActor @Observable
final class RequestResolveFlow {
    let errorID: Int
    let kind: ErrorLogKind
    /// What the button shows, this phone's wish included; nil until the row or the detail arrives.
    private(set) var record: RequestErrorRecord?
    private(set) var isSending = false
    private(set) var isGone = false
    /// Moves when a write goes out and when it ends; RequestDetailModel keeps it with each detail it reads (`detailEpoch`).
    @ObservationIgnored private(set) var writeEpoch = 0
    var isResolved: Bool { record?.resolved ?? false }
    var canToggle: Bool { record != nil && !isGone }

    /// The server's value as far as this phone knows.
    @ObservationIgnored private var confirmed: RequestErrorRecord?
    @ObservationIgnored private let source: RequestResolveSource
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let isReadOnly: @MainActor () -> Bool
    @ObservationIgnored private let onSettled: @MainActor (RequestErrorRecord) -> Void
    private static let log = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "logs")

    private enum Outcome {
        case landed(RequestErrorRecord)
        case failed(String)
        /// Cancelled, or the security prompt was closed: back to the server's value without a word.
        case quiet
        case sessionEnded
    }

    init(errorID: Int, kind: ErrorLogKind, record: RequestErrorRecord?, source: RequestResolveSource, receipts: ReceiptCenter,
         isCurrent: @escaping @MainActor () -> Bool, isReadOnly: @escaping @MainActor () -> Bool,
         onSettled: @escaping @MainActor (RequestErrorRecord) -> Void) {
        self.errorID = errorID; self.kind = kind; self.record = record; confirmed = record
        self.source = source; self.receipts = receipts
        self.isCurrent = isCurrent; self.isReadOnly = isReadOnly; self.onSettled = onSettled
    }

    /// A detail arrived: it is the server's value, unless a write is on its way or went out or ended after the read did
    /// (`epoch` is `writeEpoch` as the read went out): the write's own answer counts, the next read brings who and when.
    func adopt(_ record: RequestErrorRecord, readAt epoch: Int) {
        guard !isSending, epoch == writeEpoch else { return }
        self.record = record
        confirmed = record
    }
    /// The button: 标记已处理, or take 已处理 back.
    func toggle() async { await want(!isResolved) }
    /// The receipt's 撤销.
    func undo() async { await want(false) }

    private func want(_ resolved: Bool) async {
        guard isCurrent(), !isReadOnly(), canToggle, let shown = record, shown.resolved != resolved else { return }
        record = shown.settingResolved(resolved)
        if resolved {
            receipts.show(Receipt(text: RequestDetailCopy.marked, systemImage: "checkmark.circle", undo: { [self] in Task { await self.undo() } }))
        }
        guard !isSending else { return }
        guard let start = confirmed else { return }
        isSending = true; writeEpoch += 1
        let isLive = await sendWanted()
        isSending = false; writeEpoch += 1
        guard isLive, let confirmed, confirmed.resolved != start.resolved else { return }
        onSettled(confirmed)
    }

    /// Writes until the server holds what is wanted or a write fails. false: the session ended, so nothing more is touched.
    private func sendWanted() async -> Bool {
        while let wanted = record?.resolved, let known = confirmed, wanted != known.resolved {
            switch await write(wanted, over: known) {
            case .landed(let fresh):
                confirmed = fresh
                if record?.resolved == fresh.resolved { record = fresh }
            case .failed(let text):
                record = confirmed
                receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .caution))
                return true
            case .quiet:
                record = confirmed
                return true
            case .sessionEnded:
                return false
            }
        }
        return true
    }

    private func write(_ wanted: Bool, over known: RequestErrorRecord) async -> Outcome {
        let source = source, id = errorID, kind = kind
        do {
            try await source.setResolved(id, kind, wanted)
            return isCurrent() ? .landed(known.settingResolved(wanted)) : .sessionEnded
        } catch {
            guard isCurrent() else { return .sessionEnded }
            guard let failure = RequestResolveFailure(error) else { return .quiet }
            switch failure {
            case .resultUnknown: return await readBack(wanted)
            case .gone: isGone = true
            case .programError: logProgramError(error)
            case .opsDisabled, .readOnly, .rateLimited, .refused: break
            }
            return .failed(RequestDetailCopy.failureText(failure, marking: wanted))
        }
    }
    /// 00 §2.4: no answer came, so the detail says whether the write landed; the write itself is not sent again.
    private func readBack(_ wanted: Bool) async -> Outcome {
        let source = source, id = errorID, kind = kind
        do {
            let fresh = try await source.errorDetail(id, kind).record
            guard isCurrent() else { return .sessionEnded }
            return fresh.resolved == wanted ? .landed(fresh) : .failed(RequestDetailCopy.failureText(.resultUnknown, marking: wanted))
        } catch {
            guard isCurrent() else { return .sessionEnded }
            switch RequestResolveFailure(error) {
            case .gone?:
                isGone = true
                return .failed(RequestDetailCopy.resolveGone)
            case .opsDisabled?: return .failed(RequestDetailCopy.resolveOpsDisabled)
            default: return .failed(RequestDetailCopy.unconfirmed)
            }
        }
    }
    private func logProgramError(_ error: any Error) {
        guard let api = error as? APIError else { return }
        let route = "PUT \(kind.opsPath)/:id/resolve", requestID = api.requestID ?? "-"
        Self.log.error("\(route, privacy: .public) \(api.statusCode ?? 0, privacy: .public) \(api.reason ?? "-", privacy: .public) X-Request-ID \(requestID, privacy: .public)")
    }
}
