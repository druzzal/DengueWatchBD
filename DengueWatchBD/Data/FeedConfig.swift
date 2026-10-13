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

    /// How long to leave the cheap probe alone when the app returns to the
    /// front.
    ///
    /// This gates `summary.json` — about 350 bytes — and nothing else. The
    /// expensive download is already held back by its own two gates: the full
    /// document is fetched only when the probe reports a report date newer than
    /// the one on screen, and even then conditionally, against an ETag. So the
    /// cost of checking often is a few hundred bytes, and the cost of checking
    /// rarely is a reader looking at yesterday's figures.
    ///
    /// This was six hours, which defeated the point of having a cheap probe at
    /// all. DGHS publishes once a day but not at a fixed hour — over two weeks
    /// the report landed anywhere from 11:05 to 17:36 UTC — so a six-hour
    /// window reliably straddled publication. Measured on 7 October: the app
    /// checked at 11:47, the report landed at 12:06, and every launch for the
    /// rest of the window showed the previous day's numbers without asking.
    ///
    /// Fifteen minutes is short enough that a new report is on screen about as
    /// soon as it exists, and long enough that switching apps back and forth
    /// does not talk to the server each time.
    static let minimumProbeInterval: TimeInterval = 15 * 60

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
