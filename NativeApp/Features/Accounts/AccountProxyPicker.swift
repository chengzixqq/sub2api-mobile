import SwiftUI
import Sub2Core

/// A row of the proxy picker: 无代理 (sent as `proxy_id` 0) or one proxy.
enum AccountProxyChoice: Hashable, Sendable {
    case direct
    case proxy(id: Int, name: String)
    var proxyID: Int? { if case .proxy(let id, _) = self { id } else { nil } }
    var patchValue: Int { proxyID ?? 0 }
    /// nil for 无代理.
    var displayName: String? { if case .proxy(_, let name) = self { name } else { nil } }
}

/// 20 §3.3 代理选择 (S2-19's new account reuses it): “无代理 · 直连上游”, then `proxies/all?with_count=true`'s active proxies newest
/// first, each with its expiry badge, monospaced address and “N 个账号在用 · {地区} · {到期词}”. A note above says when the current
/// proxy is not among them. A failed read keeps 无代理 and offers 重试. `busy` spins on the row being saved; `isLocked` holds the
/// list meanwhile.
struct AccountProxyPicker: View {
    /// The chosen proxy's id; nil is 无代理.
    let selection: Int?
    var current: AccountProxy?
    var currentID: Int?
    var busy: AccountProxyChoice?
    var isLocked = false
    let onPick: (AccountProxyChoice) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var options = LoadState<[AdminProxy]>()

    var body: some View {
        let content = options.value.map {
            AccountProxyPresentation.picker($0, current: current, currentID: currentID, now: model.serverNow(),
                                            timeZone: session?.site.serverTimeZone ?? .device)
        }
        List {
            if let note = content?.currentNote {
                Section {
                    Text(note.text).font(.subheadline).foregroundStyle(note.tone.ink).accessibilityIdentifier("account.proxy.current-note")
                }
            }
            Section {
                directRow
                if let reason = options.error, options.value == nil { failure(reason) }
                if options.value == nil, options.isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 44) }
                ForEach(content?.options ?? []) { optionRow($0) }
            } footer: {
                Text(AccountProxyPresentation.pickerFootnote)
            }
        }
        .disabled(isLocked)
        .accessibilityIdentifier("account.proxy.picker")
        .task { await load() }
    }

    private var directRow: some View {
        pickRow(.direct, selected: selection == nil, id: "account.proxy.option.direct",
                spoken: [AccountProxyPresentation.directTitle, AccountProxyPresentation.directDetail]) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AccountProxyPresentation.directTitle).font(.body.weight(.semibold)).foregroundStyle(Palette.ink1)
                Text(AccountProxyPresentation.directDetail).font(.footnote).foregroundStyle(Palette.ink3)
            }
        }
    }

    private func optionRow(_ option: AccountProxyOption) -> some View {
        pickRow(.proxy(id: option.id, name: option.name), selected: selection == option.id, id: "account.proxy.option.\(option.id)",
                spoken: [option.name, option.badge, option.address, option.meta].compactMap { $0 }.filter { !$0.isEmpty }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(option.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink1)
                    if let badge = option.badge { ToneBadge(text: badge, tone: .caution) }
                }
                Text(option.address).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink2).lineLimit(1)
                if !option.meta.isEmpty { Text(option.meta).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink3) }
            }
        }
    }

    private func pickRow<Label: View>(_ choice: AccountProxyChoice, selected: Bool, id: String, spoken: [String],
                                      @ViewBuilder label: () -> Label) -> some View {
        Button { onPick(choice) } label: {
            HStack(alignment: .center, spacing: 12) {
                label()
                Spacer(minLength: 8)
                if busy == choice {
                    ProgressView()
                } else if selected {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Palette.accent).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken.joined(separator: "，"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func failure(_ reason: String) -> some View {
        HStack {
            Text("读取代理失败").foregroundStyle(Tone.critical.ink).accessibilityIdentifier("account.proxy.options.failure")
            Spacer()
            Button("重试") { Task { await load() } }
                .buttonStyle(.borderless).frame(minHeight: 44).accessibilityIdentifier("account.proxy.options.retry")
        }
        .accessibilityHint(reason)
    }

    private func load() async {
        let model = model, generation = model.sessionGeneration
        await options.load(isCurrent: { model.sessionGeneration == generation }) { try await model.allProxies(withCount: true) }
    }
}
