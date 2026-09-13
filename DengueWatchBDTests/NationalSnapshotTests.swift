import XCTest
@testable import DengueWatchBD

/// The snapshot's whole job is to keep "we don't know" distinct from "zero".
/// Almost every test here is a zero that must not be printed, or a zero that
/// must be.
final class NationalSnapshotTests: XCTestCase {

    private let day = 24.0 * 60 * 60

    private func series(_ counts: [Int], deaths: [Int]? = nil) -> [DailyPoint] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return counts.enumerated().map { index, cases in
            DailyPoint(date: start.addingTimeInterval(Double(index) * day),
                       cases: cases,
                       deaths: deaths?[safe: index] ?? 0)
        }
    }

    private func headline(ytdCases: Int? = nil, ytdDeaths: Int? = nil,
                          last24Cases: Int? = nil, last24Deaths: Int? = nil) -> FeedHeadline {
        FeedHeadline(epiWeek: nil, weekCases: nil, weekDeaths: nil,
                     ytdCases: ytdCases, ytdDeaths: ytdDeaths,
                     last24Cases: last24Cases, last24Deaths: last24Deaths,
                     dischargedLast24: nil, dischargedYtd: nil)
    }

    private func area(code: String, weeklyCases: [Int], populationThousands: Int) -> Area {
        Area(code: code, name: code, division: .dhaka,
             latitude: 23.8, longitude: 90.4,
             populationThousands: populationThousands,
             seasonCases: weeklyCases.reduce(0, +), seasonDeaths: 0,
             weeklyCases: weeklyCases, weeklyIsApportioned: false,
             geofenceRadiusMeters: 12000)
    }

    private func snapshot(headline: FeedHeadline? = nil,
                          national: [DailyPoint] = [],
                          areas: [Area] = []) -> NationalSnapshot {
        NationalSnapshot.from(headline: headline, national: national,
                              areas: areas, lastUpdated: nil)
    }

    // MARK: - Nothing at all

    func testAnEmptyFeedKnowsNothing() {
        let result = snapshot()
        XCTAssertFalse(result.hasAnything)
        XCTAssertNil(result.seasonCases, "an empty series is not a season of no cases")
        XCTAssertNil(result.last24Cases)
        XCTAssertNil(result.last24Deaths)
        XCTAssertNil(result.highRiskAreas)
    }

    // MARK: - The hotspot denominator

    func testNoAreaBreakdownIsNotZeroHotspots() {
        // The screen must say nothing rather than "0 high-risk areas".
        XCTAssertNil(snapshot(areas: []).highRiskAreas)
    }

    func testNoAreaAtHighRiskIsARealZero() {
        let calm = [area(code: "KHULNA", weeklyCases: [0, 0], populationThousands: 9000)]
        XCTAssertEqual(snapshot(areas: calm).highRiskAreas, 0,
                       "a quiet week is news; it must not be hidden")
    }

    func testTheDenominatorIsTheFeedsAreasNotSixtyFour() {
        // Regression: the caption read "of 64", the number of districts in
        // Bangladesh. This feed reports divisions and Dhaka's city
        // corporations — ten areas — and has no district breakdown at all.
        let areas = (0..<3).map { area(code: "A\($0)", weeklyCases: [0, 0],
                                       populationThousands: 1000) }
        XCTAssertEqual(snapshot(areas: areas).reportingAreas, 3)
    }

    // MARK: - Deaths

    func testAMissingDeathsFigureIsNotNoDeaths() {
        // "0 deaths" reads as good news. Not receiving the figure is not news.
        let result = snapshot(headline: headline(last24Cases: 988), national: [])
        XCTAssertEqual(result.last24Cases, 988)
        XCTAssertNil(result.last24Deaths)
    }

    func testAReportedZeroDeathsIsKept() {
        let result = snapshot(headline: headline(last24Cases: 988, last24Deaths: 0))
        XCTAssertEqual(result.last24Deaths, 0)
    }

    func testAMissingSeasonDeathsFigureIsNotZeroDeaths() {
        XCTAssertNil(snapshot().seasonDeaths)
        XCTAssertNil(snapshot(headline: headline(ytdCases: 41032)).seasonDeaths,
                     "a headline that omits deaths has not reported none")
    }

    func testSeasonDeathsPrefersTheHeadlineThenSumsTheSeries() {
        XCTAssertEqual(snapshot(headline: headline(ytdDeaths: 113)).seasonDeaths, 113)
        // The daily series carries a row only for days a death occurred, so
        // summing it gives the season total.
        let counts = [10, 20, 30]
        XCTAssertEqual(snapshot(national: series(counts, deaths: [1, 0, 2])).seasonDeaths, 3)
    }

    func testAReportedZeroSeasonDeathsIsKept() {
        XCTAssertEqual(snapshot(headline: headline(ytdDeaths: 0)).seasonDeaths, 0)
    }

    // MARK: - Where each figure comes from

    func testTheHeadlineOutranksTheSeries() {
        // DGHS's own summary block is the figure of record.
        let result = snapshot(headline: headline(ytdCases: 41032, last24Cases: 988),
                              national: series([10, 20, 30]))
        XCTAssertEqual(result.seasonCases, 41032)
        XCTAssertEqual(result.last24Cases, 988)
    }

    func testTheSeriesFillsInWhatTheHeadlineOmits() {
        let result = snapshot(headline: headline(ytdCases: nil),
                              national: series([10, 20, 30]))
        XCTAssertEqual(result.seasonCases, 60)
    }

    // MARK: - Weekly change

    func testWeeklyChangeNeedsAnEarlierWeekToCompareWith() {
        // Three days into a season there is no "last week", and 0 → 40 is not
        // "up 100%".
        XCTAssertNil(snapshot(national: series([10, 20, 10])).weeklyChange)
    }

    func testWeeklyChangeComparesTheTwoWeeks() {
        let counts = Array(repeating: 10, count: 7) + Array(repeating: 20, count: 7)
        let result = snapshot(national: series(counts))
        XCTAssertEqual(result.weekCases, 140)
        XCTAssertEqual(result.weeklyChange ?? 0, 1.0, accuracy: 0.0001)
    }

    func testWeekCasesIsNilWithNoSeriesButZeroIsKeptWhenReported() {
        XCTAssertNil(snapshot().weekCases)
        XCTAssertEqual(snapshot(national: series([0, 0, 0])).weekCases, 0)
    }
}
