import SwiftUI
import Sub2Core

/// 60 §4: the root page without a connected site, and the 添加站点 / 重新登录 sheet over the tabs. LoginController runs the
/// flow; this view draws it and forwards edits and sheet results.
struct LoginView: View {
    private let prompt: LoginPrompt?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controller: LoginController?

    /// A known site's login page (00 §1.1, §1.7.4): name, address and sign-in method prefilled, the reason shown on top.
    init(prompt: LoginPrompt? = nil) { self.prompt = prompt }

    var body: some View {
        Group {
            if let controller { LoginForm(controller: controller) } else { Color.clear }
        }
        .navigationTitle(model.activeProfile == nil ? "Sub2 Mobile" : prompt == nil ? "添加站点" : "重新登录")
        .toolbar {
            if model.activeProfile != nil {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("login.cancel") }
            }
        }
        .onAppear { if controller == nil { controller = LoginController(prompt: prompt, environment: makeEnvironment()) } }
        .onDisappear { let controller = controller; Task { await controller?.cancel() } }
    }

    private func makeEnvironment() -> LoginEnvironment {
        let model = model, dismiss = dismiss
        return LoginEnvironment(
            deviceName: model.deviceName,
            makeGateway: { profile, deviceID in
                if model.isUITesting { return DemoLoginGateway() }
                // A login client has no session hook and no security interceptor (D13).
                return APIClient(server: profile, deviceID: deviceID)
            },
            storedDeviceID: { try await model.credentials.deviceID(serverID: $0) },
            connect: { profile, credential, deviceID in
                try await model.connect(profile: profile, credential: credential, deviceID: deviceID, attempt: model.beginConnection())
                return model.siteSession?.identityEmail
            },
            cancelConnection: { model.cancelConnection() },
            didConnect: { email in
                model.receipts.show(Receipt(text: LoginCopy.connectedReceipt(email: email), systemImage: "checkmark.circle"))
                dismiss()
            })
    }
}

/// 60 §4.3: site, sign-in method, credential, agreement, error and 连接站点; on the root page also the saved sites and the
/// records still awaiting reconciliation.
private struct LoginForm: View {
    @Bindable var controller: LoginController
    @Environment(AppModel.self) private var model
    @State private var openedDocument: LoginAgreementDocument?

    var body: some View {
        Form {
            if let notice = controller.prompt?.notice {
                Section { Text(notice).foregroundStyle(Palette.cautionInk).accessibilityIdentifier("login.notice") }
            }
            siteSection
            methodSection
            credentialSection
            if let agreement = controller.agreement, agreement.mode == .checkbox {
                Section { LoginAgreementRow(agreement: agreement, checked: $controller.agreementChecked) { openedDocument = $0 } }
                    .disabled(controller.isBusy)
            }
            if let notice = controller.notice {
                Section { Text(notice).foregroundStyle(Palette.criticalInk).accessibilityIdentifier("login.error") }
            }
            Section { submitButton }
            if model.activeProfile == nil { LoginSavedSections() }
        }
        .scrollDismissesKeyboard(.immediately)
        .task(id: controller.address) { await controller.prefetchSite() }
        .task(id: controller.cooldownUntil) { await clearCooldown() }
        .onChange(of: controller.address) { controller.addressDidChange() }
        .onChange(of: controller.method) { controller.methodDidChange() }
        .onChange(of: controller.key) { controller.keyDidChange() }
        .sheet(item: $controller.captcha, onDismiss: { Task { await controller.captchaDismissed() } }) { request in
            CaptchaView(request: request) { controller.captchaCompleted($0) }
        }
        .sheet(isPresented: Binding(get: { controller.challenge != nil }, set: { if !$0 { controller.cancelTwoFactor() } })) {
            LoginTwoFactorSheet(controller: controller)
        }
        .sheet(item: Binding(get: { controller.agreementPrompt }, set: { if $0 == nil { controller.rejectAgreement() } }),
               onDismiss: { Task { await controller.agreementDismissed() } }) { agreement in
            LoginAgreementSheet(agreement: agreement, accept: controller.acceptAgreement, reject: controller.rejectAgreement)
        }
        .sheet(item: $openedDocument) { LoginDocumentSheet(document: $0) }
    }

