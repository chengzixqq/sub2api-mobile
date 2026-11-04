import Foundation
import Testing
@testable import Sub2Core

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func origin(status: String? = "active", expires: Date? = nil, name: String = "hk-01", exit: String? = "203.0.113.9") -> AdminProxy {
    AdminProxy(id: 4, name: name, scheme: "http", host: "203.0.113.9", port: 3128, status: status, expiresAt: expires, ipAddress: exit)
}
private func moved(_ id: Int, _ name: String, _ platform: String = "kimi", current: Int? = nil, currentName: String? = nil) -> ProxyFallbackAccount {
    ProxyFallbackAccount(id: id, name: name, platform: platform, type: "apikey", currentProxyID: current, currentProxyName: currentName)
}
private func item(_ id: Int, _ code: String) -> ProxyFallbackRevertResult.Item { ProxyFallbackRevertResult.Item(id: id, code: code) }

@Test func proxyFallbackRowDetailNamesTheCurrentRoute() throws {
    let wire = #"[{"id":9,"name":"Kimi-01","platform":"kimi","type":"apikey","current_proxy_id":1,"current_proxy_name":"hk-02"},"#
        + #"{"id":12,"name":"MiniMax-01","platform":"minimax","type":"apikey","current_proxy_id":null,"current_proxy_name":null}]"#
    let rows = try JSONDecoder().decode([ProxyFallbackAccount].self, from: Data(wire.utf8))
    #expect(ProxyFallbackPresentation.rowDetail(rows[0]) == "Kimi · API Key · 现在：备用 hk-02")
    #expect(ProxyFallbackPresentation.rowDetail(rows[1]) == "MiniMax · API Key · 现在：直连")
    // The backup was deleted meanwhile: the join finds no name.
    #expect(ProxyFallbackPresentation.rowDetail(moved(9, "Kimi-01", current: 1)) == "Kimi · API Key · 现在：备用 #1")
    #expect(ProxyFallbackPresentation.rowDetail(moved(9, "Kimi-01", current: 1, currentName: "  ")) == "Kimi · API Key · 现在：备用 #1")
    #expect(ProxyFallbackPresentation.rowDetail(moved(11, "GLM-直连-01", "zhipu")) == "智谱 GLM · API Key · 现在：直连")
    #expect(ProxyFallbackPresentation.rowDetail(moved(13, "X", "newcomer")) == "newcomer · API Key · 现在：直连")
    #expect(ProxyFallbackPresentation.rowName(moved(9, "Kimi-01")) == "Kimi-01")
    #expect(ProxyFallbackPresentation.rowName(moved(9, " ")) == "账号 #9")
}

@Test func proxyFallbackCanRevertMatchesTheBackendOrigin() {
    #expect(ProxyFallbackPresentation.canRevert(origin(expires: now.addingTimeInterval(86_400)), now: now))
    #expect(ProxyFallbackPresentation.canRevert(origin(expires: nil), now: now))
    // The backend's IsExpired is !expires_at.After(now): the very second counts as expired.
    #expect(!ProxyFallbackPresentation.canRevert(origin(expires: now), now: now))
    #expect(!ProxyFallbackPresentation.canRevert(origin(status: "expired"), now: now))
    #expect(!ProxyFallbackPresentation.canRevert(origin(status: "inactive"), now: now))
    #expect(ProxyFallbackPresentation.canRevert(origin(status: nil), now: now))
    // Active, but the sweep has not run yet.
    #expect(!ProxyFallbackPresentation.canRevert(origin(expires: now.addingTimeInterval(-60)), now: now))
}

