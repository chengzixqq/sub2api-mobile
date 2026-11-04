import Foundation
import Testing
@testable import Sub2Core

// S1-08: the wording of 运维监控未开启 and of the switch's results (10 §1.3.1, §1.3.2, §7.2; U10, U12; 00 §2.4, §3.4).

private let homeLine = "运维监控未开启 · 错误率与告警不可用，RPM 只计成功请求"
private let tpmNote = " · TPM 不含缓存 Tokens"
private let dataGap = "关闭期间不会记录错误请求，开启后也不会补回"

@Test func inlineTextFollowsReasonAndTPMFootnote() {
    #expect(OpsDisabledPresentation.inlineText(reason: .settingOff, tpmExcludesCache: false) == homeLine)
    #expect(OpsDisabledPresentation.inlineText(reason: .unknown, tpmExcludesCache: false) == homeLine)
    #expect(OpsDisabledPresentation.inlineText(reason: .settingOff, tpmExcludesCache: true) == homeLine + tpmNote)
    #expect(OpsDisabledPresentation.inlineText(reason: .configOff, tpmExcludesCache: false) == "运维监控已在服务器配置中关闭")
    #expect(OpsDisabledPresentation.inlineText(reason: .configOff, tpmExcludesCache: true) == "运维监控已在服务器配置中关闭" + tpmNote)
}

@Test func emptyStatePerReasonForMonitorAndDetail() {
    typealias Empty = OpsDisabledPresentation.EmptyState
    #expect(OpsDisabledPresentation.emptyState(reason: .settingOff, offersEnable: true, notesDataGap: false)
        == Empty(title: "运维监控未开启", detail: "错误率、告警、服务器状态与错误日志都不可用", actionTitle: "开启运维监控"))
    #expect(OpsDisabledPresentation.emptyState(reason: .configOff, offersEnable: false, notesDataGap: false)
        == Empty(title: "运维监控已在服务器配置中关闭", detail: "需要在服务器配置中启用（ops.enabled=false）", actionTitle: nil))
    #expect(OpsDisabledPresentation.emptyState(reason: .unknown, offersEnable: true, notesDataGap: false)
        == Empty(title: "运维监控未开启", detail: nil, actionTitle: "开启运维监控"))
    for reason in OpsDisabledReason.allCases {
        let noted = OpsDisabledPresentation.emptyState(reason: reason, offersEnable: true, notesDataGap: true)
        #expect(noted.detail?.hasSuffix(dataGap) == true)
        #expect(OpsDisabledPresentation.emptyState(reason: reason, offersEnable: false, notesDataGap: true).actionTitle == nil)
    }
    #expect(OpsDisabledPresentation.emptyState(reason: .unknown, offersEnable: true, notesDataGap: true).detail == dataGap)
    #expect(OpsDisabledPresentation.emptyState(reason: .settingOff, offersEnable: true, notesDataGap: true).detail
        == "错误率、告警、服务器状态与错误日志都不可用\n" + dataGap)
}

