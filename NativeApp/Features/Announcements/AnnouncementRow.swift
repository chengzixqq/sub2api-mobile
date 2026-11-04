import SwiftUI
import Sub2Core

/// 60 §15.3 row: title and status, who sees it (one line), then how and when with the read progress on the right. An archived
/// row is idle: its title in ink2. Every text comes from AnnouncementPresentation (S6-15); the enclosing link reads `spokenLabel`.
struct AnnouncementRow: View {
    let title: String
    let badge: AnnouncementBadge?
    let target: String
    let schedule: String
    let notifySymbol: String
    let readProgress: String?
    let isIdle: Bool

    /// `now` is the server-corrected clock; start and end follow the phone's zone, a draft's update time the site's (S6-15).
    init(announcement: Announcement, now: Date, serverTimeZone: TimeZone, supportsReadStats: Bool, groupNames: [Int: String]) {
        title = AnnouncementPresentation.displayTitle(announcement.title)
        badge = AnnouncementPresentation.badge(announcement.status)
        target = AnnouncementPresentation.targetText(announcement.targeting, groupNames: groupNames)
        schedule = AnnouncementPresentation.scheduleLine(announcement, now: now, localTimeZone: .current, serverTimeZone: serverTimeZone)
        notifySymbol = AnnouncementPresentation.notifySymbol(announcement.notifyMode)
        readProgress = AnnouncementPresentation.listReadProgress(announcement, supportsReadStats: supportsReadStats)
        isIdle = AnnouncementPresentation.isDimmed(announcement.status)
    }

    /// The whole row for VoiceOver, the target untruncated.
    var spokenLabel: String { [title, badge?.label, target, schedule, readProgress].compactMap { $0 }.joined(separator: "，") }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "megaphone")
                .font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(width: 28, height: 28)
                .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(isIdle ? Palette.ink2 : Palette.ink1).lineLimit(1)
                    Spacer(minLength: 4)
                    if let badge { ToneBadge(text: badge.label, tone: badge.tone) }
                }
                Text(target).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: notifySymbol).font(.caption2.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                    Text(schedule).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1)
                    Spacer(minLength: 8)
                    if let readProgress { Text(readProgress).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
