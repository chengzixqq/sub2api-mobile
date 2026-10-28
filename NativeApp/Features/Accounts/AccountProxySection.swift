import SwiftUI
import Sub2Core

/// 20 §3.3 代理 (design `AeProxyBody`): the proxy's name, “{协议} · {到期词}” and monospaced address, or “无代理”; a hint while the
/// proxy is expired or stopped; and, while the account is fallen back, “已回退：原代理 X” with 恢复原代理. A row with a proxy pushes
/// its detail (U23, a placeholder until S6-12); 无代理 opens the picker like “编辑”, which both need the account read first.
struct AccountProxySection: View {
    let content: AccountProxySectionContent
    let edit: AccountSectionEdit
    let isReverting: Bool
    let onOpenProxy: (Int) -> Void
    let onRevert: (AccountProxyFallbackLine) -> Void

    var body: some View {
        AccountEditSectionBox(title: "代理", key: "proxy", edit: edit, footnote: content.footnote) {
            row(content.row)
            if let hint = content.hint {
                Text(hint.text).font(.footnote).foregroundStyle(hint.tone.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("account.proxy.hint")
            }
            if let fallback = content.fallback { fallbackRow(fallback) }
        }
    }

    @ViewBuilder private func row(_ row: AccountProxyRowContent) -> some View {
        if let id = row.proxyID {
            Button { onOpenProxy(id) } label: { rowLabel(row, chevron: true) }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken(row))
                .accessibilityHint("查看代理详情")
                .accessibilityIdentifier("account.proxy.row")
        } else {
            Button(action: edit.action) { rowLabel(row, chevron: false) }
                .buttonStyle(.plain)
                .disabled(!edit.isEnabled)
                .accessibilityLabel(spoken(row))
                .accessibilityHint("选择代理")
                .accessibilityIdentifier("account.proxy.row")
                .readOnlyGate(showsCaption: false)
        }
    }

    private func rowLabel(_ row: AccountProxyRowContent, chevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(row.kind == .direct ? Palette.ink2 : Palette.ink1)
                if let detail = row.detail {
                    Text(detail).font(.footnote).monospacedDigit().foregroundStyle(row.expiry?.tone?.ink ?? Palette.ink2)
                }
                if let address = row.address {
                    Text(address).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink3).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true) }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func fallbackRow(_ fallback: AccountProxyFallbackLine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(fallback.title).font(.subheadline.weight(.semibold)).foregroundStyle(Tone.caution.ink)
                    Text(fallback.detail).font(.footnote).foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("account.proxy.fallback")
                Spacer(minLength: 8)
                Button { onRevert(fallback) } label: {
                    ZStack {
                        Text(AccountProxyCopy.revertAction).opacity(isReverting ? 0 : 1)
                        if isReverting { ProgressView() }
                    }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .disabled(isReverting)
                .accessibilityLabel(AccountProxyCopy.revertAction)
                .accessibilityIdentifier("account.proxy.revert")
                .readOnlyGate(showsCaption: false)
            }
            .padding(.vertical, 10)
        }
    }

    private func spoken(_ row: AccountProxyRowContent) -> String {
        (["代理", row.title] + [row.detail, row.address].compactMap { $0 }).joined(separator: "，")
    }
}

/// An open proxy picker: the account's version it saves on and the save flow (C-14).
struct AccountProxyEditorRequest: Identifiable {
    let id = UUID()
    let base: AccountEditBase
    let flow: AccountPatchFlow
}

extension View {
    /// The picker sheet and the 恢复原代理 question (no Face ID, no step-up), hung on the detail page.
    func accountProxyPrompts(editor: Binding<AccountProxyEditorRequest?>, reverting: Binding<AccountProxyFallbackLine?>,
                             onSaved: @escaping () -> Void, onRevert: @escaping (AccountProxyFallbackLine) -> Void) -> some View {
        sheet(item: editor) { AccountProxySheet(request: $0, onSaved: onSaved) }
            .alert(AccountProxyCopy.revertTitle(reverting.wrappedValue?.originName ?? ""),
                   isPresented: Binding(get: { reverting.wrappedValue != nil }, set: { if !$0 { reverting.wrappedValue = nil } }),
                   presenting: reverting.wrappedValue) { line in
                Button(AccountProxyCopy.revertAction) { onRevert(line) }
                Button("取消", role: .cancel) {}
            } message: { line in
                Text(AccountProxyCopy.revertMessage(line.originName))
            }
    }
}

/// 20 §3.4 代理: a tap saves at once through AccountPatchFlow (“已保存：代理 → X” with 撤销) and closes the sheet; the current
/// choice just closes it. While saving, or until 没有保存成功 / 结果未确认 settle, the list holds and the sheet cannot be swiped away.
struct AccountProxySheet: View {
    let request: AccountProxyEditorRequest
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: AccountProxyChoice?

    private var account: UpstreamAccount { request.base.account }
    private var flow: AccountPatchFlow { request.flow }

    var body: some View {
        NavigationStack {
            AccountProxyPicker(selection: account.proxyID, current: account.proxy, currentID: account.proxyID,
                               busy: flow.isSaving ? picked : nil, isLocked: flow.locksForm) { pick($0) }
                .safeAreaInset(edge: .bottom) {
                    if flow.phase != .idle, !flow.isSaving {
                        AccountPatchStatusRow(flow: flow).padding(16).background(.bar)
                    }
                }
                .navigationTitle("代理")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }.disabled(flow.isSaving).accessibilityIdentifier("account.proxy.cancel")
                    }
                }
                .accountPatchPrompts(flow)
        }
        .interactiveDismissDisabled(flow.locksForm)
        .onChange(of: flow.savedRevision) { _, _ in
            onSaved()
            dismiss()
        }
    }

    private func pick(_ choice: AccountProxyChoice) {
        guard !flow.locksForm else { return }
        guard choice.proxyID != account.proxyID else { dismiss(); return }
        picked = choice
        let change = AccountEditChange(fieldNames: [AccountProxyCopy.fieldName(choice.displayName)],
                                       request: AccountPatchRequest(proxyID: choice.patchValue), undo: AccountPatchRequest(proxyID: account.proxyID ?? 0))
        let base = request.base
        Task { await flow.save(change, base: base) }
    }
}
