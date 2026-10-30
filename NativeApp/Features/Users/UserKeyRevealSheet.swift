import SwiftUI
import Sub2Core

/// 30 §7.4 完整 Key / Key 已创建: the name, the full key in a monospaced box and “复制” (this phone only, gone after 60 seconds,
/// C-3). The key cannot be selected, so the system's copy never bypasses those rules. It is hidden while the App is inactive
/// (the App switcher's snapshot) and cleared in the background, after 30 seconds and when the sheet closes.
struct UserKeyRevealSheet: View {
    let secret: RevealedKeySecret
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(secret.name).font(.headline).foregroundStyle(Palette.ink1)
                        .accessibilityIdentifier("keys.reveal.name")
                    keyBox
                    copyButton
                    Text(notice).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("keys.reveal.notice")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.sheetBackground)
            .accessibilityIdentifier("keys.reveal.sheet")
            .navigationTitle(secret.purpose == .created ? UserKeyFormCopy.createdTitle : UserKeyFormCopy.revealTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(UserKeyFormCopy.doneAction) { dismiss() }.accessibilityIdentifier("keys.reveal.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: scenePhase, initial: true) { _, phase in secret.activityChanged(to: AppActivity(phase)) }
        .onDisappear { secret.clear() }
    }

    private var keyBox: some View {
        Text(secret.plaintext ?? DisplayFormat.missing)
            .font(.body.monospaced())
            .foregroundStyle(secret.plaintext == nil ? Palette.ink3 : Palette.ink1)
            .textSelection(.disabled)
            .privacySensitive()
            .redacted(reason: secret.isShielded ? .privacy : [])
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline))
            .accessibilityIdentifier("keys.reveal.key")
    }

    private var copyButton: some View {
        Button {
            guard let plaintext = secret.plaintext else { return }
            SensitivePasteboard.copy(plaintext, expiresIn: SensitivePasteboard.revealedKeyLifetime)
            copied = true
        } label: {
            Label(UserKeyFormCopy.copyAction, systemImage: "doc.on.doc").frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(secret.plaintext == nil || secret.isShielded)
        .accessibilityIdentifier("keys.reveal.copy")
    }

    private var notice: String {
        if secret.plaintext == nil { return secret.expired ? UserKeyFormCopy.expiredNotice : UserKeyFormCopy.backgroundNotice }
        if copied { return UserKeyFormCopy.copiedNotice }
        return secret.purpose == .created ? UserKeyFormCopy.createdNotice : UserKeyFormCopy.revealNotice
    }
}