@Test func configOffNeverOffersButtonWebOrRetry() {
    let texts = [OpsDisabledPresentation.inlineText(reason: .configOff, tpmExcludesCache: true)]
        + [true, false].flatMap { gap in
            let empty = OpsDisabledPresentation.emptyState(reason: .configOff, offersEnable: false, notesDataGap: gap)
            return [empty.title, empty.detail ?? ""]
        }
    for text in texts { #expect(!text.contains("Web") && !text.contains("设置页") && !text.contains("重试")) }
    for owner in [true, false] {
        for route in [OpsMonitoringWriteRoute.monitoringStatus, .legacySettings, .unavailable] {
            #expect(!OpsDisabledPresentation.offersEnable(reason: .configOff, isAdministrator: owner, route: route))
        }
    }
}

@Test func offersEnableOnlyForOwnerOnSitesWithAWriteRoute() {
    for reason in [OpsDisabledReason.settingOff, .unknown] {
        #expect(OpsDisabledPresentation.offersEnable(reason: reason, isAdministrator: true, route: .monitoringStatus))
        #expect(OpsDisabledPresentation.offersEnable(reason: reason, isAdministrator: true, route: .legacySettings))
        // S1D1-07: a site without `/admin/me` may reset other settings on a partial settings PUT.
        #expect(!OpsDisabledPresentation.offersEnable(reason: reason, isAdministrator: true, route: .unavailable))
        #expect(!OpsDisabledPresentation.offersEnable(reason: reason, isAdministrator: false, route: .monitoringStatus))
    }
}

@Test func offersDisableNeedsStatusRouteOwnerAndOpsOn() {
    #expect(OpsDisabledPresentation.offersDisable(isAdministrator: true, route: .monitoringStatus, isOpsDisabled: false))
    #expect(!OpsDisabledPresentation.offersDisable(isAdministrator: false, route: .monitoringStatus, isOpsDisabled: false))
    #expect(!OpsDisabledPresentation.offersDisable(isAdministrator: true, route: .legacySettings, isOpsDisabled: false))
    #expect(!OpsDisabledPresentation.offersDisable(isAdministrator: true, route: .unavailable, isOpsDisabled: false))
    #expect(!OpsDisabledPresentation.offersDisable(isAdministrator: true, route: .monitoringStatus, isOpsDisabled: true))
}

@Test func reasonPrefersLegacyConclusionThenStatusThenMeFeatures() {
    let configOffFeatures = AdminMe.Features(opsMonitoringEnabled: false, opsMonitoringDisabledReason: "config_off")
    let settingOffStatus = OpsMonitoringStatus(effective: false, disabledReason: "setting_off")
    #expect(OpsDisabledPresentation.reason(status: settingOffStatus, legacyConfigOff: true, features: .init()) == .configOff)
    #expect(OpsDisabledPresentation.reason(status: settingOffStatus, legacyConfigOff: false, features: configOffFeatures) == .settingOff)
    #expect(OpsDisabledPresentation.reason(status: OpsMonitoringStatus(effective: true), legacyConfigOff: false, features: configOffFeatures) == .configOff)
    #expect(OpsDisabledPresentation.reason(status: nil, legacyConfigOff: false, features: .init()) == .unknown)
    #expect(OpsDisabledPresentation.reason(status: nil, legacyConfigOff: false, features: .init(opsMonitoringEnabled: false)) == .unknown)
}

@Test func enableAndDisableConfirmationCopy() {
    #expect(OpsDisabledPresentation.enableConfirmation == .init(title: "开启运维监控？", message: "开启后开始记录错误请求、告警与服务器指标；关闭期间的数据不会补回。",
                                                                confirmTitle: "开启", isDestructive: false))
    #expect(OpsDisabledPresentation.disableConfirmation == .init(
        title: "关闭运维监控？", message: "关闭后不再记录错误请求、告警与服务器指标，概览的错误率与告警、监控各段都不可用；关闭期间的数据开启后也不会补回。",
        confirmTitle: "关闭运维监控", isDestructive: true))
    #expect(OpsDisabledPresentation.disableFinalConfirmation(siteName: "演示站") == .init(
        title: "确认关闭「演示站」的运维监控？", message: "这会关闭整个站点的运维监控，对所有管理员生效。", confirmTitle: "仍要关闭", isDestructive: true))
}

@Test func enableOutcomeFromStatus() {
    #expect(OpsDisabledPresentation.enableOutcome(OpsMonitoringStatus(effective: true)) == .enabled)
    #expect(OpsDisabledPresentation.enableOutcome(OpsMonitoringStatus(effective: false, disabledReason: "config_off")) == .configOff)
    #expect(OpsDisabledPresentation.enableOutcome(OpsMonitoringStatus(effective: false, disabledReason: "setting_off")) == .failed("运维监控未能开启，请重试"))
    #expect(OpsDisabledPresentation.enableOutcome(OpsMonitoringStatus()) == .failed("运维监控未能开启，请重试"))
}

