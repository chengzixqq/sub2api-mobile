import SwiftUI
import Sub2Core

/// The two sheets every analytics page opens (40 §1.2).
enum AnalyticsSheet: String, Identifiable {
    case customRange, filter
    var id: String { rawValue }
}

extension View {
    /// 自定义范围 and 筛选 over an analytics page; both write back to `session`.
    func analyticsSheets(_ session: AnalyticsSession, sheet: Binding<AnalyticsSheet?>) -> some View {
        self.sheet(item: sheet) { kind in
            switch kind {
            case .customRange: AnalyticsCustomRangeSheet(session: session)
            case .filter: AnalyticsFilterSheet(session: session)
            }
        }
    }
}

/// 40 §1.2 范围条: 今天 · 7 天 · 30 天 · 自定义 (a preset off the bar or “自选 N 天” takes 自定义's place), the caption that reopens the
/// custom sheet, and the removable filter chip. Tapping the selected segment again does nothing; 自定义 opens the sheet.
struct AnalyticsRangeBar: View {
    let session: AnalyticsSession
    @Binding var sheet: AnalyticsSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("时间范围", selection: segment) {
                ForEach(AnalyticsRangeSegment.allCases, id: \.self) { item in
                    Text(item == .custom && session.range.segment == .custom ? session.range.segmentTitle : item.title)
                        .tag(item)
                        .accessibilityIdentifier("analytics.range.segment.\(item.rawValue)")
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("analytics.range.segment")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { AnalyticsRangeCaption(session: session, sheet: $sheet); AnalyticsFilterChip(session: session) }
                VStack(alignment: .leading, spacing: 4) { AnalyticsRangeCaption(session: session, sheet: $sheet); AnalyticsFilterChip(session: session) }
            }
        }
    }

    private var segment: Binding<AnalyticsRangeSegment> {
        Binding(get: { session.range.segment }, set: { item in
            if let preset = item.preset { session.select(.preset(preset)) } else if session.range.segment != .custom { sheet = .customRange }
        })
    }
}

/// 说明行: “10月16日 周五 · 00:00 至 09:41 · 按小时”, a button back into the custom sheet.
struct AnalyticsRangeCaption: View {
    let session: AnalyticsSession
    @Binding var sheet: AnalyticsSheet?

    var body: some View {
        let caption = session.range.caption(device: .current)
        Button { sheet = .customRange } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.footnote)
                Text(caption).font(.footnote).monospacedDigit().multilineTextAlignment(.leading)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Palette.ink2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption)
        .accessibilityHint("选择日期范围")
        .accessibilityIdentifier("analytics.range.caption")
    }
}

/// “分组：高级组 ✕” / “模型：claude-opus-4 ✕” (the model name monospaced); tapping it clears the filter.
struct AnalyticsFilterChip: View {
    let session: AnalyticsSession

    var body: some View {
        if let filter = session.filter, let name = session.filterName {
            Button { session.setFilter(nil) } label: {
                AnalyticsCapsuleLabel(isOn: true, trailingSymbol: "xmark") {
                    Text("\(filter.kind.title)：\(Text(name).font(filter.kind == .model ? .subheadline.monospaced() : .subheadline))")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(filter.kind.title)：\(name)")
            .accessibilityHint("清除筛选")
            .accessibilityIdentifier("analytics.filter.chip")
        }
    }
}

/// The navigation bar's filter button (`line.3.horizontal.decrease`).
struct AnalyticsFilterButton: View {
    let session: AnalyticsSession
    @Binding var sheet: AnalyticsSheet?

    var body: some View {
        Button { sheet = .filter } label: { Image(systemName: "line.3.horizontal.decrease") }
            .accessibilityLabel("筛选")
            .accessibilityValue(session.filterName.map { "\(session.filter?.kind.title ?? "")：\($0)" } ?? "全部")
            .accessibilityIdentifier("analytics.filter.button")
    }
}

/// 40 §2.1 更多图表吸顶条右侧的范围 Menu: 今天 / 近 7 天 / 近 30 天, then 自定义… (the custom sheet).
struct AnalyticsRangeMenu: View {
    let session: AnalyticsSession
    @Binding var sheet: AnalyticsSheet?
    private static let presets: [AnalyticsPreset] = [.today, .last7, .last30]

    var body: some View {
        Menu {
            ForEach(Self.presets, id: \.self) { preset in
                Toggle(preset.title, isOn: Binding(get: { session.selection == .preset(preset) },
                                                   set: { if $0 { session.select(.preset(preset)) } }))
            }
            Section {
                Button { sheet = .customRange } label: {
                    Text("自定义…")
                    if !Self.presets.contains(where: { session.selection == .preset($0) }) { Text(session.range.name) }
                }
                .accessibilityIdentifier("analytics.range.menu.custom")
            }
        } label: {
            HStack(spacing: 4) {
                Text(session.range.name).monospacedDigit()
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel("时间范围")
        .accessibilityValue(session.range.name)
        .accessibilityIdentifier("analytics.range.menu")
    }
}

/// The analytics capsules (the filter chip, the custom sheet's shortcuts), drawn like the account list's chips.
struct AnalyticsCapsuleLabel<Title: View>: View {
    private let isOn: Bool
    private let trailingSymbol: String?
    private let title: () -> Title
    @ScaledMetric(relativeTo: .subheadline) private var height = 32.0

    init(isOn: Bool, trailingSymbol: String? = nil, @ViewBuilder title: @escaping () -> Title) {
        self.isOn = isOn; self.trailingSymbol = trailingSymbol; self.title = title
    }

    var body: some View {
        HStack(spacing: 5) {
            title().font(.subheadline)
            if let trailingSymbol { Image(systemName: trailingSymbol).font(.caption2.weight(.bold)) }
        }
        .lineLimit(1)
        .foregroundStyle(isOn ? Palette.accent : Palette.ink1)
        .padding(.horizontal, 12)
        .frame(height: height)
        .background(isOn ? Palette.accentWash : Palette.sunken, in: Capsule())
        .overlay { if isOn { Capsule().strokeBorder(Palette.accent, lineWidth: 1) } }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
