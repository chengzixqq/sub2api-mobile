import UIKit
import UniformTypeIdentifiers

/// C-3, the one way to copy a sensitive value (60 §0.4): this phone only (`.localOnly`, never Handoff), optionally gone
/// after a while. Used for a revealed key (60 seconds), a new user's random password (60 seconds), redeem codes (kept) and
/// proxy URLs (120 seconds); e-mails, request IDs and other plain values are copied the ordinary way. The text is never
/// logged; the caller shows its own receipt (“已复制兑换码”).
enum SensitivePasteboard {
    static let revealedKeyLifetime: TimeInterval = 60
    static let proxyURLLifetime: TimeInterval = 120

    @MainActor static func copy(_ text: String, expiresIn seconds: TimeInterval? = nil) {
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if let seconds, seconds > 0 { options[.expirationDate] = Date(timeIntervalSinceNow: seconds) }
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: options)
    }
}
