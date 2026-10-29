import Foundation

/// 30 §5.4 steps 2–4: what happens between the passing local check and the request.
public enum UserCreatePlan: Sendable, Equatable {
    case send
    /// Not an administrator, with an initial balance above 0.
    case confirmInitialBalance(Decimal)
    /// An administrator: step-up first (30 §0.4), then the confirmation, whatever the balance.
    case stepUpThenConfirm

    public init(role: AdminUserRole, initialBalance: Decimal?) {
        if role == .admin { self = .stepUpThenConfirm }
        else if let amount = initialBalance, amount > 0 { self = .confirmInitialBalance(amount) }
        else { self = .send }
    }
}

/// The confirmation before a new user is sent (30 §5.4 steps 2–3). Amounts are echoed as typed (`moneyExact`).
public struct UserCreateConfirmation: Sendable, Equatable {
    public let title: String
    public let message: String
    public let confirmTitle: String
    public let isDestructive: Bool

    /// “创建管理员「何琪」？”; destructive only with an initial balance, whose line carries the Face ID line.
    public static func administrator(name: String, initialBalance: Decimal?, siteName: String, stepUpVerified: Bool, faceIDLine: String?) -> Self {
        let lead = (UserEditCopy.adminGrantLead(stepUpVerified: stepUpVerified) ?? "") + UserEditCopy.adminGrantBody
        guard let amount = initialBalance, amount > 0 else {
            return Self(title: "创建管理员「\(name)」？", message: lead, confirmTitle: "创建管理员", isDestructive: false)
        }
        let money = "\n初始余额 \(DisplayFormat.moneyExact(amount)) · 站点 \(siteName)" + (faceIDLine.map { "\n" + $0 } ?? "")
        return Self(title: "创建管理员「\(name)」？", message: lead + money, confirmTitle: "创建管理员", isDestructive: true)
    }
    /// “创建「何琪」并入账 $20.00？”; without users.balance_ledger the balance is written directly, with no ledger row.
    public static func initialBalance(name: String, amount: Decimal, siteName: String, hasBalanceLedger: Bool, faceIDLine: String?) -> Self {
        let money = DisplayFormat.moneyExact(amount)
        let ledger = hasBalanceLedger ? "会写一条“初始余额”记录到充值与调整记录。" : "创建时直接写入，不会出现在“充值与调整记录”里。"
        let message = "站点 \(siteName) · 初始余额 \(money)。" + ledger + (faceIDLine.map { "\n" + $0 } ?? "")
        return Self(title: "创建「\(name)」并入账 \(money)？", message: message, confirmTitle: "创建并入账 \(money)", isDestructive: true)
    }
}

/// 30 §5.4 receipts; none offers undo (only deleting the user takes it back).
public enum UserCreateReceipt {
    public static func created(name: String, initialBalance: Decimal?) -> String {
        guard let amount = initialBalance, amount > 0 else { return "已创建用户「\(name)」" }
        return "已创建用户「\(name)」，初始余额 \(DisplayFormat.moneyExact(amount))"
    }
    public static let attributesFailed = "用户已创建，自定义属性没保存成功，可在编辑用户里补填"
    public static let foundOnServer = "已在服务器上找到这个用户"
    public static let notCreated = "没有创建成功，可以再试一次"
    public static func pendingIssues(_ count: Int) -> String { UserAccessDraft.pendingIssuesMessage(count) }
}

/// 30 §5.5: one failed creation, classified. Never the server's message (00 §3.4): the words are this table's or the catalog's.
public struct UserCreateFailure: Sendable, Equatable {
    public enum Next: Sendable, Equatable {
        /// Back to the form; the same number goes out again while the draft stays as it was.
        case unfreeze
        /// Back to the form; the next send needs a new number.
        case unfreezeWithNewKey
        /// A security prompt cleared it: confirm again with the same number and bytes (00 §2.6.2 step 4).
        case reconfirm
        /// The result is unknown: look the address up (30 §5.4 step 7).
        case readBack
    }
    public let receipt: String?
    /// Rows marked by the server's answer; the first one is where the page goes.
    public let fieldIssues: [UserDraftIssue]
    public let next: Next
    /// The answer whose “详情” the page offers (00 §3.4): a request body the server would not bind.
    public let details: APIError?
    /// 00 §2.5.3 IDEMPOTENCY_STORE_UNAVAILABLE: the same number may not go out again before then.
    public let retryNotBefore: Date?

