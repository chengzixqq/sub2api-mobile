import Foundation
import Sub2Core

// 00 §7.5: what a tapped notification opens, read from its payload; pure, so the routing is tested without the system.

/// The four pages of 00 §7.5's table.
enum PushTarget: Sendable, Hashable {
    case alert(id: Int)
    case account(id: Int)
    case accountTest(accountID: Int, runID: String?)
    case pushSettings
}

struct PushTap: Sendable, Equatable {
    let type: String?
    let siteTag: String?
    /// nil for an unknown type or a missing id: the App only opens.
    let target: PushTarget?
    /// The site this App registered with (`ServerProfile.id`); nil for a device another client registered by host name.
    var serverID: UUID? { siteTag.flatMap(UUID.init(uuidString:)) }
}

enum PushSiteDecision: Sendable, Equatable {
    case openOnly
    case current(serverID: UUID, target: PushTarget)
    case otherSite(ServerProfile, target: PushTarget)
}

/// The overview tab's new stack and the sheet over it.
struct PushNavigation: Sendable, Equatable {
    let path: [AppRoute]
    let sheet: AppSheet?
}

/// 00 §7.5 “前台收到推送…立即刷新”, merged per kind (S6D2b-08): one alert refresh per 5 seconds, one account list read per 30.
enum PushForegroundRefresh: Sendable, Hashable {
    case alerts, accounts
    var interval: TimeInterval { self == .alerts ? 5 : 30 }
}

enum PushDeepLink {
    static let pushTestType = "push.test"

    /// `type` and `site` are trimmed text; ids are positive whole numbers, as Swift `Int` or `NSNumber` (a JSON true is not).
    static func parse(_ userInfo: [AnyHashable: Any]) -> PushTap {
        let type = text(userInfo["type"])
        return PushTap(type: type, siteTag: text(userInfo["site"]), target: type.flatMap { target(of: $0, in: userInfo) })
    }

    /// The current site goes straight on; another saved site is switched to first; anything else only opens the App.
    static func decision(for tap: PushTap, activeServerID: UUID?, profiles: [ServerProfile]) -> PushSiteDecision {
        guard let target = tap.target, let serverID = tap.serverID, let profile = profiles.first(where: { $0.id == serverID }) else { return .openOnly }
        return serverID == activeServerID ? .current(serverID: serverID, target: target) : .otherSite(profile, target: target)
    }

    /// 10 §0.7-4 on the overview tab. A finished test shows its result only when this session ran it: the test sheet would
    /// otherwise start a new one (S6-23, no run_id result page yet). 设置 → 推送通知 stays on the overview too, where
    /// the search tab's field would bring up the keyboard.
    static func navigation(for target: PushTarget, showsTestResult: Bool) -> PushNavigation {
        switch target {
        case .alert(let id): PushNavigation(path: [.alert(id: id)], sheet: nil)
        case .account(let id): PushNavigation(path: [.account(id: id)], sheet: nil)
        case .accountTest(let id, _): PushNavigation(path: [.account(id: id)], sheet: showsTestResult ? .accountTest(id: id) : nil)
        case .pushSettings: PushNavigation(path: [.settings(focus: .interface), .push], sheet: nil)
        }
    }

    /// Only a push of the connected site refreshes its alert or account list.
    static func foregroundRefresh(for tap: PushTap, activeServerID: UUID?) -> PushForegroundRefresh? {
        guard let serverID = tap.serverID, serverID == activeServerID else { return nil }
        switch tap.type ?? "" {
        case PushEvent.opsAlertFired.rawValue, PushEvent.opsAlertResolved.rawValue: return .alerts
        case PushEvent.accountError.rawValue, PushEvent.accountTestFinished.rawValue: return .accounts
        default: return nil
        }
    }

    private static func target(of type: String, in userInfo: [AnyHashable: Any]) -> PushTarget? {
        switch type {
        case PushEvent.opsAlertFired.rawValue, PushEvent.opsAlertResolved.rawValue: positiveID(userInfo["alert_event_id"]).map { .alert(id: $0) }
        case PushEvent.accountError.rawValue: positiveID(userInfo["account_id"]).map { .account(id: $0) }
        case PushEvent.accountTestFinished.rawValue:
            positiveID(userInfo["account_id"]).map { .accountTest(accountID: $0, runID: text(userInfo["run_id"])) }
        case pushTestType: .pushSettings
        default: nil
        }
    }
    private static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    private static func positiveID(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let id = number.intValue
        guard id > 0, Double(id) == number.doubleValue else { return nil }
        return id
    }
}

extension AppRouter {
    /// 10 §0.7-4: the overview tab back at its root, then the target's stack, then its sheet. Called only without a sheet
    /// shown (S6D2b-07), so `select` closes nothing the administrator is in.
    func open(_ navigation: PushNavigation) {
        select(.today)
        setPath(navigation.path, for: .today)
        if let sheet = navigation.sheet { present(sheet) }
    }
}

extension PushCoordinator {
    /// The tabs of `activeServerID` take the pending target once; while a sheet is shown it waits for the sheet to close
    /// (S6D2b-07), so a write in progress is never dismissed. `showsTestResult` is asked for the account of a finished test.
    @discardableResult
    func deliverPending(to router: AppRouter, activeServerID: UUID?, showsTestResult: (Int) -> Bool) -> Bool {
        guard router.presentedSheet == nil, let activeServerID, let target = takeTarget(for: activeServerID) else { return false }
        let testedAccount: Int? = if case .accountTest(let id, _) = target { id } else { nil }
        router.open(PushDeepLink.navigation(for: target, showsTestResult: testedAccount.map(showsTestResult) ?? false))
        return true
    }
}

/// What reaches PushAppDelegate before the model is attached: the latest token, one registration failure and the latest
/// tap, handed over once in that order (S6D2b-09). Afterwards everything passes straight through.
struct PushInbox: Sendable {
    enum Delivery: Sendable, Equatable { case token(Data), registrationFailed, tap(PushTap) }
    private(set) var isAttached = false
    private var token: Data?
    private var failed = false
    private var tap: PushTap?

    mutating func receive(_ delivery: Delivery) -> [Delivery] {
        guard !isAttached else { return [delivery] }
        switch delivery {
        case .token(let data): token = data
        case .registrationFailed: failed = true
        case .tap(let value): tap = value
        }
        return []
    }
    mutating func attach() -> [Delivery] {
        guard !isAttached else { return [] }
        isAttached = true
        let held: [Delivery?] = [token.map(Delivery.token), failed ? .registrationFailed : nil, tap.map(Delivery.tap)]
        token = nil; failed = false; tap = nil
        return held.compactMap { $0 }
    }
}
