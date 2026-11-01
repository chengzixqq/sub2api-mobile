import Foundation
import Testing
@testable import Sub2Core

// 40 §4.3: a mapping row's model reads “a -> b” (the backend's requested || ' -> ' || upstream); the name shows a, the detail
// line starts with “→ b” (S4-15, S4D2b-11).

@Test func mappingNamesSplitAtTheFirstArrow() {
    let name = AnalyticsModelName("claude-opus-4 -> claude-opus-4-20250514", source: .mapping)
    #expect(name.raw == "claude-opus-4 -> claude-opus-4-20250514")
    #expect(name.source == .mapping)
    #expect(name.requested == "claude-opus-4")
    #expect(name.upstream == "claude-opus-4-20250514")
    #expect(name.displayName == "claude-opus-4")

    let chained = AnalyticsModelName("a -> b -> c", source: .mapping)
    #expect(chained.requested == "a")
    #expect(chained.upstream == "b -> c")
}

@Test func otherSourcesAndArrowlessNamesStayWhole() {
    for source in [ModelSource.requested, .upstream] {
        let name = AnalyticsModelName("claude-opus-4 -> claude-opus-4-20250514", source: source)
        #expect(name.requested == name.raw, "\(source)")
        #expect(name.upstream == nil, "\(source)")
    }
    let plain = AnalyticsModelName("gpt-5", source: .mapping)
    #expect(plain.requested == "gpt-5")
    #expect(plain.upstream == nil)
}

@Test func mappingWithAnEmptySideIsNotSplit() {
    for raw in ["a -> ", " -> b", " -> "] {
        let name = AnalyticsModelName(raw, source: .mapping)
        #expect(name.upstream == nil, "\(raw)")
        #expect(name.requested == raw, "\(raw)")
    }
}

@Test func missingOrBlankNamesReadAsUnnamed() {
    let missing = AnalyticsModelName(nil, source: .requested)
    #expect(missing.raw == "")
    #expect(missing.displayName == "未命名")
    #expect(AnalyticsModelName("  ", source: .upstream).displayName == "未命名")
}
