import Foundation
import Observation
import Sub2Core

/// 60 §13.4: the page's three calls. The client in the App, an in-memory site under -ui-testing, stubs in tests.
struct ProxyFallbackEndpoints: Sendable {
    let accounts: @Sendable (Int) async throws -> [ProxyFallbackAccount]
    let proxy: @Sendable (Int) async throws -> AdminProxy
    let revert: @Sendable (Int, [Int]) async throws -> ProxyFallbackRevertResult

    static func live(_ client: APIClient) -> ProxyFallbackEndpoints {
        ProxyFallbackEndpoints(accounts: { try await client.proxyFallbackAccounts(id: $0) }, proxy: { try await client.proxy(id: $0) },
                               revert: { try await client.revertProxyFallback(id: $0, accountIDs: $1) })
    }
}

enum ProxyFallbackOutcome: Sendable, Equatable {
    /// Nothing failed (some may have been skipped).
    case reverted
    /// Some failed; the page lists them.
    case partial
    case originUnavailable
    case proxyGone
    /// The reply was lost and the list read back.
    case unconfirmed
    case failed
    /// Face ID was refused: nothing sent, nothing said.
    case denied
    /// The proxy is not active or has expired (or is unknown): nothing sent.
    case blocked
    /// Running already, unsupported, cancelled, or the session ended.
    case ignored
}

/// 60 §13.4 被改走的账号: the accounts the proxy's expiry moved off it and the proxy itself, read side by side on entry, on pull
/// and back in the foreground. 全部恢复 (after Face ID for a batch, 60 §3.4) or one row's 恢复 is sent once without a key: the
/// server skips what is no longer moved off, so a lost reply is read back rather than resent (00 §2.4, H03). Afterwards the
/// page, the session's catalog row (the list and the detail) and, when something was restored, the account list are refreshed.
@MainActor @Observable
final class ProxyFallbackAccountsModel {
    let proxyID: Int
    private(set) var proxy: AdminProxy?
    private(set) var accounts: BlockState<[ProxyFallbackAccount]> = .idle
    /// The last revert's failed accounts; cleared when the next one starts.
    private(set) var failures: [ProxyFallbackFailureLine] = []
    private(set) var isGone = false
    /// No `proxies.fallback_accounts`, or the list answered a non-JSON 404.
    private(set) var isUnsupported = false
    private(set) var running: ProxyFallbackScope?

    @ObservationIgnored private let isSupported: Bool
    @ObservationIgnored private let endpoints: ProxyFallbackEndpoints
    @ObservationIgnored private let store: ProxyStore?
    @ObservationIgnored private let accountSignal: AccountListSignal?
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let authorize: @MainActor (GatedAction) async -> Bool
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var ticket = UUID()

    init(proxyID: Int, seed: AdminProxy?, isSupported: Bool, endpoints: ProxyFallbackEndpoints, store: ProxyStore?, accountSignal: AccountListSignal?,
         receipts: ReceiptCenter, authorize: @escaping @MainActor (GatedAction) async -> Bool, isCurrent: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date) {
        self.proxyID = proxyID; proxy = seed; self.isSupported = isSupported; self.endpoints = endpoints; self.store = store
        self.accountSignal = accountSignal; self.receipts = receipts; self.authorize = authorize; self.isCurrent = isCurrent; self.now = now
        isUnsupported = !isSupported
    }

    var proxyName: String { ProxyFallbackPresentation.proxyName(proxy, id: proxyID) }
    /// 全部恢复 and the swipes: only onto an active proxy that has not expired (`now` is the server's clock).
    var canRevert: Bool { proxy.map { ProxyFallbackPresentation.canRevert($0, now: now()) } ?? false }

    func load() async { _ = await refresh() }

    /// The caller has confirmed. Face ID for 全部恢复 only; the write goes out once.
    @discardableResult func revert(_ scope: ProxyFallbackScope) async -> ProxyFallbackOutcome {
        guard running == nil, isSupported, !isUnsupported, !isGone, isCurrent() else { return .ignored }
        guard canRevert else { return .blocked }
        running = scope
        defer { running = nil }
        if scope == .all {
            guard await authorize(.batch) else { return .denied }
            guard isCurrent() else { return .ignored }
        }
        failures = []
        let rows = accounts.value ?? []
        let names = Self.names(rows)
        let targets = scope == .all ? rows.map(\.id) : scope.accountIDs
        let name = proxyName
        do {
            let result = try await endpoints.revert(proxyID, scope.accountIDs)
            guard isCurrent() else { return .ignored }
            return await finish(result, names: names, proxyName: name)
        } catch {
            guard isCurrent() else { return .ignored }
            return await fail(error, scope: scope, targets: targets, proxyName: name)
        }
    }

    // MARK: - Reads

