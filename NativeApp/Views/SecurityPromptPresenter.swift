import SafariServices
import SwiftUI
import UIKit

/// Shows the global security sheet from a window of its own above the App (00 §2.7.1): while a page sheet such as the user
/// editor or the balance form is open, the root view cannot present a second one. The page and its confirmation stay
/// underneath. The window is made in any connected scene, so a prompt raised in the background shows on return.
@MainActor final class SecurityPromptPresenter {
    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?
    private var hosted: UIViewController?
    private var shownID: UUID?

    func sync(_ prompt: SecurityPromptCenter.Prompt?, model: AppModel) {
        guard prompt?.id != shownID else { return }
        shownID = prompt?.id
        let leaving = hosted
        hosted = nil
        let next = { [weak self] in
            guard let self, self.shownID == prompt?.id else { return }
            if let prompt { self.present(prompt, model: model) } else { self.hide() }
        }
        if let leaving, leaving.presentingViewController != nil { leaving.dismiss(animated: true, completion: next) } else { next() }
    }

    private func present(_ prompt: SecurityPromptCenter.Prompt, model: AppModel) {
        guard let window = overlayWindow(), let root = window.rootViewController else { shownID = nil; return }
        // The overlay is a window of its own, so the App's appearance setting (60 §3.4) is applied here too.
        window.overrideUserInterfaceStyle = model.preferences.appearance.userInterfaceStyle
        let sheet = prompt.kind == .compliance ? AnyView(ComplianceSheet(prompt: prompt)) : AnyView(StepUpSheet(prompt: prompt))
        let controller = UIHostingController(rootView: sheet.environment(model))
        // Only the sheet's own buttons answer the prompt.
        controller.isModalInPresentation = true
        if prompt.kind == .compliance {
            controller.modalPresentationStyle = .fullScreen
        } else if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        window.isHidden = false
        window.makeKeyAndVisible()
        root.present(controller, animated: true)
        hosted = controller
    }
    private func overlayWindow() -> UIWindow? {
        if let window, window.windowScene != nil { return window }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return nil }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        previousKeyWindow = scene.keyWindow
        self.window = window
        return window
    }
    private func hide() {
        window?.isHidden = true
        window = nil
        previousKeyWindow?.makeKey()
    }
}

private extension AppPreferences.Appearance {
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The compliance document (00 §1.10); callers pass only https URLs (`AdminComplianceStatus.documentURL(site:)`).
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