@Test func disableOutcomeFromStatus() {
    #expect(OpsDisabledPresentation.disableOutcome(OpsMonitoringStatus(effective: false, disabledReason: "setting_off")) == .disabled)
    #expect(OpsDisabledPresentation.disableOutcome(OpsMonitoringStatus(effective: true)) == .failed("运维监控未能关闭，请重试"))
}

@Test func failureOutcomeByStatusAndReason() {
    #expect(OpsDisabledPresentation.failureOutcome(APIError.server(status: 409, reason: "OPS_CONFIG_DISABLED")) == .configOff)
    #expect(OpsDisabledPresentation.failureOutcome(APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")) == .failed("只读访问令牌不能修改设置"))
    for reason in ["FORBIDDEN", "WORKSPACE_PERMISSION_DENIED", nil] {
        #expect(OpsDisabledPresentation.failureOutcome(APIError.server(status: 403, reason: reason)) == .failed("当前身份没有修改运维设置的权限"))
    }
    for status in [502, 503, 504] { #expect(OpsDisabledPresentation.failureOutcome(APIError.server(status: status, reason: nil)) == .unconfirmed) }
    #expect(OpsDisabledPresentation.failureOutcome(APIError(kind: .transport, message: "无法连接站点")) == .unconfirmed)
    let cleared = APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED").withSecurityOutcome(.passed)
    #expect(OpsDisabledPresentation.failureOutcome(cleared) == .failed("合规确认已完成，请重新确认后发送"))
    let internalError = APIError.server(status: 500, reason: "INTERNAL_ERROR")
    #expect(OpsDisabledPresentation.failureOutcome(internalError) == .failed(internalError.localizedDescription))
    #expect(OpsDisabledPresentation.failureOutcome(CancellationError()) == nil)
}

@Test func failureTextsNeverEchoServerMessage() {
    let body = #"{"code":500,"message":"secret upstream https://x.invalid","reason":"INTERNAL_ERROR"}"#
    let error = APIError.from(HTTPResponse(statusCode: 500, headers: [:], data: Data(body.utf8)))
    guard case .failed(let text)? = OpsDisabledPresentation.failureOutcome(error) else { Issue.record("expected a failure"); return }
    #expect(!text.contains("secret") && !text.contains("https://"))
}

@Test func readBackOnlyForTransportAndGatewayErrors() {
    #expect(OpsDisabledPresentation.needsReadBack(APIError(kind: .transport, message: "无法连接站点")))
    for status in [502, 503, 504] { #expect(OpsDisabledPresentation.needsReadBack(APIError.server(status: status, reason: nil))) }
    for status in [400, 403, 404, 409, 423, 429, 500] { #expect(!OpsDisabledPresentation.needsReadBack(APIError.server(status: status, reason: nil))) }
    #expect(!OpsDisabledPresentation.needsReadBack(APIError.server(status: 503, reason: "STEP_UP_UNAVAILABLE")))
    #expect(!OpsDisabledPresentation.needsReadBack(CancellationError()))
}

@Test func toggleReceiptsTextAndTone() {
    typealias Outcome = OpsDisabledPresentation.ToggleOutcome
    #expect(Outcome.enabled.receiptText == "已开启运维监控" && Outcome.enabled.receiptTone == .ok)
    #expect(Outcome.disabled.receiptText == "已关闭运维监控" && Outcome.disabled.receiptTone == .ok)
    #expect(Outcome.configOff.receiptText == "运维监控已在服务器配置中关闭" && Outcome.configOff.receiptTone == .neutral)
    #expect(Outcome.failed("只读访问令牌不能修改设置").receiptText == "只读访问令牌不能修改设置" && Outcome.failed("x").receiptTone == .critical)
    #expect(Outcome.unconfirmed.receiptText == "结果未确认，请刷新核对后再操作" && Outcome.unconfirmed.receiptTone == .caution)
}
