import XCTest
@testable import DengueWatchBD

/// The checklist claims "you have done these things today". Every rule here is
/// about that claim staying true across days, restarts and clock changes.
@MainActor
final class PreventionChecklistTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "checklist.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = dayOfMonth
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - Basics

    func testANewChecklistStartsEmpty() {
        let list = PreventionChecklist(defaults: defaults)
        XCTAssertEqual(list.completedCount, 0)
        XCTAssertFalse(list.isComplete)
        XCTAssertEqual(list.fraction, 0)
    }

    func testTogglingMarksAndUnmarks() {
        let list = PreventionChecklist(defaults: defaults)
        list.toggle(.standingWater)
        XCTAssertTrue(list.isDone(.standingWater))
        list.toggle(.standingWater)
        XCTAssertFalse(list.isDone(.standingWater), "a mistaken tick must be undoable")
    }

    func testCompletingEveryTaskReportsComplete() {
        let list = PreventionChecklist(defaults: defaults)
        for task in PreventionTask.allCases { list.toggle(task) }
        XCTAssertTrue(list.isComplete)
        XCTAssertEqual(list.fraction, 1)
    }

    func testFractionTracksProgress() {
        let list = PreventionChecklist(defaults: defaults)
        list.toggle(.containers)
        XCTAssertEqual(list.fraction, 1.0 / Double(PreventionTask.allCases.count), accuracy: 0.0001)
    }

    // MARK: - Persistence

    func testTicksSurviveRelaunchOnTheSameDay() {
        // Must be the real today, not a fixed date: the initialiser compares
        // the stored day against the clock, so a hardcoded "today" makes this
        // test pass on one calendar day and fail on every other.
        let today = Date()
        let first = PreventionChecklist(defaults: defaults)
        first.toggle(.plantTrays, now: today)
        first.toggle(.storedWater, now: today)

        // A fresh instance is what the next launch builds.
        let second = PreventionChecklist(defaults: defaults)
        XCTAssertEqual(second.completedCount, 2)
        XCTAssertTrue(second.isDone(.plantTrays))
    }

    func testUnknownStoredTasksAreIgnoredRatherThanCrashing() {
        // A task removed in a later build must not break an older device.
        defaults.set(["standingWater", "someTaskFromAnotherVersion"],
                     forKey: "prevention.checklist.completed")
        defaults.set(Calendar.current.startOfDay(for: Date()),
                     forKey: "prevention.checklist.day")
        let list = PreventionChecklist(defaults: defaults)
        XCTAssertEqual(list.completedCount, 1)
        XCTAssertTrue(list.isDone(.standingWater))
    }

    // MARK: - The daily reset, which is the whole point

    func testYesterdaysTicksDoNotCountAsTodaysProtection() {
        let yesterday = day(2026, 9, 12)
        let today = day(2026, 9, 13)

        let list = PreventionChecklist(defaults: defaults)
        for task in PreventionTask.allCases { list.toggle(task, now: yesterday) }
        XCTAssertTrue(list.isComplete)

        list.refreshIfDayChanged(now: today)
        XCTAssertEqual(list.completedCount, 0, "a new day starts from nothing")
    }

    func testTheResetSurvivesTheAppBeingClosedOvernight() {
        let yesterday = day(2026, 9, 12)
        let first = PreventionChecklist(defaults: defaults)
        first.toggle(.containers, now: yesterday)

        // Rebuilt the next morning: loading alone must not resurrect them.
        let calendar = Calendar.current
        let second = PreventionChecklist(defaults: defaults, calendar: calendar)
        second.refreshIfDayChanged(now: day(2026, 9, 13))
        XCTAssertEqual(second.completedCount, 0)
    }

    func testTheSameDayAtADifferentHourIsStillTheSameDay() {
        var morning = DateComponents()
        morning.year = 2026; morning.month = 9; morning.day = 13; morning.hour = 7
        var night = morning; night.hour = 23
        let calendar = Calendar(identifier: .gregorian)

        let list = PreventionChecklist(defaults: defaults, calendar: calendar)
        list.toggle(.protection, now: calendar.date(from: morning)!)
        list.refreshIfDayChanged(now: calendar.date(from: night)!)
        XCTAssertTrue(list.isDone(.protection), "ticks must survive until midnight")
    }

    func testTogglingAfterMidnightClearsYesterdayFirst() {
        let yesterday = day(2026, 9, 12)
        let today = day(2026, 9, 13)
        let list = PreventionChecklist(defaults: defaults)
        list.toggle(.standingWater, now: yesterday)
        list.toggle(.plantTrays, now: yesterday)

        list.toggle(.containers, now: today)
        XCTAssertEqual(list.completedCount, 1, "only today's tick should remain")
        XCTAssertTrue(list.isDone(.containers))
        XCTAssertFalse(list.isDone(.standingWater))
    }

    // MARK: - Content

    func testEveryTaskHasTextInBothLanguages() {
        for task in PreventionTask.allCases {
            XCTAssertNotNil(Strings.english[task.titleKey], "missing EN: \(task.titleKey)")
            XCTAssertNotNil(Strings.bangla[task.titleKey], "missing BN: \(task.titleKey)")
        }
    }

    func testTheListStaysShortEnoughToActuallyDo() {
        // A daily chore list that grows stops being done at all.
        XCTAssertLessThanOrEqual(PreventionTask.allCases.count, 6)
    }
}
