import XCTest
@testable import DengueWatchBD

/// Lab values are the place where recording is most easily mistaken for
/// diagnosing. These tests pin what the model is allowed to do.
final class LabReportTests: XCTestCase {

    func testAReportKnowsWhichValuesAreOutsideTheTypicalRange() {
        var report = LabReport()
        report.platelets = 96          // below 150
        report.haematocrit = 47.5      // inside 36–54
        report.whiteCells = 3.2        // below 4
        report.haemoglobin = 14.1      // inside 12–17
        XCTAssertEqual(Set(report.valuesOutsideTypicalRange), [.platelets, .whiteCells])
    }

    func testAnAbsentValueIsNotTreatedAsOutOfRange() {
        // A report that did not measure something says nothing about it.
        XCTAssertTrue(LabReport().valuesOutsideTypicalRange.isEmpty)
    }

    func testAlarmingValuesAreStillEnterable() {
        // A platelet count of 15 is an emergency and exactly the number worth
        // recording. The guard exists for typing slips, not for bad news.
        XCTAssertTrue(LabMeasure.platelets.enterableRange.contains(15))
        XCTAssertTrue(LabMeasure.haematocrit.enterableRange.contains(65))
        XCTAssertTrue(LabMeasure.whiteCells.enterableRange.contains(0.5))
    }

    func testImpossibleValuesAreNot() {
        XCTAssertFalse(LabMeasure.platelets.enterableRange.contains(50_000))
        XCTAssertFalse(LabMeasure.haematocrit.enterableRange.contains(150))
    }

    func testAnEmptyReportIsNotStored() {
        XCTAssertTrue(LabReport().isEmpty)
        var withResult = LabReport()
        withResult.ns1 = .positive
        XCTAssertFalse(withResult.isEmpty, "a test result alone is still a report")
        var withValue = LabReport()
        withValue.platelets = 200
        XCTAssertFalse(withValue.isEmpty)
    }

    func testTestsDefaultToNotDoneRatherThanNegative() {
        // "Not done" and "negative" mean opposite things, and defaulting to
        // negative would invent a result nobody reported.
        let report = LabReport()
        for test in DengueTest.allCases {
            XCTAssertEqual(report.result(for: test), .notDone, test.rawValue)
        }
    }

    func testEveryMeasureAndTestIsNamedInBothLanguages() {
        for measure in LabMeasure.allCases {
            for key in [measure.labelKey, measure.unitKey] {
                XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
                XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
            }
        }
        for test in DengueTest.allCases {
            for key in [test.labelKey, test.usefulDaysKey] {
                XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
                XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
            }
        }
        for result in TestResult.allCases {
            XCTAssertNotNil(Strings.english[result.labelKey])
            XCTAssertNotNil(Strings.bangla[result.labelKey])
        }
    }

    func testTheRangeNoteSendsTheReaderToTheirOwnReportAndDoctor() {
        // Wording may be edited; these two ideas must survive editing.
        let note = (Strings.english["lab.rangeNote"] ?? "").lowercased()
        XCTAssertTrue(note.contains("laborator") || note.contains("reference"),
                      "should point at the lab's own reference range")
        XCTAssertTrue(note.contains("doctor"), "should point at a clinician")
    }

    func testTheCarePlanDisclaimsAnyLinkToLabResults() {
        // The care plan follows the symptom check. If that ever changes, this
        // string is the promise that would be broken.
        let note = (Strings.english["care.plan.note"] ?? "").lowercased()
        XCTAssertTrue(note.contains("not your lab"), note)
    }
}
