import SwiftUI

/// Builds the CoreLocation stack the moment the process starts.
///
/// This exists for one case: iOS relaunching the app in the background because
/// the device crossed into a monitored area. Nothing in SwiftUI is guaranteed to
/// have run by then — no view, no `.task` — so if the location manager were
/// still owned by a view, the entry event would arrive with no delegate
/// listening and the alert would never fire. Touching the shared instance here
/// registers the delegate during `didFinishLaunching`, which is early enough.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = LocationManager.shared
        return true
    }
}

@main
struct DengueWatchBDApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
