import SwiftUI

/// The words under a greyed write entry (00 §1.6, §2.6.3).
enum ReadOnlyGate {
    static let caption = "只读令牌"
}

extension View {
    /// C-1, the App's one way to grey a write entry for a read-only admin access token (`\.sessionContext`'s
    /// `isReadOnlyToken`): disabled, with the footnote “只读令牌” below; unchanged otherwise, and outside a session.
    /// Put it once on a whole row or button group. In a Menu or a toolbar pass `showsCaption: false`: there is no room for the
    /// footnote, so VoiceOver reads “只读令牌” as the hint instead, and callers add no hint of their own. Swipe actions do not
    /// use it (they are simply not offered); entries the spec hides for a read-only token check `isReadOnlyToken` themselves.
    func readOnlyGate(showsCaption: Bool = true) -> some View {
        modifier(ReadOnlyGateModifier(showsCaption: showsCaption))
    }
}

/// The branch follows only the call site's constant, so a token found read-only mid-session adds the caption without
/// replacing the content (its state stays).
private struct ReadOnlyGateModifier: ViewModifier {
    let showsCaption: Bool
    @Environment(\.sessionContext) private var session

    @ViewBuilder func body(content: Content) -> some View {
        let locked = session?.isReadOnlyToken == true
        if showsCaption {
            VStack(alignment: .leading, spacing: 2) {
                content.disabled(locked)
                if locked {
                    Text(ReadOnlyGate.caption).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("readonly.caption")
                }
            }
        } else {
            content.disabled(locked).accessibilityHint(Text(ReadOnlyGate.caption), isEnabled: locked)
        }
    }
}
