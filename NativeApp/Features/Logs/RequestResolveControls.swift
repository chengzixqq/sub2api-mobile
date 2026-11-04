import SwiftUI
import UIKit
import Sub2Core

// S4-08b: the request detail's 标记已处理, its ··· menu and the 标识 rows that copy (40 §7.1, §7.3, §7.4). RequestDetailView
// only wires them in.

extension RequestResolveFlow {
    /// The page's source (LogFixtures+Detail under `-ui-testing`) with the resolve write; a change that landed goes to every
    /// usage-record list of `tab` in this window, so the row there shows it without a reload.
    convenience init(model: AppModel, session: SessionContext, router: AppRouter, tab: MainTab, errorID: Int, kind: ErrorLogKind,
                     record: RequestErrorRecord?) {
        let source = model.isUITesting
            ? RequestResolveSource(detail: .app(model, session: session, row: record)) { try await LogFixtures.resolve(id: $0, kind: $1, resolved: $2) }
            : RequestResolveSource.live(session.client, site: session.site)
        let generation = session.generation
        self.init(errorID: errorID, kind: kind, record: record, source: source, receipts: model.receipts,
                  isCurrent: { [weak model] in model?.sessionGeneration == generation },
                  isReadOnly: { [weak model] in model?.sessionContext?.isReadOnlyToken ?? true },
                  onSettled: { [weak model, weak router] record in
                      guard let router else { return }
                      model?.pageStates?.instances(of: LogsStore.self, tab: tab, in: router).forEach { $0.applyResolved(record) }
                  })
    }
}

/// 40 §7.3 按钮行's first button: “标记已处理” (prominent), or “已处理 ✓”, which takes it back. Grey until the row or the detail
/// arrives, after 404 OPS_ERROR_NOT_FOUND, and for a read-only token (with “只读令牌”). Identifier logs.detail.resolve.
struct RequestResolveButton: View {
    let flow: RequestResolveFlow

    var body: some View {
        Group {
            if flow.isResolved {
                button.buttonStyle(.bordered)
            } else {
                button.buttonStyle(.borderedProminent)
            }
        }
        .disabled(!flow.canToggle)
        .readOnlyGate()
    }

    private var button: some View {
        let title = flow.isResolved ? RequestDetailCopy.resolvedTitle : RequestDetailCopy.markTitle
        return Button { Task { await flow.toggle() } } label: {
            HStack(spacing: 6) {
                if !flow.isResolved { Image(systemName: "checkmark") }
                Text(title)
                if flow.isResolved { Image(systemName: "checkmark") }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(title)
        .accessibilityHint(flow.isResolved ? RequestDetailCopy.resolvedHint : "")
        .accessibilityIdentifier("logs.detail.resolve")
    }
}

/// 40 §7.1 导航栏 ···: 复制请求 ID and, with one, 复制上游请求 ID. Identifiers logs.detail.more, .more.request / .more.upstream.
struct RequestDetailMoreMenu: View {
    let identifiers: [RequestIdentifierRow]
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(identifiers) { row in
                if let title = row.kind.menuTitle {
                    Button(title, systemImage: "doc.on.doc") { RequestIDCopy.copy(row, receipts: model.receipts) }
                        .accessibilityIdentifier("logs.detail.more." + row.kind.rawValue)
                }
            }
        } label: {
            Label(RequestDetailCopy.moreMenu, systemImage: "ellipsis")
        }
        .accessibilityIdentifier("logs.detail.more")
    }
}

/// 40 §7.3 标识: the label over the ID in monospace (one line, cut in the middle); a tap copies it. Identifiers
/// logs.detail.id.request / .client / .upstream.
struct RequestIdentifierCopyRow: View {
    let row: RequestIdentifierRow
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { RequestIDCopy.copy(row, receipts: model.receipts) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label).font(.footnote).foregroundStyle(Palette.ink2)
                Text(row.value).font(.footnote).monospaced().foregroundStyle(row.isCopyable ? Palette.ink1 : Palette.ink3)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.isCopyable)
        .accessibilityLabel("\(row.label) \(DisplayFormat.spoken(row.value))")
        .accessibilityHint(row.isCopyable ? RequestDetailCopy.copyHint : "")
        .accessibilityIdentifier("logs.detail.id." + row.kind.rawValue)
    }
}

/// Only the ID goes to the pasteboard; it is no secret, so not SensitivePasteboard (X13 / C-3).
@MainActor enum RequestIDCopy {
    static func copy(_ row: RequestIdentifierRow, receipts: ReceiptCenter) {
        guard row.isCopyable else { return }
        UIPasteboard.general.string = row.value
        receipts.show(Receipt(text: row.kind.copiedReceipt, systemImage: "doc.on.doc"))
    }
}
