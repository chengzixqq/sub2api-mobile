import SwiftUI
import Sub2Core

/// 20 §2.3 状态卡 (design `detail-head` hero): a quiet line for 正常 / 暂停 / 停用; for 错误 and the timed states the big badge
/// with its cause, the countdown and “后自动恢复 · 预计 HH:MM” or the error text, the `errorFooter` slot (S2-09's “最近上游错误”
/// row), the schedule note and the model limits. States use the site clock (20 §0.6) and redraw every second while anything
/// counts down; absolute times use the server's zone.
struct AccountStatusCard<ErrorFooter: View>: View {
    let account: UpstreamAccount
    private let errorFooter: () -> ErrorFooter
    @Environment(\.sessionContext) private var session

    init(account: UpstreamAccount, @ViewBuilder errorFooter: @escaping () -> ErrorFooter) {
        self.account = account; self.errorFooter = errorFooter
    }

    var body: some View {
        let current = content(at: Date())
        if current.countdownTarget != nil || !current.modelLimits.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in card(content(at: timeline.date)) }
        } else {
            card(current)
        }
    }

    @ViewBuilder private func card(_ content: AccountStatusCardContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch content.style {
            case .quiet: AccountQuietStatus(content: content)
            case .alert: alert(content)
            }
            if let title = content.modelLimitsTitle {
                AccountModelLimitsBlock(title: title, rows: content.modelLimits).padding(.top, content.style == .quiet ? 12 : 14)
            }
        }
        .padding(content.style == .quiet ? EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
                 : EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .statusCapsule(tone: content.style == .alert ? content.tone : nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.detail.card")
    }

    @ViewBuilder private func alert(_ content: AccountStatusCardContent) -> some View {
        HStack(spacing: 8) {
            AccountBigStatusBadge(state: content.state, title: content.title)
            Spacer(minLength: 4)
            if let cause = content.cause {
                Text(cause).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1)
                    .accessibilityIdentifier("account.detail.card.cause")
            }
        }
        if let countdown = content.countdown {
            Text(countdown)
                .font(.system(size: 46, weight: .semibold)).monospacedDigit().foregroundStyle(content.tone.ink)
                .padding(.top, 10)
                .accessibilityIdentifier("account.detail.countdown")
            if let note = content.resumeNote {
                Text(note).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2).padding(.top, 4)
                    .accessibilityIdentifier("account.detail.resume-note")
            }
        } else if let text = content.errorBody {
            Text(text).font(.body).foregroundStyle(Palette.ink1).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                .accessibilityIdentifier("account.detail.error-body")
        }
        errorFooter()
        if let note = content.scheduleNote { AccountScheduleNoteLine(note: note) }
    }

    private func content(at local: Date) -> AccountStatusCardContent {
        AccountDetailPresentation.statusCard(account, now: local.addingTimeInterval(session?.client.serverClock.offset ?? 0),
                                             timeZone: session?.site.serverTimeZone.timeZone ?? .current)
    }
}

extension AccountStatusCard where ErrorFooter == EmptyView {
    init(account: UpstreamAccount) { self.init(account: account) { EmptyView() } }
}

/// Design `hero-quiet`: the state glyph and one line.
private struct AccountQuietStatus: View {
    let content: AccountStatusCardContent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: AccountRowPresentation.systemImage(for: content.state))
                .font(.system(size: content.state == .available ? 9 : 16, weight: .semibold))
                .foregroundStyle(content.tone.base)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(content.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink1)
                .accessibilityIdentifier("account.detail.card.title")
        }
    }
}

/// The big badge of `hero-top`: the state's icon and word on its wash.
private struct AccountBigStatusBadge: View {
    let state: AccountScheduleState
    let title: String
    @ScaledMetric(relativeTo: .subheadline) private var height = 28.0

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: AccountRowPresentation.systemImage(for: state)).accessibilityHidden(true)
            Text(title).accessibilityIdentifier("account.detail.card.title")
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(state.tone.ink)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(minHeight: height)
        .background(state.tone.wash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Design `hero-sched`: a hairline above, the pause glyph, the bold mark and its detail.
private struct AccountScheduleNoteLine: View {
    let note: AccountStatusCardContent.ScheduleNote

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "pause.fill").font(.footnote).foregroundStyle(Tone.neutral.ink).accessibilityHidden(true)
                Text("\(Text(note.emphasis).fontWeight(.semibold).foregroundStyle(Palette.ink1)) · \(note.detail)")
                    .font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account.detail.schedule-note")
    }
}

/// Design `hero-models`: “模型限流 N” in the model tone, then each model (monospaced) and its time left.
private struct AccountModelLimitsBlock: View {
    let title: String
    let rows: [AccountStatusCardContent.ModelLimitRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "cube").accessibilityHidden(true)
                Text(title).accessibilityIdentifier("account.detail.model-limits.title")
            }
            .font(.footnote.weight(.semibold)).foregroundStyle(Tone.model.ink)
            ForEach(rows, id: \.model) { row in
                HStack {
                    Text(row.model).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink1).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(row.remaining).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("account.detail.model-limit.\(row.model)")
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.detail.model-limits")
    }
}

/// 20 §2.3 按钮行 (design `.actions` / `.act`): equal capsules, the primary filled with the accent. The running action shows a
/// spinner in place of its icon but still takes taps; the caller disables the row while a write runs. Each button is greyed on
/// its own for a read-only token (C-1), with one “只读令牌” line under the row.
struct AccountActionButtonRow: View {
    let row: AccountDetailActionRow
    let running: AccountDetailAction?
    let perform: (AccountDetailAction) -> Void
    @Environment(\.sessionContext) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ForEach(row.actions) { action in
                    AccountActionButton(action: action, isPrimary: action == row.primary, isRunning: running == action) { perform(action) }
                        .readOnlyGate(showsCaption: false)
                }
            }
            if session?.isReadOnlyToken == true {
                Text(ReadOnlyGate.caption).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("readonly.caption")
            }
        }
    }
}

private struct AccountActionButton: View {
    let action: AccountDetailAction
    let isPrimary: Bool
    let isRunning: Bool
    let perform: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var height = 46.0
    @ScaledMetric(relativeTo: .body) private var size = 15.5

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                if isRunning { ProgressView().tint(isPrimary ? Palette.onAccent : Palette.ink1) }
                else { Image(systemName: action.systemImage).font(.system(size: size * 0.9, weight: .semibold)) }
                Text(action.title).font(.system(size: size, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(isPrimary ? Palette.onAccent : Palette.ink1)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(isPrimary ? Palette.accentFill : Palette.surface, in: Capsule())
            .overlay { if !isPrimary { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier("account.action.\(action.rawValue)")
    }
}
