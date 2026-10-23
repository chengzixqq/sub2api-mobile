import Foundation
import Observation
import Sub2Core

/// A receipt's one button: a custom action, or 撤销 (BUILDER_GUIDE `showToast`). VoiceOver reads its title.
struct ReceiptAction: Sendable {
    let title: String
    let perform: @MainActor @Sendable () -> Void

    init(title: String, perform: @escaping @MainActor @Sendable () -> Void) { self.title = title; self.perform = perform }
    static func undo(_ perform: @escaping @MainActor @Sendable () -> Void) -> ReceiptAction { ReceiptAction(title: "撤销", perform: perform) }
}

/// 10 §0.7-6: icon, text and at most one button. Given both, the custom action wins over undo.
struct Receipt: Identifiable, Sendable {
    let id: UUID
    let text: String
    let systemImage: String
    let tone: Tone
    let action: ReceiptAction?

    init(text: String, systemImage: String = "checkmark.circle", tone: Tone = .ok, undo: (@MainActor @Sendable () -> Void)? = nil,
         action: ReceiptAction? = nil, id: UUID = UUID()) {
        self.id = id; self.text = text; self.systemImage = systemImage; self.tone = tone
        self.action = action ?? undo.map(ReceiptAction.undo)
    }

    /// Design `setSite`, after the site menu or the settings page switched sites (10 §0.7-5).
    static func switched(to siteName: String) -> Receipt { Receipt(text: "已切换到 \(siteName)", systemImage: "server.rack") }
    /// D19, after deleting another site: the server steps that did not happen follow (60 §3.4, 00 §7.6).
    static func siteRemoved(notes: [String]) -> Receipt {
        notes.isEmpty ? Receipt(text: "已删除站点", systemImage: "trash")
            : Receipt(text: "已删除站点 · " + notes.joined(separator: "；"), systemImage: "exclamationmark.triangle", tone: .caution)
    }
}

/// The App's one receipt (10 §0.7-6). AppModel owns it, so a receipt shown right after a site switch survives the
/// rebuilt tabs; MainTabs only draws it. A new receipt replaces the old one at once and is announced here, once; it
/// leaves after 4.2 seconds (R17), and an older receipt's timer never removes a newer one.
@MainActor @Observable
final class ReceiptCenter {
    nonisolated static let displayDuration: Duration = .milliseconds(4200)

    private(set) var current: Receipt?
    @ObservationIgnored private var timer: Task<Void, Never>?
    private let duration: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let announce: @MainActor (String) -> Void

    init(duration: Duration = ReceiptCenter.displayDuration,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         announce: @escaping @MainActor (String) -> Void = { _ in }) {
        self.duration = duration; self.sleep = sleep; self.announce = announce
    }

    func show(_ receipt: Receipt) {
        timer?.cancel()
        current = receipt
        announce(receipt.text)
        let id = receipt.id, duration = duration, sleep = sleep
        timer = Task { [weak self] in
            do { try await sleep(duration) } catch { return }
            self?.dismiss(id: id)
        }
    }
    /// Only the receipt with this id; a newer one stays.
    func dismiss(id: UUID) {
        guard current?.id == id else { return }
        clear()
    }
    /// The button: the receipt leaves first, then its action runs.
    func performAction() {
        guard let receipt = current, let action = receipt.action else { return }
        clear()
        action.perform()
    }
    func clear() {
        timer?.cancel(); timer = nil
        current = nil
    }
}
