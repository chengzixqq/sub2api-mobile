import SwiftUI
import Sub2Core

/// 10 §3.3 the alert detail's status card: the capsule in the event's alertTone, the big badge with “P1 · 09:29 触发” and the block's
/// status (S1-08) on its right, the rule's name, the figure with its threshold and window, then the silence or how it ended.
/// Identifiers alert.detail.status, .badge, .cause, .ruleName, .metric, .threshold, .silenceNote, .endNote; the placeholder before
/// any event (10 §3.5 骨架) is alert.detail.skeleton.
struct AlertStatusCard<Accessory: View>: View {
    let event: AlertEvent
    let now: Date
    let timeZone: TimeZone
    var isPlaceholder = false
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                ToneBadge(text: AlertPresentation.statusWord(event.status), tone: tone ?? .neutral)
                    .accessibilityIdentifier("alert.detail.badge")
                Text(AlertScopePresentation.cause(event, now: now, timeZone: timeZone))
                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("alert.detail.cause")
                Spacer(minLength: 0)
                accessory
            }
            Text(AlertScopePresentation.ruleName(event))
                .font(.headline).foregroundStyle(Palette.ink1)
                .accessibilityIdentifier("alert.detail.ruleName")
            figure
            notes
        }
        .padding(EdgeInsets(top: 16, leading: StatusCapsuleMetrics.contentLeadingInset + 4, bottom: 16, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .statusCapsule(tone: tone)
        .redacted(reason: isPlaceholder ? .placeholder : [])
        .accessibilityElement(children: isPlaceholder ? .ignore : .contain)
        .accessibilityLabel(Text("正在读取告警…"), isEnabled: isPlaceholder)
        .accessibilityIdentifier(isPlaceholder ? "alert.detail.skeleton" : "alert.detail.status")
    }

    /// 10 §0.6: only a firing event is coloured.
    private var tone: Tone? { isPlaceholder ? nil : AlertPresentation.tone(event) }

    private var figure: some View {
        let metric = AlertScopePresentation.metricText(event)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) { metricText(metric); thresholdText }
            VStack(alignment: .leading, spacing: 2) { metricText(metric); thresholdText }
        }
    }
    private func metricText(_ metric: String) -> some View {
        Text(metric)
            .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
            .foregroundStyle(Palette.ink1)
            .spokenValue(metric)
            .accessibilityIdentifier("alert.detail.metric")
    }
    @ViewBuilder private var thresholdText: some View {
        if let threshold = AlertScopePresentation.thresholdLine(event) {
            Text(threshold).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2)
                .accessibilityIdentifier("alert.detail.threshold")
        }
    }

    @ViewBuilder private var notes: some View {
        if let silence = AlertScopePresentation.silenceNote(event, now: now, timeZone: timeZone) {
            Text(silence).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                .accessibilityIdentifier("alert.detail.silenceNote")
        }
        if let ended = AlertScopePresentation.endNote(event, now: now, timeZone: timeZone) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle").accessibilityHidden(true)
                Text(ended).accessibilityIdentifier("alert.detail.endNote")
            }
            .font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
        }
    }
}

/// 10 §3.3 按钮行, only while firing: 「手动解决」 (primary) and 「静默…」 or 「改静默时长…」, as AlertActions offers them; the whole row is
/// greyed for a read-only token (C-1, X10) and waits while a write of this event is on its way. Identifiers alert.detail.resolve,
/// alert.detail.silence.
struct AlertDetailActions: View {
    let actions: [AlertActionKind]
    let isRunning: Bool
    let onAction: (AlertActionKind) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if actions.contains(.resolve) {
                Button("手动解决", systemImage: "checkmark") { onAction(.resolve) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("alert.detail.resolve")
            }
            if let silence = actions.first(where: { $0 != .resolve }) {
                Button(silence == .silence ? "静默…" : "改静默时长…", systemImage: "hourglass") { onAction(silence) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("alert.detail.silence")
            }
        }
        .controlSize(.large)
        .disabled(isRunning)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readOnlyGate()
    }
}
