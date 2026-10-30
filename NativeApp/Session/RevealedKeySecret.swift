import Foundation
import Observation

/// 30 §7.4 (S3-13): the one holder of a full key, for the 完整 Key / Key 已创建 sheet. It lives in memory only and goes on its
/// own after 30 seconds, when the App goes to the background or when the sheet closes (`clear`); while the App is inactive the
/// sheet covers it (the App switcher's snapshot). Never printed, reflected, logged, saved or restored.
@MainActor @Observable
final class RevealedKeySecret: Identifiable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    enum Purpose: Sendable, Equatable { case reveal, created }
    nonisolated static let lifetime: Duration = .seconds(30)

    let id = UUID()
    nonisolated let keyID: Int
    let purpose: Purpose
    /// Unescaped (S3D1-12).
    let name: String
    private(set) var plaintext: String?
    /// Inactive: the sheet shows the key redacted until the App is active again.
    private(set) var isShielded = false
    /// Cleared by the 30 seconds (the sheet says which way it went).
    private(set) var expired = false
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(keyID: Int, purpose: Purpose, name: String, plaintext: String,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.keyID = keyID; self.purpose = purpose; self.name = name; self.plaintext = plaintext
        timer = Task { [weak self] in
            do { try await sleep(Self.lifetime) } catch { return }
            guard !Task.isCancelled else { return }
            self?.expire()
        }
    }

    func clear() {
        timer?.cancel(); timer = nil
        plaintext = nil
    }
    func activityChanged(to activity: AppActivity) {
        switch activity {
        case .active: isShielded = false
        case .inactive: isShielded = true
        case .background:
            isShielded = false
            clear()
        }
    }
    private func expire() {
        guard plaintext != nil else { return }
        plaintext = nil
        expired = true
        timer = nil
    }

    nonisolated var description: String { "RevealedKeySecret(keyID: \(keyID), key: <redacted>)" }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: ["keyID": keyID], displayStyle: .class) }
}
