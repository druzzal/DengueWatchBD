import XCTest
@testable import DengueWatchBD

/// Colour on a health reading is read as a verdict whether or not one is
/// intended, so the boundaries deserve pinning.
final class MeasureStatusTests: XCTestCase {

    // MARK: - Lab measures

    func testAValueInsideTheTypicalRangeIsNormal() {
        XCTAssertEqual(LabMeasure.platelets.status(250), .normal)
        XCTAssertEqual(LabMeasure.haemoglobin.status(14.1), .normal)
        XCTAssertEqual(LabMeasure.haematocrit.status(47.5), .normal)
    }

    func testAValueJustOutsideIsOutsideNotAlarming() {
        // 140 is below 150 but not the platelet count that matters in dengue.
        XCTAssertEqual(LabMeasure.platelets.status(140), .outside)
        XCTAssertEqual(LabMeasure.haemoglobin.status(11.5), .outside)
    }

    func testTheDenguePlateletCountReadsAsFarOutside() {
        // 96 is the number a clinician acts on, and it should not look the
        // same as 140.
        XCTAssertEqual(LabMeasure.platelets.status(96), .farOutside)
        XCTAssertEqual(LabMeasure.platelets.status(45), .farOutside)
    }

    func testBoundariesAreInclusiveAtTheUsualRange() {
        XCTAssertEqual(LabMeasure.platelets.status(150), .normal)
        XCTAssertEqual(LabMeasure.platelets.status(450), .normal)
        XCTAssertEqual(LabMeasure.platelets.status(149.9), .outside)
    }

    // MARK: - Vitals

    func testNormalVitalsAreNormal() {
        XCTAssertEqual(VitalKind.temperature.status(36.8), .normal)
        XCTAssertEqual(VitalKind.pulse.status(72), .normal)
        XCTAssertEqual(VitalKind.oxygenSaturation.status(98), .normal)
    }

    func testAFeverGradesUpWithItsHeight() {
        // A raised temperature and a dangerous one must not look alike.
        XCTAssertEqual(VitalKind.temperature.status(38.2), .outside)
        XCTAssertEqual(VitalKind.temperature.status(39.6), .farOutside)
    }

    func testLowOxygenIsNeverMerelySlightlyLow() {
        XCTAssertEqual(VitalKind.oxygenSaturation.status(94), .outside)
        XCTAssertEqual(VitalKind.oxygenSaturation.status(90), .farOutside)
    }

    // MARK: - Presentation

    func testTheThreeStepsMapToDistinctColours() {
        // Green, then orange, then red, using the palette already checked for
        // colour-vision separation.
        XCTAssertEqual(MeasureStatus.normal.risk, .low)
        XCTAssertEqual(MeasureStatus.outside.risk, .high)
        XCTAssertEqual(MeasureStatus.farOutside.risk, .severe)
        XCTAssertEqual(Set([MeasureStatus.normal.risk,
                            MeasureStatus.outside.risk,
                            MeasureStatus.farOutside.risk]).count, 3)
    }

    func testEachStepHasItsOwnIconSoColourIsNotTheOnlySignal() {
        let symbols = Set([MeasureStatus.normal.symbol,
                           MeasureStatus.outside.symbol,
                           MeasureStatus.farOutside.symbol])
        XCTAssertEqual(symbols.count, 3)
    }

    func testEachStepIsNamedInBothLanguages() {
        for status: MeasureStatus in [.normal, .outside, .farOutside] {
            let key = "status.\(status.rawValue)"
            XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
            XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
        }
    }

    func testTheMarkedlyAbnormalRangeAlwaysContainsTheUsualOne() {
        // Otherwise a value could be "normal" and "far outside" at once.
        for measure in LabMeasure.allCases {
            XCTAssertLessThanOrEqual(measure.markedlyAbnormalRange.lowerBound,
                                     measure.typicalRange.lowerBound, measure.rawValue)
            XCTAssertGreaterThanOrEqual(measure.markedlyAbnormalRange.upperBound,
                                        measure.typicalRange.upperBound, measure.rawValue)
        }
        for kind in VitalKind.allCases {
            XCTAssertLessThanOrEqual(kind.markedlyAbnormalRange.lowerBound,
                                     kind.usualRange.lowerBound, kind.rawValue)
            XCTAssertGreaterThanOrEqual(kind.markedlyAbnormalRange.upperBound,
                                        kind.usualRange.upperBound, kind.rawValue)
        }
    }
}