    static let emailTaken = "这个邮箱已被注册"
    static let invalidRequest = "服务器没有接受填写的内容（错误码 HTTP 400），请检查邮箱和密码"
    public static let storeUnavailable = "服务器暂时无法受理，稍后再试"

    public static func classify(_ error: any Error) -> UserCreateFailure {
        if error is CancellationError { return UserCreateFailure(receipt: nil, next: .unfreeze) }
        if let failure = error as? KeyedWriteFailure { return classify(failure) }
        guard let api = error as? APIError else { return UserCreateFailure(receipt: error.localizedDescription, next: .unfreeze) }
        if api.securityOutcome == .passed { return UserCreateFailure(receipt: nil, next: .reconfirm) }
        if let known = refusal(api) { return known }
        guard let status = api.statusCode else {
            return api.kind == .transport || api == .invalidResponse ? UserCreateFailure(receipt: nil, next: .readBack)
                : UserCreateFailure(receipt: api.localizedDescription, next: .unfreeze)
        }
        if status >= 500, api.reason == nil || RequestPolicy.isRetryableStatus(status, marker: api.reason) {
            return UserCreateFailure(receipt: nil, next: .readBack)
        }
        return UserCreateFailure(receipt: api.localizedDescription, next: .unfreeze)
    }

    init(receipt: String?, fieldIssues: [UserDraftIssue] = [], next: Next, details: APIError? = nil, retryNotBefore: Date? = nil) {
        self.receipt = receipt; self.fieldIssues = fieldIssues; self.next = next; self.details = details; self.retryNotBefore = retryNotBefore
    }
    /// After the executor's own retries (R04): only a definite refusal settles a keyed write.
    private static func classify(_ failure: KeyedWriteFailure) -> UserCreateFailure {
        switch failure.disposition {
        case .needsNewKey(.keyConflict): UserCreateFailure(receipt: "请求已变化，请重新提交", next: .unfreezeWithNewKey)
        case .needsNewKey: UserCreateFailure(receipt: failure.localizedDescription, next: .unfreezeWithNewKey)
        case .unconfirmed(.storeUnavailable, let notBefore): UserCreateFailure(receipt: storeUnavailable, next: .unfreeze, retryNotBefore: notBefore)
        case .unconfirmed: UserCreateFailure(receipt: nil, next: .readBack)
        }
    }
    /// The rows of 30 §5.5 with their own words.
    private static func refusal(_ api: APIError) -> UserCreateFailure? {
        switch (api.statusCode, api.reason) {
        case (409?, "EMAIL_EXISTS"?):
            UserCreateFailure(receipt: "创建失败：" + emailTaken, fieldIssues: [UserDraftIssue(field: .email, message: emailTaken)], next: .unfreeze)
        case (400?, nil):
            UserCreateFailure(receipt: invalidRequest, fieldIssues: [UserDraftIssue(field: .email, message: "请检查邮箱"),
                                                                     UserDraftIssue(field: .password, message: "请检查密码")],
                              next: .unfreeze, details: api)
        case (_, "STEP_UP_REQUIRED"?): UserCreateFailure(receipt: nil, next: .unfreeze)
        case (_, "STEP_UP_TOTP_NOT_ENABLED"?): UserCreateFailure(receipt: StepUpPolicy.totpNotEnabledTitle, next: .unfreeze)
        case (_, "STEP_UP_ADMIN_API_KEY_FORBIDDEN"?): UserCreateFailure(receipt: "Admin Key 登录不能创建管理员，请改用账号登录", next: .unfreeze)
        case (_, "ACCESS_TOKEN_READ_ONLY"?): UserCreateFailure(receipt: "当前登录的是只读令牌，不能新建用户", next: .unfreeze)
        case (_, "IDEMPOTENCY_KEY_CONFLICT"?): UserCreateFailure(receipt: "请求已变化，请重新提交", next: .unfreezeWithNewKey)
        case (_, "IDEMPOTENCY_KEY_INVALID"?), (_, "IDEMPOTENCY_KEY_REQUIRED"?):
            UserCreateFailure(receipt: api.localizedDescription, next: .unfreezeWithNewKey)
        case (_, "IDEMPOTENCY_STORE_UNAVAILABLE"?): UserCreateFailure(receipt: storeUnavailable, next: .unfreeze)
        default: nil
        }
    }
}
