import Foundation

/// Where the app gets its figures, and when it decides they are too old to show
/// without comment.
enum FeedConfig {
    /// The small document: headline figures and the DGHS report date. Polled to
    /// decide whether the large one is worth downloading.
    static let summaryEndpoint = URL(
        string: "https://druzzal.github.io/dengue-bd-dashboard/data/summary.json"
    )

    /// The full dataset: every chart series and table.
    static let latestEndpoint = URL(
        string: "https://druzzal.github.io/dengue-bd-dashboard/data/latest.json"
    )

    /// The DGHS page the feed is scraped from. Shown in About so a reader can
    /// check the figures at the source. The app never fetches this itself.
    static let sourceURL = "https://dashboard.dghs.gov.bd/pages/heoc_dengue_v1.php"

    /// The feed's own dashboard, for anyone who wants to see the pipeline.
    static let feedHomeURL = "https://druzzal.github.io/dengue-bd-dashboard/"

    /// Don't re-poll more often than this when the app returns to the front.
    /// DGHS publishes once a day, so six hours is already generous.
    static let minimumSyncInterval: TimeInterval = 6 * 60 * 60

    /// Past this age the app says the figures are behind rather than presenting
    /// them as current. DGHS publishes daily, so three quiet days means
    /// something is wrong upstream, not that nothing happened.
    static let stalenessThreshold: TimeInterval = 3 * 24 * 60 * 60

    /// Beyond this the figures stop being "a bit behind" and become a poor basis
    /// for a decision, so the app says so more firmly.
    static let outdatedThreshold: TimeInterval = 7 * 24 * 60 * 60

    /// Schema versions this build knows how to read. A feed that moves past
    /// this is refused rather than half-decoded into wrong numbers.
    static let supportedSchemaVersions: ClosedRange<Int> = 1...1
}
