import SwiftUI
import Sub2Core

/// 10 §1.3.5 运行（叁）: 健康分 on its gauge, 错误率 / 上游 429 / 529 and the 渠道 row; live figures, with no window in the title. The
/// header follows the ops block; the 渠道 row opens the monitor's 渠道 segment when there is something to see there. 重试 reads home
/// again past the server cache; the next poll retries by itself (S1D1-20). Identifiers home.run.*.
struct HomeRunSection: View {
    let store: LiveOpsStore
    @Environment(AppRouter.self) private var router

    var body: some View {
        let health = HomeRunPresentation.health(store.home.ops.display, opsDisabled: store.opsDisabled)
        Section {
            healthRow(health)
            ratesRow
            channelRow(HomeRunPresentation.channels(store.home.channels.display))
        } header: {
            NumberedSectionHeader(title: "运行", ordinal: "叁", id: "home.run.header") {
                if !store.opsDisabled {
                    BlockStatusAccessory(state: store.home.ops, refresh: store.homeRefresh(for: .ops), id: "home.run",
                                         resendsAfterWait: false, retry: retry)
                }
            }
        }
    }

    private func retry() { Task { await store.refreshHome(noCache: true) } }

    // MARK: 健康分

    @ViewBuilder private func healthRow(_ health: HomeRunPresentation.Health) -> some View {
        HStack(spacing: 12) {
            Text("健康分").font(.subheadline).foregroundStyle(Palette.ink2)
            HealthScoreBar(reading: health.reading)
            Text(health.numberText).font(.title2.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink1)
                .lineLimit(1).minimumScaleFactor(0.5)
            if let word = health.wordText {
                Text(word).font(.footnote.weight(.semibold)).foregroundStyle(health.tone?.ink ?? Palette.ink3).lineLimit(1)
            }
        }
        .frame(minHeight: 44)
        .redacted(reason: health == .loading ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("健康分")
        .accessibilityValue(health.spokenValue)
        .accessibilityIdentifier("home.run.health")
        if health == .failed {
            BlockFailureRow(title: HomeRunPresentation.healthFailedText, error: store.homeLastError(for: .ops), refresh: store.homeRefresh(for: .ops),
                            id: "home.run.health", resendsAfterWait: false, retry: retry)
                .homeFailureContainer("home.run.health.failed")
        }
    }

    // MARK: 错误率、上游 429、529

    private var ratesRow: some View {
        let rates = HomeRunPresentation.rates(store.home.rates.value)
        let isLoading = store.home.rates.display.homePhase == .placeholder
        return HStack(spacing: 18) {
            HomeInlineFigure(label: "错误率", value: rates.errorRate, id: "home.run.errorRate", isLoading: isLoading)
            HomeInlineFigure(label: "上游 429", value: rates.upstream429, id: "home.run.upstream429", isLoading: isLoading)
            HomeInlineFigure(label: "529", spokenLabel: "上游 529", value: rates.upstream529, id: "home.run.upstream529", isLoading: isLoading)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }

    // MARK: 渠道

    @ViewBuilder private func channelRow(_ channels: HomeRunPresentation.Channels) -> some View {
        if channels == .failed {
            VStack(alignment: .leading, spacing: 2) {
                channelTitle
                BlockFailureRow(title: HomePresentation.channelsFailedText, error: store.homeLastError(for: .channels),
                                refresh: store.homeRefresh(for: .channels), id: "home.run.channels", resendsAfterWait: false, retry: retry)
                    .padding(.leading, Self.iconWidth + 12)
            }
            .homeFailureContainer("home.run.channels.failed")
        } else if channels.isTappable {
            Button { router.select(.monitor(segment: .channels)) } label: { channelLabel(channels, showsChevron: true) }
                .buttonStyle(.plain)
                .accessibilityLabel("渠道")
                .accessibilityValue(channels.text)
                .accessibilityIdentifier("home.run.channels")
        } else {
            channelLabel(channels, showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("渠道")
                .accessibilityValue(channels.text)
                .accessibilityIdentifier("home.run.channels")
        }
    }

    private static let iconWidth: CGFloat = 24

    private var channelTitle: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(Palette.ink3).frame(width: Self.iconWidth)
                .accessibilityHidden(true)
            Text("渠道").foregroundStyle(Palette.ink1)
        }
    }

    private func channelLabel(_ channels: HomeRunPresentation.Channels, showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                channelTitle
                Text(Self.summary(channels)).font(.subheadline).foregroundStyle(Palette.ink2)
                    .redacted(reason: channels == .loading ? .placeholder : [])
                    .padding(.leading, Self.iconWidth + 12)
            }
            Spacer(minLength: 8)
            if case .summary(_, true) = channels {
                Text(BlockStatusPresentation.updateFailed).font(.footnote).foregroundStyle(Palette.ink3)
            }
            if showsChevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// “可用 3 · 性能下降 1 · 不可用 1 · 未知 1”: 性能下降 in caution ink, 不可用 in critical ink, the rest in the line's ink.
    private static func summary(_ channels: HomeRunPresentation.Channels) -> AttributedString {
        guard case .summary(let parts, _) = channels else { return AttributedString(channels.text) }
        var line = AttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 { line += AttributedString(" · ") }
            var piece = AttributedString(part.text)
            if part.tone == .caution || part.tone == .critical { piece.foregroundColor = part.tone.ink }
            line += piece
        }
        return line
    }
}
