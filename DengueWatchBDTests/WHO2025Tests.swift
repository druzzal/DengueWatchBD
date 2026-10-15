import XCTest
@testable import DengueWatchBD

/// The changes WHO's 2025 arboviral guideline made to what this app advises:
/// who is seen the same day, the haematocrit pattern it points at, and the
/// fluid log behind protocolized oral fluids.
@MainActor
final class WHO2025Tests: XCTestCase {

    // MARK: - Triage

    func testBeingUnableToDrinkIsAWarningSign() {
        XCTAssertEqual(TriageEngine.symptom(id: "oralIntolerance")?.group, .warning)
        XCTAssertEqual(TriageEngine.evaluate(selected: ["oralIntolerance"], context: .init()),
                       .seeDoctorToday)
    }

    func testAPregnantReaderWithAFeverIsSeenToday() {
        // This used to say "get a test" unless two core symptoms were ticked,
        // while the care plan beside it said hospital.
        var context = TriageEngine.Context()
        context.isPregnant = true
        XCTAssertEqual(TriageEngine.evaluate(selected: ["fever"], context: context), .seeDoctorToday)
        XCTAssertTrue(TriageEngine.isRaisedByRiskGroup(selected: ["fever"], context: context))
    }

    func testPreviousDengueAloneNoLongerRaisesTheResult() {
        var context = TriageEngine.Context()
        context.hadDengueBefore = true
        XCTAssertEqual(TriageEngine.evaluate(selected: ["fever", "headache", "aches"],
                                             context: context), .testAdvised)
    }

    func testAWarningSignIsNotDescribedAsARiskGroupResult() {
        var context = TriageEngine.Context()
        context.isPregnant = true
        XCTAssertFalse(TriageEngine.isRaisedByRiskGroup(selected: ["fever", "vomiting"],
                                                        context: context))
    }

    /// The result screen and the care plan must agree on the same answers.
    func testTheResultAndTheCarePlanAgreeOnTheSameDayGroups() {
        let contexts: [TriageEngine.Context] = [
            .init(isPregnant: true),
            .init(isUnderFiveOrOverSixty: true),
            .init(hasChronicCondition: true),
        ]
        for context in contexts {
            let outcome = TriageEngine.evaluate(selected: ["fever"], context: context)
            let plan = WHOCarePlan.evaluate(symptoms: ["fever"], vitals: nil,
                                            context: context, feverDaysAgo: nil)
            XCTAssertEqual(outcome, .seeDoctorToday)
            XCTAssertEqual(plan.group, .referral)
        }
    }

    func testTheRiskGroupSummaryExistsInBothLanguages() {
        let key = "outcome.seeDoctor.riskGroup.summary"
        XCTAssertNotNil(Strings.english[key])
        XCTAssertNotNil(Strings.bangla[key])
    }

    // MARK: - Rising haematocrit

    private func series(_ values: [Double], endingHoursAgo: Double = 2,
                        now: Date) -> [(date: Date, value: Double)] {
        values.enumerated().map { index, value in
            let hoursBack = endingHoursAgo + Double(values.count - 1 - index) * 24
            return (date: now.addingTimeInterval(-hoursBack * 3600), value: value)
        }
    }

    func testTwoMeaningfulRisesInARowAreFlagged() {
        let now = Date()
        XCTAssertTrue(CarePlanContext.haematocritIsRising(series([38, 41, 45], now: now), now: now))
    }

    func testOneRiseIsNotAProgression() {
        let now = Date()
        XCTAssertFalse(CarePlanContext.haematocritIsRising(series([38, 45], now: now), now: now))
        XCTAssertFalse(CarePlanContext.haematocritIsRising(series([45, 38, 45], now: now), now: now))
    }

    func testRisesWithinTheAssaysScatterAreNotFlagged() {
        let now = Date()
        XCTAssertFalse(CarePlanContext.haematocritIsRising(series([40, 41, 42], now: now), now: now))
    }

    func testAnOldRiseSaysNothingAboutToday() {
        let now = Date()
        XCTAssertFalse(CarePlanContext.haematocritIsRising(
            series([38, 41, 45], endingHoursAgo: 24 * 6, now: now), now: now))
    }

    // MARK: - Fluid log

