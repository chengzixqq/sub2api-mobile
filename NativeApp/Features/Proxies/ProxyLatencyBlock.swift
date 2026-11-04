import SwiftUI
import Sub2Core

/// 60 §13.3 延迟块 (design VmoLatencyBlock): the figure and its unit over the 0–500ms scale with “上次测试 10/16 09:12”; “链接失败”
/// over the probe's own error, monospaced on the critical wash; “— 还没测试过”; or “测试中”. After an edit of the address it says
/// the server is probing again (H04). Latency has no status colour: the figure and the needle are ink.
struct ProxyLatencyBlock: View {
    let reading: ProxyLatencyReading
    var isReprobing = false
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize = 44.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isReprobing {
                Text(ProxyDetailCopy.retesting).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink2)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("proxy.latency")
    }

    @ViewBuilder private var content: some View {
        switch reading {
        case .testing:
            Text(ProxyPresentation.testingText).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink2)
        case .success(let value, let unit, let needle, let lastTested):
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: figureSize, weight: .semibold)).monospacedDigit()
                Text(unit).font(.title3.weight(.medium)).foregroundStyle(Palette.ink2)
            }
            .foregroundStyle(Palette.ink1)
            // Read as one reading, “182ms” (R10).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value + unit)
            ProxyLatencyScale(needle: needle)
            if let lastTested { Text(lastTested).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2) }
        case .failed(let message):
            Text(ProxyPresentation.linkFailedText).font(.title2.weight(.semibold)).foregroundStyle(Tone.critical.ink)
            if let message {
                Text(message).font(.footnote.monospaced()).foregroundStyle(Palette.ink1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Tone.critical.wash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        case .untested:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(DisplayFormat.missing).font(.system(size: figureSize, weight: .semibold)).foregroundStyle(Palette.ink3)
                Text("还没测试过").font(.subheadline).foregroundStyle(Palette.ink2)
            }
        }
    }
}

/// 0–500ms in six marks with an ink needle; over 500 the needle rests at the right end. Decoration only.
struct ProxyLatencyScale: View {
    let needle: Double
    private static let marks = [0, 100, 200, 300, 400, 500]
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 11.0

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.sunken).frame(height: 4)
                    ForEach(Self.marks, id: \.self) { mark in
                        Rectangle().fill(Palette.ruleStrong).frame(width: 1, height: 8)
                            .offset(x: min(width - 1, width * CGFloat(mark) / CGFloat(ProxyPresentation.latencyScaleMaxMs)))
                    }
                    RoundedRectangle(cornerRadius: 1.5).fill(Palette.ink1).frame(width: 3, height: 18)
                        .offset(x: min(max(0, width * CGFloat(min(max(needle, 0), 1)) - 1.5), width - 3))
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            HStack(spacing: 0) {
                ForEach(Array(Self.marks.enumerated()), id: \.element) { index, mark in
                    if index > 0 { Spacer(minLength: 0) }
                    Text(String(mark)).font(.system(size: labelSize)).monospacedDigit().foregroundStyle(Palette.ink3)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
