import Testing
import Sub2Core
@testable import NativeSessionSupport

// S5-04: `.groups(segment:)` scrolls to the list section of the same raw value (S5-02 spec_issues 4).
@Test func groupListSegmentsMatchTheListSections() {
    #expect(GroupListSegment.allCases.map(\.rawValue) == GroupListSection.Kind.allCases.map(\.rawValue))
    #expect(GroupListSegment.allCases.map(\.title) == GroupListSection.Kind.allCases.map(\.title))
}
