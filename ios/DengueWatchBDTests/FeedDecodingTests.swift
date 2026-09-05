import XCTest
@testable import DengueWatchBD

/// Decoding the published feed.
///
/// The traps here are real ones the feed actually contains, not hypotheticals:
/// two different shapes for a chart point, a death series whose dates do not
/// line up with the case series, and age tables carrying rows where a date got
/// typed into the age column.
final class FeedDecodingTests: XCTestCase {

    // MARK: - Fixtures

    /// Structurally complete but small. Mirrors the real feed's quirks exactly.
    private var documentJSON: Data {
        Data("""
        {"schema_version":1,"fetched_at":"2026-09-05T19:04:58Z",
         "meta":{"source_url":"https://example.org","source_name":"DGHS",
                 "last_updated_label":"05-Sep-2026","last_updated":"2026-09-05","year":2026},
         "summary":{"epi_week":"W35","week_cases":7446,"week_deaths":23,
                    "ytd_cases":300,"ytd_deaths":6,"last24_cases":988,"last24_deaths":2,
                    "discharged_last24":986,"discharged_ytd":38179},
         "charts":{
           "confirmed_case":{"title":"by date","categories":["01-Jan-26","02-Jan-26","03-Jan-26"],
             "series":[{"name":"Affected","type":"column","data":[10,null,20]}]},
           "death_case":{"title":"deaths","categories":["03-Jan-26"],
             "series":[{"name":"Death","type":"column","data":[4]}]},
           "div_city_cor_case_in_year":{"title":"cases","categories":["Barishal","Dhaka (Out of CC)","DNCC","DSCC"],
             "series":[{"name":"Admitted","type":"column","data":[100,60,80,60]}]},
           "div_city_cor_death_in_year":{"title":"deaths","categories":["Barishal","Dhaka (Out of CC)","DNCC","DSCC"],
             "series":[{"name":"Death","type":"column","data":[2,1,2,1]}]},
           "affected_in_division_by_week":{"title":"weekly","categories":["W01","W02"],
             "series":[{"name":"Barisal","data":[40,60]},{"name":"Dhaka","data":[100,100]}]},
           "year_case":{"title":"years","categories":["2025","2026"],
             "series":[{"name":"Affected","type":"column","data":[102861,300]}]},
           "dengue_affected_by_gender":{"title":"sex","categories":[],
             "series":[{"name":"Brands","data":[{"name":"Male","y":180},{"name":"Female","y":120}]}]}
         },
         "tables":[
           {"title":"Age group distribution of affected cases from 1 January to till date in 2026",
            "headers":["Age Group","Male","Female","Total"],
            "rows":[{"Age Group":"0-5","Male":30,"Female":20,"Total":50},
                    {"Age Group":"42309","Male":1,"Female":1,"Total":2},
                    {"Age Group":"","Male":1,"Female":0,"Total":1},
                    {"Age Group":"80+","Male":2,"Female":1,"Total":3},
                    {"Age Group":"Grand Total","Male":34,"Female":22,"Total":56}]}
         ]}
        """.utf8)
    }

    private func decoded() throws -> FeedDocument {
        try FeedDecoder.document(from: documentJSON)
    }

    // MARK: - Wire format

    func testDecodesSnakeCaseHeadline() throws {
        let summary = try FeedDecoder.summary(from: Data("""
        {"schema_version":1,"fetched_at":"2026-09-05T19:04:58Z","last_updated":"2026-09-05",
         "year":2026,"summary":{"epi_week":"W35","week_cases":7446,"week_deaths":23,
         "ytd_cases":41032,"ytd_deaths":113,"last24_cases":988,"last24_deaths":2,
         "discharged_last24":986,"discharged_ytd":38179}}
        """.utf8))
        XCTAssertEqual(summary.lastUpdated, "2026-09-05")
        XCTAssertEqual(summary.summary.ytdCases, 41032)
        XCTAssertEqual(summary.summary.last24Cases, 988)
        XCTAssertEqual(summary.summary.dischargedYtd, 38179)
    }

    /// Highcharts emits bare numbers for columns and `{name, y}` for pies. Both
    /// appear in the same document, so both have to decode.
    func testDecodesBothPointShapes() throws {
        let document = try decoded()
        XCTAssertEqual(document.chart(.dailyCases)?.series.first?.values, [10, 0, 20])
        let sex = document.chart(.casesByGender)?.series.first?.labelled
        XCTAssertEqual(sex?.first?.name, "Male")
        XCTAssertEqual(sex?.first?.value, 180)
    }

