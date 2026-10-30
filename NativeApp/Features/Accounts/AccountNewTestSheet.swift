import SwiftUI
import Sub2Core

/// 20 §7.3 测试 sheet (design AnTest): the four progress rows, the result with its buttons, and the output, streaming while the
/// test runs and folded into its last line after. It opens once the account exists; only a running test offers 后台继续, and
/// nothing closes it while a request is out. Receipts show over it, and S2-10's version / mixed-channel questions ask here.
struct AccountNewTestSheet: View {
    let model: AccountNewModel
    @State private var outputExpanded = false

    private var tester: AccountNewTestController { model.tester }

    var body: some View {
        let snapshot = tester.snapshot
        NavigationStack {
            List {
                if let snapshot {
                    progress(snapshot)
                    if let block = AccountNewTestPresentation.resultBlock(snapshot) { result(block, status: snapshot.status) }
                    output
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("account-new.test.sheet")
            .navigationTitle(tester.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { leading(snapshot) } }
        }
        .overlay(alignment: .bottom) { ReceiptOverlay(inSheet: true) }
        .background { if let flow = tester.patchFlow { Color.clear.accountPatchPrompts(flow) } }
        .presentationDetents([.large])
        .interactiveDismissDisabled(snapshot?.isBusy ?? true)
        .confirmDelete(Binding(get: { tester.showsSheet ? tester.deleteRequest : nil }, set: { tester.deleteRequestChanged($0) }))
    }

    @ViewBuilder private func leading(_ snapshot: AccountNewTestSnapshot?) -> some View {
        if snapshot?.allowsBackground == true {
            Button(AccountNewTestPresentation.backgroundTitle) { tester.continueInBackground() }
                .accessibilityIdentifier("account-new.test.background")
        } else if snapshot?.isBusy == false {
            Button(AccountNewTestPresentation.closeTitle) { tester.closeSheet() }
                .accessibilityIdentifier("account-new.test.close")
        }
    }

    private func progress(_ snapshot: AccountNewTestSnapshot) -> some View {
        Section {
            ForEach(AccountNewTestPresentation.rows(snapshot)) { row in
                AccountNewTestStageRowView(row: row, models: tester.models) { tester.startTest(model: $0) }
            }
        } header: {
            Text("进度")
        } footer: {
            if snapshot.isBusy { Text(AccountNewTestPresentation.notice) }
        }
    }

    // MARK: - Result

    @ViewBuilder private func result(_ block: AccountNewTestResultBlock, status: AccountNewScheduleStatus) -> some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: block.systemImage).font(.title3).foregroundStyle(block.tone.base).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                        .accessibilityIdentifier("account-new.test.outcome")
                    if let mono = block.mono {
                        Text(mono).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink1).textSelection(.enabled)
                            .accessibilityIdentifier("account-new.test.outcome.raw")
                    }
                    if let detail = block.detail {
                        Text(detail).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier("account-new.test.outcome.detail")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .listRowBackground(block.tone.wash)
            if block.kind == .writeFailed, let flow = tester.patchFlow { AccountPatchStatusRow(flow: flow) }
            if let primary = block.primary {
                button(primary, status: status).buttonStyle(.borderedProminent).tint(Palette.accentFill)
            }
            if !block.secondary.isEmpty {
                HStack(spacing: 10) {
                    ForEach(block.secondary, id: \.self) { button($0, status: status).buttonStyle(.bordered) }
                }
            }
            if let footnote = block.footnote { Text(footnote).font(.footnote).foregroundStyle(Palette.ink2) }
            if let destructive = block.destructive {
                Button(AccountNewTestPresentation.buttonTitle(destructive, status: status), role: .destructive) { perform(destructive) }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .readOnlyGate(showsCaption: false)
                    .accessibilityIdentifier(Self.identifier(destructive))
            }
        }
    }

    @ViewBuilder private func button(_ kind: AccountNewTestResultBlock.Button, status: AccountNewScheduleStatus) -> some View {
        let control = Button { perform(kind) } label: {
            Text(AccountNewTestPresentation.buttonTitle(kind, status: status)).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
        }
        .accessibilityIdentifier(Self.identifier(kind))
        if Self.writes.contains(kind) { control.readOnlyGate(showsCaption: false) } else { control }
    }

    private func perform(_ kind: AccountNewTestResultBlock.Button) {
        switch kind {
        case .viewAccount: tester.complete(viewAccount: true)
        case .done: tester.complete(viewAccount: false)
        case .retryEnable: tester.retryEnable()
        case .editAndRetry: model.editAfterTest()
        case .retest: tester.retest()
        case .keep: tester.keep()
        case .saveInactive: tester.saveInactive()
        case .delete: tester.requestDelete()
        case .repause: model.perform(.retryPause)
        case .back: tester.showsSheet = false
        }
    }
    /// The buttons that send something: greyed for a read-only token.
    private static let writes: Set<AccountNewTestResultBlock.Button> = [.retryEnable, .retest, .saveInactive, .delete, .repause]
    private static func identifier(_ kind: AccountNewTestResultBlock.Button) -> String {
        switch kind {
        case .viewAccount: "account-new.test.view"
        case .done: "account-new.test.done"
        case .retryEnable: "account-new.test.retry-enable"
        case .editAndRetry: "account-new.test.edit"
        case .retest: "account-new.test.retest"
        case .keep: "account-new.test.keep"
        case .saveInactive: "account-new.test.inactive"
        case .delete: "account-new.test.delete"
        case .repause: "account-new.test.repause"
        case .back: "account-new.test.back"
        }
    }

    // MARK: - Output

    @ViewBuilder private var output: some View {
        let text = tester.outputLines.joined(separator: "\n")
        if tester.isOutputRunning {
            Section("测试输出") {
                Text(text).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("account-new.test.output")
            }
        } else if let summary = tester.outputSummary {
            Section {
                Button { withAnimation { outputExpanded.toggle() } } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("测试输出 · \(summary.count)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2)
                            if !outputExpanded {
                                Text(summary.last).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink1).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: outputExpanded ? "chevron.up" : "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Palette.ink3)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account-new.test.output")
                if outputExpanded {
                    Text(text).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink1).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// One progress row (design AnStage): its state, the title and the meta; the test row's model is a menu once the test has
/// ended, and picking one tests again.
private struct AccountNewTestStageRowView: View {
    let row: AccountNewTestStageRow
    let models: [AccountModelOption]
    let onModel: (String?) -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                icon.frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(row.state == .waiting ? Palette.ink3 : Palette.ink1)
                    if let detail = row.detail { Text(detail).font(.footnote).foregroundStyle(Tone.critical.ink) }
                }
                Spacer(minLength: 8)
                if !row.offersModelChange, let meta = row.meta {
                    Text(meta).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1).truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.title + "，" + Self.stateLabel(row.state))
            .accessibilityValue(row.meta ?? "")
            .accessibilityIdentifier("account-new.test.stage.\(row.stage.rawValue)")
            if row.offersModelChange { modelMenu }
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder private var icon: some View {
        switch row.state {
        case .running: ProgressView()
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Tone.ok.base)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Tone.critical.base)
        case .off: Image(systemName: "minus.circle").foregroundStyle(Palette.ink3)
        case .waiting: Image(systemName: "circle").foregroundStyle(Palette.ink3)
        }
    }
    private var modelMenu: some View {
        let meta = row.meta ?? AccountTestPresentation.defaultModelLabel
        return Menu {
            if models.isEmpty { Button(AccountTestPresentation.defaultModelLabel) { onModel(nil) } }
            ForEach(models) { option in Button(option.displayName) { onModel(option.id) } }
        } label: {
            HStack(spacing: 4) {
                Text(meta).font(.system(.footnote, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .frame(minHeight: 44)
        }
        .readOnlyGate(showsCaption: false)
        .accessibilityLabel("测试模型 \(meta)，点按更换")
        .accessibilityIdentifier("account-new.test.model")
    }
    private static func stateLabel(_ state: AccountNewTestStageState) -> String {
        switch state {
        case .waiting: "等待"
        case .running: "进行中"
        case .done: "完成"
        case .failed: "失败"
        case .off: "未进行"
        }
    }
}

extension View {
    /// The test sheet over the new-account form (S2-20), the 处理 question and the delete confirmation while the sheet is closed.
    /// The sheet opens as the account comes to exist, and again when the stop is retried from the dock.
    func accountNewTest(_ model: AccountNewModel) -> some View { modifier(AccountNewTestModifier(model: model)) }
}

private struct AccountNewTestModifier: ViewModifier {
    let model: AccountNewModel
    private var tester: AccountNewTestController { model.tester }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { tester.showsSheet }, set: { if !$0, tester.showsSheet { tester.closeSheet() } })) {
                AccountNewTestSheet(model: model)
            }
            .confirmationDialog(tester.resolveDialog?.title ?? "", isPresented: Binding(get: { tester.resolveDialog != nil },
                                                                                      set: { if !$0 { tester.resolveDialog = nil } }),
                                titleVisibility: .visible, presenting: tester.resolveDialog) { dialog in
                Button(AccountNewTestPresentation.saveInactiveVerb) { tester.saveInactive() }
                Button(dialog.keepTitle) { tester.keep() }
                Button(AccountNewTestPresentation.buttonTitle(.delete, status: tester.status), role: .destructive) { tester.requestDelete() }
                // Not `.cancel`: anchored to 处理 or 取消 the dialog is a popover, which leaves the cancel button out.
                Button(dialog.cancelTitle) {}
            } message: { dialog in
                Text(dialog.message)
            }
            .confirmDelete(Binding(get: { tester.showsSheet ? nil : tester.deleteRequest }, set: { tester.deleteRequestChanged($0) }))
            .onChange(of: model.submission.stage) { _, stage in if stage.opensTestSheet { tester.showsSheet = true } }
    }
}
