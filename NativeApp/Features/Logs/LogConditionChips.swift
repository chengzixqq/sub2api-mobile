import SwiftUI
import Sub2Core

extension LogListCopy {
    static let invalidParameters = "请求参数无效"
    static let clearFilters = "清除筛选"
}

/// 40 §6.3 condition chip “用户：Alice ✕”: a tap drops the condition. A greyed one (40 §6.4) is still removable and reads 未生效.
struct LogConditionChip: View {
    private let chip: LogFilterChip
    private let remove: @MainActor () -> Void

    init(_ chip: LogFilterChip, remove: @escaping @MainActor () -> Void) { self.chip = chip; self.remove = remove }

    private var spokenState: String { chip.isApplied ? "" : "未生效" }

    var body: some View {
        Button(action: remove) {
            LogChipLabel(chip.isMonospaced ? chip.kind.label + "：" : chip.text, monospacedValue: chip.isMonospaced ? chip.value : nil,
                         isOn: true, isDimmed: !chip.isApplied, trailingSymbol: "xmark")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chip.text)
        .accessibilityValue(spokenState)
        .accessibilityHint("移除筛选")
        .accessibilityIdentifier("logs.chip.\(chip.kind.rawValue)")
    }
}

/// The line under the chips while one is greyed (40 §6.4): LogFilterChips.note as it is.
struct LogChipReasons: View {
    private let note: String?

    init(_ note: String?) { self.note = note }

    var body: some View {
        if let note {
            Text(note).font(.footnote).foregroundStyle(Palette.ink3).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("logs.chips.reason")
        }
    }
}

/// 40 §6.5: the error segments over a range starting more than 30 days ago.
struct LogRetentionNote: View {
    private let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink3).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("logs.retention")
    }
}

/// “清除筛选”: every condition goes, the time and the segment stay (40 §6.5).
struct LogClearFiltersButton: View {
    private let id: String
    private let action: @MainActor () -> Void

    init(id: String, action: @escaping @MainActor () -> Void) { self.id = id; self.action = action }

    var body: some View {
        Button(action: action) {
            Text(LogListCopy.clearFilters).font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(Palette.accent)
        .accessibilityIdentifier(id)
    }
}

/// 40 §6.5 “400 其他（参数）” while a condition applies: the sentence and 清除筛选 in place of 加载失败 · 重试.
struct LogInvalidParametersRow: View {
    private let clear: @MainActor () -> Void

    init(clear: @escaping @MainActor () -> Void) { self.clear = clear }

    var body: some View {
        HStack(spacing: 6) {
            Text(LogListCopy.invalidParameters).font(.subheadline).foregroundStyle(Palette.ink2).accessibilityIdentifier("logs.invalid")
            Text("·").foregroundStyle(Palette.ink3).accessibilityHidden(true)
            LogClearFiltersButton(id: "logs.invalid.clear", action: clear)
            Spacer(minLength: 0)
        }
    }
}
