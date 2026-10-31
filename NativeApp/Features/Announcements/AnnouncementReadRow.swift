import SwiftUI
import Sub2Core

/// 60 §18.3 row: the initial, the email (truncated) and the balance; then the username, 符合条件 / 不符合 and the read time or
/// a grey “未读”. A user who no longer qualifies is idle: only the email turns ink2, so every text keeps its contrast (S2-04).
/// Every text comes from AnnouncementPresentation.readRow (S6-15); the enclosing link reads `spokenLabel`.
struct AnnouncementReadRow: View {
    let text: AnnouncementReadRowText

    /// `now` is the server-corrected clock; read_at follows the site's zone (R20).
    init(row: AnnouncementReadStatusRow, now: Date, serverTimeZone: TimeZone) {
        text = AnnouncementPresentation.readRow(row, now: now, serverTimeZone: serverTimeZone)
    }

    var spokenLabel: String {
        [text.email, text.balance, text.username, text.badge.label, text.readText].filter { !$0.isEmpty }.joined(separator: "，")
    }

    var body: some View {
        HStack(spacing: 12) {
            UserInitialAvatar(initial: text.initial, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(text.email).font(.subheadline.weight(.semibold)).foregroundStyle(text.isDimmed ? Palette.ink2 : Palette.ink1)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(text.balance).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(text.username).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
                    Spacer(minLength: 4)
                    ToneBadge(text: text.badge.label, tone: text.badge.tone)
                    Text(text.readText).font(.footnote).monospacedDigit().foregroundStyle(text.isRead ? Palette.ink2 : Palette.ink3).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
    }
}