    /// Both reads; the accounts when that read landed, nil otherwise. A failed refresh keeps the rows shown (00 §4.6).
    private func refresh() async -> [ProxyFallbackAccount]? {
        guard isSupported, !isUnsupported, !isGone, isCurrent() else { return nil }
        let ticket = UUID()
        self.ticket = ticket
        accounts = accounts.withLoading()
        let endpoints = endpoints, id = proxyID
        async let listRead = Self.capture { try await endpoints.accounts(id) }
        async let proxyRead = Self.capture { try await endpoints.proxy(id) }
        let (list, fresh) = await (listRead, proxyRead)
        guard ticket == self.ticket else { return nil }
        guard isCurrent(), !Task.isCancelled else { accounts = accounts.withCancelledLoad(); return nil }
        if case .failure(let error) = fresh, ProxyDetailFailure.isGone(error) { markGone(); return nil }
        if case .success(let row) = fresh { adopt(row) }
        switch list {
        case .success(let rows):
            accounts = .loaded(rows, at: now())
            return rows
        case .failure(let error) where error is CancellationError: accounts = accounts.withCancelledLoad()
        case .failure(let error) where ProxyDetailFailure.isGone(error): markGone()
        case .failure(let error) where (error as? APIError)?.kind == .unsupported:
            isUnsupported = true
            accounts = .idle
        case .failure(let error): accounts = accounts.withFailure(error.localizedDescription)
        }
        return nil
    }
    /// An older server's read without counts keeps the ones shown (H02); the catalog row follows.
    private func adopt(_ fresh: AdminProxy) {
        let row = fresh.keepingCounts(of: proxy)
        proxy = row
        store?.replace(row)
    }
    private func markGone() {
        ticket = UUID()
        isGone = true
        accounts = .idle
        store?.remove(id: proxyID)
    }

    // MARK: - After the write

    /// The receipt at once, then the page read again; a failed account no longer listed may have been restored after all.
    private func finish(_ result: ProxyFallbackRevertResult, names: [Int: String], proxyName: String) async -> ProxyFallbackOutcome {
        show(ProxyFallbackPresentation.receipt(result, proxyName: proxyName))
        if !result.revertedIDs.isEmpty { accountSignal?.bump() }
        let listed = await refresh()
        guard isCurrent() else { return .ignored }
        let known = names.merging(Self.names(listed ?? [])) { old, _ in old }
        failures = ProxyFallbackPresentation.failureLines(result, names: known, stillListed: listed.map { Set($0.map(\.id)) })
        return result.failed.isEmpty ? .reverted : .partial
    }
    private func fail(_ error: any Error, scope: ProxyFallbackScope, targets: [Int], proxyName: String) async -> ProxyFallbackOutcome {
        if ProxyFallbackPresentation.isOriginUnavailable(error) {
            show(ProxyFallbackNotice(text: ProxyFallbackPresentation.originUnavailable, tone: .critical))
            await load()
            return .originUnavailable
        }
        let failure = ProxyDetailFailure.classify(error)
        switch failure {
        case .cancelled: return .ignored
        case .gone:
            markGone()
            return .proxyGone
        case .unconfirmed: return await readBack(scope, targets: targets, proxyName: proxyName)
        case .reconfirm, .rejected:
            ProxyStatusWrite.report(failure, to: receipts, rejected: ProxyFallbackPresentation.rejectedText)
            return .failed
        }
    }
    /// 00 §2.4: none of the accounts sent listed any more → restored; some still listed or the list unreadable → 重试 sends
    /// the same scope again (the server skips what it already restored).
    private func readBack(_ scope: ProxyFallbackScope, targets: [Int], proxyName: String) async -> ProxyFallbackOutcome {
        let remaining = await refresh()
        guard isCurrent() else { return .ignored }
        if isGone { return .proxyGone }
        guard let remaining else {
            show(ProxyFallbackNotice(text: ProxyDetailCopy.unconfirmed, tone: .caution), retry: scope)
            return .unconfirmed
        }
        let readback = ProxyFallbackPresentation.readback(targets: targets, remaining: remaining)
        let notice = ProxyFallbackPresentation.readbackReceipt(readback, proxyName: proxyName)
        if case .confirmed = readback {
            show(notice)
            accountSignal?.bump()
        } else {
            show(notice, retry: scope)
        }
        return .unconfirmed
    }

    private func show(_ notice: ProxyFallbackNotice, retry scope: ProxyFallbackScope? = nil) {
        let action = scope.map { scope in
            ReceiptAction(title: ProxyFallbackPresentation.retry) { [weak self] in
                Task { @MainActor in await self?.revert(scope) }
            }
        }
        receipts.show(Receipt(text: notice.text, systemImage: notice.systemImage, tone: notice.tone, action: action))
    }
    private static func names(_ rows: [ProxyFallbackAccount]) -> [Int: String] {
        Dictionary(rows.map { ($0.id, ProxyFallbackPresentation.rowName($0)) }) { first, _ in first }
    }
    private nonisolated static func capture<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}

extension ProxyAccess {
    /// 60 §0.3: restoring moved accounts changes accounts, so a vendor (U01, kept for later) needs `account_manage` on top of
    /// `proxy_manage`; a read-only token never does.
    static func canRevertFallback(me: AdminMe?, isReadOnlyToken: Bool) -> Bool {
        guard canManage(me: me, isReadOnlyToken: isReadOnlyToken) else { return false }
        guard let workspace = me?.workspace else { return true }
        return workspace.permissions?.accountManage == true
    }
}