    private func at(_ hour: Int, minute: Int = 0, dayOffset: Int = 0) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        let base = Calendar.current.date(from: components)!
        return Calendar.current.date(byAdding: .day, value: dayOffset, to: base)!
    }

    func testTheDayTotalsOnlyThatDay() {
        let entries = [
            FluidEntry(date: at(8), kind: .drink, millilitres: 250),
            FluidEntry(date: at(9), kind: .drink, millilitres: 200),
            FluidEntry(date: at(10), kind: .urine),
            FluidEntry(date: at(20, dayOffset: -1), kind: .drink, millilitres: 500),
            FluidEntry(date: at(21, dayOffset: -1), kind: .urine),
        ]
        let today = FluidLog.day(at(12), entries: entries)
        XCTAssertEqual(today, FluidDay(drunkMillilitres: 450, drinks: 2, urinations: 1))
    }

    func testTheUrineAimIsWHOs() {
        XCTAssertEqual(FluidLog.urinationAim, 4...6)
    }

    func testALongGapInAKeptLogIsRaised() {
        let now = Date()
        let entries = [FluidEntry(date: now.addingTimeInterval(-7 * 3600), kind: .urine)]
        XCTAssertTrue(FluidLog.urineGapIsLong(entries: entries, now: now))
    }

    func testARecentEntryRaisesNothing() {
        let now = Date()
        let entries = [FluidEntry(date: now.addingTimeInterval(-2 * 3600), kind: .urine)]
        XCTAssertFalse(FluidLog.urineGapIsLong(entries: entries, now: now))
    }

    /// Someone who stopped logging has not stopped passing urine.
    func testAnAbandonedLogRaisesNothing() {
        let now = Date()
        let entries = [FluidEntry(date: now.addingTimeInterval(-3 * 86_400), kind: .urine)]
        XCTAssertFalse(FluidLog.urineGapIsLong(entries: entries, now: now))
        XCTAssertFalse(FluidLog.urineGapIsLong(entries: [], now: now))
    }

    func testTheStoreRejectsADrinkWithNoPlausibleAmount() {
        let store = FluidStore(filename: temporaryStoreFilename("fluids"))
        store.add(FluidEntry(kind: .drink, millilitres: nil))
        store.add(FluidEntry(kind: .drink, millilitres: 0))
        store.add(FluidEntry(kind: .drink, millilitres: 25_000))
        XCTAssertTrue(store.entries.isEmpty)
        store.add(FluidEntry(kind: .drink, millilitres: 250))
        store.add(FluidEntry(kind: .urine))
        XCTAssertEqual(store.entries.count, 2)
    }

    func testTheStoreSurvivesARelaunch() {
        let name = temporaryStoreFilename("fluids")
        let first = FluidStore(filename: name)
        first.add(FluidEntry(kind: .drink, millilitres: 300))
        let second = FluidStore(filename: name)
        XCTAssertEqual(second.entries.first?.millilitres, 300)
    }

    func testFluidsMakeADayInTheLog() {
        let entry = FluidEntry(date: at(9), kind: .drink, millilitres: 250)
        let days = HealthLog.days(vitals: [], labs: [], fluids: [entry])
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.fluids, [entry])
        XCTAssertTrue(days.first?.itemsNewestFirst.isEmpty ?? false,
                      "fluids are summed per day, not listed beside readings")
    }

    func testTheFluidLogIsInThePDF() throws {
        let day = HealthLog.days(vitals: [], labs: [],
                                 fluids: [FluidEntry(date: at(9), kind: .drink, millilitres: 250)])
        let url = try XCTUnwrap(HealthLogPDF.write(days: day, loc: LocalizationManager(),
                                                   unit: .celsius))
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
    }

    // MARK: - Fluid summary for the report

    func testTheSummaryUsesWholeDaysOnly() {
        let entries = [
            FluidEntry(date: at(9, dayOffset: -2), kind: .drink, millilitres: 2000),
            FluidEntry(date: at(10, dayOffset: -2), kind: .urine),
            FluidEntry(date: at(9, dayOffset: -1), kind: .drink, millilitres: 1000),
            FluidEntry(date: at(9, dayOffset: -1), kind: .urine),
            FluidEntry(date: at(12, dayOffset: -1), kind: .urine),
            FluidEntry(date: at(15, dayOffset: -1), kind: .urine),
            FluidEntry(date: at(18, dayOffset: -1), kind: .urine),
            // Today: half a day, which must not drag the average down.
            FluidEntry(date: at(8), kind: .drink, millilitres: 100),
        ]
        let summary = FluidLog.summary(entries, now: at(12))
        XCTAssertEqual(summary.daysLogged, 3)
        XCTAssertEqual(summary.averageMillilitres, 1500)
        XCTAssertEqual(summary.daysWithUrineLogged, 2)
        XCTAssertEqual(summary.daysUrineAimMet, 1, "4 urinations meets the aim, 1 does not")
        XCTAssertTrue(summary.includesToday)
    }

    /// A day with drinks but no urine logged is a day it was not written
    /// down, not a day of none.
    func testADayWithNoUrineLoggedIsNotCountedAsShort() {
        let entries = [FluidEntry(date: at(9, dayOffset: -1), kind: .drink, millilitres: 500)]
        let summary = FluidLog.summary(entries, now: at(12))
        XCTAssertEqual(summary.daysWithUrineLogged, 0)
        XCTAssertEqual(summary.daysUrineAimMet, 0)
        XCTAssertFalse(summary.includesToday)
    }

    func testOnlyTodayGivesNoAverageYet() {
        let entries = [FluidEntry(date: at(8), kind: .drink, millilitres: 300)]
        XCTAssertNil(FluidLog.summary(entries, now: at(12)).averageMillilitres)
    }

    func testDailyTotalsAreOldestFirstAndSkipEmptyDays() {
        let entries = [
            FluidEntry(date: at(9), kind: .drink, millilitres: 200),
            FluidEntry(date: at(9, dayOffset: -3), kind: .drink, millilitres: 400),
        ]
        let daily = FluidLog.daily(entries)
        XCTAssertEqual(daily.map(\.day.drunkMillilitres), [400, 200])
    }

    func testAMultiDayFluidLogRendersItsSummaryAndCharts() throws {
        let entries = (0..<4).flatMap { offset -> [FluidEntry] in
            [FluidEntry(date: at(9, dayOffset: -offset), kind: .drink, millilitres: 800 + offset * 300),
             FluidEntry(date: at(14, dayOffset: -offset), kind: .drink, millilitres: 500),
             FluidEntry(date: at(10, dayOffset: -offset), kind: .urine),
             FluidEntry(date: at(16, dayOffset: -offset), kind: .urine)]
            + (offset % 2 == 0 ? [] : [FluidEntry(date: at(19, dayOffset: -offset), kind: .urine),
                                       FluidEntry(date: at(22, dayOffset: -offset), kind: .urine)])
        }
        let vitals = (0..<4).map { VitalsEntry(date: at(8, dayOffset: -$0), temperature: 38.0 + Double($0) * 0.4) }
        let days = HealthLog.days(vitals: vitals, labs: [], fluids: entries)
        let url = try XCTUnwrap(HealthLogPDF.write(days: days, loc: LocalizationManager(),
                                                   unit: .celsius, generatedAt: at(17)))
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
    }

    /// Bangla labels run longer than English; the summary and both charts
    /// must still lay out.
    func testAMultiDayFluidLogRendersInBangla() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WHO2025Tests-bn"))
        defaults.set(AppLanguage.bangla.rawValue, forKey: "appLanguage")   // LocalizationManager.storageKey
        addTeardownBlock { defaults.removePersistentDomain(forName: "WHO2025Tests-bn") }
        let entries = (0..<3).flatMap { offset in
            [FluidEntry(date: at(9, dayOffset: -offset), kind: .drink, millilitres: 1200),
             FluidEntry(date: at(10, dayOffset: -offset), kind: .urine)]
        }
        let days = HealthLog.days(vitals: [], labs: [], fluids: entries)
        let url = try XCTUnwrap(HealthLogPDF.write(days: days, loc: LocalizationManager(defaults: defaults),
                                                   unit: .celsius, generatedAt: at(17)))
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
    }

    func testTheReportFluidTextExistsInBothLanguages() {
        for key in ["pdf.fluidDays", "pdf.fluids.days", "pdf.fluids.average", "pdf.fluids.aimMet",
                    "pdf.fluids.ofDays", "pdf.fluids.wholeDays", "pdf.fluids.chart.intake",
                    "pdf.fluids.chart.urine", "pdf.fluids.aim", "pdf.fluids.today"] {
            XCTAssertNotNil(Strings.english[key], key)
            XCTAssertNotNil(Strings.bangla[key], key)
        }
    }

    // MARK: - Myths

    func testTheNewMythsCarryTheGuidance() {
        let transfusion = (Strings.english["myth.transfusion.fact"] ?? "").lowercased()
        XCTAssertTrue(transfusion.contains("no bleeding"), transfusion)
        let steroids = (Strings.english["myth.steroids.fact"] ?? "").lowercased()
        XCTAssertTrue(steroids.contains("against"), steroids)
    }

    /// WHO 2025: water should always be the main source of fluids. The old
    /// prevention advice said the opposite.
    func testNoAdviceDiscouragesWater() {
        for (key, value) in Strings.english {
            XCTAssertFalse(value.lowercased().contains("plain water alone is not ideal"), key)
        }
    }
}
