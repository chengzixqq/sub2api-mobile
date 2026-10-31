import SwiftUI
import Sub2Core

/// 30 §4.3 one record, shared by the full list and the detail's latest five (S3-05): the type and the signed value, then the
/// time and note with a redeemed code's first 8 characters on the right; only the full list passes the third line (U31).
/// Rows are not tappable; a row showing a code copies the whole code on long press (30 §4.4).
struct UserLedgerRow: View {
    @Environment(AppModel.self) private var model
    let item: BalanceHistoryItem
    let timeZone: ServerTimeZone
    /// The server-corrected clock, which decides whether the time shows its year.
    let now: Date
    var adjustmentLine: String?

    init(item: BalanceHistoryItem, timeZone: ServerTimeZone, now: Date, adjustmentLine: String? = nil) {
        self.item = item; self.timeZone = timeZone; self.now = now; self.adjustmentLine = adjustmentLine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(UserLedger.title(for: item)).font(.subheadline).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text(UserLedger.valueText(for: item)).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink1)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(UserLedger.secondLine(for: item, timeZone: timeZone, now: now)).font(.footnote).monospacedDigit()
                    .foregroundStyle(Palette.ink2)
                Spacer(minLength: 0)
                if let prefix = UserLedger.codePrefix(for: item) {
                    Text(prefix).font(.footnote.monospaced()).foregroundStyle(Palette.ink2).fixedSize()
                }
            }
            if let adjustmentLine {
                Text(adjustmentLine).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink3)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(UserLedger.spokenLabel(for: item, timeZone: timeZone, now: now, adjustmentLine: adjustmentLine)))
        .accessibilityIdentifier("user.ledger.row.\(item.id)")
        .modifier(CopyRedeemCode(code: UserLedger.copyableCode(for: item), copy: copy))
    }

    /// Through C-3 (this phone only, kept); the code is never logged.
    private func copy(_ code: String) {
        SensitivePasteboard.copy(code)
        model.receipts.show(Receipt(text: "已复制兑换码", systemImage: "doc.on.doc"))
    }
}

/// A row without a code gets no menu at all rather than an empty one.
private struct CopyRedeemCode: ViewModifier {
    let code: String?
    let copy: @MainActor (String) -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if let code {
            content
                .contextMenu {
                    Button("复制兑换码", systemImage: "doc.on.doc") { copy(code) }.accessibilityIdentifier("user.ledger.copy")
                }
                .accessibilityAction(named: "复制兑换码") { copy(code) }
        } else {
            content
        }
    }
}

/// 30 §4.5 首次加载: a placeholder of the same height.
struct UserLedgerRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("余额充值（兑换）").font(.subheadline)
                Spacer(minLength: 8)
                Text("+$00.00").font(.subheadline.weight(.medium))
            }
            Text("10/16 09:20 · 备注占位").font(.footnote)
        }
        .foregroundStyle(Palette.ink3)
        .redacted(reason: .placeholder)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在加载记录"))
        .accessibilityIdentifier("user.ledger.skeleton")
    }
}
