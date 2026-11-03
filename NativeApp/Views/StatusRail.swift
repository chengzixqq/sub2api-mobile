import SwiftUI
import Sub2Core

extension View {
    /// 00 §8.1 status capsule at the leading edge: 4pt wide, 6pt in, the tone's base colour. Nothing is drawn for nil or
    /// for tones without a rail (ok, neutral). Only an end of the rail (`capsTop` / `capsBottom`) is rounded and inset from
    /// the edge (`RailPosition.insets`: 22pt, less in a short row), so in a list the container computes each row's position
    /// with `RailPosition.positions`, sets the rows' top and bottom `listRowInsets` to 0 and pads the content itself:
    /// adjacent capsules then meet in one rail.
    func statusCapsule(tone: Tone?, position: RailPosition = .single) -> some View {
        overlay(alignment: .leading) {
            if let tone, tone.drawsRail {
                StatusCapsuleShape(position: position)
                    .fill(tone.base)
                    .frame(width: StatusCapsuleMetrics.width)
                    .padding(.leading, StatusCapsuleMetrics.leadingInset)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The capsule within the full height of its row: the insets come from the height it is given, so the overlay never
/// changes the row's size and a short row still shows at least `RailPosition.minimumLength`.
struct StatusCapsuleShape: Shape {
    var position: RailPosition = .single

    func path(in rect: CGRect) -> Path {
        let insets = position.insets(height: Double(rect.height))
        let body = CGRect(x: rect.minX, y: rect.minY + insets.top, width: rect.width,
                          height: max(0, rect.height - insets.top - insets.bottom))
        let radius = StatusCapsuleMetrics.width / 2
        return UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
            topLeading: position.capsTop ? radius : 0, bottomLeading: position.capsBottom ? radius : 0,
            bottomTrailing: position.capsBottom ? radius : 0, topTrailing: position.capsTop ? radius : 0))
            .path(in: body)
    }
}
