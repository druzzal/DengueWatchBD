import XCTest
@testable import DengueWatchBD

/// Reading numbers off a photograph is the most dangerous thing in this app,
/// because a misread value looks exactly like a correct one. Everything the
/// parser produces is shown for confirmation before saving — these tests are
/// about it proposing the right thing in the first place, and proposing
/// nothing when it cannot tell.
final class LabReportParserTests: XCTestCase {

    // MARK: - Units as Bangladeshi labs actually print them

    func testPlateletsWrittenInFull() {
        // "96,000 /cumm" is the common form on a Dhaka CBC report.
        let report = LabReportParser.draft(from: "Platelet Count      96,000 /cumm")
        XCTAssertEqual(try XCTUnwrap(report.platelets), 96, accuracy: 0.01)
    }

    func testPlateletsAlreadyInThousands() {
        let report = LabReportParser.draft(from: "Platelets  96 x10^3/µL")
        XCTAssertEqual(try XCTUnwrap(report.platelets), 96, accuracy: 0.01)
    }

    func testPlateletsInLakh() {
        // 1.5 lakh is 150,000, which is 150 in the unit this app stores.
        let report = LabReportParser.draft(from: "Platelet: 1.5 lakh")
        XCTAssertEqual(try XCTUnwrap(report.platelets), 150, accuracy: 0.01)
    }

    func testWhiteCellsWrittenInFull() {
        let report = LabReportParser.draft(from: "Total WBC Count   3,600 /cumm")
        XCTAssertEqual(try XCTUnwrap(report.whiteCells), 3.6, accuracy: 0.01)
    }

    // MARK: - Labels labs actually use

    func testAbbreviationsAreRecognised() {
        let text = """
        Hb        14.1 g/dl
        PCV       47.5 %
        TLC       3.6
        PLT       96
        """
        let report = LabReportParser.draft(from: text)
        XCTAssertEqual(try XCTUnwrap(report.haemoglobin), 14.1, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.haematocrit), 47.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.whiteCells), 3.6, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.platelets), 96, accuracy: 0.01)
    }

    func testAmericanAndBritishSpellingsBothWork() {
        XCTAssertNotNil(LabReportParser.draft(from: "Hemoglobin 13.2").haemoglobin)
        XCTAssertNotNil(LabReportParser.draft(from: "Haemoglobin 13.2").haemoglobin)
    }

    // MARK: - Serology

    func testPositiveAndNegativeResultsAreRead() {
        let text = """
        Dengue NS1 Antigen ......... Positive
        Dengue IgM Antibody ........ Negative
        """
        let report = LabReportParser.draft(from: text)
        XCTAssertEqual(report.ns1, .positive)
        XCTAssertEqual(report.igm, .negative)
    }

    func testReactiveAndNonReactiveAreRead() {
        XCTAssertEqual(LabReportParser.draft(from: "NS1: Reactive").ns1, .positive)
        XCTAssertEqual(LabReportParser.draft(from: "NS1: Non-Reactive").ns1, .negative)
    }

    func testATestNotOnThePageStaysNotDone() {
        // Absent must never become negative: they mean opposite things.
        let report = LabReportParser.draft(from: "Dengue NS1 Antigen: Positive")
        XCTAssertEqual(report.igg, .notDone)
        XCTAssertEqual(report.igm, .notDone)
    }

    // MARK: - Refusing to guess

    func testAReferenceRangeIsNotMistakenForAResult() {
        // Reports print the normal range beside the value. Picking the first
        // plausible number must not turn "150 - 450" into the reading.
        let report = LabReportParser.draft(from: "Platelet Count  96,000 /cumm   (150,000 - 450,000)")
        XCTAssertEqual(try XCTUnwrap(report.platelets), 96, accuracy: 0.01)
    }

    func testNonsenseLinesProduceNothing() {
        let report = LabReportParser.draft(from: """
        Dhaka Medical Laboratory
        Patient: Mr Rahman     Age: 34
        Collected: 13/09/2026
        """)
        XCTAssertTrue(report.isEmpty, "no measure should be invented from a header")
    }

    func testAnEmptyScanProducesAnEmptyDraft() {
        XCTAssertTrue(LabReportParser.draft(from: "").isEmpty)
        XCTAssertTrue(LabReportParser.draft(from: "   \n  \n").isEmpty)
    }

    func testValuesOutsideWhatAPersonCanHaveAreRejected() {
        // A misread decimal point should produce nothing rather than a number
        // that would sit in the record looking authoritative.
        XCTAssertNil(LabReportParser.draft(from: "Haemoglobin 1410 g/dl").haemoglobin)
    }

    // MARK: - A whole report

    func testATypicalDengueCBCIsReadEndToEnd() {
        let text = """
        POPULAR DIAGNOSTIC CENTRE LTD
        COMPLETE BLOOD COUNT (CBC)

        Haemoglobin            14.1    g/dL      (13.0 - 17.0)
        Total WBC Count        3,600   /cumm     (4,000 - 11,000)
        Platelet Count         96,000  /cumm     (150,000 - 450,000)
        Haematocrit (PCV)      47.5    %         (40.0 - 50.0)

        Dengue NS1 Antigen     Positive
        Dengue IgM             Negative
        """
        let report = LabReportParser.draft(from: text)
        XCTAssertEqual(try XCTUnwrap(report.platelets), 96, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.whiteCells), 3.6, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.haemoglobin), 14.1, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.haematocrit), 47.5, accuracy: 0.01)
        XCTAssertEqual(report.ns1, .positive)
        XCTAssertEqual(report.igm, .negative)
        XCTAssertEqual(report.igg, .notDone)
    }
}