    func testRejectsUnsupportedSchemaVersion() {
        let future = Data(#"{"schema_version":99,"meta":{},"summary":{},"charts":{},"tables":[]}"#.utf8)
        XCTAssertThrowsError(try FeedDecoder.document(from: future)) { error in
            guard case FeedError.unsupportedSchema(let version) = error else {
                return XCTFail("expected unsupportedSchema, got \(error)")
            }
            XCTAssertEqual(version, 99)
        }
    }

    // MARK: - Mapping

    /// The regression this guards: cases are published for every day of the
    /// season, deaths only for days a death occurred. Zipping the two by index
    /// files deaths under the wrong dates — here it would put 4 deaths on
    /// 01-Jan instead of 03-Jan.
    @MainActor
    func testDeathsAreJoinedByDateNotByIndex() async throws {
        let store = DengueStore()
        await store.apply(document: try decoded(), source: .bundled)

        XCTAssertEqual(store.national.count, 3)
        XCTAssertEqual(store.national.map(\.cases), [10, 0, 20])
        XCTAssertEqual(store.national.map(\.deaths), [0, 0, 4],
                       "the single death entry belongs on 03-Jan, its own date")
    }

    @MainActor
    func testAreaTotalsMatchTheFeed() async throws {
        let store = DengueStore()
        await store.apply(document: try decoded(), source: .bundled)

        XCTAssertEqual(store.areas.count, Geography.definitions.count)
        let barishal = try XCTUnwrap(store.area(code: "BARISHAL"))
        XCTAssertEqual(barishal.seasonCases, 100)
        XCTAssertEqual(barishal.seasonDeaths, 2)
        XCTAssertEqual(barishal.weeklyCases, [40, 60])
        XCTAssertFalse(barishal.weeklyIsApportioned)

        // An area the feed does not mention must read as zero, not crash.
        XCTAssertEqual(store.area(code: "SYLHET")?.seasonCases, 0)
    }

    /// Dhaka's three feed rows share one weekly series. Splitting it by season
    /// share must preserve the division's weekly total — otherwise the map and
    /// the national roll-up disagree.
    @MainActor
    func testDhakaApportionmentPreservesTheDivisionTotal() async throws {
        let store = DengueStore()
        await store.apply(document: try decoded(), source: .bundled)

        let dhaka = store.areas.filter { $0.division == .dhaka }
        XCTAssertEqual(dhaka.count, 3)
        XCTAssertTrue(dhaka.allSatisfy(\.weeklyIsApportioned))

        // Season cases 60 / 80 / 60 of 200 against a division series of [100, 100].
        for week in 0..<2 {
            let shared = dhaka.reduce(0) { $0 + ($1.weeklyCases[safe: week] ?? 0) }
            XCTAssertEqual(shared, 100, "week \(week) must still sum to the division's figure")
        }
    }

    /// DGHS's age tables carry rows where a date was typed into the age column
    /// ("42309", an Excel serial) and blank rows. Neither is an age band.
    @MainActor
    func testAgeBandsDropSourceGlitches() async throws {
        let store = DengueStore()
        await store.apply(document: try decoded(), source: .bundled)

        XCTAssertEqual(store.ageBandsCases.map(\.label), ["0-5", "80+"])
        XCTAssertEqual(store.ageBandsCases.first?.total, 50)
    }

    @MainActor
    func testHeadlineFiguresComeFromTheSummaryBlock() async throws {
        let store = DengueStore()
        await store.apply(document: try decoded(), source: .bundled)

        XCTAssertEqual(store.seasonCases, 300)
        XCTAssertEqual(store.seasonDeaths, 6)
        XCTAssertEqual(store.cases24h, 988)
        XCTAssertEqual(store.epiWeekLabel, "W35")
        XCTAssertEqual(store.sexSplitCases?.male, 180)
    }

    // MARK: - Risk

    func testRiskBandsAreCalibratedForATwoWeekWindow() {
        XCTAssertEqual(RiskLevel(incidencePer100k: 0.3), .low)
        XCTAssertEqual(RiskLevel(incidencePer100k: 4.9), .low)
        XCTAssertEqual(RiskLevel(incidencePer100k: 5), .moderate)
        XCTAssertEqual(RiskLevel(incidencePer100k: 26.1), .high)
        XCTAssertEqual(RiskLevel(incidencePer100k: 60), .severe)
    }

    // MARK: - The dataset actually shipped

    /// The bundled seed has to decode with the same code that reads a download,
    /// or the app's first launch shows an error before it ever reaches network.
    @MainActor
    func testBundledSeedDecodesAndPopulatesEveryArea() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "dengue-feed", withExtension: "json"),
                                "dengue-feed.json is missing from the app bundle")
        let document = try FeedDecoder.document(from: try Data(contentsOf: url))

        let store = DengueStore()
        await store.apply(document: document, source: .bundled)

        XCTAssertEqual(store.areas.count, 10)
        XCTAssertGreaterThan(store.seasonCases, 0)
        XCTAssertFalse(store.national.isEmpty)
        XCTAssertFalse(store.epiWeeks.isEmpty)

        // The feed's own area breakdown sums to its national headline; if that
        // stops holding, the map and the dashboard are telling different stories.
        let areaTotal = store.areas.reduce(0) { $0 + $1.seasonCases }
        XCTAssertEqual(areaTotal, store.seasonCases)
        let deathTotal = store.areas.reduce(0) { $0 + $1.seasonDeaths }
        XCTAssertEqual(deathTotal, store.seasonDeaths)
    }

    /// Every string the UI asks for must exist in both languages.
    func testLocalizationParity() {
        XCTAssertEqual(Strings.missingBanglaKeys, [])
    }
}
