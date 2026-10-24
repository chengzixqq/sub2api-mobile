import SwiftUI
import Sub2Core

/// 00 §1.4 step 1, checkbox mode: the row above 连接站点 (Web's zh texts), with each document one tap away.
struct LoginAgreementRow: View {
    let agreement: LoginAgreement
    @Binding var checked: Bool
    let open: (LoginAgreementDocument) -> Void

    var body: some View {
        Button { checked.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? Palette.accent : Palette.ink3).accessibilityHidden(true)
                Text("我已阅读并同意" + agreement.documents.map { "《\($0.title)》" }.joined(separator: "、"))
                    .foregroundStyle(Palette.ink1).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityIdentifier("login.agreement")
        ForEach(Array(agreement.documents.enumerated()), id: \.element.id) { index, document in
            Button("查看《\(document.title)》") { open(document) }
                .font(.subheadline).foregroundStyle(Palette.accent).frame(minHeight: 44)
                .accessibilityIdentifier("login.agreement.doc.\(index)")
        }
    }
}

/// Modal mode: asked after 连接站点 is tapped; a swipe down counts as 拒绝.
struct LoginAgreementSheet: View {
    let agreement: LoginAgreement
    let accept: () -> Void
    let reject: () -> Void
    @State private var document: LoginAgreementDocument?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("继续登录前需要先同意最新条款。").foregroundStyle(Palette.ink2)
                }
                Section("相关文档") {
                    ForEach(agreement.documents) { item in
                        Button { document = item } label: {
                            Label(item.title, systemImage: "doc.text").foregroundStyle(Palette.ink1).frame(minHeight: 44)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button(action: reject) { Text("拒绝").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.bordered).accessibilityIdentifier("login.agreement.reject")
                    Button(action: accept) { Text("同意并继续").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent).tint(Palette.accentFill).accessibilityIdentifier("login.agreement.accept")
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Palette.sheetBackground)
            }
            .navigationTitle("登录条款")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $document) { LoginDocumentSheet(document: $0) }
        }
    }
}

/// A document's `content_md`: paragraphs split on blank lines, inline Markdown only; links open in the system only for http(s).
struct LoginDocumentSheet: View {
    let document: LoginAgreementDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let paragraphs = Self.paragraphs(document.contentMarkdown)
                    if paragraphs.isEmpty { Text("暂无正文内容").foregroundStyle(Palette.ink3) }
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph).foregroundStyle(Palette.ink1).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.sheetBackground)
            .environment(\.openURL, OpenURLAction { url in
                ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
            })
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.accessibilityIdentifier("login.document.done") } }
        }
    }

    static func paragraphs(_ markdown: String) -> [AttributedString] {
        markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { (try? AttributedString(markdown: $0, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString($0) }
    }
}
