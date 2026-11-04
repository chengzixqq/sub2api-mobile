import SwiftUI
import Sub2Core

/// 20 §7.1 the glass dock (design `.an-dock`): what is still missing (the whole block scrolls to the first item), or the stage of
/// the create, then a secondary and the main button. The main button turns while a request is out and is greyed for a
/// read-only token.
struct AccountNewDock: View {
    let content: AccountNewDockContent
    let onJump: () -> Void
    let onAction: (AccountNewDockContent.Action) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if content.jumpsToFirstMissing {
                Button(action: onJump) { text }
                    .buttonStyle(.plain)
                    .accessibilityLabel(content.accessibilityLabel)
                    .accessibilityIdentifier("account-new.dock.missing")
            } else {
                text
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(content.accessibilityLabel)
                    .accessibilityIdentifier("account-new.dock.text")
            }
            if let secondary = content.secondary {
                Button(secondary.title) { onAction(secondary) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("account-new.dock.secondary")
                    .readOnlyGate(showsCaption: false)
            }
            if let primary = content.primary { primaryButton(primary) }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-new.dock")
    }

    private var text: some View {
        let tone = content.tone?.ink ?? Palette.ink1
        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                if content.jumpsToFirstMissing {
                    Text(content.title).font(.caption).foregroundStyle(Palette.ink2)
                    Text(content.detail ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1).lineLimit(2)
                } else {
                    Text(content.title).font(.subheadline.weight(.semibold)).foregroundStyle(tone).lineLimit(2)
                    if let detail = content.detail { Text(detail).font(.caption).foregroundStyle(Palette.ink2).lineLimit(3) }
                }
            }
            if content.jumpsToFirstMissing {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func primaryButton(_ action: AccountNewDockContent.Action) -> some View {
        Button { onAction(action) } label: {
            HStack(spacing: 6) {
                if content.showsProgress { ProgressView().tint(Palette.onAccent) }
                Text(action.title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.accentFill)
        .disabled(!action.isEnabled)
        .accessibilityIdentifier("account-new.submit")
        .readOnlyGate(showsCaption: false)
    }
}
