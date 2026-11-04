import SwiftUI
import UIKit

/// A blocked downward swipe on a sheet (20 §3.4, 50 §3.4, 60 §14.4, §17.4): with interactiveDismissDisabled the sheet stays and
/// UIKit tells the presentation's delegate about the attempt. The proxy stands in for SwiftUI's delegate, forwards everything to
/// it and reports the attempt first. Used with interactiveDismissDisabled; should it not get installed, only 取消 asks
/// (S6D1-16, S6D2a-05).
struct DismissAttemptBridge: UIViewControllerRepresentable {
    let onAttempt: @MainActor () -> Void

    func makeCoordinator() -> DismissAttemptProxy { DismissAttemptProxy(onAttempt: onAttempt) }
    func makeUIViewController(context: Context) -> Probe { Probe(proxy: context.coordinator) }
    /// Again after SwiftUI has finished this update, which may set its own delegate back.
    func updateUIViewController(_ probe: Probe, context: Context) {
        context.coordinator.onAttempt = onAttempt
        probe.install()
        Task { @MainActor in probe.install() }
    }

    final class Probe: UIViewController {
        private let proxy: DismissAttemptProxy
        init(proxy: DismissAttemptProxy) {
            self.proxy = proxy
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { nil }
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }
        /// Onto the presented controller at the top of this one's parents, once.
        func install() {
            var root: UIViewController = self
            while let parent = root.parent { root = parent }
            guard root.presentingViewController != nil, let presentation = root.presentationController, presentation.delegate !== proxy else { return }
            proxy.original = presentation.delegate
            presentation.delegate = proxy
        }
    }

    final class DismissAttemptProxy: NSObject, UIAdaptivePresentationControllerDelegate {
        var onAttempt: @MainActor () -> Void
        nonisolated(unsafe) weak var original: (any UIAdaptivePresentationControllerDelegate)?

        init(onAttempt: @escaping @MainActor () -> Void) { self.onAttempt = onAttempt }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            original?.presentationControllerShouldDismiss?(presentationController) ?? true
        }
        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            original?.presentationControllerWillDismiss?(presentationController)
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            original?.presentationControllerDidDismiss?(presentationController)
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onAttempt()
            original?.presentationControllerDidAttemptToDismiss?(presentationController)
        }
        /// Everything else (adaptive styles) goes to SwiftUI's delegate as if it were still the delegate.
        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }
        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }
}

extension View {
    /// A downward swipe that interactiveDismissDisabled blocked runs `action`, the sheet's 取消 path.
    func onDismissAttempt(_ action: @escaping @MainActor () -> Void) -> some View {
        background(DismissAttemptBridge(onAttempt: action))
    }
}
