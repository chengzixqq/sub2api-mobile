import Foundation
import Testing
@testable import Sub2Core

// 50 §0.5, §0.8 and S5D2a-06: how a failed write of a group goes on, and the receipts of the four group actions.

private let groupCooldown = Date(timeIntervalSince1970: 1_800_000_010)
private func keyed(_ disposition: KeyedWriteFailure.Disposition) -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: disposition, key: "k", actionID: nil, lastError: nil)
}

@Test(arguments: [
    (CancellationError() as any Error, GroupWriteDisposition.cancelled),
    (APIError.server(status: 409, reason: "GROUP_EXISTS").withSecurityOutcome(.cancelled), .cancelled),
    (APIError.server(status: 423, reason: "COMPLIANCE_REQUIRED").withSecurityOutcome(.passed), .reconfirm),
    (keyed(.needsNewKey(.keyConflict)), .reconfirm),
    (keyed(.needsNewKey(.invalid)), .reconfirm),
    (keyed(.needsNewKey(.keyRequired)), .reconfirm),
    (keyed(.unconfirmed(.transport, retryNotBefore: nil)), .unconfirmed(retryNotBefore: nil)),
    (keyed(.unconfirmed(.stillProcessing, retryNotBefore: nil)), .unconfirmed(retryNotBefore: nil)),
    (keyed(.unconfirmed(.unreadableResponse, retryNotBefore: nil)), .unconfirmed(retryNotBefore: nil)),
    (keyed(.unconfirmed(.storeUnavailable, retryNotBefore: groupCooldown)), .unconfirmed(retryNotBefore: groupCooldown)),
    (APIError(kind: .transport, message: "无法连接站点"), .unconfirmed(retryNotBefore: nil)),
    (APIError.invalidResponse, .unconfirmed(retryNotBefore: nil)),
    (APIError.server(status: 408, reason: nil), .unconfirmed(retryNotBefore: nil)),
    (APIError.server(status: 500, reason: nil), .unconfirmed(retryNotBefore: nil)),
    (APIError.server(status: 500, reason: "INTERNAL_ERROR"), .unconfirmed(retryNotBefore: nil)),
    (APIError.server(status: 502, reason: nil), .unconfirmed(retryNotBefore: nil)),
    (APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE"), .unconfirmed(retryNotBefore: nil)),
    (APIError.server(status: 504, reason: nil), .unconfirmed(retryNotBefore: nil)),
    (APIError.server(status: 404, reason: "GROUP_NOT_FOUND"), .gone),
    (APIError.server(status: 404, reason: "RESOURCE_NOT_FOUND"), .gone),
    (APIError.server(status: 409, reason: "GROUP_NOT_EMPTY"), .rejected("分组里还有账号，先移出成员再删除。")),
    (APIError.server(status: 403, reason: "FORBIDDEN"), .rejected("你的工作区没有这个权限。")),
    (APIError.server(status: 403, reason: "SIMPLE_MODE_OPERATION_UNSUPPORTED"), .rejected("简易模式下不支持此操作。")),
    (APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), .rejected("当前管理访问令牌只读，不能执行此操作"))
] as [(any Error, GroupWriteDisposition)])
func groupWriteDispositionClassifiesFailures(error: any Error, expected: GroupWriteDisposition) {
    #expect(GroupWriteDisposition.of(error) == expected)
}

@Test func groupWriteDispositionRejectsWhatNeverRan() {
    for error: APIError in [.refreshDeferred, .stationMismatch, APIError(kind: .validation, message: "无效的对象编号。"),
                            APIError.server(status: 404, envelope: nil), APIError.server(status: 409, reason: "GROUP_EXISTS"),
                            APIError.server(status: 400, reason: nil), APIError.server(status: 422, reason: nil),
                            APIError.server(status: 429, reason: nil)] {
        guard case .rejected(let text) = GroupWriteDisposition.of(error) else { Issue.record("\(error)"); continue }
        #expect(text == error.localizedDescription || text == "已有同名分组。")
    }
}

