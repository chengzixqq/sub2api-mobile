import SwiftUI
import Sub2Core

/// 10 §0.7-6: the receipt above the tab bar of the tab in view. MainTabs puts one over each tab's stack; ReceiptCenter
/// announces it once, so the overlays never speak. A sheet with its own overlay (`inSheet`) takes the receipt while shown.
struct ReceiptOverlay: View {
    var inSheet = false
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var host = UUID()

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.receipts.draws(host: inSheet ? host : nil), let receipt = model.receipts.current {
                ReceiptBar(receipt: receipt) { model.receipts.performAction(id: receipt.id) }
                    .id(receipt.id)
                    // Without a button it is only read: taps reach the page under it (S0-16 shows one after every login).
                    .allowsHitTesting(receipt.action != nil)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12 + model.receipts.bottomClearance)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.28), value: model.receipts.current?.id)
        .onAppear { if inSheet { model.receipts.addSheetHost(host) } }
        .onDisappear { if inSheet { model.receipts.removeSheetHost(host) } }
    }
}

/// Design `.toast`: system glass, the tone's icon, 15pt text and one accent button with a 44pt target (00 §8.2.4–§8.2.5).
struct ReceiptBar: View {
    let receipt: Receipt
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: receipt.systemImage).font(.body.weight(.semibold)).foregroundStyle(receipt.tone.base)
                .accessibilityHidden(true)
            Text(receipt.text).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("receipt.text")
            if let action = receipt.action {
                Button(action.title, action: onAction)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("receipt.action")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, receipt.action == nil ? 18 : 8)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receipt")
    }
}
