import SwiftUI
import UIKit

/// Bridges a prepared share image to the system `UIActivityViewController`.
///
/// The presenter is a real `UIViewController` embedded in the birthday screen's
/// own hierarchy (attached via a zero-footprint `background`), so the share sheet
/// is presented from a controller that lives *above* the full-screen birthday
/// cover — no global/top-controller search, and a valid iPad popover anchored to
/// the presenter's view. Setting `image` presents; the controller clears it on
/// completion so a cancel or a completed share both reset cleanly and the sheet
/// can be reopened.
struct ActivityShareSheet: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> ActivityHostController {
        ActivityHostController()
    }

    func updateUIViewController(_ host: ActivityHostController, context: Context) {
        host.present(image: image) {
            // Clear on the next loop so we don't mutate state during this update.
            DispatchQueue.main.async { image = nil }
        }
    }

    static func dismantleUIViewController(_ host: ActivityHostController, coordinator: Void) {
        // The representable is going away (birthday screen torn down): invalidate
        // any queued presentation so a late runloop hop can't present an orphaned
        // sheet or fire a completion against a dead view.
        host.invalidatePending()
    }
}

/// A lightweight host that owns the activity presentation. It refuses to present
/// a second sheet while one is up (guarding against duplicate share requests) and
/// only presents once attached to a window.
final class ActivityHostController: UIViewController {
    private var isPresentingShare = false
    /// Monotonic token identifying the latest queued request, so a deferred hop
    /// can tell whether it is still the current one.
    private var requestToken = 0

    func present(image: UIImage?, onComplete: @escaping () -> Void) {
        guard let image, !isPresentingShare, presentedViewController == nil else { return }
        isPresentingShare = true
        requestToken &+= 1
        let token = requestToken

        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            // Anchor the iPad popover to the centre of the presenter's view.
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.isPresentingShare = false
            onComplete()
        }

        // Present on the next runloop so we never present during a SwiftUI view
        // update, and only while actually in a window.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Abort if this request was superseded/invalidated, or the host can no
            // longer present. Crucially we still reset state AND clear the pending
            // image via onComplete, so sharing is re-enabled instead of being left
            // stuck disabled with a non-nil shareImage.
            guard self.requestToken == token,
                  self.view.window != nil,
                  self.presentedViewController == nil else {
                self.isPresentingShare = false
                onComplete()
                return
            }
            self.present(activity, animated: true)
        }
    }

    /// Cancels any queued-but-not-yet-presented request so its deferred hop no-ops.
    func invalidatePending() {
        requestToken &+= 1
        isPresentingShare = false
    }
}
