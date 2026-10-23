import SwiftUI

/// A section title with its number on the right (60 §1.3, §3.3). The number only decorates and is not read out.
struct NumberedSectionHeader: View {
    let title: String
    let ordinal: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            Text(ordinal).font(.subheadline).foregroundStyle(Palette.ink3)
        }
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}
