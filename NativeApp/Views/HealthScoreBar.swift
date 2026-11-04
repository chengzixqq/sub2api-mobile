import SwiftUI
import Sub2Core

/// 10 §1.3.5 健康分 gauge: the track, the 60 and 90 marks, the fill up to the score in ink and a needle in the band's tone. Without a
/// score only the track and the marks. Decoration only: the row reads out the number and the word. S1-13's monitor overview reuses it.
struct HealthScoreBar: View {
    let reading: MonitorPresentation.HealthReading

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.sunken).frame(height: 6)
                if let fraction = reading.fraction {
                    Capsule().fill(Palette.ink2).frame(width: width * CGFloat(fraction), height: 6)
                }
                ForEach(HomeRunPresentation.healthZones, id: \.self) { zone in
                    Rectangle().fill(Palette.ink3.opacity(0.6)).frame(width: 1, height: 12).offset(x: width * CGFloat(zone) / 100)
                }
                if let fraction = reading.fraction {
                    RoundedRectangle(cornerRadius: 1).fill(reading.tone?.base ?? Palette.ink2)
                        .frame(width: 2, height: 14).offset(x: min(max(width * CGFloat(fraction) - 1, 0), width - 2))
                }
            }
            .frame(width: width, height: proxy.size.height)
        }
        .frame(height: 14)
        .frame(minWidth: 48)
        .accessibilityHidden(true)
    }
}
