import SwiftUI
import Sub2Core

/// 30 §1.3 `cols` row (C-8): letter avatar, name and email; on the right the balance with its one mark, and today's spend.
/// The list and the global search (S6-21: `today: .hidden`, the “禁用” badge and a trailing note) share it. The chevron is
/// the enclosing NavigationLink's; the container sets the row's top, bottom and leading insets to 0 so capsules join.
struct UserRow: View {
    typealias Today = UserTodayCell
    let user: AdminUser
    let today: Today
    let mark: UserListMark?
    let railPosition: RailPosition?
    var showsDisabledBadge = false
    var trailingNote: String?

    init(user: AdminUser, today: Today, mark: UserListMark?, railPosition: RailPosition?, showsDisabledBadge: Bool = false,
         trailingNote: String? = nil) {
        self.user = user; self.today = today; self.mark = mark; self.railPosition = railPosition
        self.showsDisabledBadge = showsDisabledBadge; self.trailingNote = trailingNote
    }

    /// What VoiceOver reads; the enclosing link uses it too.
    var spokenLabel: String {
        UserListPresentation.rowSpokenLabel(displayName: user.displayName, email: user.email, balance: user.balance, mark: mark,
                                            today: today, showsDisabledBadge: showsDisabledBadge, trailingNote: trailingNote)
    }
    /// 30 §1.3 行变暗: a disabled user's whole row is secondary.
    private var isIdle: Bool { user.status == "disabled" }

    var body: some View {
        HStack(spacing: 12) {
            UserInitialAvatar(initial: UserPresentation.initial(user.displayName), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(isIdle ? Palette.ink3 : Palette.ink1)
                Text(trailingNote.map { "\(user.email) \($0)" } ?? user.email).font(.footnote)
                    .foregroundStyle(isIdle ? Palette.ink3 : Palette.ink2).truncationMode(.middle)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    if let mark { UserListMarkGlyph(mark: mark) }
                    Text(DisplayFormat.money(user.balance)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(isIdle ? Palette.ink3 : Palette.ink1)
                    if showsDisabledBadge { ToneBadge(text: UserListMark.disabled.label, tone: .neutral) }
                }
                if let text = today.text { Text(text).font(.caption).monospacedDigit().foregroundStyle(isIdle ? Palette.ink3 : Palette.ink2) }
            }
            .lineLimit(1)
        }
        .padding(EdgeInsets(top: 10, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 10, trailing: 0))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .statusCapsule(tone: railPosition == nil ? nil : .caution, position: railPosition ?? .single)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
    }
}

/// The three marks have different shapes, so none relies on colour (30 §1.3): 余额低 a filled dot, 待核对 the docCheck
/// glyph of the banner and the strip's badge, 禁用 a minus. The row and the legend name them in text.
struct UserListMarkGlyph: View {
    let mark: UserListMark
    @ScaledMetric(relativeTo: .caption) private var dot = 7.0

    var body: some View {
        Group {
            switch mark {
            case .lowBalance: Circle().fill(Tone.caution.base).frame(width: dot, height: dot)
            case .pending: Image(systemName: "doc.text.magnifyingglass").foregroundStyle(Tone.caution.base)
            case .disabled: Image(systemName: "minus").foregroundStyle(Tone.neutral.base)
            }
        }
        .font(.caption.weight(.bold))
        .accessibilityHidden(true)
    }
}

/// The first letter of the display name in a circle (30 §0.3).
struct UserInitialAvatar: View {
    let initial: String
    let size: CGFloat

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Palette.ink2)
            .frame(width: size, height: size)
            .background(Palette.sunken, in: Circle())
            .accessibilityHidden(true)
    }
}

/// 30 §1.5 首次加载: a placeholder row of the same height.
struct UserRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            UserInitialAvatar(initial: " ", size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("用户名占位").font(.subheadline.weight(.semibold))
                Text("user@example.com").font(.footnote)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("$000.00").font(.subheadline.weight(.semibold))
                Text("今日 $0.00").font(.caption)
            }
        }
        .foregroundStyle(Palette.ink3)
        .redacted(reason: .placeholder)
        .padding(EdgeInsets(top: 10, leading: StatusCapsuleMetrics.contentLeadingInset, bottom: 10, trailing: 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在加载用户"))
        .accessibilityIdentifier("users.skeleton")
    }
}
