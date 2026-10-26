import Testing
@testable import NativeSessionSupport

@Test func withheldCapabilitiesReadsTheCommaSeparatedValueAfterTheFlag() {
    let arguments = ["-ui-testing", UITestArguments.withoutCapabilities, "dashboard.home,admin.access_tokens", "-ui-other"]
    #expect(UITestArguments.withoutCapabilities == "-ui-without-capabilities")
    #expect(UITestArguments.withheldCapabilities(arguments: arguments) == ["dashboard.home", "admin.access_tokens"])
}

@Test func withheldCapabilitiesTrimsBlanksAndDropsEmptyItems() {
    let arguments = [UITestArguments.withoutCapabilities, " redeem_codes.stats , ,announcements.read_stats,"]
    #expect(UITestArguments.withheldCapabilities(arguments: arguments) == ["redeem_codes.stats", "announcements.read_stats"])
}

@Test(arguments: [
    ["-ui-testing"],
    ["-ui-testing", "-ui-without-capabilities"],
    ["-ui-without-capabilities", "-ui-testing"],
    ["-ui-without-capabilities", ""],
    ["-ui-without-capabilities", " , "]
])
func withheldCapabilitiesIsEmptyWithoutAValue(arguments: [String]) {
    #expect(UITestArguments.withheldCapabilities(arguments: arguments).isEmpty)
}
