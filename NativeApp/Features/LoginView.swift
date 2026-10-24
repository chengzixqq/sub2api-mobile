import SwiftUI
import Sub2Core

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var kind = AuthenticationKind.password
    @State private var email = ""
    @State private var password = ""
    @State private var key = ""
    @State private var code = ""
    @State private var challenge: TwoFactorChallenge?
    @State private var loginClient: APIClient?
    @State private var pendingProfile: ServerProfile?
    @State private var pendingAttempt: UUID?
    @State private var proof: CaptchaProof?
    @State private var proofExpiresAt: Date?
    @State private var captcha: CaptchaRequest?
    @State private var error: String?
    @State private var busy = false
    @State private var unsupported = false
    @State private var task: Task<Void, Never>?
    /// X-Device-ID of this login; saved with the credential once connected, renewed when the address changes (00 §1.2).
    @State private var draftDeviceID = UUID()
    /// A known site's login page (00 §1.1, §1.7.4): name, address and sign-in method prefilled, the reason shown on top.
    private let prompt: LoginPrompt?

    init(prompt: LoginPrompt? = nil) {
        self.prompt = prompt
        guard let site = prompt?.profile else { return }
        _name = State(initialValue: site.name)
        _address = State(initialValue: site.baseURL.absoluteString)
        // Until the three-way login page (S0-16) a sat_ token is pasted into the Admin Key field.
        _kind = State(initialValue: site.authentication == .password ? .password : .adminKey)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill").font(.largeTitle).foregroundStyle(.indigo)
                    Text("连接你的 Sub2API").font(.title2.bold())
                    Text("管理站点、上游账号与用户。凭据仅保存在本机安全存储。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }
            if let notice = prompt?.notice {
                Section { Text(notice).foregroundStyle(.orange).accessibilityIdentifier("login.notice") }
            }
            Section("站点") {
                TextField("站点名称", text: $name).textContentType(.organizationName).accessibilityIdentifier("login.name")
                TextField("https://sub2.example.com", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("login.url")
                if prompt?.reusesSiteID != true {
                    Text("同一站点可保存多个身份，建议为每个账号使用不同名称。新增登录将建立独立身份。").font(.footnote).foregroundStyle(.secondary)
                }
            }.disabled(busy || challenge != nil)
            Section("身份验证") {
                Picker("登录方式", selection: $kind) {
                    Text("邮箱和密码").tag(AuthenticationKind.password)
                    Text("Admin Key").tag(AuthenticationKind.adminKey)
                }.accessibilityIdentifier("login.kind")
                if kind == .adminKey {
                    SecureField("Admin Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("login.key")
                } else {
                    TextField("管理员邮箱", text: $email).keyboardType(.emailAddress).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("login.email")
                    SecureField("密码", text: $password).textContentType(.password).accessibilityIdentifier("login.password")
                }
            }.disabled(busy || challenge != nil)
            if let challenge {
                Section("两步验证") {
                    if let masked = challenge.maskedEmail { Text(masked).foregroundStyle(.secondary) }
                    TextField("6 位动态验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .accessibilityIdentifier("login.totp")
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("login.error") } }
            if unsupported {
                Section { Label("当前版本仅支持管理员。普通用户功能将在后续版本提供，请使用站点 Web 后台。", systemImage: "person.crop.circle.badge.exclamationmark") }
            }
            Section {
                Button(action: submit) {
                    HStack { Spacer(); if busy { ProgressView() }; Text(challenge == nil ? "连接站点" : "完成验证"); Spacer() }.frame(minHeight: 44)
                }.disabled(busy).accessibilityIdentifier("login.submit")
                if challenge != nil {
                    Button("重新登录") { resetChallenge() }.disabled(busy).frame(minHeight: 44)
                }
            }
            if !model.profiles.isEmpty && model.activeProfile == nil {
                Section("已保存的站点") {
                    ForEach(model.profiles) { profile in
                        Button { Task { await model.switchTo(profile) } } label: {
                            LabeledContent(profile.name, value: profile.baseURL.host ?? "")
                        }.frame(minHeight: 44).accessibilityIdentifier("login.saved.\(profile.name)")
                    }
                }
            }
            if model.activeProfile == nil && !model.pendingBalances.isEmpty {
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
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Sub2 Mobile")
        .toolbar { if model.activeProfile != nil { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } } }
        .sheet(item: $captcha) { request in
            CaptchaView(request: request) { result in
                captcha = nil
                switch result {
                case .success(let proof): self.proof = proof; proofExpiresAt = Date().addingTimeInterval(120); submit()
                case .failure(let failure): proof = nil; proofExpiresAt = nil; error = failure.localizedDescription
                }
            }
        }
        .onChange(of: kind) { _, _ in resetChallenge() }
        .onChange(of: address) { _, _ in resetChallenge(); draftDeviceID = UUID() }
        .onDisappear { task?.cancel(); model.cancelConnection(); password = ""; key = ""; proof = nil; proofExpiresAt = nil; code = "" }
    }

    /// A known site keeps its id when the address is unchanged (LoginPrompt, D17); “添加站点” always makes a new site.
    private func siteProfile(name: String, url: URL) -> ServerProfile {
        prompt?.profile(name: name, url: url, authentication: kind) ?? ServerProfile(name: name, baseURL: url, authentication: kind)
    }
    /// The same site signs in with its own device ID (session binding, 00 §1.2); a new site with this form's draft.
    private func loginDeviceID(for profile: ServerProfile) async throws -> UUID {
        guard profile.id == prompt?.profile.id else { return draftDeviceID }
        return try await model.credentials.deviceID(serverID: profile.id)
    }

    private func resetChallenge() {
        challenge = nil; code = ""; proof = nil; proofExpiresAt = nil; loginClient = nil; pendingProfile = nil; pendingAttempt = nil
    }

    private func submit() {
        error = nil; unsupported = false
        guard !busy else { return }
        let profile: ServerProfile
        do {
            let url = try AppModel.validatedURL(address)
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure("请填写站点名称。") }
            guard kind == .adminKey ? !key.isEmpty : (!email.isEmpty && !password.isEmpty) else { throw AppFailure("请完整填写登录凭据。") }
            profile = pendingProfile ?? siteProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), url: url)
        } catch { self.error = error.localizedDescription; return }
        busy = true
        task = Task {
            defer { busy = false }
            let attempt = pendingAttempt ?? model.beginConnection()
            pendingAttempt = attempt
            do {
                let deviceID = try await loginDeviceID(for: profile)
                if model.isUITesting {
                    let fixture = kind == .adminKey ? Credential.fromAPIKey(key) : DemoData.passwordCredential
                    try await model.connect(profile: profile, credential: fixture, deviceID: deviceID, attempt: attempt)
                    password = ""; key = ""; dismiss(); return
                }
                if kind == .adminKey {
                    // A pasted sat_ token is an access token (00 §1.3).
                    try await model.connect(profile: profile, credential: .fromAPIKey(key), deviceID: deviceID, attempt: attempt)
                } else {
                    let candidate = loginClient ?? APIClient(server: profile, deviceID: deviceID)
                    loginClient = candidate
                    pendingProfile = profile
                    let session: AuthSession
                    if let challenge {
                        guard code.count == 6 && code.allSatisfy(\.isNumber) else { throw AppFailure("请输入 6 位动态验证码。") }
                        session = try await candidate.completeTOTP(tempToken: challenge.tempToken, code: code)
                    } else {
                        let settings = try await candidate.publicSettings()
                        if let expiry = proofExpiresAt, expiry <= Date() { proof = nil; proofExpiresAt = nil }
                        // Decoding no longer rejects a conflict; stop here with the catalog wording (00 §1.4).
                        if settings.isCaptchaConflict { throw APIError.server(status: 503, reason: "CAPTCHA_PROVIDER_CONFLICT", context: .login) }
                        if settings.captchaEnabled && proof == nil {
                            guard ["turnstile", "tencent", "aliyun"].contains(settings.captchaProvider ?? "") else {
                                throw AppFailure("此站点的验证码暂不支持原生验证，请使用 Web 后台。")
                            }
                            captcha = CaptchaRequest(server: profile, provider: settings.captchaProvider!, path: CaptchaBridge.defaultPath, showsFallbackHint: false)
                            return
                        }
                        let result = try await candidate.login(email: email, password: password, proof: proof, deviceName: model.deviceName,
                                                               declaresCaptchaProvider: settings.hasCaptchaProviderKey)
                        proof = nil
                        proofExpiresAt = nil
                        switch result {
                        case .twoFactor(let next): challenge = next; return
                        case .authenticated(let authenticated): session = authenticated
                        }
                    }
                    // Other roles never get here: login already discarded their session (00 §1.11).
                    try await model.connect(profile: profile, credential: .tokens(session.tokens), deviceID: deviceID, attempt: attempt)
                }
                password = ""; key = ""; code = ""; proof = nil; proofExpiresAt = nil; dismiss()
            } catch {
                proof = nil
                proofExpiresAt = nil
                if let failure = error as? APIError, failure == .administratorRequired { unsupported = true }
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
}
