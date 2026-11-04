import SwiftUI
import Sub2Core

/// 30 §6.1 the edit page's fixed identity strip: the avatar letter, the display name, the email and its badges (role,
/// 启用 / 禁用, 本人“你”, this phone's “待核对”), the available balance, and the 44pt “充值 / 退款” capsule that opens the
/// keypad (S3-08; a record awaiting its check asks first). Folded (scrolled past 24pt or a field focused) it is one line: the
/// name, the balance and the capsule.
struct UserEditIdentityStrip: View {
    let user: AdminUser
    let isSelf: Bool
    let isPending: Bool
    let compact: Bool
    let onBalance: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 10) {
            identity
            Button(action: onBalance) {
                Text(UserEditCopy.topupCapsule).font(.subheadline.weight(.semibold)).lineLimit(1).frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .readOnlyGate(showsCaption: false)
            .accessibilityIdentifier("user-edit.topup")
        }
    }

    private var identity: some View {
        HStack(spacing: 10) {
            if !compact {
                Circle().fill(Palette.accentWash).frame(width: 36, height: 36)
                    .overlay { Text(UserPresentation.initial(user.displayName)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent) }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName).font(.headline).foregroundStyle(Palette.ink1).lineLimit(1)
                if !compact {
                    Text(user.email).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
                    badges
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if !compact { Text(UserDetailPresentation.balanceLabel).font(.caption).foregroundStyle(Palette.ink2) }
                Text(DisplayFormat.money(user.balance)).font(.headline).monospacedDigit().foregroundStyle(Palette.ink1)
                    .accessibilityIdentifier("user-edit.identity.balance")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("user-edit.identity")
    }

    private var badges: some View {
        HStack(spacing: 4) {
            ToneBadge(text: UserPresentation.roleWord(user.role), tone: .neutral)
            ToneBadge(text: UserPresentation.statusWord(user.status), tone: user.status == "disabled" ? .caution : .ok)
            if isSelf { ToneBadge(text: "你", tone: .neutral) }
            if isPending { ToneBadge(text: "待核对", tone: .caution) }
        }
    }
}
