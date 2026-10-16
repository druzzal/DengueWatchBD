import XCTest
@testable import DengueWatchBD

/// How old a report is, in the calendar days the feed dates it by — the same
/// count Android makes, so the two apps say "yesterday" about the same report.
@MainActor
final class ReportAgeTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dhaka")!
        return calendar
    }

    private func day(_ value: String) throws -> Date {
        try XCTUnwrap(FeedDate.iso(from: value))
    }

    func testAReportIsTodayYesterdayOrSomeDaysOld() throws {
        let loc = LocalizationManager()
        let report = try day("2026-10-16")
        let noonOn = { (d: String) in try self.day(d).addingTimeInterval(12 * 3600) }

        XCTAssertEqual(loc.reportAge(report, now: try noonOn("2026-10-16"), calendar: calendar),
                       loc.t("common.today").lowercased(with: loc.style.locale))
        XCTAssertEqual(loc.reportAge(report, now: try noonOn("2026-10-17"), calendar: calendar),
                       loc.t("common.yesterday").lowercased(with: loc.style.locale))
        let fiveDays = loc.reportAge(report, now: try noonOn("2026-10-21"), calendar: calendar)
        XCTAssertTrue(fiveDays.contains(loc.num(5)), fiveDays)
    }

    func testEarlyTheNextMorningIsStillYesterday() throws {
        // Four in the morning on the 17th is under 24 hours after the
        // report's midnight, and still "yesterday" — not "22 hours ago".
        let loc = LocalizationManager()
        let report = try day("2026-10-16")
        XCTAssertEqual(loc.reportAge(report, now: try day("2026-10-17").addingTimeInterval(4 * 3600),
                                     calendar: calendar),
                       loc.t("common.yesterday").lowercased(with: loc.style.locale))
    }
}
