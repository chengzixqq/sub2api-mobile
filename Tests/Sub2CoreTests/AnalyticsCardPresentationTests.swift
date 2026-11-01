import Foundation
import Testing
@testable import Sub2Core

// 40 §1.6: what an analytics card says when it has no value or its last refresh failed (S4-13).

@Test func timeoutSaysStatisticsAreSlowAndOffersRetry() {
    for error in [APIError.server(status: 504, reason: nil), APIError.transport(URLError(.timedOut))] {
        let failure = AnalyticsCardFailure(error: error)
        #expect(failure.title == "统计较慢，加载超时", "\(error)")
        #expect(failure.allowsRetry, "\(error)")
    }
}

@Test func badRequestAndLocalValidationHaveNoRetry() {
    // The backend's response.BadRequest leaves the reason empty; AnalyticsQuery's own check has no status.
    let local = APIError(kind: .validation, message: "请选择一年以内的有效时间范围，并填写正整数对象 ID。")
    for error in [APIError.server(status: 400, reason: nil), local] {
        #expect(AnalyticsCardFailure(error: error).title == "请求参数无效", "\(error)")
        #expect(!AnalyticsCardFailure(error: error).allowsRetry, "\(error)")
    }
}

@Test func forbiddenHasNoRetry() {
    let failure = AnalyticsCardFailure(error: .server(status: 403, reason: "FORBIDDEN"))
    #expect(failure.title == "当前身份无权查看")
    #expect(!failure.allowsRetry)
}

@Test func otherFailuresSayLoadFailed() {
    let errors: [APIError?] = [.server(status: 500, reason: nil), nil, .server(status: 429, reason: nil),
                               .server(status: 423, reason: "COMPLIANCE_REQUIRED"), .transport(URLError(.notConnectedToInternet))]
    for error in errors {
        #expect(AnalyticsCardFailure(error: error) == AnalyticsCardFailure(error: .server(status: 502, reason: nil)), "\(String(describing: error))")
        #expect(AnalyticsCardFailure(error: error).title == "加载失败")
        #expect(AnalyticsCardFailure(error: error).allowsRetry)
    }
    #expect(AnalyticsCardText.retry == "重试本项")
}

@Test func staleLineShowsTheShownDataTimeInTheSiteZone() {
    let shownAt = ISO8601DateFormatter().date(from: "2026-10-16T01:40:00Z")!
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    #expect(AnalyticsCardText.staleLine(shownAt: shownAt, timeZone: shanghai) == "更新失败 · 显示的是 09:40 的数据")
    #expect(AnalyticsCardText.staleLine(shownAt: shownAt, timeZone: TimeZone(identifier: "UTC")!) == "更新失败 · 显示的是 01:40 的数据")
    #expect(AnalyticsCardText.staleLine(shownAt: nil, timeZone: shanghai) == "更新失败")
}

@Test func figureKeepsItsKeyLabelAndValue() {
    let figure = AnalyticsFigure("profit", label: "利润", value: "$772.42")
    #expect(figure.key == "profit" && figure.label == "利润" && figure.value == "$772.42")
    #expect(figure.id == "profit")
}
