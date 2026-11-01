import SwiftUI
import Sub2Core

/// 40 §6.3 time capsule: the four rolling presets, the one shown ticked, then “自定义…”. Identifier `logs.time`; system menu items
/// are found by their title.
struct LogTimeMenu: View {
    private let title: String
    private let selection: LogTimePreset
    private let onPick: @MainActor (LogTimePreset) -> Void
    private let onCustom: @MainActor () -> Void

    init(title: String, selection: LogTimePreset, onPick: @escaping @MainActor (LogTimePreset) -> Void,
         onCustom: @escaping @MainActor () -> Void) {
        self.title = title; self.selection = selection; self.onPick = onPick; self.onCustom = onCustom
    }

    var body: some View {
        Menu {
            ForEach(LogTimePreset.rollingPresets, id: \.self) { preset in
                Button { onPick(preset) } label: {
                    if preset == selection { Label(preset.menuTitle, systemImage: "checkmark") } else { Text(preset.menuTitle) }
                }
            }
            Button(LogCustomRangeSheet.menuTitle) { onCustom() }
        } label: {
            LogChipLabel(title, isOn: true, trailingSymbol: "chevron.down")
        }
        .accessibilityLabel("时间：" + title)
        .accessibilityIdentifier("logs.time")
    }
}

/// “自定义…”: start and end in the site's zone, up to now, at most 366 days (40 §0.2, §6.3). Identifiers
/// `logs.time.custom.start / end / invalid / cancel / apply`.
struct LogCustomRangeSheet: View {
    static let menuTitle = "自定义…"
    static let title = "自定义时段"
    static let footnote = "按站点时区计算，最长 366 天"
    static let invalidText = "开始时间要早于结束时间，跨度最长 366 天"

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    private let timeZone: ServerTimeZone
    private let now: Date
    private let apply: @MainActor (LogTimePreset) -> Void

    init(initial: (start: Date, end: Date), timeZone: ServerTimeZone, now: Date, apply: @escaping @MainActor (LogTimePreset) -> Void) {
        _start = State(initialValue: min(initial.start, now)); _end = State(initialValue: min(initial.end, now))
        self.timeZone = timeZone; self.now = now; self.apply = apply
    }

    private var preset: LogTimePreset? { LogTimePreset.validatedCustom(start: start, end: end) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("开始", selection: $start, in: ...now).accessibilityIdentifier("logs.time.custom.start")
                    DatePicker("结束", selection: $end, in: ...now).accessibilityIdentifier("logs.time.custom.end")
                } footer: {
                    Text(Self.footnote)
                }
                if preset == nil {
                    Text(Self.invalidText).font(.footnote).foregroundStyle(Tone.critical.ink)
                        .accessibilityIdentifier("logs.time.custom.invalid")
                }
            }
            .environment(\.timeZone, timeZone.timeZone)
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("logs.time.custom.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用", action: confirm).disabled(preset == nil).accessibilityIdentifier("logs.time.custom.apply")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func confirm() {
        guard let preset else { return }
        apply(preset)
        dismiss()
    }
}

/// Design `.chip` for the page's capsules: 34pt, accent wash and edge when on, sunken when off; a dimmed condition is grey with a
/// dashed edge and its monospaced value struck through (S4-05b). S4-05b's removable chips and S4-07's “+ 筛选” compose it.
struct LogChipLabel: View {
    private let title: String
    private let monospacedValue: String?
    private let isOn: Bool
    private let isDimmed: Bool
    private let leadingSymbol: String?
    private let trailingSymbol: String?
    @ScaledMetric(relativeTo: .subheadline) private var size = 14.5
    @ScaledMetric(relativeTo: .footnote) private var symbolSize = 11.5
    @ScaledMetric(relativeTo: .subheadline) private var height = 34.0

    init(_ title: String, monospacedValue: String? = nil, isOn: Bool, isDimmed: Bool = false, leadingSymbol: String? = nil,
         trailingSymbol: String? = nil) {
        self.title = title; self.monospacedValue = monospacedValue; self.isOn = isOn; self.isDimmed = isDimmed
        self.leadingSymbol = leadingSymbol; self.trailingSymbol = trailingSymbol
    }

    private var isLit: Bool { isOn && !isDimmed }

    var body: some View {
        HStack(spacing: 6) {
            if let leadingSymbol { symbol(leadingSymbol) }
            HStack(spacing: 0) {
                Text(title)
                if let monospacedValue { Text(monospacedValue).monospaced().strikethrough(isDimmed) }
            }
            .font(.system(size: size))
            if let trailingSymbol { symbol(trailingSymbol) }
        }
        .lineLimit(1)
        .foregroundStyle(isDimmed ? Palette.ink3 : isLit ? Palette.accent : Palette.ink1)
        .padding(.horizontal, 13)
        .frame(height: height)
        .background(isLit ? Palette.accentWash : Palette.sunken, in: Capsule())
        .overlay {
            if isLit { Capsule().strokeBorder(Palette.accent, lineWidth: 1) }
            if isDimmed { Capsule().strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: symbolSize, weight: .bold)).accessibilityHidden(true)
    }
}
