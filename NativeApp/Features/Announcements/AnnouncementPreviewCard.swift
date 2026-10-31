import SwiftUI
import Sub2Core

/// 60 §16.3 “用户看到的样子”: a popup is a card set in from the edges with a “知道了” button drawn below (only a picture of
/// one); a silent announcement is a notification card with a neutral rail. The edit sheet's preview uses it as is (S6-18).
struct AnnouncementPreviewCard: View {
    let title: String
    let content: String
    let notifyMode: AnnouncementNotifyMode
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, content: String, notifyMode: AnnouncementNotifyMode) {
        self.title = title; self.content = content; self.notifyMode = notifyMode
    }

    private var isPopup: Bool { notifyMode == .popup }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            label
            card
                .padding(.horizontal, isPopup ? 10 : 0)
                .padding(.top, isPopup ? 4 : 0)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 16, trailing: 14))
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("announcement.preview")
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: AnnouncementPresentation.notifySymbol(notifyMode)).accessibilityHidden(true)
            Text(AnnouncementDetailPresentation.previewLabel(notifyMode))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Palette.ink2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("announcement.preview.label")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AnnouncementPresentation.displayTitle(title)).font(.headline).foregroundStyle(Palette.ink1)
                .accessibilityIdentifier("announcement.preview.title")
            if AnnouncementDetailPresentation.hasBody(content) {
                MiniMarkdownView(text: content)
            } else {
                Text(AnnouncementDetailPresentation.emptyBody).font(.subheadline).foregroundStyle(Palette.ink3)
                    .accessibilityIdentifier("announcement.preview.empty")
            }
            if isPopup { dismissPicture.padding(.top, 6) }
        }
        .padding(EdgeInsets(top: 16, leading: isPopup ? 16 : 18, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.06))
            }
        }
        .overlay(alignment: .leading) { if !isPopup { rail } }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.10), radius: colorScheme == .dark ? 14 : 12, y: colorScheme == .dark ? 10 : 8)
    }

    /// The bell list's entry: the 00 §8.1 capsule in the neutral tone, which `statusCapsule` leaves undrawn.
    private var rail: some View {
        Capsule().fill(Palette.neutral)
            .frame(width: StatusCapsuleMetrics.width)
            .padding(.vertical, StatusCapsuleMetrics.verticalInset)
            .padding(.leading, StatusCapsuleMetrics.leadingInset)
            .accessibilityHidden(true)
    }

    private var dismissPicture: some View {
        Text(AnnouncementDetailPresentation.previewDismiss)
            .font(.callout.weight(.semibold)).foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Palette.accentFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(AnnouncementDetailPresentation.previewDismiss + "（示意）")
            .accessibilityIdentifier("announcement.preview.dismiss")
    }
}
