import XCTest
@testable import DengueWatchBD

/// A direction is a fact about numbers. These tests pin that it is only ever
/// that, and that it is not claimed when the data cannot support one.
final class HealthTrendTests: XCTestCase {

    func testASingleReadingHasNoDirection() {
        XCTAssertEqual(HealthTrend.direction(of: [38.5], minimumChange: 0.3), .notEnoughData)
        XCTAssertEqual(HealthTrend.direction(of: [], minimumChange: 0.3), .notEnoughData)
    }

    func testFallingPlateletsReadAsFalling() {
        // The pattern that matters most in dengue, described and not explained.
        XCTAssertEqual(HealthTrend.direction(of: [220, 168, 96], minimumChange: 20), .falling)
    }

    func testRisingTemperatureReadsAsRising() {
        XCTAssertEqual(HealthTrend.direction(of: [37.2, 38.1, 38.9], minimumChange: 0.3), .rising)
    }

    func testScatterBelowTheThresholdReadsAsSteady() {
        // Thermometers disagree with themselves by a tenth or two; calling that
        // a rising fever would alarm someone over nothing.
        XCTAssertEqual(HealthTrend.direction(of: [37.0, 37.1, 37.2], minimumChange: 0.3), .steady)
        XCTAssertEqual(HealthTrend.direction(of: [200, 210, 195], minimumChange: 20), .steady)
    }

    func testTheThresholdIsExclusiveSoJustOverItCounts() {
        XCTAssertEqual(HealthTrend.direction(of: [37.0, 37.31], minimumChange: 0.3), .rising)
        XCTAssertEqual(HealthTrend.direction(of: [37.0, 37.29], minimumChange: 0.3), .steady)
    }

    func testDirectionIsFirstToLastNotHighestToLowest() {
        // A fever that spiked and came back down has not risen overall, and
        // saying it had would misdescribe the illness.
        XCTAssertEqual(HealthTrend.direction(of: [37.0, 40.0, 37.0], minimumChange: 0.3), .steady)
    }

    func testThresholdsAreInEachMeasuresOwnUnits() {
        // A single fraction cannot serve both: 5% of a temperature is a third
        // of a degree, 5% of a platelet count is noise.
        XCTAssertEqual(VitalKind.temperature.minimumMeaningfulChange, 0.3)
        XCTAssertEqual(LabMeasure.platelets.minimumMeaningfulChange, 20)
        XCTAssertGreaterThan(LabMeasure.platelets.minimumMeaningfulChange,
                             VitalKind.temperature.minimumMeaningfulChange)
    }

    func testEveryDirectionIsNamedInBothLanguages() {
        for trend: HealthTrend in [.rising, .falling, .steady, .notEnoughData] {
            XCTAssertNotNil(Strings.english[trend.labelKey], "missing EN: \(trend.labelKey)")
            XCTAssertNotNil(Strings.bangla[trend.labelKey], "missing BN: \(trend.labelKey)")
        }
        for key in ["trend.chart.temperature", "trend.chart.platelets",
                    "trend.readings", "trend.note"] {
            XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
            XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
        }
    }

    func testTheTrendNoteRefusesToInterpret() {
        // The sentence that keeps this a chart rather than a diagnosis.
        let note = (Strings.english["trend.note"] ?? "").lowercased()
        XCTAssertTrue(note.contains("does not say what that means"), note)
        XCTAssertTrue(note.contains("doctor"), note)
    }
}
