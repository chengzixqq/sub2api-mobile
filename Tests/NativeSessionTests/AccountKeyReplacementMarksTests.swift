import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// The site clock when the key was replaced: 2026-10-24T08:00:00Z.
private let replacedAt = Date(timeIntervalSince1970: 1_792_828_800)

private func keyAccount(_ id: Int, status: String = "active", errorAt: TimeInterval? = nil, rawErrorAt: String? = nil) -> UpstreamAccount {
    UpstreamAccount(id: id, name: "账号 \(id)", platform: "openai", type: "apikey", status: status,
                    errorAt: rawErrorAt ?? errorAt.map { ServerTime.utcTimestamp(replacedAt.addingTimeInterval($0)) })
}

@MainActor @Test func recordedMarkAppliesToSameAccountOnly() {
    let marks = AccountKeyReplacementMarks()
    marks.record(keyAccount(7, status: "error", errorAt: -60), at: replacedAt)
    let mark = marks.mark(for: keyAccount(7, status: "error", errorAt: -60))
    #expect(mark?.replacedAt == replacedAt && mark?.wasError == true)
    #expect(marks.isReplaced(keyAccount(7, status: "error", errorAt: -60)))
    #expect(marks.mark(for: keyAccount(4)) == nil && !marks.isReplaced(keyAccount(4)))
}

/// 20 §2.3: an error account's mark ends once the error is gone (a test that passed clears it), and never comes back.
@MainActor @Test func errorAccountMarkClearsOnceErrorIsGone() {
    let marks = AccountKeyReplacementMarks()
    marks.record(keyAccount(7, status: "error", errorAt: -60), at: replacedAt)
    #expect(marks.mark(for: keyAccount(7)) == nil)
    marks.reconcile(keyAccount(7))
    #expect(marks.marks.isEmpty)
    #expect(marks.mark(for: keyAccount(7, status: "error")) == nil)
}

/// A healthy account keeps “已更换 · HH:MM” until the new key is refused too.
@MainActor @Test func healthyAccountMarkClearsWhenAccountErrors() {
    let marks = AccountKeyReplacementMarks()
    marks.record(keyAccount(4), at: replacedAt)
    #expect(marks.mark(for: keyAccount(4))?.wasError == false)
    #expect(marks.mark(for: keyAccount(4, status: "error", errorAt: 30)) == nil)
    marks.reconcile(keyAccount(4, status: "error", errorAt: 30))
    #expect(marks.marks[4] == nil)
}

/// The new key failed its test: the account was marked in error again after the replacement.
@MainActor @Test func newerErrorAtInvalidatesMark() {
    let marks = AccountKeyReplacementMarks()
    marks.record(keyAccount(7, status: "error", errorAt: -300), at: replacedAt)
    #expect(marks.mark(for: keyAccount(7, status: "error", errorAt: -300)) != nil)
    #expect(marks.mark(for: keyAccount(7, status: "error", errorAt: 30)) == nil)
    #expect(marks.mark(for: keyAccount(7, status: "error", rawErrorAt: "not a time")) != nil)
    #expect(marks.mark(for: keyAccount(7, status: "error")) != nil)
    // reconcile keeps a mark that still holds.
    marks.reconcile(keyAccount(7, status: "error", errorAt: -300))
    #expect(marks.marks[7] != nil)
}

@MainActor @Test func recordingAgainReplacesTimeAndBaseline() {
    let marks = AccountKeyReplacementMarks()
    marks.record(keyAccount(7, status: "error"), at: replacedAt)
    let later = replacedAt.addingTimeInterval(600)
    marks.record(keyAccount(7), at: later)
    #expect(marks.mark(for: keyAccount(7))?.replacedAt == later)
    #expect(marks.mark(for: keyAccount(7))?.wasError == false)
}

@MainActor @Test func removeDropsMarkAndFreshInstanceIsEmpty() {
    let marks = AccountKeyReplacementMarks()
    marks.record(keyAccount(4), at: replacedAt)
    marks.remove(accountID: 4)
    #expect(marks.mark(for: keyAccount(4)) == nil)
    // AppModel builds a new one in publish and endActiveSession, so no mark outlives its session.
    #expect(AccountKeyReplacementMarks().marks.isEmpty)
}
