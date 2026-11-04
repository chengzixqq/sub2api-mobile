import SwiftUI
import Sub2Core

/// 20 §1.3 (S2-22): a platform header's alert, its own button after the title (design useVaAlert): the level's badge with a thin
/// edge in its tone, 44pt to touch without making the header taller. Identifier accounts.section.<platform>.alert.
struct AccountAlertBadgeButton: View {
    let badge: AccountAlertBadge
    let platform: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            ToneBadge(text: badge.text, tone: badge.tone)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(badge.tone.ink.opacity(0.22), lineWidth: 1)
                }
                .padding(.horizontal, 2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .padding(.vertical, -11)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.accessibilityLabel)
        .accessibilityIdentifier("accounts.section.\(platform).alert")
    }
}

/// 20 §1.4 the 告警 sheet over the account list: the event card, 维度 and 状态, the note, 手动解决 and 静默… (改静默时长…) through
/// 10 §7.1's AlertActions (its dialogs, receipts, undo and error words), then 只看需处理的账号 › and 告警详情 ›. It shows the session's
/// live copy of the event. A write started here that the store then shows (the event left the firing list, or its silence
/// changed) closes the sheet; a failure keeps it open, with the receipt drawn over it since the tab's own is under the sheet.
/// Identifiers accounts.alert.sheet, .close, .card, .title, .level, .detail, .scope, .status, .note, .resolve, .silence, .needs,
/// .detailLink.
struct AccountAlertSheet: View {
    let event: AlertEvent
    let catalog: MetaCatalog
    let onShowNeeds: @MainActor () -> Void
    let onOpenDetail: @MainActor () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var request: AlertActionRequest?
    /// The event as it was when this sheet's write started.
    @State private var writeBase: AlertEvent?
    /// The last live copy, kept once the event leaves the list.
    @State private var lastSeen: AlertEvent?

    var body: some View {
        let shown = live ?? lastSeen ?? event
        let content = AccountAlertMatch.sheetContent(shown, now: now, timeZone: timeZone, platformName: platformName,
                                                     latencyMetricsSupported: session?.has(.opsAlertLatencyMetrics) == true)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AccountAlertCard(content: content)
                    facts(content)
                    Text(AccountAlertMatch.note)
                        .font(.footnote).foregroundStyle(Palette.ink2)
                        .accessibilityIdentifier("accounts.alert.note")
                    actionRow(shown)
                    VStack(spacing: 0) {
                        link(AccountAlertMatch.showNeedsTitle, id: "accounts.alert.needs", action: onShowNeeds)
                        link(AccountAlertMatch.detailLinkTitle, id: "accounts.alert.detailLink", action: onOpenDetail)
                    }
                }
                .padding(20)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("accounts.alert.sheet")
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.sheetBackground)
            .navigationTitle(AccountAlertMatch.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.accessibilityIdentifier("accounts.alert.close")
                }
            }
            .alertActions($request)
        }
        .overlay(alignment: .bottom) { ReceiptOverlay() }
        .presentationDetents([.medium, .large])
        .onChange(of: live) { _, fresh in if let fresh { lastSeen = fresh } }
        .onChange(of: isRunning) { wasRunning, running in if wasRunning, !running { writeEnded() } }
    }

    private var live: AlertEvent? { model.liveOps?.firingAlerts.first { $0.id == event.id } }
    private var isRunning: Bool { model.liveOps?.alertActions.isRunning(event.id) ?? false }
    private var now: Date { session?.client.serverClock.now() ?? Date() }
    private var timeZone: TimeZone { session?.site.serverTimeZone.timeZone ?? .current }
    /// The rule's filter as written; the catalog knows ids in lower case.
    private func platformName(_ platform: String) -> String { AccountNaming.platformName(platform.lowercased(), catalog: catalog) }

    /// A failure keeps the base, so 重试 on its receipt still closes the sheet once it goes through.
    private func writeEnded() {
        guard let base = writeBase, AccountAlertMatch.actionTookEffect(before: base, after: live) else { return }
        writeBase = nil
        dismiss()
    }

    private func facts(_ content: AccountAlertSheetContent) -> some View {
        VStack(spacing: 0) {
            fact("维度", content.scope, id: "accounts.alert.scope")
            Divider().overlay(Palette.hairline).padding(.leading, 14)
            fact("状态", content.status, id: "accounts.alert.status")
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func fact(_ label: String, _ value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().foregroundStyle(Palette.ink1).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    /// 10 §3.3's button row (S1-12), as AlertActions offers the event's actions; greyed for a read-only token inside it (C-1).
    @ViewBuilder private func actionRow(_ shown: AlertEvent) -> some View {
        if let actions = model.liveOps?.alertActions {
            AlertDetailActions(actions: actions.availableActions(for: shown), isRunning: actions.isRunning(shown.id),
                               identifierPrefix: "accounts.alert") { kind in
                writeBase = shown
                request = AlertActionRequest(event: shown, kind: kind)
            }
        }
    }

    private func link(_ title: String, id: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).accessibilityHidden(true)
            }
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Design `va-alert-card`: the status capsule in the event's tone, the title with the level's badge, then scope · rule.
private struct AccountAlertCard: View {
    let content: AccountAlertSheetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(content.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("accounts.alert.title")
                ToneBadge(text: content.level, tone: content.tone).accessibilityIdentifier("accounts.alert.level")
            }
            Text(content.detail).font(.footnote).foregroundStyle(Palette.ink2)
                .accessibilityIdentifier("accounts.alert.detail")
        }
        .padding(EdgeInsets(top: 12, leading: StatusCapsuleMetrics.contentLeadingInset + 1, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1) }
        .statusCapsule(tone: content.tone)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accounts.alert.card")
    }
}
