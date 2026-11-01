import Foundation
import Sub2Core

// What PushCoordinator is given (00 §7, 60 §7.4): the system's permission and registration, the site's push endpoints and
// this phone's details. The App passes the real ones (NativeApp/PushAppDelegate.swift), UI tests the fixtures
// (NativeApp/Features/Settings/PushFixtures.swift).

/// The system's notification permission; provisional and ephemeral count as authorized.
enum PushAuthorization: Sendable, Equatable { case notDetermined, denied, authorized }

protocol NotificationAuthorizing: Sendable {
    func authorizationStatus() async -> PushAuthorization
    /// `[.alert, .sound, .badge]`, asked only when the switch is turned on (00 §7.1).
    func requestAuthorization() async throws -> Bool
}

/// `registerForRemoteNotifications()`. The token or the failure comes back through `didReceiveDeviceToken` /
/// `didFailToRegister`: the system's through PushAppDelegate, a fixture's directly.
@MainActor
protocol RemoteNotificationRegistering {
    func registerForRemoteNotifications(reportingTo coordinator: PushCoordinator)
}

/// The two push requests of this phone's device; `APIClient` is the real one.
protocol PushDeviceAPI: Sendable {
    func registerPushDevice(_ registration: PushDeviceRegistration) async throws -> (device: PushDevice, created: Bool)
    func deletePushDevice(id: Int) async throws
}
extension APIClient: PushDeviceAPI {}

/// The registration's details of this phone (00 §7.2).
struct PushDeviceInfo: Sendable {
    let bundleID: String?
    let deviceName: @MainActor @Sendable () -> String
    let timeZone: @Sendable () -> String
    /// Only a build with the development `aps-environment` (APNS_SANDBOX) sends `environment: sandbox`.
    let sandbox: Bool
}

/// The connected site, as AppModel publishes it.
struct PushSite: Sendable {
    let serverID: UUID
    let generation: UUID
    /// `push.notifications` outside a workspace (SettingsPresentation.showsNotifications); otherwise nothing is registered and
    /// only the pending deletions are retried.
    let supportsPush: Bool
    let api: any PushDeviceAPI
    /// Returns once the teardowns of the same address have ended (BACKLOG “推送登记要等待该站点的收尾结束”).
    let waitForTeardowns: @MainActor @Sendable () async -> Void
}

enum PushEnableOutcome: Sendable, Equatable {
    case enabled(deviceID: Int)
    /// `config.ready == false`: nothing was asked or sent (00 §7.1).
    case notReady
    /// The switch goes back off; `authorization == .denied` shows “去设置”.
    case permissionDenied
    case failed(String)
    /// No site, a site without push, a change already running or a session that ended.
    case cancelled
}

enum PushDisableOutcome: Sendable, Equatable {
    case disabled
    case failed(String)
    case cancelled
}

/// A tapped notification's page, kept until that site's tabs take it (00 §7.5).
struct PushPendingTarget: Sendable, Equatable {
    /// New for every tap, so tapping the same notification twice is seen twice.
    let id: UUID
    let serverID: UUID
    let target: PushTarget
    init(serverID: UUID, target: PushTarget) { id = UUID(); self.serverID = serverID; self.target = target }
}

enum PushSiteOpening: Sendable, Equatable { case connected, loginPage, failed }

/// AppModel for a tap of another site: switching first (00 §1.1, §7.5).
@MainActor
protocol PushSiteNavigating: AnyObject {
    var activeServerID: UUID? { get }
    var profiles: [ServerProfile] { get }
    /// Connected, its login page (credential cleared or session refused), or failed.
    func openSite(_ profile: ServerProfile) async -> PushSiteOpening
}
