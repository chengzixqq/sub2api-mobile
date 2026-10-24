import SwiftUI
import Sub2Core

extension View {
    /// 00 §8.1 status capsule at the leading edge: 4pt wide, 6pt in, the tone's base colour. Nothing is drawn for nil or
    /// for tones without a rail (ok, neutral). Only an end of the rail (`capsTop` / `capsBottom`) is rounded and kept
    /// 10pt from the edge, so in a list the container computes each row's position with `RailPosition.positions`, sets
    /// the rows' top and bottom `listRowInsets` to 0 and pads the content itself: adjacent capsules then meet in one rail.
    func statusCapsule(tone: Tone?, position: RailPosition = .single) -> some View {
        overlay(alignment: .leading) {
            if let tone, tone.drawsRail {
                let radius = StatusCapsuleMetrics.width / 2
                UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
                    topLeading: position.capsTop ? radius : 0, bottomLeading: position.capsBottom ? radius : 0,
                    bottomTrailing: position.capsBottom ? radius : 0, topTrailing: position.capsTop ? radius : 0))
                    .fill(tone.base)
                    .frame(width: StatusCapsuleMetrics.width)
                    .padding(.top, position.capsTop ? StatusCapsuleMetrics.verticalInset : 0)
                    .padding(.bottom, position.capsBottom ? StatusCapsuleMetrics.verticalInset : 0)
                    .padding(.leading, StatusCapsuleMetrics.leadingInset)
                    .accessibilityHidden(true)
            }
        }
    }
}