    private var siteSection: some View {
        Section {
            TextField("https://sub2.example.com", text: $controller.address)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel("站点地址").accessibilityIdentifier("login.url")
            TextField(controller.namePlaceholder, text: $controller.name).textContentType(.organizationName)
                .accessibilityLabel("站点名称").accessibilityIdentifier("login.name")
            if controller.showsBackendModeHint {
                Label(LoginSite.backendModeHint, systemImage: "lock.shield").font(.footnote).foregroundStyle(Palette.cautionInk)
                    .accessibilityIdentifier("login.backendMode")
            }
        } header: {
            Text("站点")
        } footer: {
            if controller.prompt?.reusesSiteID != true {
                Text("同一站点可保存多个身份，建议为每个账号使用不同名称。新增登录将建立独立身份。")
            }
        }
        .disabled(controller.isBusy)
    }

    private var methodSection: some View {
        Section {
            ForEach(LoginMethod.allCases) { method in
                let selected = controller.method == method
                Button { controller.method = method } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? Palette.accent : Palette.ink3).accessibilityHidden(true)
                        Text(method.title).foregroundStyle(Palette.ink1)
                        if let badge = method.badge { ToneBadge(text: badge, tone: method == .password ? .ok : .caution) }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("login.method.\(method.rawValue)")
            }
        } header: {
            Text("登录方式")
        } footer: {
            if let note = controller.method.note { Text(note).accessibilityIdentifier("login.method.note") }
        }
        .disabled(controller.isBusy)
    }

    /// The token and the Admin Key share one field in one branch, so a pasted `sat_` switching the method keeps the text
    /// and the focus.
    private var credentialSection: some View {
        Section {
            if controller.method.usesKey {
                SecureField("管理访问令牌或 Admin Key", text: $controller.key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("login.key")
            } else {
                TextField("管理员邮箱", text: $controller.email).keyboardType(.emailAddress).textContentType(.username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("login.email")
                SecureField("密码", text: $controller.password).textContentType(.password).accessibilityIdentifier("login.password")
            }
        }
        .disabled(controller.isBusy)
    }

    /// 00 §2.7.2: during a 429 the button counts down and cannot be tapped.
    @ViewBuilder private var submitButton: some View {
        if controller.cooldownUntil != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in submit(remaining: controller.cooldownRemaining(at: context.date)) }
        } else {
            submit(remaining: 0)
        }
    }
    private func submit(remaining: Int) -> some View {
        Button { Task { await controller.submit() } } label: {
            HStack {
                Spacer()
                if controller.isBusy { ProgressView() }
                Text(remaining > 0 ? LoginCopy.cooldownButton(remaining) : "连接站点")
                Spacer()
            }
            .frame(minHeight: 44)
        }
        .disabled(controller.isBusy || remaining > 0)
        .accessibilityIdentifier("login.submit")
    }
    private func clearCooldown() async {
        guard let until = controller.cooldownUntil else { return }
        // A little past the end, so the rounded-up remainder is 0 when the button is redrawn.
        do { try await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 0.05)) } catch { return }
        controller.cooldownElapsed()
    }
}

/// The root page's saved sites and the balance requests still awaiting reconciliation (unchanged from before S0-16).
private struct LoginSavedSections: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.profiles.isEmpty {
            Section("已保存的站点") {
                ForEach(model.profiles) { profile in
                    Button { Task { await model.switchTo(profile) } } label: {
                        LabeledContent(profile.name, value: profile.baseURL.host ?? "")
                    }.frame(minHeight: 44).accessibilityIdentifier("login.saved.\(profile.name)")
                }
            }
        }
        if !model.pendingBalances.isEmpty {
            Section("待核对的余额请求") {
                Text("以下请求保留原操作编号。退出后新增登录属于独立身份；请在原站点 Web 后台核对账务，勿新建重复操作。")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(model.pendingBalances) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(model.profileForRecord(serverID: item.serverID)?.name ?? "原站点") · 用户 #\(item.userID)")
                        Text("\(item.operation.rawValue) \(DisplayFormat.moneyExact(item.amount))").font(.caption)
                        Text(item.id.uuidString).font(.caption2).textSelection(.enabled)
                        if let profile = model.profileForRecord(serverID: item.serverID) { Link("打开原站点核对", destination: profile.baseURL).frame(minHeight: 44) }
                    }
                }
            }
        }
    }
}
