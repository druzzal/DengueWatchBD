import XCTest
@testable import DengueWatchBD

/// The WHO management groups. These rules decide whether someone is told to
/// stay home or go to an emergency department, so the tests are about the
/// direction of every influence as much as the outcome.
final class WHOCarePlanTests: XCTestCase {

    private func vitals(systolic: Double? = nil, diastolic: Double? = nil,
                        pulse: Double? = nil, oxygen: Double? = nil,
                        temperature: Double? = nil) -> VitalsEntry {
        VitalsEntry(date: Date(), temperature: temperature, pulse: pulse,
                    systolic: systolic, diastolic: diastolic,
                    oxygenSaturation: oxygen)
    }

    private func plan(_ symptoms: Set<String> = [],
                      vitals: VitalsEntry? = nil,
                      context: TriageEngine.Context = .init(),
                      feverDaysAgo: Int? = nil) -> WHOCarePlan {
        WHOCarePlan.evaluate(symptoms: symptoms, vitals: vitals,
                             context: context, feverDaysAgo: feverDaysAgo)
    }

    // MARK: - The groups

    func testPlainFeverIsManagedAtHome() {
        XCTAssertEqual(plan(["fever", "headache"]).group, .home)
    }

    func testAWarningSignMeansHospitalAssessment() {
        // WHO's warning signs are the whole reason Group B exists.
        for sign in ["abdominal", "vomiting", "bleeding", "fatigue", "fluid", "noUrine"] {
            XCTAssertEqual(plan(["fever", sign]).group, .referral, sign)
        }
    }

    func testASevereSignIsAnEmergency() {
        for sign in ["faint", "confusion", "heavyBleed"] {
            XCTAssertEqual(plan(["fever", sign]).group, .emergency, sign)
        }
    }

    func testAHigherRiskConditionAloneMeansAssessment() {
        // WHO puts co-existing conditions in Group B even without warning signs.
        var context = TriageEngine.Context()
        context.isPregnant = true
        XCTAssertEqual(plan(["fever"], context: context).group, .referral)
    }

    // MARK: - Readings

    func testANarrowPulsePressureIsTreatedAsShock() {
        // WHO's earliest measurable sign of compensated shock.
        let result = plan(["fever"], vitals: vitals(systolic: 100, diastolic: 82))
        XCTAssertEqual(result.group, .emergency)
        XCTAssertTrue(result.reasons.contains(.narrowPulsePressure))
    }

    func testLowBloodPressureIsAnEmergency() {
        XCTAssertEqual(plan(["fever"], vitals: vitals(systolic: 85, diastolic: 60)).group,
                       .emergency)
    }

    func testAFastPulseOrLowOxygenRaisesToAssessment() {
        XCTAssertEqual(plan(["fever"], vitals: vitals(pulse: 130)).group, .referral)
        XCTAssertEqual(plan(["fever"], vitals: vitals(oxygen: 91)).group, .referral)
    }

    func testNormalReadingsDoNotLowerTheGroup() {
        // The danger: a reassuring blood pressure quietly cancelling a warning
        // sign the reader reported. It must not.
        let result = plan(["fever", "vomiting"],
                          vitals: vitals(systolic: 118, diastolic: 76, pulse: 80, oxygen: 98))
        XCTAssertEqual(result.group, .referral)
    }

    func testAMissingReadingIsNotANormalReading() {
        // No vitals at all must leave the group exactly where the symptoms put it.
        XCTAssertEqual(plan(["fever", "vomiting"], vitals: nil).group,
                       plan(["fever", "vomiting"], vitals: vitals(pulse: 80)).group)
    }

    func testHalfABloodPressureRaisesNoPulsePressureConcern() {
        // Systolic without diastolic cannot give a pulse pressure, and must
        // not be guessed at.
        let result = plan(["fever"], vitals: vitals(systolic: 100))
        XCTAssertFalse(result.reasons.contains(.narrowPulsePressure))
    }

    // MARK: - Phase

    func testTheCriticalPhaseIsNamedAsAReason() {
        let result = plan(["fever"], feverDaysAgo: 4)      // day 5
        XCTAssertEqual(result.phase, .critical)
        XCTAssertTrue(result.reasons.contains(.criticalPhase))
    }

    func testFeverDayCountsFromOneNotZero() {
        XCTAssertEqual(plan(["fever"], feverDaysAgo: 0).feverDay, 1)
        XCTAssertEqual(plan(["fever"], feverDaysAgo: 4).feverDay, 5)
        XCTAssertNil(plan(["fever"]).feverDay)
    }

    /// Being in the critical phase is worth saying, but on its own it is not
    /// a reason to send someone to hospital — most people pass through it at
    /// home. Escalating on the calendar alone would send every dengue patient
    /// in the country to an emergency department on day 4.
    func testTheCriticalPhaseAloneDoesNotEscalate() {
        XCTAssertEqual(plan(["fever"], feverDaysAgo: 4).group, .home)
    }

    // MARK: - What it shows

    func testTheReasonsAreNeverEmpty() {
        // A plan with no stated reason reads as an oracle.
        XCTAssertEqual(plan(["fever"]).reasons, [.noneOfThese])
        XCTAssertFalse(plan([]).reasons.isEmpty)
    }

    func testTheMostSeriousReasonComesFirst() {
        let result = plan(["fever", "vomiting", "confusion"], feverDaysAgo: 4)
        XCTAssertEqual(result.reasons.first, .severeSign)
    }

    func testMeasuredReasonsAreSeparableFromReportedOnes() {
        // The screen adds a caveat to the measured ones, so it has to be able
        // to tell them apart.
        let result = plan(["fever", "vomiting"], vitals: vitals(pulse: 130))
        XCTAssertEqual(result.measuredReasons, [.fastPulse])
        XCTAssertTrue(result.reasons.contains(.warningSign))
    }

    func testEveryGroupAndReasonHasTextInBothLanguages() {
        for group in WHOCarePlan.Group.allCases {
            for key in [group.titleKey, group.detailKey] + group.adviceKeys {
                XCTAssertNotNil(Strings.english[key], key)
                XCTAssertNotNil(Strings.bangla[key], key)
            }
        }
        let reasons: [WHOCarePlan.Reason] = [.severeSign, .warningSign, .coMorbidity,
                                             .criticalPhase, .narrowPulsePressure,
                                             .lowBloodPressure, .fastPulse, .lowOxygen,
                                             .noneOfThese]
        for reason in reasons {
            XCTAssertNotNil(Strings.english[reason.labelKey], reason.labelKey)
            XCTAssertNotNil(Strings.bangla[reason.labelKey], reason.labelKey)
        }
    }

    /// The advice must not contradict the app's standing line on painkillers,
    /// and must not quietly become dosing instructions.
    func testTheAdviceNamesTheDrugsToAvoidAndGivesNoDoses() {
        let home = (1...4).map { Strings.english["who.group.home.advice\($0)"] ?? "" }
        let joined = home.joined(separator: " ").lowercased()
        XCTAssertTrue(joined.contains("aspirin"), joined)
        XCTAssertTrue(joined.contains("ibuprofen"), joined)
        for dose in ["mg", "500", "tablet", "twice a day"] {
            XCTAssertFalse(joined.contains(dose), "no dosing advice: \(joined)")
        }
    }

    /// The card must keep saying what it is not.
    func testTheSourceLineDisclaimsDiagnosis() {
        let source = (Strings.english["who.plan.source"] ?? "").lowercased()
        XCTAssertTrue(source.contains("who"), source)
        XCTAssertTrue(source.contains("does not decide whether you have dengue"), source)
    }
}
