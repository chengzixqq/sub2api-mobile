import Foundation
import Testing
@testable import Sub2Core

// S3-10: what “创建用户” does after the local check (30 §5.4, R04, R05) and how each answer is shown (30 §5.5).

private func amount(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
private func unconfirmed(_ cause: KeyedWriteFailure.UnconfirmedCause) -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: .unconfirmed(cause, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
}
private func newKey(_ cause: KeyedWriteFailure.NewKeyCause) -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: .needsNewKey(cause), key: "k", actionID: nil, lastError: nil)
}

/// 30 §5.4 steps 2–4: an administrator is verified, then confirmed; a positive initial balance is confirmed; anything else goes out.
@Test func planChoosesStepUpConfirmationOrDirectSend() {
    #expect(UserCreatePlan(role: .admin, initialBalance: nil) == .stepUpThenConfirm)
    #expect(UserCreatePlan(role: .admin, initialBalance: 20) == .stepUpThenConfirm)
    #expect(UserCreatePlan(role: .user, initialBalance: 20) == .confirmInitialBalance(20))
    #expect(UserCreatePlan(role: .vendor, initialBalance: amount("0.01")) == .confirmInitialBalance(amount("0.01")))
    #expect(UserCreatePlan(role: .user, initialBalance: 0) == .send)
    #expect(UserCreatePlan(role: .vendor, initialBalance: nil) == .send)
}

/// 30 §5.4 step 2; S3D1-01: without a verification the lead sentence is left out.
@Test func administratorConfirmationCopy() {
    let plain = UserCreateConfirmation.administrator(name: "何琪", initialBalance: nil, siteName: "主站", stepUpVerified: true, faceIDLine: nil)
    #expect(plain.title == "创建管理员「何琪」？")
    #expect(plain.message == "二次验证已通过。管理员可以管理全部账号、用户和资金。")
    #expect(plain.confirmTitle == "创建管理员")
    #expect(!plain.isDestructive)
    let funded = UserCreateConfirmation.administrator(name: "何琪", initialBalance: 20, siteName: "主站", stepUpVerified: true,
                                                      faceIDLine: "超过 $100，确认后验证 Face ID。")
    #expect(funded.message == "二次验证已通过。管理员可以管理全部账号、用户和资金。\n初始余额 $20.00 · 站点 主站\n超过 $100，确认后验证 Face ID。")
    #expect(funded.isDestructive)
    let unverified = UserCreateConfirmation.administrator(name: "何琪", initialBalance: 0, siteName: "主站", stepUpVerified: false, faceIDLine: nil)
    #expect(unverified.message == "管理员可以管理全部账号、用户和资金。")
    #expect(!unverified.isDestructive)
}

/// 30 §5.4 step 3: both ledger texts; the typed amount is echoed as typed (moneyExact).
@Test func initialBalanceConfirmationCopy() {
    let ledger = UserCreateConfirmation.initialBalance(name: "何琪", amount: 20, siteName: "主站", hasBalanceLedger: true, faceIDLine: nil)
    #expect(ledger.title == "创建「何琪」并入账 $20.00？")
    #expect(ledger.message == "站点 主站 · 初始余额 $20.00。会写一条“初始余额”记录到充值与调整记录。")
    #expect(ledger.confirmTitle == "创建并入账 $20.00")
    #expect(ledger.isDestructive)
    let direct = UserCreateConfirmation.initialBalance(name: "何琪", amount: amount("12.345"), siteName: "主站", hasBalanceLedger: false,
                                                       faceIDLine: "超过 $100，确认后验证 Face ID。")
    #expect(direct.title == "创建「何琪」并入账 $12.345？")
    #expect(direct.message == "站点 主站 · 初始余额 $12.345。创建时直接写入，不会出现在“充值与调整记录”里。\n超过 $100，确认后验证 Face ID。")
}

/// 30 §5.4 steps 1, 6, 7.
@Test func receiptsMatchSpec() {
    #expect(UserCreateReceipt.created(name: "何琪", initialBalance: 20) == "已创建用户「何琪」，初始余额 $20.00")
    #expect(UserCreateReceipt.created(name: "何琪", initialBalance: nil) == "已创建用户「何琪」")
    #expect(UserCreateReceipt.created(name: "何琪", initialBalance: 0) == "已创建用户「何琪」")
    #expect(UserCreateReceipt.attributesFailed == "用户已创建，自定义属性没保存成功，可在编辑用户里补填")
    #expect(UserCreateReceipt.foundOnServer == "已在服务器上找到这个用户")
    #expect(UserCreateReceipt.notCreated == "没有创建成功，可以再试一次")
    #expect(UserCreateReceipt.pendingIssues(2) == "还有 2 项需要填写或修改")
}

