import SwiftUI
import Sub2Core
import UniformTypeIdentifiers

/// 20 §7.1 新建账号 (design AnForm): a tall sheet with 取消 on the left, “新建账号” and the 还差 / created subtitle; the sections in
/// order, the glass dock at the bottom, the receipts above it. With a platform picked it cannot be swiped away; 取消 asks first.
/// The form closes once the account exists outside the scheduler (S2-20 opens the test sheet there instead).
struct AccountNewView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router

    var body: some View { AccountNewForm(app: app, router: router) }
}

private struct AccountNewForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AccountNewModel
    @State private var importingVertex = false

    init(app: AppModel, router: AppRouter) { _model = State(initialValue: AccountNewModel(app: app, router: router)) }

    var body: some View {
        NavigationStack(path: $model.path) {
            ScrollViewReader { scroller in
                Form {
                    if model.isPauseUnconfirmed, let id = model.submission.createdAccountID { pauseBanner(id) }
                    // 00 §2.5.4 step 4: nothing changes while a result is out or once the account exists.
                    Group {
                        AccountNewPlatformSection(model: model)
                        AccountNewCredentialSection(model: model, importingVertex: $importingVertex)
                        AccountNewNameSection(model: model)
                        AccountNewGroupSection(model: model)
                        AccountNewScheduleSection(model: model)
                        AccountNewNetworkSection(model: model)
                        AccountNewMoreSection(model: model)
                    }
                    .disabled(model.submission.locksForm)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation { scroller.scrollTo(target, anchor: .top) }
                    model.scrollTarget = nil
                }
                .onChange(of: model.isPauseUnconfirmed) { _, shown in if shown { model.scrollTarget = .banner } }
            }
            .overlay(alignment: .bottom) { ReceiptOverlay() }
            .safeAreaInset(edge: .bottom) {
                AccountNewDock(content: model.dock, onJump: { model.jumpToFirstMissing() }, onAction: { model.perform($0) })
            }
            .navigationTitle(AccountNewCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(model.subtitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancel() }.disabled(model.submission.isBusy).accessibilityIdentifier("account-new.cancel")
                }
            }
            .navigationDestination(for: AccountNewPage.self) { destination($0) }
            .mixedChannelQuestion(model)
        }
        .interactiveDismissDisabled(model.blocksInteractiveDismiss)
        .accountNewPrompts(model, dismiss: { dismiss() })
        .fileImporter(isPresented: $importingVertex, allowedContentTypes: [.json]) { model.importVertex($0.map { [$0] }) }
        .onChange(of: model.draft) { _, draft in model.submission.draftDidChange(try? draft.createRequest()) }
        .onChange(of: model.isFinished) { _, finished in if finished { dismiss() } }
        .task { await model.load() }
    }

    private func pauseBanner(_ id: Int) -> some View {
        Section {
            StatusBanner(tone: .critical, systemImage: "exclamationmark.octagon.fill", title: AccountNewCopy.pauseBannerTitle,
                         detail: AccountNewCopy.pauseBannerDetail(id: id)) { EmptyView() }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("account-new.banner")
                .id(AccountNewModel.Anchor.banner)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    @ViewBuilder private func destination(_ page: AccountNewPage) -> some View {
        switch page {
        case .proxy:
            AccountProxyPicker(selection: model.draft.proxyID) { model.pickProxy($0) }
                .navigationTitle("代理").navigationBarTitleDisplayMode(.inline)
        case .expiry:
            AccountExpiryPicker(expiresAt: $model.draft.expiresAt, now: model.app.serverNow(), serverTimeZone: serverTimeZone,
                                onCustom: { model.path.append(.customExpiry) }, onDone: { model.path.removeAll() })
        case .customExpiry:
            AccountExpiryCustomPage(expiresAt: $model.draft.expiresAt, now: model.app.serverNow(), onDone: { model.path.removeAll() })
        }
    }
    private var serverTimeZone: ServerTimeZone { model.app.siteSession?.serverTimeZone ?? .device }

    private func cancel() {
        if model.cancelRequested() { dismiss() }
    }
}

private extension View {
    /// 20 §0.4-7 / §7.4-1: 继续创建 sends the confirmation under a new key; 返回修改分组 scrolls to the groups.
    func mixedChannelQuestion(_ model: AccountNewModel) -> some View {
        alert(AccountNewCopy.mixedTitle, isPresented: Binding(get: { model.mixedChannelWarning != nil }, set: { _ in }),
              presenting: model.mixedChannelWarning) { _ in
            Button(AccountNewCopy.mixedContinue, role: .destructive) { model.confirmMixedChannel() }
            Button(AccountNewCopy.mixedBack, role: .cancel) { model.declineMixedChannel() }
        } message: { warning in
            Text(warning.message)
        }
    }

    /// S2-18's questions (放弃 / 换平台 / 换方式 / 切换授权方式), and the stop or the create that was not confirmed.
    func accountNewPrompts(_ model: AccountNewModel, dismiss: @escaping () -> Void) -> some View {
        let question = model.prompt?.confirmation
        return alert(question?.title ?? "", isPresented: Binding(get: { model.prompt?.confirmation != nil },
                                                                 set: { if !$0, model.prompt?.confirmation != nil { model.prompt = nil } }),
                     presenting: question) { question in
            Button(question.confirmTitle, role: .destructive) { if model.confirmPrompt() { dismiss() } }
            Button(question.cancelTitle, role: .cancel) { model.prompt = nil }
        } message: { question in
            Text(question.message)
        }
        .confirmationDialog(model.prompt == .createUnconfirmed ? AccountNewCopy.createUnconfirmedTitle(name: model.accountName)
                                : AccountNewCopy.pauseUnconfirmedTitle(name: model.accountName),
                            isPresented: Binding(get: { model.prompt?.isResolution == true },
                                                 set: { if !$0, model.prompt?.isResolution == true { model.prompt = nil } }),
                            titleVisibility: .visible, presenting: model.prompt) { prompt in
            if prompt == .createUnconfirmed {
                Button(AccountNewDockContent.Action.reconcile.title) { model.prompt = nil; model.perform(.reconcile) }
            } else {
                Button(AccountNewCopy.pauseRetry) { model.prompt = nil; model.perform(.retryPause) }
            }
            Button(AccountNewCopy.closeAnyway, role: .destructive) { model.prompt = nil; model.closeAnyway() }
            Button(AccountNewCopy.keepHandling, role: .cancel) { model.prompt = nil }
        } message: { prompt in
            Text(prompt == .createUnconfirmed ? AccountNewCopy.createUnconfirmedMessage
                 : AccountNewCopy.pauseUnconfirmedMessage(id: model.submission.createdAccountID ?? 0))
        }
    }
}
