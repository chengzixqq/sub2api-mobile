import Foundation
import Observation

/// C-34 (S6D1-02): an announcement was published, archived, withdrawn, deleted or saved, so the list and the detail read again.
/// Take it only through `model.announcementChanges` (the current session's generation); writers call `bump()`, readers watch
/// `revision`. One instance per generation, the latest four kept, so a switch or sign-out starts a new one.
@MainActor @Observable
final class AnnouncementChangeSignal {
    private(set) var revision = 0

    private init() {}

    func bump() { revision += 1 }

    /// The same generation always gets the same instance; an older generation never replaces the newer ones.
    static func signal(for generation: UUID) -> AnnouncementChangeSignal {
        if let signal = signals[generation] { return signal }
        let signal = AnnouncementChangeSignal()
        signals[generation] = signal
        order.append(generation)
        while order.count > kept { signals[order.removeFirst()] = nil }
        return signal
    }

    private static let kept = 4
    private static var signals: [UUID: AnnouncementChangeSignal] = [:]
    private static var order: [UUID] = []
}
