import XCTest
@testable import DengueWatchBD

/// The merge of two stores into one day-ordered record.
final class HealthLogTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Dhaka")!
        return c
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day,
                                           hour: hour, minute: minute))!
    }

    private func check(_ date: Date) -> CaseLogEntry {
        CaseLogEntry(date: date, symptomIDs: ["fever"], outcomeRawValue: 1)
    }

    private func vitals(_ date: Date, temperature: Double = 38.0) -> VitalsEntry {
        VitalsEntry(date: date, temperature: temperature)
    }

    private func lab(_ date: Date, platelets: Double = 96, ns1: TestResult = .positive) -> LabReport {
        LabReport(date: date, platelets: platelets, ns1: ns1)
    }

    private func days(checks: [CaseLogEntry] = [],
                      vitals: [VitalsEntry] = [],
                      labs: [LabReport] = []) -> [HealthLogDay] {
        HealthLog.days(checks: checks, vitals: vitals, labs: labs, calendar: calendar)
    }

    // MARK: - Numbering

    private func numbers(checks: [CaseLogEntry] = [],
                         vitals: [VitalsEntry] = [],
                         labs: [LabReport] = []) -> [Date: Int] {
        HealthLog.numbers(for: days(checks: checks, vitals: vitals, labs: labs))
    }

    /// Numbers count from the oldest day, so a day keeps its number when a
    /// newer one arrives. Numbering the list as displayed would make "Log 3"
    /// a different day every morning.
    func testNumbersCountFromTheOldestDay() {
        let result = numbers(vitals: [vitals(at(12, 9)), vitals(at(10, 9)), vitals(at(11, 9))])
        XCTAssertEqual(result[at(10, 0)], 1)
        XCTAssertEqual(result[at(11, 0)], 2)
        XCTAssertEqual(result[at(12, 0)], 3)
    }

    func testANewerDayDoesNotRenumberTheOlderOnes() {
        let before = numbers(vitals: [vitals(at(10, 9))])
        let after = numbers(vitals: [vitals(at(10, 9)), vitals(at(12, 9))])
        XCTAssertEqual(before[at(10, 0)], after[at(10, 0)],
                       "recording another day must not move an older one")
    }

    /// Everything recorded on one day is one log, so a second reading that
    /// afternoon must not claim a number of its own.
    func testASecondRecordOnTheSameDayDoesNotTakeANewNumber() {
        let result = numbers(checks: [check(at(10, 8))],
                             vitals: [vitals(at(10, 9)), vitals(at(10, 21))],
                             labs: [lab(at(10, 12))])
        XCTAssertEqual(result.count, 1, "four records, one day, one number")
        XCTAssertEqual(result[at(10, 0)], 1)
    }

    /// The three kinds share one sequence of days: they are all records in
    /// one log, not three parallel logs.
    func testEveryKindSharesTheSameSequence() {
        let result = numbers(checks: [check(at(10, 8))],
                             vitals: [vitals(at(11, 9))],
                             labs: [lab(at(12, 10))])
        XCTAssertEqual(result[at(10, 0)], 1)
        XCTAssertEqual(result[at(11, 0)], 2)
        XCTAssertEqual(result[at(12, 0)], 3)
        XCTAssertEqual(Set(result.values).count, 3, "no two days share a number")
    }

    func testNothingRecordedIsNumberedNothing() {
        XCTAssertTrue(numbers().isEmpty)
    }

    func testNothingRecordedIsNoDays() {
        XCTAssertTrue(days().isEmpty)
    }

    func testEveryKindOfRecordSharesOneDay() {
        let result = days(checks: [check(at(10, 9))],
                          vitals: [vitals(at(10, 21))],
                          labs: [lab(at(10, 12))])
        XCTAssertEqual(result.count, 1, "one day, not one day per store")
        XCTAssertEqual(result[0].checks.count, 1)
        XCTAssertEqual(result[0].vitals.count, 1)
        XCTAssertEqual(result[0].labs.count, 1)
        XCTAssertEqual(result[0].itemsNewestFirst.count, 3)
    }

    func testALabReportOnItsOwnStillMakesADay() {
        let result = days(labs: [lab(at(10, 12))])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].checks.isEmpty)
        XCTAssertTrue(result[0].vitals.isEmpty)
    }

    func testLabsTakeTheirPlaceInTheDaysTimeOrder() {
        let result = days(checks: [check(at(10, 8))],
                          vitals: [vitals(at(10, 20))],
                          labs: [lab(at(10, 14))])
        XCTAssertEqual(result[0].itemsNewestFirst.map(\.date),
                       [at(10, 20), at(10, 14), at(10, 8)])
    }

    func testADayIsTheReadersCalendarDayNotTwentyFourHours() {
        // 11pm and 1am are different days even though they are two hours apart.
        let result = days(vitals: [vitals(at(10, 23)), vitals(at(11, 1))])
        XCTAssertEqual(result.count, 2)
    }

    func testDaysRunNewestFirst() {
        let result = days(checks: [check(at(8, 9)), check(at(12, 9)), check(at(10, 9))])
        XCTAssertEqual(result.map(\.date), [at(12, 0), at(10, 0), at(8, 0)])
    }

    func testWithinADayTheNewestRecordIsFirst() {
        let result = days(checks: [check(at(10, 8))],
                          vitals: [vitals(at(10, 20)), vitals(at(10, 14))])
        let times = result[0].itemsNewestFirst.map(\.date)
        XCTAssertEqual(times, [at(10, 20), at(10, 14), at(10, 8)])
    }

    func testAKindOfRecordMayBeMissingFromADay() {
        let result = days(checks: [check(at(10, 9))], vitals: [vitals(at(9, 9))])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].vitals.isEmpty, "a day with only a check is still a day")
        XCTAssertTrue(result[1].checks.isEmpty)
    }

    /// A gap is a day the reader wrote nothing down. Filling it with an empty
    /// row would read as "nothing was wrong that day", which is a claim the
    /// record cannot make.
    func testDaysWithNothingRecordedAreAbsentRatherThanEmpty() {
        let result = days(vitals: [vitals(at(10, 9)), vitals(at(14, 9))])
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { $0.isEmpty })
    }

    func testEveryItemKeepsTheIdentityOfItsOwnEntry() {
        // The view deletes by id, because a row's position in the merged log
        // says nothing about its index in either store.
        let c = check(at(10, 9))
        let v = vitals(at(10, 10))
        let l = lab(at(10, 11))
        let items = days(checks: [c], vitals: [v], labs: [l])[0].itemsNewestFirst
        XCTAssertEqual(Set(items.map(\.id)), [c.id, v.id, l.id])
    }
}