@Test func proxyFallbackConfirmationAndNames() {
    #expect(ProxyFallbackPresentation.proxyName(origin(), id: 4) == "hk-01")
    #expect(ProxyFallbackPresentation.proxyName(origin(name: "  hk-01 "), id: 4) == "hk-01")
    #expect(ProxyFallbackPresentation.proxyName(origin(name: " "), id: 4) == "代理 #4")
    #expect(ProxyFallbackPresentation.proxyName(nil, id: 4) == "代理 #4")
    #expect(ProxyFallbackPresentation.revertAllTitle(proxyName: "hk-01") == "全部恢复到 hk-01")
    #expect(ProxyFallbackPresentation.confirmTitle(.all, count: 2, accountName: nil, proxyName: "hk-01") == "把 2 个账号改回走 hk-01？")
    #expect(ProxyFallbackPresentation.confirmTitle(.account(9), count: 1, accountName: "Kimi-01", proxyName: "hk-01") == "把「Kimi-01」改回走 hk-01？")
    #expect(ProxyFallbackPresentation.confirmTitle(.account(9), count: 1, accountName: nil, proxyName: "hk-01") == "把「账号 #9」改回走 hk-01？")
    #expect(ProxyFallbackPresentation.confirmMessage(.all, exitIP: "203.0.113.9") == "它们的出口 IP 会变回 203.0.113.9。")
    #expect(ProxyFallbackPresentation.confirmMessage(.all, exitIP: nil) == "它们的出口 IP 会随之改变。")
    #expect(ProxyFallbackPresentation.confirmMessage(.account(9), exitIP: " 203.0.113.9 ") == "它的出口 IP 会变回 203.0.113.9。")
    #expect(ProxyFallbackPresentation.confirmMessage(.account(9), exitIP: "") == "它的出口 IP 会随之改变。")
    #expect(ProxyFallbackScope.all.accountIDs == [] && ProxyFallbackScope.account(9).accountIDs == [9])
    #expect(ProxyFallbackScope.all.id != ProxyFallbackScope.account(9).id)
}

@Test func proxyFallbackReceiptCombinations() {
    func receipt(_ reverted: [Int], skipped: [ProxyFallbackRevertResult.Item] = [], failed: [ProxyFallbackRevertResult.Item] = []) -> ProxyFallbackNotice {
        ProxyFallbackPresentation.receipt(ProxyFallbackRevertResult(revertedIDs: reverted, skipped: skipped, failed: failed), proxyName: "hk-01")
    }
    #expect(receipt([9, 12]) == ProxyFallbackNotice(text: "已恢复 2 个账号到 hk-01", tone: .ok))
    #expect(receipt([9, 12]).systemImage == "checkmark.circle")
    #expect(receipt([12], skipped: [item(9, "ACCOUNT_NOT_IN_FALLBACK")])
        == ProxyFallbackNotice(text: "已恢复 1 个账号到 hk-01 · 1 个已不在回退状态，已跳过", tone: .ok))
    #expect(receipt([12], skipped: [item(9, "ACCOUNT_NOT_FALLBACK_OF_PROXY")]).text == "已恢复 1 个账号到 hk-01 · 1 个已不在回退状态，已跳过")
    #expect(receipt([], skipped: [item(9, "ACCOUNT_NOT_IN_FALLBACK")]) == ProxyFallbackNotice(text: "1 个已不在回退状态，已跳过", tone: .neutral))
    #expect(receipt([], failed: [item(9, ""), item(12, "")]) == ProxyFallbackNotice(text: "2 个没有恢复", tone: .critical))
    #expect(receipt([9], failed: [item(12, "")]) == ProxyFallbackNotice(text: "已恢复 1 个账号到 hk-01 · 1 个没有恢复", tone: .caution))
    #expect(receipt([9], failed: [item(12, "")]).systemImage == "exclamationmark.triangle")
    #expect(receipt([]) == ProxyFallbackNotice(text: "已恢复 0 个账号到 hk-01", tone: .neutral))
}

