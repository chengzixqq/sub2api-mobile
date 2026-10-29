import SwiftUI
import Sub2Core

/// 60 §13.3 状态卡 (design `vmo-lat-hero`): the badge and its cause, the latency block and the three facts; on the critical wash
/// with the status capsule while the link fails and the proxy is active or carries accounts.
struct ProxyStatusCardView: View {
    let card: ProxyStatusCard
    let reading: ProxyLatencyReading
    let facts: ProxyFacts
    let isReprobing: Bool
    /// The shape before the proxy is read (13.5): redacted, read as “正在读取代理…”.
    var isPlaceholder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ToneBadge(text: card.badge.text, tone: card.badge.tone).accessibilityIdentifier("proxy.detail.badge")
                if let cause = card.cause {
                    Text(cause).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("proxy.detail.cause")
                }
                Spacer(minLength: 0)
            }
            ProxyLatencyBlock(reading: reading, isReprobing: isReprobing)
            ProxyFactsRow(facts: facts)
        }
        .padding(EdgeInsets(top: 16, leading: StatusCapsuleMetrics.contentLeadingInset + 4, bottom: 16, trailing: 16))
        .background(card.isCritical ? Tone.critical.wash : Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .statusCapsule(tone: card.isCritical ? .critical : nil)
        .redacted(reason: isPlaceholder ? .placeholder : [])
        .accessibilityElement(children: isPlaceholder ? .ignore : .contain)
        .accessibilityLabel(Text("正在读取代理…"), isEnabled: isPlaceholder)
        .accessibilityIdentifier(isPlaceholder ? "proxy.detail.placeholder" : "proxy.detail.card")
    }
}

/// 13.5: entered with only an id, the card's shape until the proxy is read.
struct ProxyStatusCardPlaceholder: View {
    var body: some View {
        ProxyStatusCardView(card: ProxyStatusCard(badge: ProxyBadge(text: "正常", tone: .neutral), cause: nil, isCritical: false),
                            reading: .success(value: "000", unit: "ms", needle: 0, lastTested: "上次测试 00/00 00:00"),
                            facts: ProxyFacts(exitIP: "000.000.000.000", exitIPIsMonospaced: true, region: "地区", quality: "A · 00", qualityDate: nil),
                            isReprobing: false, isPlaceholder: true)
    }
}

/// 出口 IP (monospaced), 地区, 质量 with its MM/DD beside the label.
struct ProxyFactsRow: View {
    let facts: ProxyFacts

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cell("出口 IP", facts.exitIP, isMonospaced: facts.exitIPIsMonospaced, id: "exitIP")
            cell("地区", facts.region, id: "region")
            cell(facts.qualityDate.map { "质量 · \($0)" } ?? "质量", facts.quality, id: "quality")
        }
    }

    private func cell(_ label: String, _ value: String, isMonospaced: Bool = false, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Palette.ink2)
            Text(value).font(isMonospaced ? .subheadline.monospaced() : .subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Palette.ink1).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("proxy.facts.\(id)")
    }
}

/// 13.3 按钮行: an expired proxy offers 续期 first, any other 测试连接 then 编辑. Hidden for who may not write.
struct ProxyDetailActions: View {
    let isExpired: Bool
    let isTesting: Bool
    let isBusy: Bool
    let onTest: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isExpired {
                Button("续期", systemImage: "arrow.clockwise", action: onEdit).buttonStyle(.borderedProminent)
                    .disabled(isBusy).accessibilityIdentifier("proxy.action.renew")
                testButton.buttonStyle(.bordered)
            } else {
                testButton.buttonStyle(.borderedProminent)
                Button("编辑", systemImage: "square.and.pencil", action: onEdit).buttonStyle(.bordered)
                    .disabled(isBusy).accessibilityIdentifier("proxy.action.edit")
            }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var testButton: some View {
        Button(isTesting ? "测试中…" : "测试连接", systemImage: "waveform", action: onTest)
            .disabled(isTesting || isBusy)
            .accessibilityIdentifier("proxy.action.test")
    }
}

