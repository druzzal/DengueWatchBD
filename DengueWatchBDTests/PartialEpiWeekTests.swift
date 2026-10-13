import XCTest
@testable import DengueWatchBD

/// The weekly breakdown carries the EPI week in progress, and it must not be
/// read as a whole week.
///
/// On the live feed of 13 October, W41 held 6,314 cases — Sunday to Tuesday —
/// beside 12,713 for W40. Read as a week, that was a 50% fall in every area,
/// and a fortnight banded on ten days of cases.
final class PartialEpiWeekTests: XCTestCase {

    // MARK: - Area figures

    private func area(_ weeks: [Int], partial: Bool) -> Area {
        Area(code: "TEST", name: "Test", division: .barishal,
             latitude: 22.7, longitude: 90.35, populationThousands: 1_000,
             seasonCases: weeks.reduce(0, +), seasonDeaths: 0,
             weeklyCases: weeks, weeklyIsApportioned: false,
             geofenceRadiusMeters: 55_000, latestWeekIsPartial: partial)
    }

    func testAnOpenWeekIsLeftOutOfTheFigures() {
        let a = area([300, 300, 90], partial: true)
        XCTAssertEqual(a.lastWeekCases, 300)
        XCTAssertEqual(a.previousWeekCases, 300)
        XCTAssertEqual(a.recentCases, 600)
        XCTAssertEqual(a.weeklyChange ?? .nan, 0, accuracy: 0.0001,
                       "three days against seven is not a fall")
        XCTAssertEqual(a.risk, .severe, "60/100k over the last complete fortnight")
        XCTAssertEqual(a.recentWeeks(12), [300, 300])
        XCTAssertEqual(a.weeklyCases, [300, 300, 90], "the chart still draws the open week")
    }

    func testAClosedWeekCountsInFull() {
        let a = area([300, 300, 90], partial: false)
        XCTAssertEqual(a.lastWeekCases, 90)
        XCTAssertEqual(a.recentCases, 390)
        XCTAssertEqual(a.weeklyChange ?? .nan, -0.7, accuracy: 0.0001)
    }

    // MARK: - Detecting the open week

    /// Daily cases of 100 from Sunday 4 October, so a week is 700.
    private func document(dailyThrough lastDay: Int, weeks: [(String, Int)]) throws -> FeedDocument {
        let days = (4...lastDay).map { String(format: "%02d-Oct-26", $0) }
        let categories = days.map { "\"\($0)\"" }.joined(separator: ",")
        let values = days.map { _ in "100" }.joined(separator: ",")
        let weekNames = weeks.map { "\"\($0.0)\"" }.joined(separator: ",")
        let weekValues = weeks.map { String($0.1) }.joined(separator: ",")
        let json = """
        {"schema_version":1,"fetched_at":"2026-10-13T19:00:00Z",
         "meta":{"source_url":"https://example.org","source_name":"DGHS",
                 "last_updated_label":"\(days.last!)","last_updated":"2026-10-\(lastDay)","year":2026},
         "summary":{"ytd_cases":1000,"ytd_deaths":0},
         "charts":{
           "confirmed_case":{"title":"by date","categories":[\(categories)],
             "series":[{"name":"Affected","type":"column","data":[\(values)]}]},
           "div_city_cor_case_in_year":{"title":"cases","categories":["Barishal"],
             "series":[{"name":"Admitted","type":"column","data":[1000]}]},
           "affected_in_division_by_week":{"title":"weekly","categories":[\(weekNames)],
             "series":[{"name":"Barisal","data":[\(weekValues)]}]}
         },
         "tables":[]}
        """
        return try FeedDecoder.document(from: Data(json.utf8))
    }

    @MainActor
    private func barishal(_ document: FeedDocument) async throws -> Area {
        let store = DengueStore()
        await store.apply(document: document, source: .bundled)
        return try XCTUnwrap(store.area(code: "BARISHAL"))
    }

    /// Tuesday's report: W41 holds Sunday to Tuesday.
    @MainActor
    func testAMidweekReportOpensTheLastWeek() async throws {
        let doc = try document(dailyThrough: 13, weeks: [("W40", 700), ("W41", 300)])
        let a = try await barishal(doc)
        XCTAssertTrue(a.latestWeekIsPartial)
        XCTAssertEqual(a.lastWeekCases, 700)
    }

    /// Saturday's report closes the week.
    @MainActor
    func testASaturdayReportClosesTheWeek() async throws {
        let doc = try document(dailyThrough: 10, weeks: [("W40", 700)])
        let a = try await barishal(doc)
        XCTAssertFalse(a.latestWeekIsPartial)
        XCTAssertEqual(a.lastWeekCases, 700)
    }

    /// A weekly table that has not caught up with the daily one ends on a
    /// complete week, and dropping it would throw away the newest real week.
    @MainActor
    func testALaggingWeeklyTableIsNotMistakenForAnOpenWeek() async throws {
        let doc = try document(dailyThrough: 13, weeks: [("W39", 650), ("W40", 700)])
        let a = try await barishal(doc)
        XCTAssertFalse(a.latestWeekIsPartial)
        XCTAssertEqual(a.lastWeekCases, 700)
    }

    // MARK: - Compact numbers at a unit boundary

    func testCompactNumbersMoveUpAUnitRatherThanPrintAHundredOfTheOldOne() {
        let en = NumberStyle(language: .english)
        let bn = NumberStyle(language: .bangla)
        XCTAssertEqual(en.compact(999_600), "1.0M")
        XCTAssertEqual(en.compact(999_400), "999k")
        XCTAssertEqual(bn.compact(99_600), "১.০ লাখ")
        XCTAssertEqual(bn.compact(99_400), "৯৯ হাজার")
        XCTAssertEqual(bn.compact(9_996_000), "১.০ কোটি")
        XCTAssertEqual(bn.compact(1_500), "১.৫ হাজার", "the map legend's smallest circle")
        XCTAssertEqual(bn.compact(6_600), "৬.৬ হাজার")
    }
}
