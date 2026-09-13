import XCTest
@testable import DengueWatchBD

/// The join between readings and advice. The rules here are all about it
/// staying narrow: it decides whether to raise a line, never what the advice is.
final class CarePlanContextTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 24 * 60 * 60)
    }

    private func context(vitals: [(VitalKind, Double, Date)] = [],
                         labs: [(LabMeasure, Double, Date)] = []) -> CarePlanContext {
        CarePlanContext.from(
            vitals: vitals.map { (kind: $0.0, value: $0.1, date: $0.2) },
            labs: labs.map { (measure: $0.0, value: $0.1, date: $0.2) },
            now: now)
    }

    // MARK: - What gets raised

    func testNormalReadingsRaiseNothing() {
        let result = context(vitals: [(.temperature, 36.8, daysAgo(0)), (.pulse, 72, daysAgo(0))],
                             labs: [(.platelets, 250, daysAgo(0))])
        XCTAssertFalse(result.hasAnything)
    }

    func testMerelyOutsideTheRangeRaisesNothing() {
        // A haemoglobin a fraction under the line every week would make this
        // line permanent furniture, and people stop seeing furniture.
        let result = context(labs: [(.haemoglobin, 11.5, daysAgo(0))])
        XCTAssertFalse(result.hasAnything, "only far-out readings should be raised")
    }

    func testAFarOutReadingIsRaised() {
        let result = context(labs: [(.platelets, 96, daysAgo(0))])
        XCTAssertEqual(result.notableLabs, [.platelets])
    }

    func testVitalsAndLabsAreBothConsidered() {
        let result = context(vitals: [(.oxygenSaturation, 89, daysAgo(1))],
                             labs: [(.platelets, 80, daysAgo(1))])
        XCTAssertEqual(result.notableVitals, [.oxygenSaturation])
        XCTAssertEqual(result.notableLabs, [.platelets])
    }

    // MARK: - Recency

    func testAnOldReadingIsNotRaised() {
        // A platelet count from last month says nothing about today.
        XCTAssertFalse(context(labs: [(.platelets, 96, daysAgo(30))]).hasAnything)
    }

    func testTheRecencyWindowIsThreeDays() {
        XCTAssertTrue(context(labs: [(.platelets, 96, daysAgo(2))]).hasAnything)
        XCTAssertFalse(context(labs: [(.platelets, 96, daysAgo(4))]).hasAnything)
    }

    func testARecentReadingCountsEvenIfAnOlderNormalOneExists() {
        let result = context(labs: [(.platelets, 250, daysAgo(5)),
                                    (.platelets, 96, daysAgo(1))])
        XCTAssertEqual(result.notableLabs, [.platelets])
    }

    // MARK: - Shape

    func testAMeasureIsNamedOnceEvenWithSeveralBadReadings() {
        let result = context(labs: [(.platelets, 96, daysAgo(0)),
                                    (.platelets, 80, daysAgo(1)),
                                    (.platelets, 70, daysAgo(2))])
        XCTAssertEqual(result.notableLabs, [.platelets], "the line names measures, not readings")
    }

    func testOrderIsStableBetweenRenders() {
        let first = context(labs: [(.platelets, 96, daysAgo(0)), (.whiteCells, 1.2, daysAgo(0))])
        let second = context(labs: [(.whiteCells, 1.2, daysAgo(0)), (.platelets, 96, daysAgo(0))])
        XCTAssertEqual(first.notableLabs, second.notableLabs)
    }

    func testNoReadingsAtAllRaisesNothing() {
        XCTAssertFalse(context().hasAnything)
    }

    // MARK: - The line it produces

    func testTheWordingPromptsAskingRatherThanConcluding() {
        let text = (Strings.english["care.plan.readings"] ?? "").lowercased()
        XCTAssertTrue(text.contains("doctor"), text)
        XCTAssertTrue(text.contains("does not read them for you"), text)
        // It must not name a condition.
        for word in ["dengue", "severe", "shock", "diagnos"] {
            XCTAssertFalse(text.contains(word), "must not interpret: \(text)")
        }
    }

    func testTheCarePlanStillDisclaimsBeingDrivenByLabs() {
        // The outcome above the line is unchanged by any reading.
        let note = (Strings.english["care.plan.note"] ?? "").lowercased()
        XCTAssertTrue(note.contains("not your lab"), note)
    }

    /// Regression: the in-app language toggle is independent of the device
    /// locale, so a device-locale list formatter rendered
    /// "অক্সিজেনের মাত্রা and প্লেটলেট" on the Bengali screen.
    func testNamesAreJoinedInTheChosenLanguageNotTheDeviceLocale() {
        let names = ["অক্সিজেনের মাত্রা", "প্লেটলেট"]
        let bangla = NumberStyle(language: .bangla).list(names)
        XCTAssertFalse(bangla.contains("and"), bangla)
        XCTAssertTrue(bangla.contains("এবং"), bangla)

        let english = NumberStyle(language: .english).list(["Oxygen saturation", "Platelets"])
        XCTAssertTrue(english.contains("and"), english)
    }

    func testJoiningOneNameAddsNoConjunction() {
        let one = NumberStyle(language: .english).list(["Platelets"])
        XCTAssertEqual(one, "Platelets")
    }

    func testBothStringsExistInBengali() {
        for key in ["care.plan.readings", "care.plan.recheck"] {
            XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
        }
    }
}
