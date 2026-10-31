import SwiftUI

/// A section title with its number on the right (60 §1.3, §3.3; C-33). An optional meta (“00:00 起”) sits before the number and an
/// accessory (a block's status) right after the title. VoiceOver reads the title with the meta as its value; the accessory is its
/// own element and the number only decorates. Without an ordinal no number is drawn; `id` names the title element.
struct NumberedSectionHeader<Accessory: View>: View {
    let title: String
    let ordinal: String?
    let meta: String?
    let id: String?
    let accessory: Accessory

    init(title: String, ordinal: String? = nil, meta: String? = nil, id: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title; self.ordinal = ordinal; self.meta = meta; self.id = id; self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
                .accessibilityValue(Text(meta ?? ""))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(id ?? "")
            accessory
            Spacer(minLength: 8)
            if let meta { Text(meta).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink3).accessibilityHidden(true) }
            if let ordinal { Text(ordinal).font(.subheadline).foregroundStyle(Palette.ink3).accessibilityHidden(true) }
        }
        .textCase(nil)
    }
}

extension NumberedSectionHeader where Accessory == EmptyView {
    init(title: String, ordinal: String? = nil, meta: String? = nil, id: String? = nil) {
        self.init(title: title, ordinal: ordinal, meta: meta, id: id) { EmptyView() }
    }
}
