import SwiftUI
import Sub2Core

/// C-6, 10 §1.3.3 and §6.3: one alert event as a row on the status rail, for the overview's 待处理 (home) and the monitor's alerts
/// segment (S1-16). Home: a bell, the level as the badge and “阈值 5.0% · 12 分钟前触发 · 已静默”. Monitor: “P1 · 告警中”, the scope
/// and rule unclipped, the silence and the time; an event no longer firing has no capsule, a check mark and a grey title. With
/// `onOpen` the row is one button. A firing monitor row with `showsActions` and `onAction` also has 静默… / 改静默… and 手动解决 beside
/// its time: their own buttons over the row's corner, not inside its button (a button in a button would fire both); a hidden copy
/// keeps the time clear of them. Monitor rows are named monitor.alerts.row.<id>.
struct AlertRow: View {
    enum Context: Sendable, Equatable { case home, monitor }

    let event: AlertEvent
    let context: Context
    let railPosition: RailPosition?
    let showsActions: Bool
    let onAction: ((AlertActionRequest.Kind) -> Void)?
    let onOpen: (() -> Void)?
    @Environment(\.sessionContext) private var session

    init(event: AlertEvent, context: Context, railPosition: RailPosition?, showsActions: Bool = false,
         onAction: ((AlertActionRequest.Kind) -> Void)? = nil, onOpen: (() -> Void)? = nil) {
        self.event = event; self.context = context; self.railPosition = railPosition; self.showsActions = showsActions
        self.onAction = onAction; self.onOpen = onOpen
    }

    var body: some View {
        Group {
            if let onOpen {
                openButton(onOpen)
            } else {
                content
            }
        }
        .railRow(tone: tone, position: railPosition)
    }

    private var tone: Tone? { AlertPresentation.tone(event) }
    private var now: Date { session?.client.serverClock.now() ?? Date() }
    private var timeZone: TimeZone { session?.site.serverTimeZone.timeZone ?? .current }
    /// Only a firing event offers actions (10 §6.3 底行右).
    private var actionHandler: ((AlertActionRequest.Kind) -> Void)? { showsActions && event.isFiring ? onAction : nil }

    @ViewBuilder private func openButton(_ onOpen: @escaping () -> Void) -> some View {
        let button = Button(action: onOpen) { content }.buttonStyle(.plain)
        if context == .monitor {
            button
                .accessibilityIdentifier("monitor.alerts.row.\(event.id)")
                .overlay(alignment: .bottomTrailing) {
                    if let onAction = actionHandler {
                        AlertActionBar(event: event, identifierPrefix: Self.monitorPrefix, onAction: onAction)
                            .padding(.trailing, 4)
                            .padding(.bottom, AttentionMetrics.verticalPadding - AlertActionBar.touchInset)
                    }
                }
        } else {
            button
        }
    }

    private static let monitorPrefix = "monitor.alerts"

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.isFiring ? "bell.fill" : "checkmark.circle")
                .foregroundStyle(tone.map { $0.drawsRail ? $0.base : Palette.ink3 } ?? Palette.ink3)
                .frame(width: AttentionMetrics.iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AlertPresentation.title(event)).font(.subheadline.weight(.semibold))
                        .foregroundStyle(event.isFiring ? Palette.ink1 : Palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !badge.isEmpty { ToneBadge(text: badge, tone: tone ?? .neutral) }
                }
                let lines = self.lines
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if index == lines.count - 1, let onAction = actionHandler {
                        HStack(spacing: 8) {
                            lineText(line).frame(maxWidth: .infinity, alignment: .leading)
                            AlertActionBar(event: event, identifierPrefix: Self.monitorPrefix, isPlaceholder: true, onAction: onAction)
                        }
                    } else {
                        lineText(line)
                    }
                }
            }
            if onOpen != nil { AttentionChevron() }
        }
        .railRowContent()
        .accessibilityElement(children: .combine)
    }

    private func lineText(_ line: String) -> some View {
        Text(line).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(context == .home ? 2 : nil)
    }

    private var badge: String {
        switch context {
        case .home: event.severity.trimmingCharacters(in: .whitespacesAndNewlines)
        case .monitor: AlertPresentation.badge(event)
        }
    }

    private var lines: [String] {
        switch context {
        case .home:
            [AlertPresentation.homeSubtitle(event, now: now, timeZone: timeZone)].filter { !$0.isEmpty }
        case .monitor:
            [AlertPresentation.detailLine(event, platformName: GroupPlatform.title,
                                          latencyMetricsSupported: session?.has(.opsAlertLatencyMetrics) == true),
             AlertPresentation.silenceLine(event, now: now, timeZone: timeZone),
             AlertPresentation.sinceText(event, now: now, timeZone: timeZone)].compactMap { $0 }.filter { !$0.isEmpty }
        }
    }
}

