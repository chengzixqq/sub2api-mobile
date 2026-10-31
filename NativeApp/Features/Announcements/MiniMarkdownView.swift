import SwiftUI
import Sub2Core

/// 60 §16.7: an announcement body drawn from MiniMarkdown blocks — small headings, paragraphs with their line breaks, “•”
/// lists — with bold and http / https links inline; a link opens through the environment's `openURL`. An empty body is the
/// caller's to show.
struct MiniMarkdownView: View {
    private let blocks: [MiniMarkdownBlock]

    init(text: String) { blocks = MiniMarkdown.blocks(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .heading(let title):
                    Text(MiniMarkdown.inline(title)).font(.callout.weight(.semibold)).foregroundStyle(Palette.ink1)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("announcement.markdown.heading.\(index)")
                case .paragraph(let text):
                    Text(MiniMarkdown.inline(text)).font(.subheadline).foregroundStyle(Palette.ink1).lineSpacing(4)
                        .accessibilityIdentifier("announcement.markdown.paragraph.\(index)")
                case .list(let items):
                    list(items, block: index)
                }
            }
        }
        .tint(Palette.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(_ items: [String], block: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").font(.subheadline).foregroundStyle(Palette.ink2).accessibilityHidden(true)
                    Text(MiniMarkdown.inline(item)).font(.subheadline).foregroundStyle(Palette.ink1).lineSpacing(4)
                        .accessibilityIdentifier("announcement.markdown.list.\(block).item.\(index)")
                }
            }
        }
        .padding(.leading, 4)
    }
}
