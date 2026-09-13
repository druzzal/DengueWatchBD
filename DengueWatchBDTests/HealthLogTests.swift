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

    private func days(checks: [CaseLogEntry] = [], vitals: [VitalsEntry] = []) -> [HealthLogDay] {
        HealthLog.days(checks: checks, vitals: vitals, calendar: calendar)
    }

    func testNothingRecordedIsNoDays() {
        XCTAssertTrue(days().isEmpty)
    }

    func testBothKindsOfRecordShareOneDay() {
        let result = days(checks: [check(at(10, 9))], vitals: [vitals(at(10, 21))])
        XCTAssertEqual(result.count, 1, "one day, not one day per store")
        XCTAssertEqual(result[0].checks.count, 1)
        XCTAssertEqual(result[0].vitals.count, 1)
        XCTAssertEqual(result[0].itemsNewestFirst.count, 2)
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
        let items = days(checks: [c], vitals: [v])[0].itemsNewestFirst
        XCTAssertEqual(Set(items.map(\.id)), [c.id, v.id])
    }
}
