import SwiftUI
import Sub2Core

// 60 §11.3 结果待核对页的部件 (S6-06; S6-09's compensation page reuses them): they draw what they are given and never read
// AppModel. Identifiers start with `money.pending.` unless the page passes its own.

/// The icon, the title and one line under it, on the tone's wash.
struct MoneyPendingHeader: View {
    let systemImage: String
    let title: String
    let message: String?
    let tone: Tone
    var identifier = "money.pending.header"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 28, weight: .semibold)).foregroundStyle(tone.base).accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink1).multilineTextAlignment(.center)
                .accessibilityIdentifier(identifier + ".title")
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
                    .accessibilityIdentifier(identifier + ".message")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 20, leading: 16, bottom: 18, trailing: 16))
        .background(tone.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// Label on the left, value on the right; the record's number is monospaced and may be selected (it is not a secret).
struct MoneyPendingReceipt: View {
    let lines: [MoneyReceiptLine]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(lines) { line in
                row(line)
                if line.id != lines.last?.id { Divider().overlay(Palette.hairline) }
            }
        }
        .padding(.horizontal, 14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("money.pending.receipt")
    }

    private func row(_ line: MoneyReceiptLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(line.label).font(.subheadline).foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                value(line)
                if let note = line.note { Text(note).font(.footnote).foregroundStyle(Palette.ink2).multilineTextAlignment(.trailing) }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("money.pending.receipt." + line.id)
    }

    @ViewBuilder private func value(_ line: MoneyReceiptLine) -> some View {
        if line.isKey {
            Text(line.value).font(.footnote.monospaced()).foregroundStyle(Palette.ink1).multilineTextAlignment(.trailing).textSelection(.enabled)
        } else {
            Text(line.value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1).multilineTextAlignment(.trailing)
        }
    }
}

/// One button of the page; `id` is also its accessibility identifier.
struct MoneyPendingAction: Identifiable, Equatable {
    let id: String
    let title: String
    let isPrimary: Bool
    let isEnabled: Bool
}

/// The page's buttons, full width, the primary one filled. While a request runs the page passes them all disabled.
struct MoneyPendingActions: View {
    let actions: [MoneyPendingAction]
    let perform: @MainActor (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(actions) { action in button(action) }
        }
    }

    @ViewBuilder private func button(_ action: MoneyPendingAction) -> some View {
        let base = Button { perform(action.id) } label: {
            Text(action.title).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }
        Group {
            if action.isPrimary { base.buttonStyle(.borderedProminent).tint(Palette.accentFill) } else { base.buttonStyle(.bordered).tint(Palette.ink1) }
        }
        .disabled(!action.isEnabled)
        .accessibilityIdentifier(action.id)
    }
}

/// What the last request said (核对失败, 结果未确认…), as a banner of its tone.
struct MoneyPendingNotice: View {
    let text: String
    let tone: Tone
    var identifier = "money.pending.notice"

    var body: some View {
        StatusBanner(tone: tone, systemImage: tone == .critical ? "exclamationmark.octagon" : "exclamationmark.triangle", title: text)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
    }
}

/// Small lines: why a button is missing or grey, the old server's caveat, the page's footnote.
struct MoneyPendingFootnote: View {
    let text: String
    var identifier = "money.pending.footnote"

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
    }
}
