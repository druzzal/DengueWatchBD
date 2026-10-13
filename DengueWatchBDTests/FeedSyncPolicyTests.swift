import XCTest
@testable import DengueWatchBD

/// When the app decides to ask DGHS whether there is a newer report.
///
/// This policy once skipped the check for six hours after any successful sync.
/// The check costs about 350 bytes — `summary.json` — and the expensive
/// download has its own gate behind it, so six hours bought almost nothing and
/// cost a reader the thing the app is for.
///
/// Measured on 7 October 2026: the app checked at 11:47 UTC, the DGHS report
/// landed at 12:06, and every launch for the rest of the window showed the
/// previous day's figures without asking. Over the preceding fortnight the
/// report landed anywhere between 11:05 and 17:36 UTC, so a six-hour window did
/// not merely risk straddling publication — it was wider than the spread.
@MainActor
final class FeedSyncPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    private func probes(after seconds: TimeInterval,
                        force: Bool = false,
                        hasCachedPayload: Bool = true) -> Bool {
        FeedSync.shouldProbe(force: force,
                             lastSuccess: now.addingTimeInterval(-seconds),
                             hasCachedPayload: hasCachedPayload,
                             now: now)
    }

    // MARK: - The floor

    func testTheProbeIsSkippedImmediatelyAfterASuccessfulCheck() {
        XCTAssertFalse(probes(after: 0))
        XCTAssertFalse(probes(after: 60))
    }

    func testTheProbeRunsOnceTheFloorHasPassed() {
        XCTAssertTrue(probes(after: FeedConfig.minimumProbeInterval))
        XCTAssertTrue(probes(after: FeedConfig.minimumProbeInterval + 1))
    }

    /// The regression this exists for: an app opened during the hours DGHS
    /// publishes must ask, not assume.
    func testAnAppOpenedAnHourLaterAsksAgain() {
        XCTAssertTrue(probes(after: 60 * 60),
                      "an hour after the last check the report may well have moved")
    }

    /// The floor has to be shorter than the spread of DGHS publication times,
    /// or it can sit across the moment the report lands — which is exactly what
    /// six hours did.
    func testTheFloorIsShorterThanTheSpreadOfPublicationTimes() {
        let observedSpread: TimeInterval = 6.5 * 60 * 60   // 11:05 to 17:36 UTC
        XCTAssertLessThan(FeedConfig.minimumProbeInterval, observedSpread / 4,
                          "a floor near the publication spread reintroduces the blind window")
    }

    /// Short, but not so short that switching apps back and forth talks to the
    /// server every time.
    func testTheFloorIsLongEnoughToSurviveAppSwitching() {
        XCTAssertGreaterThanOrEqual(FeedConfig.minimumProbeInterval, 5 * 60)
    }

    // MARK: - What the floor must never block

    func testPullToRefreshIsNeverThrottled() {
        XCTAssertTrue(probes(after: 0, force: true))
    }

    /// Elapsed time alone would skip the check even when the cache had gone
    /// missing, leaving the app serving the bundled seed with a working
    /// connection.
    func testACheckAlwaysRunsWhenThereIsNoCachedPayloadToFallBackOn() {
        XCTAssertTrue(probes(after: 0, hasCachedPayload: false))
    }

    func testTheFirstEverLaunchChecks() {
        XCTAssertTrue(FeedSync.shouldProbe(force: false,
                                           lastSuccess: nil,
                                           hasCachedPayload: true,
                                           now: now))
    }

    /// A clock that has gone backwards — a timezone change, a manual set —
    /// leaves a "last success" in the future. That must not lock the app out of
    /// checking until the clock catches up.
    func testAFutureTimestampDoesNotLockOutTheCheck() {
        let stuck = FeedSync.shouldProbe(force: false,
                                         lastSuccess: now.addingTimeInterval(60 * 60 * 24),
                                         hasCachedPayload: true,
                                         now: now)
        XCTAssertTrue(stuck, "a clock moved backwards must not stop the app checking")
    }
}
