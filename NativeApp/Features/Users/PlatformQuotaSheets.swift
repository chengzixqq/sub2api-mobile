import SwiftUI
import Sub2Core

/// Which platform quota sheet is up (30 §8.1): the picker, or one platform's limits.
enum PlatformQuotaSheetRoute: Identifiable, Hashable {
    case picker
    case edit(String)
    var id: String {
        switch self {
        case .picker: "picker"
        case .edit(let platform): "edit." + platform
        }
    }
}

/// 30 §8.3 添加平台限额 (design UeAddQuotaSheet): the catalog's platforms without a quota, in its order; one opens its sheet.
struct PlatformQuotaPickerSheet: View {
    let store: PlatformQuotaStore
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.addablePlatforms, id: \.self) { platform in
                    Button { onPick(platform) } label: {
                        HStack {
                            Text(store.name(platform)).foregroundStyle(Palette.ink1)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("keys.quota.pick.\(platform)")
                }
            }
            .navigationTitle(PlatformQuotaPresentation.pickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("keys.quota.picker.cancel")
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// 30 §8.3 “<平台> 限额” (design UeQuotaSheet): three limits (empty = 不限, 0 = 禁止), each window's use and 重置该窗口, and
/// 清空三个窗口, which only clears the fields. “保存” lights only when a window really changes; saving and resetting take effect
/// at once. While a write is out the sheet cannot be swiped away.
struct PlatformQuotaEditSheet: View {
    let store: PlatformQuotaStore
    let platform: String
    let userName: String
    let hasActiveSubscription: Bool
    @State private var draft: PlatformQuotaDraft
    @State private var resetKind: PlatformQuotaWindowKind?
    @Environment(\.dismiss) private var dismiss

    init(store: PlatformQuotaStore, platform: String, userName: String, hasActiveSubscription: Bool) {
        self.store = store; self.platform = platform; self.userName = userName; self.hasActiveSubscription = hasActiveSubscription
        _draft = State(initialValue: PlatformQuotaDraft(original: store.row(platform)?.limits))
    }

    private var live: UserPlatformQuota? { store.row(platform) }
    private var name: String { store.name(platform) }
    private var isBusy: Bool { store.busyPlatforms.contains(platform) }
    private var readable: Bool { live?.limitsReadable ?? true }
    private var writable: Bool { store.canWrite && readable && !isBusy }

    var body: some View {
        NavigationStack {
            Form {
                if hasActiveSubscription { Section { PlatformQuotaSubscriptionNotice() } }
                Section {
                    Text("\(PlatformQuotaPresentation.sheetNoteLead)\(Text(PlatformQuotaPresentation.sheetNoteBold).bold())\(PlatformQuotaPresentation.sheetNoteTail)")
                        .font(.subheadline).foregroundStyle(Palette.ink1)
                }
                ForEach(PlatformQuotaWindowKind.allCases) { windowSection($0) }
                if live != nil { clearSection }
                if let message = store.sheetError ?? (readable ? nil : PlatformQuotaPresentation.unreadable) {
                    Section {
                        Text(message).font(.footnote).foregroundStyle(Palette.critical).accessibilityIdentifier("keys.quota.error")
                    }
                }
                Section {} footer: { Text(PlatformQuotaPresentation.sheetFootnote).accessibilityIdentifier("keys.quota.sheet.footnote") }
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("keys.quota.sheet")
            .navigationTitle(PlatformQuotaPresentation.sheetTitle(name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert(resetKind.map { PlatformQuotaPresentation.resetTitle(platform: name, kind: $0) } ?? "", isPresented: resetShown, presenting: resetKind) { kind in
                Button(PlatformQuotaPresentation.resetWindow, role: .destructive) { Task { await store.confirmReset(platform: platform, window: kind) } }
                Button("取消", role: .cancel) {}
            } message: { kind in
                Text(PlatformQuotaPresentation.resetMessage(userName: userName, platform: name, kind: kind, usage: live?.window(kind).usage ?? 0))
            }
        }
        .overlay(alignment: .bottom) { ReceiptOverlay(inSheet: true) }
        .interactiveDismissDisabled(isBusy)
        .onAppear { store.clearSheetError() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }.disabled(isBusy).accessibilityIdentifier("keys.quota.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isBusy {
                ProgressView().accessibilityIdentifier("keys.quota.saving")
            } else {
                Button("保存") { save() }
                    .disabled(!draft.canSave || !writable)
                    .accessibilityIdentifier("keys.quota.save")
                    .readOnlyGate(showsCaption: false)
            }
        }
    }

    private func windowSection(_ kind: PlatformQuotaWindowKind) -> some View {
        let window = live?.window(kind) ?? PlatformQuotaWindow()
        let context = store.context
        return Section {
            LabeledContent(PlatformQuotaPresentation.inputTitle(kind)) {
                HStack(spacing: 4) {
                    Text("$").foregroundStyle(Palette.ink2).accessibilityHidden(true)
                    TextField(PlatformQuotaPresentation.inputPlaceholder, text: text(kind))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .accessibilityLabel(PlatformQuotaPresentation.inputTitle(kind))
                        .accessibilityIdentifier("keys.quota.input.\(kind.rawValue)")
                }
            }
            .frame(minHeight: 44)
            if case .invalid(let message) = draft.input(kind) {
                Text(message).font(.footnote).foregroundStyle(Palette.critical).accessibilityIdentifier("keys.quota.invalid.\(kind.rawValue)")
            }
            if draft.showsZeroWarning(kind) {
                Label(PlatformQuotaPresentation.zeroWarning(name), systemImage: "octagon")
                    .font(.footnote).foregroundStyle(Palette.critical)
                    .accessibilityIdentifier("keys.quota.zero.\(kind.rawValue)")
            }
            if let live, readable, let limit = window.limit, limit > 0 {
                let cell = PlatformQuotaPresentation.cell(live, kind: kind)
                ProgressView(value: cell.progress ?? 0).tint(cell.tone?.base ?? Palette.accent).accessibilityHidden(true)
            }
            HStack(spacing: 8) {
                Text(PlatformQuotaPresentation.usageLine(window, kind: kind, now: context?.now() ?? Date(), zone: context?.serverTimeZone ?? .device))
                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("keys.quota.usage.\(kind.rawValue)")
                Spacer(minLength: 8)
                if PlatformQuotaPresentation.showsReset(window, hasQuota: live != nil) {
                    Button(PlatformQuotaPresentation.resetWindow) { resetKind = kind }
                        .buttonStyle(.borderless)
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(!store.canWrite || isBusy)
                        .accessibilityIdentifier("keys.quota.reset.\(kind.rawValue)")
                }
            }
        }
    }

    private var clearSection: some View {
        Section {
            Button { draft = draft.clearingAll() } label: {
                Label(PlatformQuotaPresentation.clearAll, systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(!writable)
            .accessibilityIdentifier("keys.quota.clear")
        }
    }

    private func text(_ kind: PlatformQuotaWindowKind) -> Binding<String> {
        Binding(get: { draft.text(kind) }, set: { value in
            draft = draft.setting(kind, to: PlatformQuotaInput.sanitized(value))
            store.clearSheetError()
        })
    }
    private var resetShown: Binding<Bool> { Binding(get: { resetKind != nil }, set: { if !$0 { resetKind = nil } }) }
    private func save() {
        guard let limits = draft.limits else { return }
        Task { if await store.save(platform: platform, limits: limits) { dismiss() } }
    }
}
