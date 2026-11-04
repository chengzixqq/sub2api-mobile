import SwiftUI
import Sub2Core

/// 60 §6: the account's access tokens, listed and revoked. The App issues none (U02), so there is no + and no sheet. A
/// read-only token may revoke only itself (00 §2.6.3); revoking this App's own token ends the session through
/// AppModel.revokeAccessToken. A failed reload keeps the older list under “刷新失败 · 重试” (00 §4.6). No step-up, no
/// idempotency key, no polling.
struct AccessTokensView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var list = LoadState<[AdminAccessToken]>()
    /// Revoked rows stay hidden even when a later reload fails and the older list is shown.
    @State private var removedIDs: Set<Int> = []
    @State private var confirming: AdminAccessToken?
    @State private var revokingID: Int?
    private static let refreshFailedText = "刷新失败 · 重试"

    var body: some View {
        content
            .navigationTitle("管理访问令牌")
            .navigationSubtitle(model.activeProfile?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task { await reload() }
            // A read stopped by the background is read again on return (D18).
            .onChange(of: model.foregroundRevision) { _, _ in Task { await reload() } }
            .confirmationDialog(confirming?.revokeTitle ?? "", isPresented: confirmingBinding, titleVisibility: .visible,
                                presenting: confirming) { token in
                Button(AdminAccessToken.revokeActionTitle, role: .destructive) { Task { await revoke(token) } }
                    .accessibilityIdentifier("accessTokens.confirm")
            } message: { token in Text(token.revokeMessage) }
    }

    private var shownTokens: [AdminAccessToken] { (list.value ?? []).filter { !removedIDs.contains($0.id) } }
    private var confirmingBinding: Binding<Bool> { Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }) }
    /// 00 §2.6.3: the server lets a read-only token delete only itself.
    private func canRevoke(_ token: AdminAccessToken) -> Bool { !(session?.isReadOnlyToken ?? false) || token.current }

    @ViewBuilder private var content: some View {
        switch list.state.display {
        case .placeholder:
            ProgressView("正在读取访问令牌…").frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("accessTokens.loading")
        case .failed(let reason):
            FailureView(message: reason ?? "") { Task { await reload() } }
        case .value(_, let at, _, let updateFailed):
            tokenList(updateFailed: updateFailed, updatedAt: at)
        case .disabled:
            tokenList(updateFailed: false, updatedAt: nil)
        }
    }

    private func tokenList(updateFailed: Bool, updatedAt: Date?) -> some View {
        let tokens = shownTokens
        let now = session?.client.serverClock.now() ?? Date()
        let zone = session?.site.serverTimeZone ?? .device
        return List {
            Section {
                Text(AdminAccessToken.intro).font(.subheadline).foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("accessTokens.intro")
            }
            if updateFailed { refreshFailedBanner(updatedAt: updatedAt, zone: zone) }
            Section {
                if tokens.isEmpty { emptyState } else { ForEach(tokens) { row($0, now: now, zone: zone) } }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await reload() }
        .accessibilityIdentifier("accessTokens.list")
    }

    private var emptyState: some View {
        ContentUnavailableView(AdminAccessToken.emptyTitle, systemImage: "key", description: Text(AdminAccessToken.emptyMessage))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("accessTokens.empty")
            .listRowBackground(Color.clear)
    }

    /// The time of the list shown, in the site's clock and zone like the rows; tapping reads the list again.
    private func refreshFailedBanner(updatedAt: Date?, zone: ServerTimeZone) -> some View {
        let shown = updatedAt.map { $0.addingTimeInterval(session?.site.clockOffset ?? 0) }
        let detail = shown.map { "更新于 " + DisplayFormat.clock($0, timeZone: zone.timeZone) }
        return Section {
            Button { Task { await reload() } } label: {
                StatusBanner(tone: .caution, systemImage: "exclamationmark.triangle", title: Self.refreshFailedText, detail: detail)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(list.isLoading)
            .accessibilityLabel([Self.refreshFailedText, detail].compactMap { $0 }.joined(separator: "，"))
            .accessibilityIdentifier("accessTokens.refreshFailed")
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private func row(_ token: AdminAccessToken, now: Date, zone: ServerTimeZone) -> some View {
        let usage = token.usageLine(now: now, timeZone: zone), expiry = token.expiryLine(now: now, timeZone: zone)
        let isExpiringSoon = token.isExpiringSoon(now: now, timeZone: zone)
        let parts: [String?] = [token.displayName, token.scopeTitle, token.current ? AdminAccessToken.currentBadgeText : nil, token.maskedText,
                                usage, DisplayFormat.spoken(expiry)]
        let content = AccessTokenRow(token: token, usage: usage, expiry: expiry, isExpiringSoon: isExpiringSoon, isRevoking: revokingID == token.id)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(parts.compactMap { $0 }.joined(separator: "，"))
            .accessibilityValue(isExpiringSoon ? "即将到期" : "")
            .accessibilityIdentifier("accessTokens.row.\(token.id)")
        if canRevoke(token) {
            content.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // A tint rather than the destructive role, which would start removing the row before the confirmation.
                Button(AdminAccessToken.revokeActionTitle) { confirming = token }
                    .tint(Tone.critical.base)
                    .disabled(revokingID != nil)
                    .accessibilityIdentifier("accessTokens.row.\(token.id).revoke")
            }
        } else {
            content
        }
    }

    private func reload() async {
        guard let context = session, context.generation == model.sessionGeneration else { return }
        let source = AccessTokensSource(model: model, context: context)
        await list.load(isCurrent: { context.generation == model.sessionGeneration }) { try await source.list() }
    }

    /// 60 §6.4: the row goes with a receipt, also when it was gone already; this App's own token ends the session instead.
    private func revoke(_ token: AdminAccessToken) async {
        guard let context = session, context.generation == model.sessionGeneration, revokingID == nil else { return }
        revokingID = token.id
        // Throws only when the session ended meanwhile.
        let outcome = try? await model.revokeAccessToken(token, context: context)
        revokingID = nil
        guard let outcome, context.generation == model.sessionGeneration else { return }
        switch outcome.kind {
        case .revoked, .alreadyGone:
            removedIDs.insert(token.id)
            model.receipts.show(Receipt(text: AdminAccessToken.revokedReceipt(token.displayName)))
            await reload()
        case .revokedCurrent:
            return
        case .failed:
            // An ended session is the client's to report: the page is about to give way to the login page.
            if let failure = outcome.failure, SessionInvalidation(error: failure) == nil { model.report(failure) }
        }
    }
}

/// Name with the scope and 本机 badges, the masked token, its last use and its expiry (60 §6.3).
private struct AccessTokenRow: View {
    let token: AdminAccessToken
    let usage: String
    let expiry: String
    let isExpiringSoon: Bool
    let isRevoking: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(token.displayName).font(.headline).foregroundStyle(Palette.ink1).lineLimit(1)
                    ToneBadge(text: token.scopeTitle, tone: token.scopeTone)
                    if token.current { ToneBadge(text: AdminAccessToken.currentBadgeText, tone: .neutral) }
                }
                Text(token.maskedText).font(.subheadline.monospaced()).foregroundStyle(Palette.ink2).lineLimit(1)
                Text(usage).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1)
                Text(expiry).font(.footnote).foregroundStyle(isExpiringSoon ? Tone.caution.ink : Palette.ink3).lineLimit(1)
            }
            Spacer(minLength: 8)
            if isRevoking { ProgressView() }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The endpoint, or the `-ui-testing` fixture in SettingsModuleFixtures.
private struct AccessTokensSource: Sendable {
    let model: AppModel
    let context: SessionContext

    @MainActor func list() async throws -> [AdminAccessToken] {
        guard model.isUITesting else { return try await context.client.accessTokens() }
        return try DemoData.accessTokens(context: context)
    }
}
