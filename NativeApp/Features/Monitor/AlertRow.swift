import SwiftUI
import Sub2Core

/// C-6, 10 §1.3.3 and §6.3: one alert event as a row on the status rail, for the overview's 待处理 (home) and the monitor's alerts
/// segment (S1-16). Home: a bell, the level as the badge and “阈值 5.0% · 12 分钟前触发 · 已静默”. Monitor: “P1 · 告警中”, the scope
/// and rule unclipped, the silence and the time; an event no longer firing has no capsule, a check mark and a grey title. With
/// `onOpen` the row is one button. The actions under the text (`showsActions`, `onAction`) are S1-16's.
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
                Button(action: onOpen) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
        .railRow(tone: tone, position: railPosition)
    }

    private var tone: Tone? { AlertPresentation.tone(event) }
    private var now: Date { session?.client.serverClock.now() ?? Date() }
    private var timeZone: TimeZone { session?.site.serverTimeZone.timeZone ?? .current }

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
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(context == .home ? 2 : nil)
                }
            }
            if onOpen != nil { AttentionChevron() }
        }
        .railRowContent()
        .accessibilityElement(children: .combine)
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
