import Foundation

enum AppConfig {
    /// Where daily surveillance data is fetched from.
    ///
    /// Still `nil`, because this needs a host rather than more code. DGHS
    /// publishes its daily dengue figures only as PDF press releases, so
    /// `server/` in this repository parses them into the `SurveillancePayload`
    /// shape and writes `surveillance.json`. Publish that file anywhere the app
    /// can GET it, set this to its URL, and automatic updates start working —
    /// conditional GET, on-disk caching and refresh-on-reconnect are already
    /// built around it.
    ///
    ///     static let surveillanceEndpoint = URL(string: "https://your-host/surveillance.json")
    ///
    /// A URL that quietly 404s would be worse than an honest gap, so this stays
    /// nil until a real one exists.
    static let surveillanceEndpoint: URL? = nil

    /// Don't re-fetch more often than this when the app comes back to the front.
    static let minimumSyncInterval: TimeInterval = 6 * 60 * 60

    /// Treat data older than this as stale enough to warn about.
    static let stalenessThreshold: TimeInterval = 48 * 60 * 60
}