@Test func proxyFallbackFailureWordsNeverEchoTheServer() throws {
    #expect(ProxyFallbackPresentation.failureText(code: "ACCOUNT_NOT_FOUND") == "账号不存在或已删除")
    #expect(ProxyFallbackPresentation.failureText(code: "RESOURCE_NOT_FOUND") == "账号不存在或已删除")
    #expect(ProxyFallbackPresentation.failureText(code: "PROXY_FALLBACK_ORIGIN_UNAVAILABLE") == "原代理已过期或已停用")
    #expect(ProxyFallbackPresentation.failureText(code: "ACCOUNT_NOT_IN_FALLBACK") == "已不在回退状态")
    #expect(ProxyFallbackPresentation.failureText(code: "SOME_NEW_CODE") == "没有恢复（错误码 SOME_NEW_CODE）")
    for odd in ["", "has space", "lower_case", String(repeating: "A", count: 65)] {
        #expect(ProxyFallbackPresentation.failureText(code: odd) == "服务器没能恢复这个账号")
    }
    let wire = #"{"reverted_ids":[],"skipped":[],"failed":[{"id":11,"code":"","message":"pq: deadlock detected"}]}"#
    let result = try JSONDecoder().decode(ProxyFallbackRevertResult.self, from: Data(wire.utf8))
    let lines = ProxyFallbackPresentation.failureLines(result, names: [11: "GLM-直连-01"], stillListed: [11])
    #expect(lines.map(\.reason) == ["服务器没能恢复这个账号"])
    #expect(!lines.contains { $0.reason.contains("deadlock") || $0.name.contains("deadlock") })
    #expect(!ProxyFallbackPresentation.receipt(result, proxyName: "hk-01").text.contains("deadlock"))
}

@Test func proxyFallbackFailureLinesUseNamesAndTheListReadAgain() {
    let result = ProxyFallbackRevertResult(revertedIDs: [10], skipped: [item(9, "ACCOUNT_NOT_IN_FALLBACK")],
                                           failed: [item(11, ""), item(99, "ACCOUNT_NOT_FOUND")])
    let listed = ProxyFallbackPresentation.failureLines(result, names: [11: "GLM-直连-01"], stillListed: [11, 99])
    #expect(listed == [ProxyFallbackFailureLine(id: 11, name: "GLM-直连-01", reason: "服务器没能恢复这个账号", tone: .critical),
                       ProxyFallbackFailureLine(id: 99, name: "账号 #99", reason: "账号不存在或已删除", tone: .critical)])
    // 11 left the list although it failed: the shadow sync failed after the account itself was restored.
    let left = ProxyFallbackPresentation.failureLines(result, names: [11: "GLM-直连-01"], stillListed: [99])
    #expect(left[0].reason == ProxyFallbackPresentation.maybeReverted && left[0].tone == .caution)
    #expect(left[1].tone == .critical)
    let unknown = ProxyFallbackPresentation.failureLines(result, names: [:], stillListed: nil)
    #expect(unknown.map(\.reason) == ["服务器没能恢复这个账号", "账号不存在或已删除"])
}

@Test func proxyFallbackErrorsAndReadBack() {
    #expect(ProxyFallbackPresentation.isOriginUnavailable(APIError.server(status: 409, reason: "PROXY_FALLBACK_ORIGIN_UNAVAILABLE")))
    #expect(!ProxyFallbackPresentation.isOriginUnavailable(APIError.server(status: 409, reason: nil)))
    #expect(!ProxyFallbackPresentation.isOriginUnavailable(URLError(.timedOut)))
    #expect(ProxyFallbackPresentation.rejectedText("请求无效") == "恢复没有成功：请求无效")
    #expect(ProxyFallbackPresentation.readback(targets: [9, 12], remaining: []) == .confirmed(2))
    #expect(ProxyFallbackPresentation.readback(targets: [9, 12], remaining: [moved(12, "MiniMax-01"), moved(3, "Other")]) == .remaining(1))
    #expect(ProxyFallbackPresentation.readbackReceipt(.confirmed(2), proxyName: "hk-01") == ProxyFallbackNotice(text: "已恢复 2 个账号到 hk-01", tone: .ok))
    #expect(ProxyFallbackPresentation.readbackReceipt(.remaining(1), proxyName: "hk-01")
        == ProxyFallbackNotice(text: "恢复结果未确认 · 还有 1 个没有恢复", tone: .caution))
}