/// 壹 有效期: the sentence, or 剩余 and 到期回退 among the rows; then “被改走的账号 N 个 ›”.
struct ProxyExpirySection: View {
    let proxyID: Int
    let note: ProxyExpiryNote?
    let rows: [ProxyKV]
    let fallbackLink: String?

    var body: some View {
        Section {
            if let note {
                Label { Text(note.text) } icon: { Image(systemName: "clock.badge.exclamationmark").foregroundStyle(note.tone.base) }
                    .font(.subheadline).foregroundStyle(Palette.ink1)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("proxy.expiry.note")
            }
            ForEach(rows) { ProxyKVRow(row: $0) }
            if let fallbackLink {
                NavigationLink(value: AppRoute.proxyFallbackAccounts(proxyID: proxyID)) { Text(fallbackLink) }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("proxy.fallbackLink")
            }
        } header: {
            NumberedSectionHeader(title: "有效期", ordinal: "壹")
        }
    }
}

/// 贰 使用该 IP 的账号: each row pushes the account; its badge only when the session's availability lists the account.
struct ProxyAccountsSection: View {
    let state: BlockState<[ProxyAccountRef]>
    let detail: (ProxyAccountRef) -> String
    let stateOf: (Int) -> AccountDisplayState?
    let now: Date
    let onRetry: () -> Void

    var body: some View {
        Section {
            switch state.display {
            case .placeholder, .disabled:
                ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("proxy.accounts.loading")
            case .failed:
                Button(ProxyDetailCopy.accountsUnavailable, action: onRetry).frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("proxy.accounts.retry")
            case .value(let accounts, _, _, _) where accounts.isEmpty:
                Text(ProxyDetailCopy.noAccounts).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("proxy.accounts.empty")
            case .value(let accounts, _, _, _):
                ForEach(accounts) { account in
                    NavigationLink(value: AppRoute.account(id: account.id)) {
                        ProxyAccountRow(account: account, detail: detail(account), state: stateOf(account.id), now: now)
                    }
                    .accessibilityIdentifier("proxy.account.\(account.id)")
                }
            }
        } header: {
            NumberedSectionHeader(title: "使用该 IP 的账号", ordinal: "贰", meta: state.value.map { ProxyDetailCopy.accountsMeta($0.count) },
                                  id: "proxy.accounts.meta")
        }
    }
}

private struct ProxyAccountRow: View {
    let account: ProxyAccountRef
    let detail: String
    let state: AccountDisplayState?
    let now: Date
    @ScaledMetric(relativeTo: .body) private var glyphSize = 17.0
    @ScaledMetric(relativeTo: .body) private var dotSize = 8.0
    @ScaledMetric(relativeTo: .body) private var glyphWidth = 22.0

    var body: some View {
        HStack(spacing: 10) {
            glyph
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name.isEmpty ? "账号 #\(account.id)" : account.name).font(.body).foregroundStyle(Palette.ink1).lineLimit(1)
                    if let state { AccountStatusBadge(state: state, now: now) }
                }
                Text(detail).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(state.map { $0.label } ?? ""))
    }

    /// The state's symbol in its tone; without one a neutral dot (the state is not known here).
    private var glyph: some View {
        let shown = state?.state ?? .available
        return Image(systemName: AccountRowPresentation.systemImage(for: shown))
            .font(.system(size: shown == .available ? dotSize : glyphSize, weight: .semibold))
            .foregroundStyle(state.map { $0.tone.base } ?? Palette.ink3)
            .frame(width: glyphWidth, height: glyphWidth)
            .accessibilityHidden(true)
    }
}

/// 叁 连接.
struct ProxyConnectionSection: View {
    let rows: [ProxyKV]

    var body: some View {
        Section {
            ForEach(rows) { ProxyKVRow(row: $0) }
        } header: {
            NumberedSectionHeader(title: "连接", ordinal: "叁")
        }
    }
}

private struct ProxyKVRow: View {
    let row: ProxyKV

    var body: some View {
        LabeledContent(row.label) {
            Text(row.value).font(row.isMonospaced ? .body.monospaced() : .body).monospacedDigit()
                .foregroundStyle(Palette.ink1).multilineTextAlignment(.trailing).textSelection(.disabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("proxy.kv.\(row.key.rawValue)")
    }
}
