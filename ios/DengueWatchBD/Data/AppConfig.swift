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

    /// Don't re-fetch more often than this when the app comes back to the front.
    /// The DGHS page the published dataset is compiled from. Shown in About so
    /// a reader can verify the figures at the source. The app never fetches
    /// this — only the ingestion pipeline does.
    static let sourceURL = "https://dashboard.dghs.gov.bd/pages/heoc_dengue_v1.php"

    static let minimumSyncInterval: TimeInterval = 6 * 60 * 60

    /// Past this age the dashboard says so explicitly rather than presenting
    /// old figures as current. DGHS publishes daily, so three days without a
    /// newer report means something is wrong upstream or in the pipeline —
    /// not simply a quiet day.
    static let stalenessThreshold: TimeInterval = 3 * 24 * 60 * 60

    /// Beyond this the figures stop being "a bit behind" and become a poor
    /// basis for a decision, so the app says so more firmly. Matches the
    /// OUTDATED_AFTER_DAYS the ingestion pipeline uses when it publishes
    /// status.json, so app and server never disagree about the same dataset.
    static let outdatedThreshold: TimeInterval = 7 * 24 * 60 * 60
}
