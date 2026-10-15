import UIKit

/// Presents the system share sheet for a file that already exists.
///
/// `ShareLink` with a lazily exported `Transferable` opened the sheet before
/// the PDF did: no thumbnail, no file name, and Files, WhatsApp and Mail each
/// waited on the page layout after the reader had already chosen them — the
/// share felt stuck. Handing the sheet a finished file gives every target the
/// same thing at once, with the preview the reader expects.
@MainActor
enum ShareSheet {
    static func present(_ url: URL) {
        guard let top = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // An iPad shows the sheet as a popover, which needs an anchor; the
        // export button sits at the top trailing corner.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.maxX - 40, y: top.view.safeAreaInsets.top + 22,
                                        width: 1, height: 1)
            popover.permittedArrowDirections = .up
        }
        top.present(controller, animated: true)
    }

    /// The screen currently on top — the log is itself a sheet, so the share
    /// sheet has to be presented from it rather than from the root.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
