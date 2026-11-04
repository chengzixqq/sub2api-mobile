import Foundation
import Testing
@testable import Sub2Core

@Test func toneDrawsRailOnlyForCautionCriticalAndModel() {
    #expect(Tone.allCases.count == 5)
    #expect(Tone.caution.drawsRail && Tone.critical.drawsRail && Tone.model.drawsRail)
    #expect(!Tone.ok.drawsRail && !Tone.neutral.drawsRail)
}

@Test func accountScheduleStateMapsToStateMetaToneAndLabel() {
    let expected: [(AccountScheduleState, String, Tone)] = [
        (.error, "错误", .critical), (.overloaded, "过载中", .critical), (.rateLimited, "限流中", .caution),
        (.tempUnschedulable, "临时不可调度", .caution), (.paused, "暂停", .neutral), (.inactive, "停用", .neutral), (.available, "正常", .ok)
    ]
    for (state, label, tone) in expected {
        #expect(state.label == label, "\(state)")
        #expect(state.tone == tone, "\(state)")
    }
}

@Test func accountScheduleStateRawValuesMatchBackendConstants() {
    // account_status_summary.go constants, in the design's STATE_ORDER.
    #expect(AccountScheduleState.allCases.map(\.rawValue) == [
        "error", "overloaded", "rate_limited", "temp_unschedulable", "paused", "inactive", "available"
    ])
    #expect(AccountScheduleState(rawValue: "disabled") == nil)
    #expect(AccountScheduleState(rawValue: "normal") == nil)
}

// Design `codeTone`; codes outside 100...599 count as missing.
private func codes(_ values: [Int?], _ tone: Tone) -> [(Int?, Tone)] { values.map { ($0, tone) } }
private let codeTones: [(Int?, Tone)] = codes([nil, 0, -1, 600, 999], .neutral) + codes([200, 201, 299], .ok) + codes([429], .caution)
    + codes([304, 400, 401, 403, 404, 423, 500, 502, 503, 504, 529], .critical)

@Test(arguments: codeTones)
func httpStatusToneFollowsCodeTone(code: Int?, tone: Tone) {
    #expect(Tone.httpStatus(code) == tone)
}

@Test func alertToneColoursOnlyFiringEvents() {
    #expect(Tone.alert(severity: "P0", status: "firing") == .critical)
    #expect(Tone.alert(severity: "P1", status: "firing") == .caution)
    #expect(Tone.alert(severity: "P2", status: "firing") == .caution)
    #expect(Tone.alert(severity: "P3", status: "firing") == .neutral)
    #expect(Tone.alert(severity: " p0 ", status: "firing") == .critical)
    #expect(Tone.alert(severity: "p3", status: " FIRING ") == .neutral)
    #expect(Tone.alert(severity: "warning", status: "firing") == .caution)
    #expect(Tone.alert(severity: nil, status: "firing") == .caution)
    #expect(Tone.alert(severity: "P0", status: "resolved") == nil)
    #expect(Tone.alert(severity: "P0", status: "manual_resolved") == nil)
    #expect(Tone.alert(severity: "P0", status: nil) == nil)
}
