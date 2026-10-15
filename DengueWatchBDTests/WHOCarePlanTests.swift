import XCTest
@testable import DengueWatchBD

/// Where WHO's 2025 guidance puts the reader. These rules decide whether someone is told to
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
        // WHO 2025 lists the warning signs, and being unable to drink, among
        // the reasons clinicians admit.
        for sign in ["abdominal", "vomiting", "oralIntolerance", "bleeding", "fatigue",
                     "fluid", "noUrine"] {
            XCTAssertEqual(plan(["fever", sign]).group, .referral, sign)
        }
    }

    func testASevereSignIsAnEmergency() {
        for sign in ["faint", "confusion", "heavyBleed"] {
            XCTAssertEqual(plan(["fever", sign]).group, .emergency, sign)
        }
    }

    func testPregnancyAloneMeansHospitalAssessment() {
        // WHO 2025 lists pregnancy on its own among the criteria to admit.
        var context = TriageEngine.Context()
        context.isPregnant = true
        let result = plan(["fever"], context: context)
        XCTAssertEqual(result.group, .referral)
        XCTAssertTrue(result.reasons.contains(.pregnancy))
    }

    func testAgeAndLongTermConditionsStillMeanAssessment() {
        // WHO leaves these to the clinician ("may elect to admit"); the app
        // keeps sending them to be seen rather than deciding for the clinician.
        var age = TriageEngine.Context()
        age.isUnderFiveOrOverSixty = true
        var chronic = TriageEngine.Context()
        chronic.hasChronicCondition = true
        for context in [age, chronic] {
            let result = plan(["fever"], context: context)
            XCTAssertEqual(result.group, .referral)
            XCTAssertTrue(result.reasons.contains(.higherRiskGroup))
        }
    }

    /// WHO 2025 names a second infection as raising the risk of severe
    /// disease, not as a reason to admit. It is said, and it moves nothing.
    func testPreviousDengueIsAReasonButNotAMove() {
        var context = TriageEngine.Context()
        context.hadDengueBefore = true
        let result = plan(["fever"], context: context)
        XCTAssertEqual(result.group, .home)
        XCTAssertEqual(result.reasons, [.previousDengue])
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

    // MARK: - How long a record speaks for

    /// A symptom check is a snapshot. Presenting last month's as "your care
    /// plan" is the same mistake as a surveillance figure with no date on it.
    func testAPlanOnlySpeaksForTodayForAFewDays() {
        XCTAssertTrue(WHOCarePlan.describesToday(checkedDaysAgo: 0))
        XCTAssertTrue(WHOCarePlan.describesToday(checkedDaysAgo: WHOCarePlan.freshForDays))
        XCTAssertFalse(WHOCarePlan.describesToday(checkedDaysAgo: WHOCarePlan.freshForDays + 1))
        XCTAssertFalse(WHOCarePlan.describesToday(checkedDaysAgo: 40))
    }

    /// A clock that moved backwards should not make an old check look new.
    func testAFutureDatedCheckIsNotTreatedAsCurrent() {
        XCTAssertFalse(WHOCarePlan.describesToday(checkedDaysAgo: -1))
    }

    /// The timeline charts a live illness, not an old record. Past the window
    /// no day of the strip is today, so it would draw a whole illness with
    /// nothing marked and a headline counting "day 41 of a fever".
    func testTheTimelineStopsOnceTheIllnessIsOver() {
        XCTAssertTrue(WHOCarePlan.showsTimeline(feverDaysAgo: 0))
        XCTAssertTrue(WHOCarePlan.showsTimeline(feverDaysAgo: 9))
        XCTAssertFalse(WHOCarePlan.showsTimeline(feverDaysAgo: WHOCarePlan.illnessWindowDays))
        XCTAssertFalse(WHOCarePlan.showsTimeline(feverDaysAgo: 40))
    }

    func testTheTimelineRejectsNegativeDays() {
        XCTAssertFalse(WHOCarePlan.showsTimeline(feverDaysAgo: -3))
    }

    func testTheStaleNoticeExistsInBothLanguages() {
        for key in ["who.plan.stale", "who.plan.checkedAt"] {
            XCTAssertNotNil(Strings.english[key], key)
            XCTAssertNotNil(Strings.bangla[key], key)
        }
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
        for reason in WHOCarePlan.Reason.allCases {
            XCTAssertNotNil(Strings.english[reason.labelKey], reason.labelKey)
            XCTAssertNotNil(Strings.bangla[reason.labelKey], reason.labelKey)
        }
    }

    /// The advice must not contradict the app's standing line on painkillers,
    /// and must not quietly become dosing instructions.
    func testTheAdviceNamesTheDrugsToAvoidAndGivesNoDoses() {
        let home = WHOCarePlan.Group.home.adviceKeys.map { Strings.english[$0] ?? "" }
        let joined = home.joined(separator: " ").lowercased()
        XCTAssertTrue(joined.contains("aspirin"), joined)
        XCTAssertTrue(joined.contains("ibuprofen"), joined)
        for dose in ["mg", "500", "tablet", "twice a day"] {
            XCTAssertFalse(joined.contains(dose), "no dosing advice: \(joined)")
        }
    }

    /// The card must keep saying what it is not, and which guidance it is.
    func testTheSourceLineDisclaimsDiagnosis() {
        let source = (Strings.english["who.plan.source"] ?? "").lowercased()
        XCTAssertTrue(source.contains("who"), source)
        XCTAssertTrue(source.contains("2025"), "cites the current guideline: \(source)")
        XCTAssertTrue(source.contains("does not decide whether you have dengue"), source)
    }

    /// The 2009 letters must not survive the move to the 2025 guideline: a
    /// clinician reading "Group B" would look for a classification WHO no
    /// longer uses.
    func testNoGroupIsTitledWithA2009Letter() {
        for group in WHOCarePlan.Group.allCases {
            for table in [Strings.english, Strings.bangla] {
                let title = table[group.titleKey] ?? ""
                XCTAssertFalse(title.contains("Group") || title.contains("গ্রুপ"), title)
            }
        }
    }

    /// WHO 2025 advises against steroids at home, and its home advice now
    /// leads with measured oral fluids.
    func testTheHomeAdviceCarriesThe2025Recommendations() {
        let home = WHOCarePlan.Group.home.adviceKeys
            .map { Strings.english[$0] ?? "" }.joined(separator: " ").lowercased()
        XCTAssertTrue(home.contains("steroid"), home)
        XCTAssertTrue(home.contains("measure"), home)
        XCTAssertTrue(home.contains("4 to 6 times a day"), home)
    }
}
