import SwiftUI
import Sub2Core

/// 30 §8.3 替换分组 (S3-15, design UeReplaceSec): under 平台限额, one row per exclusive group the user has (the page's base),
/// left out when there is none. A row opens ReplaceGroupSheet, hung on the page (UserKeyPrompts). Rows wait for the key list
/// (their count and the undo are read from it) and for “保存” to finish (S3D1-11).
struct ReplaceGroupSection: View {
    let editor: UserEditorModel
    let keys: UserKeysModel
    let groups: [AdminGroup]
    let onSelect: (Int) -> Void

    private var sources: [AdminGroup] {
        editor.baseline.map { ReplaceGroupTargets.sources(baseline: $0, catalog: UserGroupCatalog(groups: groups)) } ?? []
    }

    var body: some View {
        let sources = self.sources
        if !sources.isEmpty {
            Section {
                ForEach(sources) { row($0) }
            } header: {
                NumberedSectionHeader(title: ReplaceGroupCopy.sectionTitle, id: "keys.replace.section")
            } footer: {
                Text(ReplaceGroupCopy.footnote).accessibilityIdentifier("keys.replace.footnote")
            }
        }
    }

    private func row(_ group: AdminGroup) -> some View {
        Button { onSelect(group.id) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ReplaceGroupCopy.rowTitle(group.name)).foregroundStyle(Palette.ink1)
                    Text(ReplaceGroupCopy.rowSubtitle(keys: keys.bindingCount(groupID: group.id))).font(.footnote).foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(keys.phase != .loaded || !editor.canStartImmediateWrite)
        .accessibilityIdentifier("keys.replace.row.\(group.id)")
        .readOnlyGate()
    }
}

/// 30 §8.3–§8.4 替换专属分组 (design UeReplaceSheet): one target among the active exclusive standard groups the user neither has
/// nor added in the draft, then the confirmation; the replace takes effect at once. The sheet stays on a refusal (the
/// directory is read again) and cannot be swiped away while the replace is out.
struct ReplaceGroupSheet: View {
    let editor: UserEditorModel
    let keys: UserKeysModel
    @State private var flow: ReplaceGroupFlow
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    init(source: Int, editor: UserEditorModel, keys: UserKeysModel) {
        self.editor = editor; self.keys = keys
        _flow = State(initialValue: ReplaceGroupFlow(sourceGroupID: source, editor: editor, keys: keys))
    }

    private var groups: [AdminGroup] { model.groupDirectory?.groups ?? [] }
    private var options: [AdminGroup] {
        guard let baseline = editor.baseline else { return [] }
        return ReplaceGroupTargets.options(source: flow.sourceGroupID, baseline: baseline, draft: editor.draft, catalog: UserGroupCatalog(groups: groups))
    }
    private var target: AdminGroup? { options.first { $0.id == flow.target } }
    private var sourceName: String { UserKeyPresentation.groupName(flow.sourceGroupID, groups: groups) }
    private var boundKeys: Int { keys.bindingCount(groupID: flow.sourceGroupID) }
    private var canSubmit: Bool { target != nil && !flow.isBusy && keys.phase == .loaded && editor.canStartImmediateWrite }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(ReplaceGroupCopy.sheetNote(source: sourceName, keys: boundKeys))
                        .font(.subheadline).foregroundStyle(Palette.ink1)
                        .accessibilityIdentifier("keys.replace.note")
                }
                Section {
                    if options.isEmpty {
                        Text(ReplaceGroupCopy.empty).foregroundStyle(Palette.ink2).frame(minHeight: 44).accessibilityIdentifier("keys.replace.empty")
                    }
                    ForEach(options) { option($0) }
                }
                if let error = flow.error {
                    Section { Text(error).font(.footnote).foregroundStyle(Palette.critical).accessibilityIdentifier("keys.replace.error") }
                }
            }
            .accessibilityIdentifier("keys.replace.sheet")
            .navigationTitle(ReplaceGroupCopy.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(flow.isBusy).accessibilityIdentifier("keys.replace.cancel")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { submitBar }
            .alert(target.map { ReplaceGroupCopy.confirmTitle(source: sourceName, target: $0.name) } ?? "", isPresented: $flow.asksConfirmation,
                   presenting: target) { target in
                Button(ReplaceGroupCopy.confirm) { Task { await flow.confirm(model: model) } }
                Button("取消", role: .cancel) {}
            } message: { target in
                Text(ReplaceGroupCopy.confirmMessage(user: editor.editDisplayName, source: sourceName, target: target.name, keys: boundKeys))
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(flow.isBusy)
        .onChange(of: flow.finished) { _, finished in if finished { dismiss() } }
    }

    private func option(_ group: AdminGroup) -> some View {
        let on = flow.target == group.id
        return Button { flow.select(group.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").font(.title3)
                    .foregroundStyle(on ? Palette.accent : Palette.ink3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).foregroundStyle(Palette.ink1)
                    Text(ReplaceGroupCopy.optionSubtitle(group, platformName: UserEditAccessSection.platformName(group)))
                        .font(.footnote).foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(flow.isBusy)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("keys.replace.option.\(group.id)")
    }

    private var submitBar: some View {
        Button { flow.askConfirmation() } label: {
            HStack(spacing: 8) {
                if flow.isBusy { ProgressView() }
                Text(ReplaceGroupCopy.submit(target: target?.name))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSubmit)
        .readOnlyGate(showsCaption: false)
        .accessibilityIdentifier("keys.replace.submit")
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