/// R11: the words come from the catalog or GroupErrorCopy, never from the server's message.
@Test func groupWriteDispositionNeverEchoesTheServer() {
    func envelope(_ reason: String) throws -> ErrorEnvelope {
        try JSONDecoder().decode(ErrorEnvelope.self, from: Data(#"{"code":1,"reason":"\#(reason)","message":"internal detail"}"#.utf8))
    }
    let errors = [APIError.server(status: 409, envelope: try? envelope("GROUP_NOT_EMPTY")), APIError.server(status: 400, envelope: try? envelope("SOMETHING_NEW"))]
    for error in errors {
        guard case .rejected(let text) = GroupWriteDisposition.of(error) else { Issue.record("\(error)"); continue }
        #expect(!text.contains("internal detail"))
    }
}

@Test func groupActionReceiptsSayWhatHappened() {
    #expect([GroupActionKind.disable, .enable, .duplicate, .delete, .undo].map(\.verb) == ["停用", "启用", "复制", "删除", "撤销"])
    #expect([GroupReceiptButton.undo, .view, .retry, .retrySameKey, .check].map(\.title) == ["撤销", "查看", "重试", "用同一编号重试", "核对"])
    #expect(GroupActionCopy.statusChanged(name: "高级组", active: false)
            == GroupReceiptCopy(text: "已停用「高级组」", systemImage: "pause.fill", tone: .neutral, button: .undo))
    #expect(GroupActionCopy.statusChanged(name: "高级组", active: true)
            == GroupReceiptCopy(text: "已启用「高级组」", systemImage: "play.fill", tone: .ok, button: .undo))
    #expect(GroupActionCopy.duplicated(newName: "高级组 (Copy)", memberCount: 3)
            == GroupReceiptCopy(text: "已复制为「高级组 (Copy)」 · 停用中 · 3 个成员账号", systemImage: "plus.square.on.square", tone: .neutral,
                                button: .view))
    let failed = GroupActionCopy.failed(.delete, reason: "分组里还有账号，先移出成员再删除。")
    #expect(failed.text == "删除没有成功：分组里还有账号，先移出成员再删除。" && failed.tone == .critical && failed.button == nil)
    #expect(GroupActionCopy.failed(.undo, reason: "站点暂时不可用").text == "撤销没有成功：站点暂时不可用")
    let refused = GroupActionCopy.notAccepted(.disable)
    #expect(refused.text == "停用没有生效：服务器没有接受这项修改" && refused.tone == .caution && refused.button == nil)
}

@Test func groupActionReceiptsOfferTheRightButton() {
    #expect(GroupActionCopy.notApplied(.disable).text == "停用没有生效，可以重试" && GroupActionCopy.notApplied(.disable).button == .retry)
    #expect(GroupActionCopy.unconfirmedRetry(.delete).text == "删除结果未确认，可用同一编号重试")
    #expect(GroupActionCopy.unconfirmedRetry(.delete).button == .retrySameKey)
    #expect(GroupActionCopy.storeUnavailable(.enable).text == "启用没有生效：服务器暂时无法受理，稍后用同一编号重试")
    #expect(GroupActionCopy.storeUnavailable(.enable).button == .retrySameKey)
    #expect(GroupActionCopy.checkFailed(.disable).text == "停用结果未确认，请刷新核对后再操作" && GroupActionCopy.checkFailed(.disable).button == .check)
    #expect(GroupActionCopy.duplicateUnconfirmed.text == "复制结果未确认，已刷新列表，请核对是否已有副本")
    #expect(GroupActionCopy.duplicateUnconfirmed.button == .retrySameKey)
    #expect(GroupActionCopy.reconfirm(.duplicate).text == "复制没有执行，请重新操作" && GroupActionCopy.reconfirm(.duplicate).button == .retry)
    #expect(GroupActionCopy.readOnly.text == "当前管理访问令牌只读，不能执行此操作" && GroupActionCopy.readOnly.button == nil)
    for copy in [GroupActionCopy.notApplied(.enable), GroupActionCopy.unconfirmedRetry(.disable), GroupActionCopy.checkFailed(.delete),
                 GroupActionCopy.duplicateUnconfirmed] {
        #expect(copy.tone == .caution && copy.systemImage == "exclamationmark.triangle")
    }
}
