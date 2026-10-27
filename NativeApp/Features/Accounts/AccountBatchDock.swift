import SwiftUI
import Sub2Core

// 20 §8 on screen (S2-07): the selection mode's chrome on the account list, the glass dock and the results sheet.

/// Design `.dock`: “已选 N 个”, then 停止调度 and the primary 启用调度; both greyed with nothing picked, the running one spins
/// and neither takes a tap meanwhile. It lifts the receipt above itself (C-15).
struct AccountBatchDock: View {
    let selectedCount: Int
    let running: Bool?
    let isConfirming: Bool
    let onStop: () -> Void
    let onEnable: () -> Void
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .body) private var height = 64.0

    var body: some View {
        HStack(spacing: 8) {
            Text(isConfirming ? AccountBatchPlan.confirming : AccountBatchPlan.selectedCount(selectedCount))
                .font(.system(size: 15)).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("accounts.batch.count")
            HStack(spacing: 8) {
                button(enables: false, action: onStop)
                button(enables: true, action: onEnable)
            }
            .readOnlyGate()
        }
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 8))
        .frame(minHeight: height)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accounts.batch.dock")
        .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { model.receipts.setBottomClearance($0 + 8) }
        .onDisappear { model.receipts.setBottomClearance(0) }
    }

    private func button(enables: Bool, action: @escaping () -> Void) -> some View {
        let title = AccountActionKind.setSchedulable(enables).verb
        return Button(action: action) {
            HStack(spacing: 6) {
                if running == enables { ProgressView().tint(enables ? Palette.onAccent : Palette.ink1) }
                else { Image(systemName: enables ? "play.fill" : "pause.fill").font(.system(size: 14, weight: .semibold)) }
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(enables ? Palette.onAccent : Palette.ink1)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(enables ? Palette.accentFill : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selectedCount == 0 || running != nil)
        .opacity(selectedCount == 0 ? 0.4 : 1)
        .accessibilityLabel(title)
        .accessibilityIdentifier(enables ? "accounts.batch.enable" : "accounts.batch.stop")
    }
}

/// 20 §1.3 in selection mode: 全选 / 取消全选 over the section's loaded rows, and “已选 N” while it is collapsed. A sibling of
/// the header's own button, so the two never fire together.
struct AccountSectionSelectControl: View {
    let platform: String
    let platformName: String
    let picked: Int
    let allSelected: Bool
    let isCollapsed: Bool
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isCollapsed, picked > 0 {
                Text(AccountBatchPlan.pickedInSection(picked))
                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.accent).lineLimit(1).fixedSize()
                    // The header's own label reads it (design VaSection).
                    .accessibilityHidden(true)
            }
            let title = AccountBatchPlan.sectionToggleTitle(allSelected: allSelected)
            Button(title, action: onToggle)
                .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Palette.accent).lineLimit(1).fixedSize()
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .disabled(!isEnabled)
                .accessibilityLabel("\(platformName)：\(title)")
                .accessibilityIdentifier("accounts.section.\(platform).selectAll")
        }
    }
}

/// 20 §8.3: every account that did not go through as “名称（#id）” and its reason, never the server's text.
struct AccountBatchResultsSheet: View {
    let results: AccountBatchResults
    let onUndo: (AccountBatchUndo) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results.rows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title).font(.body.weight(.medium)).foregroundStyle(Palette.ink1)
                            Text(row.reason).font(.subheadline).foregroundStyle(Palette.ink2)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("accounts.batch.result.\(row.id)")
                    }
                } header: {
                    Text(results.siteName).accessibilityIdentifier("accounts.batch.results.site")
                }
                if let undo = results.undo {
                    Section {
                        Button(AccountBatchPlan.undoTitle(original: !undo.enabled, count: undo.ids.count)) {
                            dismiss()
                            onUndo(undo)
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("accounts.batch.results.undo")
                    }
                }
            }
            .navigationTitle(AccountBatchPlan.resultsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("accounts.batch.results.done")
                }
            }
        }
        .accessibilityIdentifier("accounts.batch.results")
        .presentationDetents([.medium, .large])
    }
}

/// 20 §1.1 / §8.1: “选择” on the left (“完成”, prominent, while selecting), the tab bar hidden and the dock at the bottom while
/// selecting, and the results sheet. The light refresh pauses while selecting or while the sheet is open (20 §1.6).
private struct AccountBatchModeModifier: ViewModifier {
    let list: AccountListModel
    @Bindable var runner: AccountBatchRunner

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { selectButton }
            }
            .toolbar(list.isSelecting ? .hidden : .automatic, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                if list.isSelecting {
                    AccountBatchDock(selectedCount: list.selection.count, running: runner.running, isConfirming: runner.isConfirming,
                                     onStop: { Task { await runner.run(enabled: false) } }, onEnable: { Task { await runner.run(enabled: true) } })
                        .padding(EdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14))
                }
            }
            .sheet(item: $runner.results) { results in
                AccountBatchResultsSheet(results: results) { undo in Task { await runner.undo(undo) } }
            }
            .onChange(of: runner.results != nil) { _, shown in list.setSheetPresented(shown) }
    }

    @ViewBuilder private var selectButton: some View {
        if list.isSelecting {
            Button("完成") { list.endSelecting() }
                .buttonStyle(.glassProminent)
                .disabled(runner.isRunning)
                .accessibilityIdentifier("accounts.select")
        } else {
            Button("选择") { list.beginSelecting() }
                .disabled(list.list.value == nil)
                .accessibilityIdentifier("accounts.select")
        }
    }
}

extension View {
    func accountBatchMode(list: AccountListModel, runner: AccountBatchRunner) -> some View {
        modifier(AccountBatchModeModifier(list: list, runner: runner))
    }
}
