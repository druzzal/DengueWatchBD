import XCTest
@testable import DengueWatchBD

/// The names a reader gives to days of their record.
///
/// A name belongs to the day, not to any one reading in it, so the store is
/// keyed by the start of the day. The risks are a name drifting off its day
/// when the reading was taken at an odd hour, and a name outliving the day
/// whose records were deleted — where it would reappear on an unrelated day
/// that later happens to reuse the number.
@MainActor
final class LogNameStoreTests: XCTestCase {

    private func store() -> LogNameStore {
        LogNameStore(filename: "log-names-\(UUID().uuidString).json")
    }

    private var calendar: Calendar { Calendar.current }

    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    func testADayWithoutANameHasNone() {
        XCTAssertNil(store().name(for: at(10, 9)), "an unnamed day falls back to its number")
    }

    func testANamedDayKeepsItsName() {
        let names = store()
        names.rename(day: at(10, 9), to: "Clinic visit")
        XCTAssertEqual(names.name(for: at(10, 9)), "Clinic visit")
    }

    /// Every reading in a day answers to the day's name, whatever hour it was
    /// taken at — that is the whole point of naming the day rather than a row.
    func testAnyHourOfTheDayFindsTheSameName() {
        let names = store()
        names.rename(day: at(10, 9), to: "Clinic visit")
        XCTAssertEqual(names.name(for: at(10, 6)), "Clinic visit")
        XCTAssertEqual(names.name(for: at(10, 23)), "Clinic visit")
    }

    func testNamingOneDayLeavesTheNextUnnamed() {
        let names = store()
        names.rename(day: at(10, 9), to: "Clinic visit")
        XCTAssertNil(names.name(for: at(11, 9)))
    }

    /// Clearing the field puts the day back to "Log 3" rather than leaving a
    /// blank row the reader cannot tell apart from its neighbours.
    func testClearingTheNameRestoresTheNumber() {
        let names = store()
        names.rename(day: at(10, 9), to: "Clinic visit")
        names.rename(day: at(10, 9), to: "")
        XCTAssertNil(names.name(for: at(10, 9)))
    }

    func testANameOfNothingButSpacesIsNoName() {
        let names = store()
        names.rename(day: at(10, 9), to: "   ")
        XCTAssertNil(names.name(for: at(10, 9)))
    }

    func testSurroundingSpaceIsTrimmedFromAName() {
        let names = store()
        names.rename(day: at(10, 9), to: "  Clinic visit  ")
        XCTAssertEqual(names.name(for: at(10, 9)), "Clinic visit")
    }

    /// Deleting a day's records deletes its name too. Otherwise the name would
    /// wait in the file and reattach itself if the reader ever recorded
    /// something on that date again.
    func testForgettingADayRemovesItsName() {
        let names = store()
        names.rename(day: at(10, 9), to: "Clinic visit")
        names.forget(day: at(10, 14))
        XCTAssertNil(names.name(for: at(10, 9)))
    }

    func testForgettingOneDayLeavesTheOthersNamed() {
        let names = store()
        names.rename(day: at(10, 9), to: "Clinic visit")
        names.rename(day: at(11, 9), to: "Back home")
        names.forget(day: at(10, 9))
        XCTAssertEqual(names.name(for: at(11, 9)), "Back home")
    }

    func testClearingRemovesEveryName() {
        let names = store()
        names.rename(day: at(10, 9), to: "Clinic visit")
        names.rename(day: at(11, 9), to: "Back home")
        names.clear()
        XCTAssertNil(names.name(for: at(10, 9)))
        XCTAssertNil(names.name(for: at(11, 9)))
    }

    func testANameSurvivesBeingReopened() {
        let filename = "log-names-\(UUID().uuidString).json"
        LogNameStore(filename: filename).rename(day: at(10, 9), to: "Clinic visit")
        XCTAssertEqual(LogNameStore(filename: filename).name(for: at(10, 9)), "Clinic visit")
    }
}
