import SwiftUI
import UniformTypeIdentifiers
import Sub2Core

/// 00 §3.4: the rows of an error's “详情” — status, reason, X-Request-ID and time, never the server's message.
struct ErrorDetailsRows: View {
    let details: ErrorDetails
    var body: some View {
        ForEach(details.rows) { row in
            LabeledContent(row.label) {
                Text(row.value).font(.callout.monospaced()).foregroundStyle(Palette.ink2).textSelection(.enabled)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("error.details.\(row.id)")
        }
    }
}

/// The collapsed “详情” of a block's error state; pages adopt it when they are rewritten (stages 1–6).
struct ErrorDetailsDisclosure: View {
    let details: ErrorDetails
    var body: some View {
        DisclosureGroup("详情") { ErrorDetailsRows(details: details) }
            .accessibilityIdentifier("error.details.disclosure")
    }
}

/// Opened from the root alert's “详情”: the details to pass on to the site owner, copied only to this device.
struct ErrorDetailsSheet: View {
    let details: ErrorDetails
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text(details.message).foregroundStyle(Palette.ink1) }
                Section { ErrorDetailsRows(details: details) } footer: { Text("把这些信息发给站长，便于在服务器日志里定位这次请求。") }
                Section {
                    Button("复制详情", systemImage: "doc.on.doc") {
                        UIPasteboard.general.setItems([[UTType.plainText.identifier: details.text]], options: [.localOnly: true])
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("error.details.copy")
                }
            }
            .navigationTitle("错误详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("error.details.done")
                }
            }
        }
    }
}
