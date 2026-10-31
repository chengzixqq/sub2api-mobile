import SwiftUI
import Sub2Core

/// `.redeemGenerate` (60 §10): 类型 → 面额与数量 → 有效期与确认 in the sheet's NavigationStack, then in the same sheet the result
/// (S6-06's RedeemResultView) or 结果待核对 (S6-06's RedeemReconcileView, which has its own NavigationStack). The sheet stays while
/// Face ID asks or the request is out (10.5); a new session closes it.
struct RedeemGenerateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var state = RedeemGenerateModel()

    var body: some View {
        content
            .interactiveDismissDisabled(state.isWorking)
            .task(id: session?.generation) { await model.groupDirectory?.ensureLoaded() }
            .onChange(of: model.sessionGeneration) { _, _ in dismiss() }
    }

    @ViewBuilder private var content: some View {
        switch state.phase {
        case .editing: wizard
        case .generated(let codes, let replayed, let spec): result(codes, replayed: replayed, spec: spec)
        case .pending(let batchID): RedeemReconcileView(batchID: batchID)
        }
    }

    private var now: Date { session?.client.serverClock.now() ?? Date() }
    private var zone: ServerTimeZone { session?.site.serverTimeZone ?? .device }

    // MARK: Wizard

    private var wizard: some View {
        let groups = RedeemGenerateModel.subscriptionGroups(model: model), step = state.wizard.step
        return NavigationStack {
            VStack(spacing: 0) {
                RedeemGenerateStepBar(step: step)
                switch step {
                case .type:
                    RedeemTypeStep(selected: state.wizard.type) { type in state.update { $0.choosing(type) } }
                case .value:
                    RedeemValueStep(state: state, subscriptionGroups: groups)
                case .expiry:
                    RedeemExpiryStep(state: state, subscriptionGroups: groups, now: now, timeZone: zone.timeZone) {
                        state.submit(model: model, subscriptionGroups: groups, now: now, timeZone: zone.timeZone)
                    }
                }
            }
            .background(Palette.sheetBackground)
            .navigationTitle(step.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { leadingButton(step) } }
        }
        .overlay { if state.isVerifying { RedeemFaceIDOverlay() } }
        .alert(state.confirmation?.summary.confirmTitle ?? "", isPresented: confirmationShown, presenting: state.confirmation) { shown in
            Button(shown.summary.confirmButton, role: shown.summary.isDestructive ? .destructive : nil) { state.confirm(shown, model: model) }
            Button("取消", role: .cancel) {}
        } message: { shown in
            Text(shown.message)
        }
    }

    @ViewBuilder private func leadingButton(_ step: RedeemGenerateStep) -> some View {
        if step == .type {
            Button(step.leadingTitle) { dismiss() }.accessibilityIdentifier("sheet.close")
        } else {
            Button(step.leadingTitle) { state.update { $0.goingBack() } }
                .disabled(state.isWorking)
                .accessibilityIdentifier("redeem.generate.back")
        }
    }

    private var confirmationShown: Binding<Bool> {
        let id = state.confirmation?.id
        return Binding(get: { id != nil && state.confirmation?.id == id }, set: { if !$0, let id { state.dismissConfirmation(id) } })
    }

    // MARK: Result

    private func result(_ codes: [AdminRedeemCode], replayed: Bool, spec: RedeemGenerateSpec) -> some View {
        NavigationStack {
            ScrollView {
                RedeemResultView(kind: replayed ? .replayed : .generated, spec: spec, codes: codes, timeZone: zone).padding(16)
            }
            .background(Palette.sheetBackground)
            .navigationTitle("生成结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.accessibilityIdentifier("sheet.close") }
            }
            .accessibilityIdentifier("redeem.generate.result")
        }
    }
}

/// 60 §10.5: “Face ID · 验证后生成兑换码” over the sheet while the check runs.
private struct RedeemFaceIDOverlay: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "faceid").font(.system(size: 48, weight: .regular)).foregroundStyle(Palette.accent).accessibilityHidden(true)
            Text("Face ID").font(.headline).foregroundStyle(Palette.ink1)
            Text("验证后生成兑换码").font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("redeem.generate.overlay")
    }
}
