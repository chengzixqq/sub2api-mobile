import Foundation

/// One block of an announcement body (60 §16.3, §16.7).
public enum MiniMarkdownBlock: Equatable, Sendable {
    case heading(String)
    /// Consecutive lines, their line breaks kept as the Web's `breaks: true` shows them.
    case paragraph(String)
    case list([String])
}

/// The Markdown an announcement body is written in, as small as the Web editor produces (60 §16.7, S6D1-14): “# ”–“### ”
/// headings, “- ” lists and blank lines between paragraphs; inside them bold and links. HTML is never interpreted, and only
/// http / https links stay tappable.
public enum MiniMarkdown {
    public static let allowedLinkSchemes: Set<String> = ["http", "https"]

    public static func isAllowedLink(_ url: URL) -> Bool { url.scheme.map { allowedLinkSchemes.contains($0.lowercased()) } ?? false }

    public static func blocks(_ text: String) -> [MiniMarkdownBlock] {
        var builder = BlockBuilder()
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) { builder.add(line) }
        return builder.finished()
    }

    #if canImport(Darwin)
    /// Bold, italics, code and links of one block, white space and line breaks kept. A link to anything but http / https
    /// keeps its text and loses its target; text that does not parse is shown as typed.
    public static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var parsed = try? AttributedString(markdown: text, options: options) else { return AttributedString(text) }
        let unsafe = parsed.runs.compactMap { run in run.link.flatMap { isAllowedLink($0) ? nil : run.range } }
        for range in unsafe { parsed[range].link = nil }
        return parsed
    }
    #endif

    fileprivate static func heading(_ line: String) -> String? {
        let marks = line.prefix { $0 == "#" }.count
        guard (1...3).contains(marks), line.dropFirst(marks).first == " " else { return nil }
        return line.dropFirst(marks + 1).trimmingCharacters(in: .whitespaces)
    }
}

private struct BlockBuilder {
    private var blocks: [MiniMarkdownBlock] = []
    private var paragraph: [String] = []
    private var items: [String]?

    mutating func add(_ line: String) {
        if line.hasPrefix("- ") {
            flushParagraph()
            items = (items ?? []) + [String(line.dropFirst(2))]
            return
        }
        flushList()
        if line.trimmingCharacters(in: .whitespaces).isEmpty { return flushParagraph() }
        guard let title = MiniMarkdown.heading(line) else { paragraph.append(line); return }
        flushParagraph()
        if !title.isEmpty { blocks.append(.heading(title)) }
    }

    mutating func finished() -> [MiniMarkdownBlock] {
        flushParagraph(); flushList()
        return blocks
    }

    private mutating func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
    }
    private mutating func flushList() {
        guard let items else { return }
        blocks.append(.list(items))
        self.items = nil
    }
}
