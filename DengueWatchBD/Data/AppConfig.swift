import Foundation

enum AppConfig {
    /// Where daily surveillance data is fetched from.
    ///
    /// Served straight from the repository the daily job commits to. No API
    /// server, no database and no credential: the workflow writes
    /// `public/surveillance.json`, GitHub serves it, and the app fetches it
    /// with a conditional GET so an unchanged file costs a 304 rather than a
    /// download.
    ///
    /// Requires the repository to be public — raw.githubusercontent.com will
    /// not serve a private repo without a token, and shipping a token inside
    /// the app is exactly what we are avoiding.
    static let surveillanceEndpoint = URL(
        string: "https://raw.githubusercontent.com/druzzal/DengueWatchBD/main/public/surveillance.json"
    )

    /// Pipeline health, published beside the dataset.
    static let statusEndpoint = URL(
        string: "https://raw.githubusercontent.com/druzzal/DengueWatchBD/main/public/status.json"
    )

    /// Don't re-fetch more often than this when the app comes back to the front.
    static let minimumSyncInterval: TimeInterval = 6 * 60 * 60

    /// Treat data older than this as stale enough to warn about.
    static let stalenessThreshold: TimeInterval = 48 * 60 * 60
}