/// 10 §6.3 底行右 (S1-16, C-6): 静默… or 改静默… and 手动解决 (primary), as AlertActions offers them; 30pt to see, 44pt to touch.
/// Greyed while this event's write is on its way and for a read-only token (C-1, X10). `isPlaceholder` is the hidden copy a row
/// keeps beside its time. S2-22's alert sheet can use it with `compact: false` (改静默时长…). Identifiers `<prefix>.resolve.<id>`
/// and `<prefix>.silence.<id>`.
struct AlertActionBar: View {
    static let height: CGFloat = 30
    /// What the 44pt touch area adds above and below the button.
    static let touchInset: CGFloat = (44 - height) / 2

    let event: AlertEvent
    let compact: Bool
    let identifierPrefix: String
    let isPlaceholder: Bool
    let onAction: (AlertActionRequest.Kind) -> Void
    @Environment(AppModel.self) private var model

    init(event: AlertEvent, compact: Bool = true, identifierPrefix: String, isPlaceholder: Bool = false,
         onAction: @escaping (AlertActionRequest.Kind) -> Void) {
        self.event = event; self.compact = compact; self.identifierPrefix = identifierPrefix; self.isPlaceholder = isPlaceholder
        self.onAction = onAction
    }

    var body: some View {
        if let actions = model.liveOps?.alertActions {
            let kinds = MonitorAlertsPresentation.orderedActions(actions.availableActions(for: event))
            if !kinds.isEmpty {
                let bar = HStack(spacing: 8) { ForEach(kinds, id: \.self) { button($0) } }
                    .disabled(actions.isRunning(event.id))
                    .readOnlyGate()
                if isPlaceholder {
                    bar.hidden().accessibilityHidden(true)
                } else {
                    bar
                }
            }
        }
    }

    private func button(_ kind: AlertActionKind) -> some View {
        Button { onAction(kind) } label: {
            Text(MonitorAlertsPresentation.actionTitle(kind, compact: compact)).lineLimit(1)
        }
        .buttonStyle(AlertActionButtonStyle(isPrimary: kind == .resolve, expandsTouchArea: !isPlaceholder))
        .accessibilityLabel(MonitorAlertsPresentation.spokenAction(kind, title: AlertPresentation.title(event)))
        .accessibilityIdentifier("\(identifierPrefix).\(kind == .resolve ? "resolve" : "silence").\(event.id)")
    }
}

/// A small capsule with its pressed and disabled looks; in a List row it answers only its own area.
private struct AlertActionButtonStyle: ButtonStyle {
    let isPrimary: Bool
    let expandsTouchArea: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isPrimary ? Palette.onAccent : Palette.ink1)
            .padding(.horizontal, 10)
            .frame(minHeight: AlertActionBar.height)
            .background(isPrimary ? Palette.accentFill : Palette.sunken, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .frame(minWidth: 44, minHeight: expandsTouchArea ? 44 : nil)
            .contentShape(Rectangle())
    }
}

/// 00 §8.1 rows on the status rail, shared by the overview's 待处理 and the monitor's alerts.
enum AttentionMetrics {
    static let iconWidth: CGFloat = 22
    static let verticalPadding: CGFloat = 11
    static let trailingInset: CGFloat = 16
}

extension View {
    /// A List row on the status rail (00 §8.1): no inset above, below or before it, so the capsules of adjacent rows meet in one
    /// rail; the separator starts with the content. Without a position no capsule is drawn.
    func railRow(tone: Tone?, position: RailPosition?) -> some View {
        statusCapsule(tone: position == nil ? nil : tone, position: position ?? .single)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: AttentionMetrics.trailingInset))
            .alignmentGuide(.listRowSeparatorLeading) { _ in StatusCapsuleMetrics.contentLeadingInset }
    }

    /// The content of such a row: 16pt in, 11pt above and below, and the whole width hit-testable, so a row's button covers it.
    func railRowContent() -> some View {
        padding(.leading, StatusCapsuleMetrics.contentLeadingInset)
            .padding(.vertical, AttentionMetrics.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// The trailing chevron of a row that opens a page.
struct AttentionChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
    }
}
