import SwiftUI
import Sub2Core

/// 40 §6.3 (C-8): the time over the status code, the model over “用户 · 账号”, the amount over “首字/耗时”, and the status capsule
/// where the container gives a rail position. Display values only; the container adds the chevron and the identifier, so 60 §2's
/// search reuses it as it is.
struct LogRow: View {
    let row: LogRowPresentation
    let railPosition: RailPosition?
    @ScaledMetric(relativeTo: .footnote) private var leadWidth = 48.0

    init(_ row: LogRowPresentation, railPosition: RailPosition?) { self.row = row; self.railPosition = railPosition }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.time).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
                ToneBadge(text: row.badge, tone: row.badgeTone)
            }
            .frame(width: leadWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.model).font(.subheadline.weight(.medium)).monospaced().foregroundStyle(Palette.ink1).lineLimit(1)
                HStack(spacing: 4) {
                    Text(row.user).truncationMode(.middle)
                    Text("·").foregroundStyle(Palette.ink3)
                    Text(row.account).layoutPriority(1)
                }
                .font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(row.amount).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(row.amount == DisplayFormat.missing ? Palette.ink3 : Palette.ink1)
                Text(row.timing).font(.caption).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1)
            }
        }
        .padding(EdgeInsets(top: 10, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 10, trailing: 0))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .statusCapsule(tone: railPosition == nil ? nil : row.capsule, position: railPosition ?? .single)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
    }

    /// Each part as shown, the missing mark read as 无数据 (both sides of “首字/耗时” on their own).
    var spokenLabel: String {
        let timing = row.timing.split(separator: "/", omittingEmptySubsequences: false).map { DisplayFormat.spoken(String($0)) }
        return [DisplayFormat.spoken(row.time), "状态 " + DisplayFormat.spoken(row.badge), DisplayFormat.spoken(row.model),
                DisplayFormat.spoken(row.user), DisplayFormat.spoken(row.account), "金额 " + DisplayFormat.spoken(row.amount),
                "首字/耗时 " + timing.joined(separator: "/")].joined(separator: "，")
    }
}
