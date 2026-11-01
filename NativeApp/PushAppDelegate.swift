import Sub2Core
import UIKit
import UserNotifications

/// 60 §7.7: the system's push callbacks for PushCoordinator. Tokens, a failed registration and taps that arrive before the
/// model is attached wait in PushInbox (S6D2b-09). The notification center calls its delegate off the main thread, so those
/// methods are nonisolated and only the parsed, Sendable PushTap crosses to the main actor.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var inbox = PushInbox()
    private weak var model: AppModel?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set before launch ends, so a tap that launched the App reaches didReceive.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// After `restore()`, so a tap that launched the App finds the restored site.
    func attach(_ model: AppModel) {
        self.model = model
        for delivery in inbox.attach() { forward(delivery, to: model) }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receive(.token(deviceToken))
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        receive(.registrationFailed)
    }

    /// 00 §7.5: shown as a banner with sound, and the connected site's alert or account list refreshes.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let tap = PushDeepLink.parse(notification.request.content.userInfo)
        completionHandler([.banner, .sound])
        Task { @MainActor in await self.model?.pushArrivedInForeground(tap) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier != UNNotificationDismissActionIdentifier {
            let tap = PushDeepLink.parse(response.notification.request.content.userInfo)
            Task { @MainActor in self.receive(.tap(tap)) }
        }
        completionHandler()
    }

    private func receive(_ delivery: PushInbox.Delivery) {
        let ready = inbox.receive(delivery)
        guard let model else { return }
        for item in ready { forward(item, to: model) }
    }
    private func forward(_ delivery: PushInbox.Delivery, to model: AppModel) {
        switch delivery {
        case .token(let data): model.pushCoordinator.didReceiveDeviceToken(data)
        case .registrationFailed: model.pushCoordinator.didFailToRegister(PushRegistrationFailure())
        case .tap(let tap): Task { await model.pushCoordinator.openTap(tap, navigator: model) }
        }
    }
}

/// `didFailToRegisterForRemoteNotificationsWithError`; PushCoordinator shows 60 §7.5's text for any of them.
private struct PushRegistrationFailure: Error {}

/// `UNUserNotificationCenter` permission, asked with `[.alert, .sound, .badge]` (00 §7.1).
struct SystemNotificationAuthorizer: NotificationAuthorizing {
    func authorizationStatus() async -> PushAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}

/// The token or failure arrives through PushAppDelegate.
struct SystemRemoteNotificationRegistrar: RemoteNotificationRegistering {
    func registerForRemoteNotifications(reportingTo coordinator: PushCoordinator) {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

extension PushDeviceInfo {
    /// 00 §7.2: only the Debug build, signed with the development `aps-environment`, registers for the sandbox.
    @MainActor static var application: PushDeviceInfo {
        PushDeviceInfo(bundleID: Bundle.main.bundleIdentifier, deviceName: { UIDevice.current.name },
                       timeZone: { TimeZone.current.identifier }, sandbox: PushBuild.usesSandbox)
    }
}

private enum PushBuild {
    #if APNS_SANDBOX
    static let usesSandbox = true
    #else
    static let usesSandbox = false
    #endif
}

extension AppModel: PushSiteNavigating {
    var activeServerID: UUID? { activeProfile?.id }

    /// 00 §1.1 through `switchTo`: connected, or the site's login page when its credential is gone or its session refused.
    func openSite(_ profile: ServerProfile) async -> PushSiteOpening {
        await switchTo(profile)
        if activeProfile?.id == profile.id { return .connected }
        return loginPrompt?.profile.id == profile.id ? .loginPage : .failed
    }
}

extension AppModel {
    /// The tabs of the connected site take a tapped notification's page; a sheet in use is never closed for it (S6D2b-07).
    func openPendingPushTarget(in router: AppRouter) {
        pushCoordinator.deliverPending(to: router, activeServerID: activeProfile?.id) { accountTests?.state(for: $0) != nil }
    }

    /// 00 §7.5 “前台收到推送”: the alert list or the account list reads again, at most once per interval (S6D2b-08).
    func pushArrivedInForeground(_ tap: PushTap) async {
        switch pushCoordinator.foregroundRefresh(for: tap, activeServerID: activeProfile?.id) {
        case .alerts?: await liveOps?.refreshFiringAlerts(maxAge: 0)
        case .accounts?: accountListSignal.bump()
        case nil: break
        }
    }
}
