import XCTest

/// 20 §7 新建账号 (S2-19, and the test sheet of S2-20) on the fixture site (DemoData+Accounts, DemoData+AccountNew): 11 demo accounts, the next id is 13;
/// Anthropic has 3 accounts (Claude-04), OpenAI 2 (OpenAI-03), Antigravity none (Antigravity-01); 高级组 (#1) holds Anthropic
/// accounts. Keys are typed (PasteButton, fileImporter, Safari and the loopback listener need a real device).
final class AccountNewUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let site = "新建账号站点"
        static let newID = 13
        static let claudeName = "Claude-04"
        static let key = "sk-ant-api03-ui-fixture-key-0001"
        static let createLegacy = "-ui-account-create-legacy"
        static let createUnconfirmed = "-ui-account-create-unconfirmed"
        static let createLost = "-ui-account-create-lost"
        static let createCheckFail = "-ui-account-create-check-fail"
        static let catalogError = "-ui-account-new-catalog-error"
        static let groupsError = "-ui-account-groups-error"
        static let proxiesError = "-ui-account-proxies-error"
        static let writeFail = "-ui-account-write-fail"
        static let newTestFail = "-ui-account-new-test-fail"
        static let newPauseFail = "-ui-account-new-pause-fail"
        static let testSlow = "-ui-account-test-slow"
        static let failedOutcome = "测试未通过 · API Key 无效或已撤销"
        static let passedOutcome = "测试通过 · 已启用调度"
    }

    /// 20 §1.1, §7.1, §7.4-4: “＋” opens the form with everything missing; 取消 before a platform closes it without asking.
    @MainActor func testPlusOpensFormAndCancelWithoutPlatformClosesDirectly() {
        launchAndLogin()
        defer { diagnostics("account-new-open-final") }
        openForm()
        XCTAssertTrue(text(containing: "\(Fixture.site) · 还差 3 项").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("account-new.dock.missing").label, "还差平台、凭据、名称，跳到平台")
        XCTAssertFalse(app.buttons["account-new.submit"].isEnabled, app.debugDescription)
        app.buttons["account-new.cancel"].tap()
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 5), app.debugDescription)
    }

    /// 20 §7.3 坞: the missing items follow the form; tapping them scrolls to the first; filled in, “可以创建了”.
    @MainActor func testDockListsMissingItemsAndJumpsToFirst() {
        launchAndLogin()
        defer { diagnostics("account-new-dock-final") }
        openForm()
        pickPlatform("Anthropic")
        waitForValue(element("account-new.name"), equals: Fixture.claudeName)
        reveal(element("account-new.name.footnote"))
        waitForLabel(element("account-new.dock.missing"), equals: "还差认证方式、凭据，跳到认证方式")
        pickMethod("apikey")
        clear("account-new.name")
        waitForLabel(element("account-new.dock.missing"), equals: "还差API Key、名称，跳到API Key")
        XCTAssertTrue(text(containing: "\(Fixture.site) · 还差 2 项").exists, app.debugDescription)
        reveal(element("account-new.more"))
        element("account-new.dock.missing").tap()
        XCTAssertTrue(waitUntil(element("account-new.apikey"), "isHittable == true"), app.debugDescription)
        typeSecret(Fixture.key, in: "account-new.apikey")
        enter(Fixture.claudeName, in: "account-new.name")
        waitForLabel(element("account-new.dock.text"), equals: "可以创建了，创建后立即停止调度，测试通过再启用")
        XCTAssertTrue(text(containing: "\(Fixture.site) · 必填已填齐").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["account-new.submit"].isEnabled, app.debugDescription)
    }

    /// 20 §7.1, §7.3, §7.4-1: the defaults, then 创建并测试 creates outside the scheduler and tests in the sheet; the pass turns
    /// scheduling on, 完成 closes the form with “参与调度” and the list reads again.
    @MainActor func testAPIKeyCreateTestsEnablesSchedulingAndCompletes() {
        launchAndLogin()
        defer { diagnostics("account-new-create-final") }
        fillClaudeConsole()
        reveal(element("account-new.groups.default"))
        XCTAssertEqual(element("account-new.groups.default").label, "不选分组时，如果站点有「anthropic-default」分组会自动加入")
        XCTAssertEqual(element("account-new.groups.count").label, "可不选")
        for (id, value) in [("account-new.concurrency", "10"), ("account-new.priority", "1"), ("account-new.rate", "1")] {
            reveal(element(id))
            XCTAssertEqual(element(id).value as? String, value, id)
        }
        reveal(element("account-new.proxy"))
        XCTAssertTrue(readout(element("account-new.proxy")).contains("无代理") || text(containing: "无代理").exists, app.debugDescription)
        reveal(element("account-new.more"))
        XCTAssertTrue(text(containing: "不过期").exists, app.debugDescription)
        submit()
        XCTAssertTrue(element("account-new.test.sheet").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["创建并测试"].exists, app.debugDescription)
        waitForValue(element("account-new.test.stage.create"), equals: "#\(Fixture.newID)")
        waitForLabel(element("account-new.test.outcome"), equals: Fixture.passedOutcome)
        XCTAssertEqual(element("account-new.test.stage.enable").value as? String, "参与调度")
        XCTAssertTrue(element("account-new.test.view").exists, app.debugDescription)
        waitForLabel(element("account-new.test.output"), containing: "行")
        diagnostics("account-new-create-passed")
        tapInSheet("account-new.test.done")
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 5), app.debugDescription)
        waitForReceipt("已创建「\(Fixture.claudeName)」· 参与调度")
        XCTAssertEqual(app.buttons["receipt.action"].label, "查看")
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.buttons["account.\(Fixture.newID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row.label.contains(Fixture.claudeName) && !row.label.contains("暂停"), row.label)
    }

    /// An older server ignores `schedulable: false`: the App stops the account right after (20 §7.4-1). The key is refused, the
    /// backend marks the account as an error, and 保留（错误状态） closes with its receipt (20 §7.3 失败, §7.4-3).
    @MainActor func testServerIgnoringSchedulableIsStoppedAfterCreate() {
        launchAndLogin(arguments: [Fixture.createLegacy, Fixture.newTestFail])
        defer { diagnostics("account-new-legacy-final") }
        fillClaudeConsole()
        submit()
        waitForLabel(element("account-new.test.outcome"), equals: Fixture.failedOutcome)
        XCTAssertEqual(element("account-new.test.stage.pause").value as? String, "不接收请求")
        XCTAssertEqual(element("account-new.test.stage.enable").value as? String, "未启用")
        XCTAssertEqual(element("account-new.test.outcome.raw").label, "上游返回 401 · API returned 401: invalid x-api-key")
        XCTAssertTrue(element("account-new.test.outcome.detail").label.contains("后端已把账号 #13 标为“错误”"), app.debugDescription)
        XCTAssertEqual(element("account-new.test.keep").label, "保留（错误状态）")
        tapInSheet("account-new.test.keep")
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 5), app.debugDescription)
        waitForReceipt("已保留「\(Fixture.claudeName)」· 错误（已停止调度）")
        XCTAssertEqual(app.buttons["receipt.action"].label, "查看")
        XCTAssertTrue(app.buttons["account.\(Fixture.newID)"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// The stop fails: the sheet says so with 重试停止调度 and 删除账号…; closed, the form stays locked with the banner; 取消 offers
    /// 仍然关闭 and 删除账号….
    @MainActor func testPauseFailureKeepsCreatedAccountLocked() {
        launchAndLogin(arguments: [Fixture.createLegacy, Fixture.writeFail])
        defer { diagnostics("account-new-pause-failure-final") }
        fillClaudeConsole()
        submit()
        waitForLabel(element("account-new.test.outcome"), equals: "停止调度没有确认 · 结果待核对")
        XCTAssertEqual(element("account-new.test.stage.pause").value as? String, "没有确认")
        XCTAssertTrue(element("account-new.test.repause").exists && element("account-new.test.delete").exists, app.debugDescription)
        tapInSheet("account-new.test.close")
        XCTAssertTrue(element("account-new.test.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        waitForLabel(element("account-new.dock.text"), equals: "停止调度没有确认，账号 #13 可能在接收请求")
        let banner = element("account-new.banner")
        reveal(banner, towardBottom: false)
        XCTAssertTrue(banner.label.contains("停止调度没有确认 · 结果待核对") && banner.label.contains("账号 #13 可能正在参与调度。"), banner.label)
        XCTAssertEqual(app.buttons["account-new.submit"].label, "重试停止调度")
        XCTAssertTrue(text(containing: "#13 已创建 · 调度状态待核对").exists, app.debugDescription)
        reveal(element("account-new.platform.locked"), towardBottom: false)
        XCTAssertTrue(element("account-new.platform.locked").label.contains("已创建，不能更换"), app.debugDescription)
        reveal(element("account-new.apikey"))
        XCTAssertFalse(element("account-new.apikey").isEnabled, app.debugDescription)
        diagnostics("account-new-pause-failure")
        app.buttons["account-new.cancel"].tap()
        XCTAssertTrue(text(containing: "账号「\(Fixture.claudeName)」可能还在参与调度").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["仍然关闭"].exists && app.buttons["删除账号…"].exists, app.debugDescription)
        app.buttons["仍然关闭"].tap()
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 5), app.debugDescription)
        waitForReceipt("「\(Fixture.claudeName)」停止调度没有确认 · 结果待核对")
    }

    /// 20 §7.4-1, §0.4-7: a picked group with Anthropic members is marked; creating asks, 返回修改分组 sends nothing, 继续创建 creates.
    @MainActor func testMixedChannelAsksBeforeCreatingAndSendsConfirmation() {
        launchAndLogin()
        defer { diagnostics("account-new-mixed-final") }
        fillAntigravityUpstream()
        turnMixedScheduling(on: true)
        let high = element("account-new.group.1")
        reveal(high)
        high.tap()
        waitForLabel(high, containing: "有混合渠道风险")
        XCTAssertEqual(element("account-new.groups.count").label, "已选 1 · 1 个需确认")
        XCTAssertEqual(element("account-new.groups.risk.1").label, "「高级组」里已有 Anthropic 账号，创建时要确认混合渠道风险。")
        submit()
        let alert = app.alerts["混合渠道警告"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        let message = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "分组“高级组”中同时包含 Antigravity 和 Anthropic 账号"))
        XCTAssertTrue(message.firstMatch.exists, app.debugDescription)
        alert.buttons["返回修改分组"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        XCTAssertTrue(waitUntil(high, "isHittable == true"), app.debugDescription)
        submit()
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        alert.buttons["继续创建"].tap()
        finishPassingTest(name: "Antigravity-01")
    }

    /// 20 §7.4-5: turning “在 /v1/messages 中使用” off drops the Anthropic group; 撤销 puts both back.
    @MainActor func testTurningOffMixedSchedulingRemovesGroupsWithUndo() {
        launchAndLogin()
        defer { diagnostics("account-new-mixed-undo-final") }
        openForm()
        pickPlatform("Antigravity")
        turnMixedScheduling(on: true)
        let high = element("account-new.group.1")
        reveal(high)
        high.tap()
        waitForLabel(element("account-new.groups.count"), containing: "已选 1")
        tapMixedScheduling(to: false)
        // The receipt stays 4.2 seconds: it first, one look at the switch and the chip, then 撤销.
        waitForReceipt("已移除 1 个不再适用的分组")
        XCTAssertEqual(app.switches["account-new.groups.mixed"].value as? String, "0")
        XCTAssertFalse(high.exists, app.debugDescription)
        app.buttons.matching(NSPredicate(format: "identifier == 'receipt.action' AND label == '撤销'")).firstMatch.tap()
        XCTAssertTrue(high.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(high.isSelected, app.debugDescription)
        XCTAssertEqual(app.switches["account-new.groups.mixed"].value as? String, "1")
    }

    /// 20 §7.4-4 / -5: another platform asks once something was entered, keeps the name rule, notes and scheduling; 取消 asks before
    /// dropping the form.
    @MainActor func testCancelAndPlatformSwitchAskBeforeDiscarding() {
        launchAndLogin()
        defer { diagnostics("account-new-switch-final") }
        fillClaudeConsole()
        enter("spare-note", in: "account-new.notes")
        pickPlatform("OpenAI")
        let question = app.alerts["换成 OpenAI？"]
        XCTAssertTrue(question.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(question.staticTexts["已填写的凭据会清空，名称、调度和代理保留。"].exists, app.debugDescription)
        question.buttons["取消"].tap()
        reveal(element("account-new.apikey.hint"))
        XCTAssertEqual(element("account-new.platform").value as? String, "Anthropic")
        pickPlatform("OpenAI")
        XCTAssertTrue(question.waitForExistence(timeout: 5), app.debugDescription)
        question.buttons["更换平台"].tap()
        waitForValue(element("account-new.name"), equals: "OpenAI-03")
        XCTAssertFalse(element("account-new.apikey.hint").exists, app.debugDescription)
        reveal(element("account-new.notes"))
        XCTAssertEqual(element("account-new.notes").value as? String, "spare-note")
        app.buttons["account-new.cancel"].tap()
        let discard = app.alerts["放弃新建账号？"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(discard.staticTexts["已填写的内容不会保存。"].exists, app.debugDescription)
        discard.buttons["继续填写"].tap()
        XCTAssertTrue(app.buttons["account-new.cancel"].exists, app.debugDescription)
        app.buttons["account-new.cancel"].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        discard.buttons["放弃"].tap()
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["account.\(Fixture.newID)"].exists, app.debugDescription)
    }

    /// 20 §7.3 / §7.4-6: the pasted code is exchanged; “已授权 · {邮箱}”. Setup Token after that asks, then starts over.
    @MainActor func testOAuthPastedCodeCompletesAuthorization() {
        launchAndLogin()
        defer { diagnostics("account-new-oauth-final") }
        openForm()
        pickPlatform("Anthropic")
        pickMethod("oauth")
        let generate = app.buttons["oauth.generate"]
        reveal(generate)
        generate.tap()
        XCTAssertTrue(element("oauth.link").waitForExistence(timeout: 10), app.debugDescription)
        let code = element("oauth.code")
        reveal(code)
        code.tap()
        code.typeText("demo-code#demo-state\n")
        let finish = app.buttons["account-new.oauth.finish"]
        reveal(finish)
        XCTAssertTrue(waitUntil(finish, "isEnabled == true"), app.debugDescription)
        finish.tap()
        let done = element("account-new.oauth.done")
        XCTAssertTrue(done.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(done.label, "已授权 · ops@example.com")
        waitForLabel(element("account-new.dock.text"), equals: "可以创建了，创建后立即停止调度，测试通过再启用")
        let setup = app.segmentedControls["account-new.oauth.kind"].buttons["Setup Token"]
        reveal(setup)
        setup.tap()
        let question = app.alerts["切换到 Setup Token？"]
        XCTAssertTrue(question.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(question.staticTexts["切换会丢弃当前授权，需要重新在浏览器里授权。"].exists, app.debugDescription)
        question.buttons["切换"].tap()
        XCTAssertTrue(app.buttons["oauth.generate"].waitForExistence(timeout: 5), app.debugDescription)
        waitForLabel(element("account-new.dock.missing"), equals: "还差授权，跳到授权")
    }

    /// 20 §7.3 凭据, 分组 and 更多 follow the platform and method.
    @MainActor func testCredentialSectionsFollowMethod() {
        launchAndLogin()
        defer { diagnostics("account-new-sections-final") }
        openForm()
        pickPlatform("Kimi")
        pickMethod("mode.payg")
        let protocolPicker = element("account-new.protocol")
        reveal(protocolPicker)
        XCTAssertTrue(readout(protocolPicker).contains("自适应"), protocolPicker.debugDescription)
        reveal(element("account-new.endpoint.official"))
        pickPlatform("Anthropic")
        pickMethod("bedrock")
        for id in ["account-new.bedrock.akid", "account-new.bedrock.secret", "account-new.bedrock.session"] { reveal(element(id)) }
        XCTAssertTrue(app.secureTextFields["account-new.bedrock.session"].exists, app.debugDescription)
        let region = element("account-new.bedrock.region")
        reveal(region)
        XCTAssertTrue(readout(region).contains("us-east-1"), region.debugDescription)
        let auth = app.segmentedControls["account-new.bedrock.auth"].buttons["Bedrock API Key"]
        reveal(auth, towardBottom: false)
        auth.tap()
        reveal(element("account-new.bedrock.apikey"))
        XCTAssertFalse(element("account-new.bedrock.akid").exists, app.debugDescription)
        pickMethod("vertex")
        let file = element("account-new.vertex.file")
        reveal(file)
        XCTAssertTrue(file.label.contains("从“文件”选择 JSON"), file.label)
        pickPlatform("Grok")
        let empty = element("account-new.groups.empty")
        reveal(empty)
        XCTAssertEqual(empty.label, "没有可选的 Grok 分组，不分组也能创建。")
        let more = text(containing: "过期时间、负载因子")
        reveal(more)
        more.tap()
        let footnote = element("account-new.more.footnote")
        reveal(footnote)
        XCTAssertEqual(footnote.label, "模型白名单与映射、自定义错误码、配额等，创建后在账号详情里设置。")
        reveal(element("account-new.load-factor"), towardBottom: false)
        XCTAssertEqual(element("account-new.load-factor").label, "默认")
    }

    /// 20 §7.5: the first answer was lost after the account was stored; the check by name finds it, so nothing is created twice.
    @MainActor func testUnconfirmedCreateIsMatchedByNameWithoutDuplicate() {
        launchAndLogin(arguments: [Fixture.createUnconfirmed])
        defer { diagnostics("account-new-unconfirmed-final") }
        fillClaudeConsole()
        submit()
        finishPassingTest(name: Fixture.claudeName)
        XCTAssertTrue(app.buttons["account.\(Fixture.newID)"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["account.\(Fixture.newID + 1)"].exists, app.debugDescription)
    }

    /// 20 §7.5: lost before it was stored, the check finds nothing; 用同一编号重试 creates it once.
    @MainActor func testLostCreateOffersRetryWithSameNumber() {
        launchAndLogin(arguments: [Fixture.createLost])
        defer { diagnostics("account-new-lost-final") }
        fillClaudeConsole()
        submit()
        waitForLabel(element("account-new.dock.text"), equals: "没有创建成功")
        let retry = app.buttons["account-new.submit"]
        XCTAssertEqual(retry.label, "用同一编号重试")
        retry.tap()
        finishPassingTest(name: Fixture.claudeName)
        XCTAssertTrue(app.buttons["account.\(Fixture.newID)"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["account.\(Fixture.newID + 1)"].exists, app.debugDescription)
    }

    /// 20 §7.5: the catalog, groups and proxies each say 读取失败 with 重试; the built-in list still creates.
    @MainActor func testLoadFailuresShowRetryAndStillAllowCreate() {
        launchAndLogin(arguments: [Fixture.catalogError, Fixture.groupsError, Fixture.proxiesError])
        defer { diagnostics("account-new-load-failures-final") }
        openForm()
        XCTAssertTrue(element("account-new.platform.retry").waitForExistence(timeout: 10), app.debugDescription)
        pickPlatform("Anthropic")
        pickMethod("apikey")
        typeSecret(Fixture.key, in: "account-new.apikey")
        let groups = element("account-new.groups.retry")
        reveal(groups)
        XCTAssertTrue(groups.exists, app.debugDescription)
        let proxies = element("account-new.proxy.retry")
        reveal(proxies)
        XCTAssertTrue(proxies.exists, app.debugDescription)
        submit()
        finishPassingTest(name: Fixture.claudeName)
    }

    /// 00 §2.5.4, 20 §7.5: the answer and the check by name are both lost, so the account may exist; 取消 says so rather than
    /// 放弃新建账号, and 仍然关闭 leaves a receipt to check the list (the fixture did store the account).
    @MainActor func testCancelWhileResultUnconfirmedWarnsAccountMayExist() {
        launchAndLogin(arguments: [Fixture.createUnconfirmed, Fixture.createCheckFail])
        defer { diagnostics("account-new-result-unconfirmed-final") }
        fillClaudeConsole()
        submit()
        waitForLabel(element("account-new.dock.text"), containing: "结果未确认")
        XCTAssertEqual(app.buttons["account-new.submit"].label, "用同一编号重试")
        app.buttons["account-new.cancel"].tap()
        XCTAssertTrue(text(containing: "账号「\(Fixture.claudeName)」可能已经创建").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.alerts["放弃新建账号？"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["仍然关闭"].exists, app.debugDescription)
        app.buttons["仍然关闭"].tap()
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 5), app.debugDescription)
        waitForReceipt("「\(Fixture.claudeName)」创建结果未确认 · 请到账号列表核对")
        XCTAssertTrue(app.buttons["account.\(Fixture.newID)"].waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: - S2-20 测试 sheet

    /// 20 §7.4-2 / -3: 修改凭据后重试 returns to the form with the banner, the note and 重新测试; 处理 → 保存为停用 closes with its receipt.
    @MainActor func testFailedTestSavedAsInactiveFromBanner() {
        launchAndLogin(arguments: [Fixture.newTestFail])
        defer { diagnostics("account-new-inactive-final") }
        fillClaudeConsole()
        submit()
        waitForLabel(element("account-new.test.outcome"), equals: Fixture.failedOutcome)
        tapInSheet("account-new.test.edit")
        XCTAssertTrue(element("account-new.test.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "测试未通过 · #13 已标为错误").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(containing: "#13 已创建 · 错误（已停止调度）").exists, app.debugDescription)
        waitForLabel(app.buttons["account-new.submit"], equals: "重新测试")
        reveal(element("account-new.retry-note"))
        XCTAssertTrue(element("account-new.retry-note").label.contains("账号 #13 已创建，已被标为错误（已停止调度）"), app.debugDescription)
        let resolve = app.buttons["account-new.banner.resolve"]
        reveal(resolve, towardBottom: false)
        resolve.tap()
        XCTAssertTrue(text(containing: "账号「\(Fixture.claudeName)」已创建，怎么处理？").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["保留（错误状态）"].exists && app.buttons["删除账号…"].exists && app.buttons["继续修改"].exists, app.debugDescription)
        app.buttons["保存为停用"].tap()
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 5), app.debugDescription)
        waitForReceipt("已保存「\(Fixture.claudeName)」为停用 · 不参与调度")
        XCTAssertEqual(app.buttons["receipt.action"].label, "查看")
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }

    /// DECISIONS 第 114 行, X09: 删除账号… in the result asks for the whole name (Face ID is off in the fixture), case and all.
    @MainActor func testFailedTestDeleteRequiresTypedNameWithFaceIDOff() {
        launchAndLogin(arguments: [Fixture.newTestFail])
        defer { diagnostics("account-new-delete-final") }
        fillClaudeConsole()
        submit()
        waitForLabel(element("account-new.test.outcome"), equals: Fixture.failedOutcome)
        tapInSheet("account-new.test.delete")
        let title = element("delete.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(title.label.contains("删除账号") && title.label.contains(Fixture.claudeName), title.label)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        let input = element("delete.input")
        input.tap()
        input.typeText("claude-04")
        XCTAssertFalse(confirm.isEnabled, app.debugDescription)
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9) + Fixture.claudeName)
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 10), app.debugDescription)
        waitForReceipt("已删除账号「\(Fixture.claudeName)」")
        XCTAssertTrue(app.buttons["account.\(Fixture.newID)"].waitForNonExistence(timeout: 10), app.debugDescription)
    }

    /// 20 §7.4-2: a new key makes the dock 保存并重新测试; the PATCH goes first (保存修改 #13), then the test passes and clears the error.
    @MainActor func testEditedCredentialsAreSavedThenRetestPasses() {
        launchAndLogin(arguments: [Fixture.newTestFail])
        defer { diagnostics("account-new-retest-final") }
        fillClaudeConsole()
        submit()
        waitForLabel(element("account-new.test.outcome"), equals: Fixture.failedOutcome)
        tapInSheet("account-new.test.edit")
        XCTAssertTrue(element("account-new.test.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        typeSecret("sk-ant-api03-ui-fixture-key-0002", in: "account-new.apikey")
        waitForLabel(app.buttons["account-new.submit"], equals: "保存并重新测试")
        submit()
        XCTAssertTrue(app.navigationBars["保存并重新测试"].waitForExistence(timeout: 10), app.debugDescription)
        waitForLabel(element("account-new.test.outcome"), equals: Fixture.passedOutcome)
        XCTAssertEqual(element("account-new.test.stage.save").value as? String, "#13")
        XCTAssertTrue(element("account-new.test.outcome.detail").label.hasPrefix("错误状态已自动清除。"), app.debugDescription)
        tapInSheet("account-new.test.done")
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 5), app.debugDescription)
        waitForReceipt("已创建「\(Fixture.claudeName)」· 参与调度")
    }

    /// 20 §7.3 停调度失败: 重试停止调度 works this time and the test starts by itself.
    @MainActor func testPauseFailureRetryStopsSchedulingThenTests() {
        launchAndLogin(arguments: [Fixture.newPauseFail])
        defer { diagnostics("account-new-repause-final") }
        fillClaudeConsole()
        submit()
        waitForLabel(element("account-new.test.outcome"), equals: "停止调度没有确认 · 结果待核对")
        XCTAssertEqual(element("account-new.test.stage.pause").value as? String, "没有确认")
        tapInSheet("account-new.test.repause")
        finishPassingTest(name: Fixture.claudeName)
    }

    /// 20 §7.4-4, §4.4: 后台继续 while the test runs closes the form; the run goes on and turns scheduling on, then says so.
    @MainActor func testClosingDuringTestContinuesInBackgroundWithReceipts() {
        launchAndLogin(arguments: [Fixture.testSlow])
        defer { diagnostics("account-new-background-final") }
        fillClaudeConsole()
        submit()
        let background = app.buttons["account-new.test.background"]
        XCTAssertTrue(background.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["account-new.test.close"].exists, app.debugDescription)
        background.tap()
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 5), app.debugDescription)
        waitForReceipt("「\(Fixture.claudeName)」在后台继续测试，完成后通知你")
        let passed = "「\(Fixture.claudeName)」测试通过 · 已启用调度"
        XCTAssertTrue(waitUntil(app.staticTexts["receipt.text"], "label == %@", passed, timeout: 20), app.debugDescription)
        XCTAssertEqual(app.buttons["receipt.action"].label, "查看")
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: - Helpers

    /// The sheet opens once the account exists; the fixture's test passes and turns scheduling on; 完成 closes everything.
    @MainActor private func finishPassingTest(name: String, file: StaticString = #filePath, line: UInt = #line) {
        let outcome = element("account-new.test.outcome")
        XCTAssertTrue(outcome.waitForExistence(timeout: 15), app.debugDescription, file: file, line: line)
        waitForLabel(outcome, equals: Fixture.passedOutcome, file: file, line: line)
        tapInSheet("account-new.test.done", file: file, line: line)
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForNonExistence(timeout: 5), app.debugDescription, file: file, line: line)
        waitForReceipt("已创建「\(name)」· 参与调度", file: file, line: line)
    }
    /// A button of the test sheet, scrolled into view first: the list makes rows below the fold only once they are near.
    @MainActor private func tapInSheet(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let item = element(identifier), list = element("account-new.test.sheet")
        XCTAssertTrue(list.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        for _ in 0..<6 where !(item.waitForExistence(timeout: 2) && item.isHittable) { list.swipeUp() }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
        item.tap()
    }

    @MainActor private func launchAndLogin(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-accounts-long-windows"] + arguments; app.launch()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://account-new.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openForm() {
        let plus = app.buttons["accounts.new"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10), app.debugDescription)
        plus.tap()
        XCTAssertTrue(app.buttons["account-new.cancel"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// Anthropic · Claude Console with a typed key and the suggested name.
    @MainActor private func fillClaudeConsole() {
        openForm()
        pickPlatform("Anthropic")
        pickMethod("apikey")
        typeSecret(Fixture.key, in: "account-new.apikey")
        waitForValue(element("account-new.name"), equals: Fixture.claudeName)
        waitForLabel(element("account-new.dock.text"), equals: "可以创建了，创建后立即停止调度，测试通过再启用")
    }
    @MainActor private func fillAntigravityUpstream() {
        openForm()
        pickPlatform("Antigravity")
        pickMethod("upstream")
        enter("https://upstream.example.invalid", in: "account-new.upstream.url")
        typeSecret("ag-ui-fixture-key-0001", in: "account-new.upstream.key")
        waitForValue(element("account-new.name"), equals: "Antigravity-01")
    }
    @MainActor private func pickPlatform(_ name: String) {
        let menu = element("account-new.platform")
        reveal(menu, towardBottom: false)
        menu.tap()
        let item = menuItem(name)
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.tap()
    }
    @MainActor private func pickMethod(_ id: String) {
        let row = element("account-new.method.\(id)")
        reveal(row)
        row.tap()
    }
    @MainActor private func turnMixedScheduling(on: Bool) {
        tapMixedScheduling(to: on)
        XCTAssertTrue(waitUntil(app.switches["account-new.groups.mixed"], "value == %@", on ? "1" : "0"), app.debugDescription)
    }
    /// The tap alone, for a check that cannot wait (the receipt after turning it off).
    @MainActor private func tapMixedScheduling(to on: Bool) {
        let toggle = app.switches["account-new.groups.mixed"]
        reveal(toggle)
        if (toggle.value as? String == "1") != on {
            let knob = toggle.switches.firstMatch
            (knob.exists ? knob : toggle).tap()
        }
    }
    @MainActor private func submit() {
        let button = app.buttons["account-new.submit"]
        XCTAssertTrue(waitUntil(button, "isEnabled == true", timeout: 10), app.debugDescription)
        button.tap()
    }
    /// PasteButton asks the system; the tests type, and Return ends the editing.
    @MainActor private func typeSecret(_ value: String, in identifier: String) {
        let field = element(identifier)
        reveal(field)
        field.tap()
        field.typeText(value + "\n")
    }
    /// The text is trailing-aligned, and a tap puts the caret on the nearest word boundary: the tap goes to the field's last
    /// points so the caret lands after the last word, then deletes. A caret that still landed inside a word gets another round.
    @MainActor private func clear(_ identifier: String) {
        let field = element(identifier)
        reveal(field)
        var focused = false
        for _ in 0..<3 {
            guard let value = field.value as? String, !value.isEmpty, value != field.placeholderValue else { break }
            field.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -2, dy: 0)).tap()
            focused = true
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 2))
        }
        if focused { field.typeText("\n") }
    }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
        if identifier.hasPrefix("account-new.") { field.typeText("\n") }
    }
    /// System menu items carry no identifier and read “title, detail”.
    @MainActor private func menuItem(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == '' AND (label == %@ OR label BEGINSWITH %@)", label, label + ",")).firstMatch
    }
    @MainActor private func text(containing part: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    /// A row's label and value together: menus and links read “title, value”, or keep the value apart.
    @MainActor private func readout(_ item: XCUIElement) -> String { item.label + " " + String(describing: item.value ?? "") }
    /// A receipt lasts 4.2 seconds: the wait ends as soon as it is there (a predicate expectation is polled once a second).
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let receipt = app.staticTexts.matching(NSPredicate(format: "identifier == 'receipt.text' AND label == %@", text)).firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), "≠ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, equals text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntil(item, "label == %@", text, timeout: 10), "\(item.label) ≠ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntil(item, "label CONTAINS %@", text, timeout: 10), "\(item.label) ∌ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitForValue(_ item: XCUIElement, equals expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntil(item, "value == %@", expected, timeout: 10), "\(String(describing: item.value))\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitUntil(_ item: XCUIElement, _ format: String, _ arguments: CVarArg..., timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: format, argumentArray: arguments)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: item)], timeout: timeout) == .completed
    }
    /// The sheet's dock floats over the last rows, and the keyboard over more: an item counts once it sits above both. A row the
    /// list has not made yet is looked for in `towardBottom`'s direction first, then the other way.
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        var downward = towardBottom
        for attempt in 0..<16 {
            if item.exists && item.isHittable && isClear(item) { item.waitUntilSettled(); return }
            if item.exists { downward = item.frame.minY >= upperLimit } else if attempt == 8 { downward.toggle() }
            let top = upperLimit + 20, bottom = lowerLimit - 30
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.8))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.2))
            (downward ? lower : upper).press(forDuration: 0.05, thenDragTo: downward ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
        item.waitUntilSettled()
    }
    @MainActor private var upperLimit: CGFloat { app.frame.minY + 150 }
    @MainActor private var lowerLimit: CGFloat {
        let keyboard = app.keyboards.firstMatch, dock = element("account-new.dock"), bar = app.tabBars.firstMatch
        if keyboard.exists { return keyboard.frame.minY }
        if dock.exists { return dock.frame.minY }
        return bar.exists ? bar.frame.minY : app.frame.maxY - 60
    }
    @MainActor private func isClear(_ item: XCUIElement) -> Bool { item.frame.maxY <= lowerLimit && item.frame.minY >= upperLimit - 60 }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