/// 30 §5.5 row by row.
@Test func failureTableRows() {
    let taken = UserCreateFailure.classify(APIError.server(status: 409, reason: "EMAIL_EXISTS"))
    #expect(taken.receipt == "创建失败：这个邮箱已被注册")
    #expect(taken.fieldIssues == [UserDraftIssue(field: .email, message: "这个邮箱已被注册")])
    #expect(taken.next == .unfreeze)

    let invalid = UserCreateFailure.classify(APIError.server(status: 400, reason: nil))
    #expect(invalid.receipt == "服务器没有接受填写的内容（错误码 HTTP 400），请检查邮箱和密码")
    #expect(invalid.fieldIssues.map(\.field) == [.email, .password])
    #expect(invalid.next == .unfreeze)
    #expect(invalid.details?.statusCode == 400)

    let verified = UserCreateFailure.classify(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed))
    #expect(verified.next == .reconfirm)
    #expect(verified.receipt == nil)
    let closed = UserCreateFailure.classify(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled))
    #expect(closed.next == .unfreeze)
    #expect(closed.receipt == nil)

    let noTOTP = UserCreateFailure.classify(APIError.server(status: 403, reason: "STEP_UP_TOTP_NOT_ENABLED").withSecurityOutcome(.cancelled))
    #expect(noTOTP.receipt == "需要先在 Web 端开启二次验证")
    #expect(noTOTP.next == .unfreeze)
    #expect(UserCreateFailure.classify(APIError.server(status: 403, reason: "STEP_UP_ADMIN_API_KEY_FORBIDDEN")).receipt
            == "Admin Key 登录不能创建管理员，请改用账号登录")
    #expect(UserCreateFailure.classify(APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")).receipt == "当前登录的是只读令牌，不能新建用户")

    let conflict = UserCreateFailure.classify(newKey(.keyConflict))
    #expect(conflict.receipt == "请求已变化，请重新提交")
    #expect(conflict.next == .unfreezeWithNewKey)
    let notBefore = Date(timeIntervalSince1970: 1_800_000_010)
    let store = UserCreateFailure.classify(KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: notBefore), key: "k",
                                                             actionID: nil, lastError: nil))
    #expect(store.receipt == "服务器暂时无法受理，稍后再试")
    #expect(store.next == .unfreeze)
    #expect(store.retryNotBefore == notBefore)
    #expect(taken.retryNotBefore == nil)
}

/// 30 §5.4 step 7 (R04, R06): lost, still running or unreadable after the executor gave up, and 5xx without a reason, are
/// read back; a new number for an invalid key; nothing echoes the server's message.
@Test func uncertainResultsReadBack() {
    #expect(UserCreateFailure.classify(unconfirmed(.transport)).next == .readBack)
    #expect(UserCreateFailure.classify(unconfirmed(.stillProcessing)).next == .readBack)
    #expect(UserCreateFailure.classify(unconfirmed(.unreadableResponse)).next == .readBack)
    #expect(UserCreateFailure.classify(APIError(kind: .transport, message: "网络连接已断开")).next == .readBack)
    #expect(UserCreateFailure.classify(APIError.invalidResponse).next == .readBack)
    #expect(UserCreateFailure.classify(APIError.server(status: 500, reason: nil)).next == .readBack)
    #expect(UserCreateFailure.classify(APIError.server(status: 502, envelope: nil)).next == .readBack)
    #expect(UserCreateFailure.classify(newKey(.invalid)).next == .unfreezeWithNewKey)
    let other = UserCreateFailure.classify(APIError.server(status: 422, reason: "SOMETHING_ELSE"))
    #expect(other.next == .unfreeze)
    #expect(other.receipt == APIError.server(status: 422, reason: "SOMETHING_ELSE").localizedDescription)
    let cancelled = UserCreateFailure.classify(CancellationError())
    #expect(cancelled.next == .unfreeze)
    #expect(cancelled.receipt == nil)
}

/// The read-back failed too: still unknown, in 00 §2.5.4's words with a key and 00 §2.4's without.
@Test func unconfirmedReceiptFollowsTheKey() {
    #expect(UserCreateReceipt.unconfirmed(sendsIdempotencyKey: true) == "结果未确认：服务器可能已执行。可以核对，或用同一编号重试，不会重复执行")
    #expect(UserCreateReceipt.unconfirmed(sendsIdempotencyKey: false) == "结果未确认，请刷新核对后再操作")
}

/// 30 §5.5: a 400 without a reason marks 邮箱 and 密码 together. They stand while both hold what was sent and both go once
/// either changes, so fixing the email alone sends again; spaces around the email are not a change.
@Test func serverMarksStandTogetherUntilAMarkedRowChanges() {
    var sent = UserAccessDraft()
    sent.email = "qi,he@example.com"
    sent.password = "Qm7v-Tr2p-Hx9k"
    let refusal = UserCreateFailure.classify(APIError.server(status: 400, reason: nil))
    let marks = UserServerMarks(refusal.fieldIssues, sent: sent)
    #expect(marks.standing(in: sent).map(\.field) == [.email, .password])
    var padded = sent
    padded.email = " qi,he@example.com "
    padded.username = "何琪"
    #expect(marks.standing(in: padded).count == 2)
    var fixed = sent
    fixed.email = "qi.he@example.com"
    #expect(marks.standing(in: fixed).isEmpty)
    var retyped = sent
    retyped.password = "Zx8c-Vb3n-Mq1w"
    #expect(marks.standing(in: retyped).isEmpty)
    let taken = UserServerMarks(UserCreateFailure.classify(APIError.server(status: 409, reason: "EMAIL_EXISTS")).fieldIssues, sent: sent)
    #expect(taken.standing(in: retyped).map(\.message) == ["这个邮箱已被注册"])
    #expect(taken.standing(in: fixed).isEmpty)
}
