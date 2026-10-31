import Foundation

/// Launch arguments shared by the `-ui-testing` fixtures. Kept apart from DemoData so NativeSessionSupport compiles and
/// tests the parsing.
enum UITestArguments {
    /// X05: `-ui-without-capabilities a,b` takes those raw capability values out of the fixture site's capabilities.
    static let withoutCapabilities = "-ui-without-capabilities"

    /// The comma-separated raw values that follow the flag; a missing, trailing, dash-prefixed or empty value yields [].
    static func withheldCapabilities(arguments: [String]) -> Set<String> {
        guard let index = arguments.firstIndex(of: withoutCapabilities), arguments.indices.contains(index + 1),
              !arguments[index + 1].hasPrefix("-") else { return [] }
        let values = arguments[index + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return Set(values.filter { !$0.isEmpty })
    }
}
