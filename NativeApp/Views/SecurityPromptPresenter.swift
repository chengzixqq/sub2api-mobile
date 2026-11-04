import SafariServices
import SwiftUI
import UIKit

/// Shows the global security sheet from a window of its own above the App (00 §2.7.1): while a page sheet such as the user
/// editor or the balance form is open, the root view cannot present a second one. The page and its confirmation stay
/// underneath. The window is made in any connected scene, so a prompt raised in the background shows on return. Sheets come
/// and go one transition at a time (SecurityPromptOverlay).
@MainActor final class SecurityPromptPresenter {
    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?
    private var hosted: UIViewController?
    private var overlay = SecurityPromptOverlay()
    private var prompt: SecurityPromptCenter.Prompt?
    private var model: AppModel?

    func sync(_ prompt: SecurityPromptCenter.Prompt?, model: AppModel) {
        self.prompt = prompt; self.model = model
        perform(overlay.want(prompt?.id))
    }

    private func perform(_ step: SecurityPromptOverlay.Step) {
        switch step {
        case .wait: return
        case .hide: hide()
        case .present:
            guard let prompt, let model else { overlay.presentFailed(); return }
            present(prompt, model: model)
        case .dismiss:
            let leaving = hosted
            hosted = nil
            guard let leaving, leaving.presentingViewController != nil else { perform(overlay.transitionEnded()); return }
            leaving.dismiss(animated: true) { [weak self] in self?.transitionEnded() }
        }
    }
    private func transitionEnded() { perform(overlay.transitionEnded()) }

    private func present(_ prompt: SecurityPromptCenter.Prompt, model: AppModel) {
        guard let window = overlayWindow(), let root = window.rootViewController else { overlay.presentFailed(); return }
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
        hosted = controller
        root.present(controller, animated: true) { [weak self] in self?.transitionEnded() }
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
