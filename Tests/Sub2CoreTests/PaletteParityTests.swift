import Foundation
import Testing

// NativeApp/Design/Palette.swift is not part of the package, so its token lines are compared as text with the design CSS (00 §8.2.6).
private let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private let expectedTokens = [
    "canvas", "surface", "sheetBackground", "sunken", "segmentOn", "hairline", "ruleStrong", "ink1", "ink2", "ink3",
    "accent", "accentFill", "onAccent", "accentWash",
    "ok", "okInk", "okWash", "caution", "cautionInk", "cautionWash", "critical", "criticalInk", "criticalWash",
    "neutral", "neutralInk", "neutralWash", "model", "modelInk", "modelWash",
    "legendActual", "legendCost", "legendStandard", "chartMain", "chartBarNow", "chartCompare", "chartBar"
]
private let cssNameExceptions = [
    "sheetBackground": "sheet-bg", "segmentOn": "seg-on-bg",
    "legendActual": "lg-actual", "legendCost": "lg-cost", "legendStandard": "lg-standard"
]

private func cssName(_ token: String) -> String {
    cssNameExceptions[token] ?? token.reduce(into: "") { name, character in
        if character.isUppercase { name += "-" + character.lowercased() } else { name.append(character) }
    }
}

private func cssBlock(_ css: String, selector: String) throws -> [String: String] {
    let start = try #require(css.range(of: selector + " {"))
    let end = try #require(css.range(of: "}", range: start.upperBound..<css.endIndex))
    let body = css[start.upperBound..<end.lowerBound]
    var values: [String: String] = [:]
    for match in body.matches(of: /--([a-z0-9-]+):\s*#([0-9A-Fa-f]{6})\b/) {
        values[String(match.1)] = match.2.uppercased()
    }
    return values
}

@Test func paletteTokensMatchVernierCSS() throws {
    let swift = try String(contentsOf: repositoryRoot.appending(path: "NativeApp/Design/Palette.swift"), encoding: .utf8)
    let css = try String(contentsOf: repositoryRoot.appending(path: "docs/ui-reassessment-claude-20261016/html-preview/shared/vernier-palette.css"),
                         encoding: .utf8)
    let light = try cssBlock(css, selector: ".pal-vernier.light")
    let dark = try cssBlock(css, selector: ".pal-vernier.dark")
    let lines = swift.matches(of: /static let (\w+) = Color\.vernier\(light: 0x([0-9A-F]{6}), dark: 0x([0-9A-F]{6})\)/)
    let names = lines.map { String($0.1) }
    #expect(names.count == Set(names).count, "duplicate tokens")
    #expect(Set(names) == Set(expectedTokens))
    for line in lines {
        let token = String(line.1), name = cssName(token)
        #expect(light[name] == String(line.2), "\(token) light (--\(name))")
        #expect(dark[name] == String(line.3), "\(token) dark (--\(name))")
    }
}
