import SwiftUI
import Sub2Core

/// 60 §10.3 结果页, shared by the generate sheet (S6-07) and the check sheet (S6-06): the head with the batch line, 全部复制,
/// every code in full with its own copy button, and the footnote. The codes live only in this view (gone when the sheet
/// closes), are never selectable and leave the phone only through SensitivePasteboard (S6D1-20). A count that does not match
/// and an old server's guess show their caution and “我已核对” (`onConfirmChecked`), which settles the record.
struct RedeemResultView: View {
    let kind: RedeemResultKind
    let spec: RedeemGenerateSpec
    let codes: [AdminRedeemCode]
    /// The record's time, for the check's footnote.
    let startedAt: Date?
    let timeZone: ServerTimeZone
    let onConfirmChecked: (() -> Void)?
    let isConfirming: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var copiedAll = false

    init(kind: RedeemResultKind, spec: RedeemGenerateSpec, codes: [AdminRedeemCode], startedAt: Date? = nil, timeZone: ServerTimeZone,
         onConfirmChecked: (() -> Void)? = nil, isConfirming: Bool = false) {
        self.kind = kind; self.spec = spec; self.codes = codes; self.startedAt = startedAt; self.timeZone = timeZone
        self.onConfirmChecked = onConfirmChecked; self.isConfirming = isConfirming
    }

    var body: some View {
        let now = session?.client.serverClock.now() ?? Date()
        let header = RedeemReconcilePresentation.resultHeader(kind, spec: spec, codes: codes, timeZone: timeZone, now: now)
        VStack(spacing: 16) {
            MoneyPendingHeader(systemImage: header.systemImage, title: header.title, message: header.message, tone: header.tone,
                               identifier: "redeem.result.header")
            if let caution = RedeemReconcilePresentation.resultCaution(kind, found: codes.count) {
                MoneyPendingNotice(text: caution, tone: .caution, identifier: "redeem.result.caution")
            }
            if let onConfirmChecked { confirmButton(onConfirmChecked) }
            if !codes.isEmpty {
                copyAllButton
                LazyVStack(spacing: 8) {
                    ForEach(Array(codes.enumerated()), id: \.element.id) { index, code in row(code, number: index + 1) }
                }
            }
            MoneyPendingFootnote(text: RedeemReconcilePresentation.resultFootnote(kind, startedAt: startedAt, codes: codes, timeZone: timeZone, now: now),
                                 identifier: "redeem.result.footnote")
        }
    }

    private func confirmButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(RedeemReconcilePresentation.confirmTitle).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent).tint(Palette.accentFill)
        .disabled(isConfirming)
        .accessibilityIdentifier("redeem.result.confirm")
    }

    private var copyAllButton: some View {
        Button(action: copyAll) {
            Label(RedeemReconcilePresentation.copyAllTitle(count: codes.count, copied: copiedAll), systemImage: copiedAll ? "checkmark" : "doc.on.doc")
                .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered).tint(Palette.ink1)
        .accessibilityIdentifier("redeem.result.copyAll")
    }

    private func row(_ code: AdminRedeemCode, number: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.footnote.monospacedDigit()).foregroundStyle(Palette.ink3).frame(minWidth: 24, alignment: .trailing)
                .accessibilityHidden(true)
            RedeemCodeBox(code: code.code, initiallyRevealed: true, identifier: "redeem.result.code.\(number)") { copy(code) }
        }
    }

    private func copyAll() {
        SensitivePasteboard.copy(RedeemReconcilePresentation.copyAllText(codes))
        copiedAll = true
    }
    private func copy(_ code: AdminRedeemCode) {
        SensitivePasteboard.copy(code.code)
        model.receipts.show(Receipt(text: RedeemListText.copiedReceipt, systemImage: "doc.on.doc"))
    }
}
