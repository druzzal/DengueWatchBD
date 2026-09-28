import XCTest
@testable import DengueWatchBD

/// Which side of a threshold line matters.
///
/// Temperature counts when it climbs above the line; a platelet count counts
/// when it falls below one. The chart draws both the same way, so the only
/// thing keeping them apart is this — and getting it backwards would mark the
/// readings nobody is worried about while leaving the alarming ones plain.
final class TrendThresholdTests: XCTestCase {

    private typealias Threshold = HealthTrendChart.Threshold

    func testAFeverCrossesAThresholdByRising() {
        let fever = Threshold(value: 37.8, concern: .above)
        XCTAssertTrue(fever.isCrossed(by: 39.4))
        XCTAssertFalse(fever.isCrossed(by: 36.9))
    }

    func testAPlateletCountCrossesAThresholdByFalling() {
        let low = Threshold(value: 150, concern: .below)
        XCTAssertTrue(low.isCrossed(by: 88))
        XCTAssertFalse(low.isCrossed(by: 240))
    }

    /// A reading exactly on the line has not crossed it, in either direction.
    func testSittingOnTheLineIsNotCrossingIt() {
        XCTAssertFalse(Threshold(value: 37.8, concern: .above).isCrossed(by: 37.8))
        XCTAssertFalse(Threshold(value: 150, concern: .below).isCrossed(by: 150))
    }

    /// The mistake this exists to prevent: a platelet threshold read the way a
    /// fever one is would call 240 alarming and 88 fine.
    func testTheDirectionsAreNotInterchangeable() {
        let asFever = Threshold(value: 150, concern: .above)
        let asCount = Threshold(value: 150, concern: .below)
        XCTAssertNotEqual(asFever.isCrossed(by: 88), asCount.isCrossed(by: 88))
        XCTAssertNotEqual(asFever.isCrossed(by: 240), asCount.isCrossed(by: 240))
    }

    // MARK: - The line the chart actually draws

    /// The floor of the usual range, not its ceiling. Marking 450 would draw
    /// attention to a high count while a falling one passed unremarked.
    func testThePlateletThresholdIsTheFloorOfTheUsualRange() {
        XCTAssertEqual(LabMeasure.platelets.typicalRange.lowerBound, 150)
        XCTAssertTrue(Threshold(value: LabMeasure.platelets.typicalRange.lowerBound,
                                concern: .below).isCrossed(by: 88))
    }

    func testTheFeverThresholdIsTheCeilingOfTheUsualRange() {
        XCTAssertEqual(VitalKind.temperature.usualRange.upperBound, 37.8)
    }

    /// A count that has barely moved is not a trend. The assay's own
    /// run-to-run variation is 20, so anything smaller is noise.
    func testAPlateletTrendIgnoresMovementInsideTheAssaysNoise() {
        let noise = HealthTrend.direction(of: [186, 180, 178],
                                          minimumChange: LabMeasure.platelets.minimumMeaningfulChange)
        XCTAssertEqual(noise, .steady)

        let falling = HealthTrend.direction(of: [186, 124, 88],
                                            minimumChange: LabMeasure.platelets.minimumMeaningfulChange)
        XCTAssertEqual(falling, .falling)
    }

    /// Two counts are a line; one is a dot. A single reading is reported as
    /// having no direction rather than as a steady one — "steady" is a claim
    /// about a course, and one count is not a course.
    func testOneCountIsNotATrend() {
        XCTAssertEqual(HealthTrend.direction(of: [88],
                                             minimumChange: LabMeasure.platelets.minimumMeaningfulChange),
                       .notEnoughData)
    }
}
