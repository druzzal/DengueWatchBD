import CoreLocation
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
             "series":[{"name":"Barisal","data":[40,60]},{"name":"Dhaka","data":[100,101]}]},
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

        // Season cases 60 / 80 / 60 of 200 against a division series of [100, 101].
        // The second week is the one that matters: 101 does not divide cleanly,
        // so rounding each share on its own yields 30 + 40 + 30 = 100 and loses
        // a case. Largest remainder has to place it.
        for (week, divisionTotal) in [(0, 100), (1, 101)] {
            let shared = dhaka.reduce(0) { $0 + ($1.weeklyCases[safe: week] ?? 0) }
            XCTAssertEqual(shared, divisionTotal,
                           "week \(week) must sum to the division's own figure")
        }
    }

    /// The property the area page promises: the parts always add back up.
    func testApportionmentIsExactAcrossAwkwardSplits() {
        for value in [0, 1, 7, 99, 101, 1165, 7446] {
            for weights in [[6017, 4895, 5400], [1, 1, 1], [1, 0, 0], [3, 5, 7, 11]] {
                let parts = Series.apportion(value, across: weights)
                XCTAssertEqual(parts.reduce(0, +), value,
                               "\(value) across \(weights) must not drift")
                XCTAssertTrue(parts.allSatisfy { $0 >= 0 })
            }
        }
        // A weightless split cannot invent a distribution.
        XCTAssertEqual(Series.apportion(10, across: [0, 0]), [0, 0])
        XCTAssertEqual(Series.apportion(10, across: []), [])
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
        XCTAssertEqual(store.headline?.epiWeek, "W35")
        XCTAssertEqual(store.sexSplitCases?.male, 180)
    }

    /// A feed whose area breakdown is missing or renamed must produce no areas,
    /// so the map can say so. Ten places reporting zero beside a national total
    /// of 300 would be worse than an empty state.
    @MainActor
    func testMissingAreaBreakdownYieldsNoAreas() async throws {
        let stripped = Data("""
        {"schema_version":1,"fetched_at":"2026-09-05T19:04:58Z",
         "meta":{"last_updated":"2026-09-05","year":2026},
         "summary":{"ytd_cases":300,"ytd_deaths":6},
         "charts":{"div_city_cor_case_in_year":{"title":"renamed","categories":["Something Else"],
                    "series":[{"name":"Admitted","data":[10]}]}},
         "tables":[]}
        """.utf8)

        let store = DengueStore()
        await store.apply(document: try FeedDecoder.document(from: stripped), source: .bundled)

        XCTAssertTrue(store.areas.isEmpty, "unrecognised categories are not ten zeroes")
        XCTAssertEqual(store.seasonCases, 300, "the national headline still stands")
        XCTAssertEqual(store.nationalRisk, .low)
        XCTAssertEqual(store.nationalIncidencePer100k, 0)
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

        // Against the real feed, independent rounding missed the Dhaka
        // division's weekly figure in 9 weeks out of 35. Check every week of
        // the shipped data, not a fixture chosen to divide cleanly.
        let divisionWeeks = try XCTUnwrap(
            document.chart(.divisionCasesByWeek)?.series(named: "Dhaka")?.values)
        let dhaka = store.areas.filter { $0.weeklyIsApportioned }
        XCTAssertEqual(dhaka.count, 3)
        for week in divisionWeeks.indices {
            let shared = dhaka.reduce(0) { $0 + ($1.weeklyCases[safe: week] ?? 0) }
            XCTAssertEqual(shared, divisionWeeks[week],
                           "week \(week + 1) drifted from the division's own figure")
        }
        XCTAssertEqual(dhaka.reduce(0) { $0 + Series.sum($1.weeklyCases) },
                       divisionWeeks.reduce(0, +),
                       "the season must not drift either")
    }

    /// Every string the UI asks for must exist in both languages.
    func testLocalizationParity() {
        XCTAssertEqual(Strings.missingBanglaKeys, [])
    }

    // MARK: - Entry alerts survive a background relaunch

    /// The alert has to be composable from disk alone.
    ///
    /// When iOS relaunches the app because the device crossed a boundary, the
    /// feed has not loaded and no view exists. Everything the notification says
    /// must therefore come from the snapshot written when the geofences were
    /// armed — otherwise the alert silently fails in exactly the case it is for.
    @MainActor
    func testWatchedAreaSnapshotRoundTripsWithoutTheStore() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "geofence.snapshot.test"))
        defaults.removePersistentDomain(forName: "geofence.snapshot.test")

        let store = DengueStore()
        await store.apply(document: try FeedDecoder.document(
            from: try Data(contentsOf: try XCTUnwrap(
                Bundle.main.url(forResource: "dengue-feed", withExtension: "json")))),
                          source: .bundled)

        let hotspots = store.hotspots
        XCTAssertFalse(hotspots.isEmpty, "the shipped feed has areas in the high band")

        WatchedAreaStore.save(hotspots.map(WatchedArea.init), to: defaults)
        let restored = WatchedAreaStore.load(from: defaults)
        XCTAssertEqual(restored.count, hotspots.count)

        // Everything the notification needs, with the store out of the picture.
        for area in hotspots {
            let watched = try XCTUnwrap(WatchedAreaStore.area(code: area.code, in: defaults))
            XCTAssertEqual(watched.name, area.name)
            XCTAssertEqual(watched.risk, area.risk)
            XCTAssertGreaterThanOrEqual(watched.risk, .high)
            XCTAssertEqual(watched.lastWeekCases, area.lastWeekCases)
            // The Bengali name is resolved by code at fire time, not stored.
            XCTAssertFalse(PlaceNames.area(code: watched.code,
                                           fallback: watched.name,
                                           language: .bangla).isEmpty)
        }

        WatchedAreaStore.clear(defaults)
        XCTAssertTrue(WatchedAreaStore.load(from: defaults).isEmpty)
        defaults.removePersistentDomain(forName: "geofence.snapshot.test")
    }

    // MARK: - Where the user is

    /// Nearest-centroid alone put Shillong (75 km from the Sylhet centre) and
    /// Kolkata (121 km from Khulna's) inside Bangladesh, while St Martin's
    /// Island — genuinely Bangladeshi — sits 198 km from Chattogram's. No
    /// distance threshold separates those, which is why containment is tested.
    func testContainmentAcceptsBangladeshAndRejectsNeighbours() {
        let inside = [("Dhaka", 23.78, 90.40), ("Teknaf", 20.90, 92.30),
                      ("Tetulia", 26.55, 88.40), ("Sundarbans", 21.90, 89.20),
                      ("Sylhet town", 24.90, 91.87)]
        for (name, lat, lon) in inside {
            XCTAssertTrue(Geography.containsBangladesh(latitude: lat, longitude: lon),
                          "\(name) is in Bangladesh")
        }

        let outside = [("Kolkata", 22.57, 88.36), ("Shillong", 25.57, 91.88),
                       ("Yangon", 16.87, 96.20), ("Dubai", 25.20, 55.27),
                       ("Kathmandu", 27.72, 85.32)]
        for (name, lat, lon) in outside {
            XCTAssertFalse(Geography.containsBangladesh(latitude: lat, longitude: lon),
                           "\(name) is not in Bangladesh")
        }
    }

    /// Dhaka's three areas share one metro, so nearest-centroid put Savar in
    /// DNCC by 0.5 km and sent Gazipur, Tongi, Narayanganj and Keraniganj into
    /// city corporations they are outside. The corporations read High while the
    /// rest of the division reads Moderate, so that was a band error shown to a
    /// reader standing somewhere else entirely.
    @MainActor
    func testDhakaMetroResolvesToTheRightArea() async throws {
        let store = DengueStore()
        await store.apply(document: try FeedDecoder.document(
            from: try Data(contentsOf: try XCTUnwrap(
                Bundle.main.url(forResource: "dengue-feed", withExtension: "json")))),
                          source: .bundled)

        let expected: [(String, Double, Double, String)] = [
            ("Mirpur",      23.806, 90.369, "DNCC"),
            ("Uttara",      23.874, 90.400, "DNCC"),
            ("Gulshan",     23.792, 90.414, "DNCC"),
            ("Dhanmondi",   23.746, 90.376, "DNCC"),
            ("Motijheel",   23.733, 90.417, "DSCC"),
            ("Old Dhaka",   23.710, 90.400, "DSCC"),
            ("Jatrabari",   23.710, 90.435, "DSCC"),
            ("Savar",       23.858, 90.266, "DHAKA_OUT_CC"),
            ("Gazipur",     23.999, 90.420, "DHAKA_OUT_CC"),
            ("Tongi",       23.890, 90.405, "DHAKA_OUT_CC"),
            ("Narayanganj", 23.623, 90.500, "DHAKA_OUT_CC"),
            ("Keraniganj",  23.700, 90.360, "DHAKA_OUT_CC"),
            ("Manikganj",   23.861, 90.000, "DHAKA_OUT_CC"),
        ]

        for (name, lat, lon, code) in expected {
            let here = CLLocation(latitude: lat, longitude: lon)
            XCTAssertEqual(store.nearestArea(to: here)?.code, code, "\(name)")
        }
    }

    /// Outside Dhaka the centroid is still the right tool.
    @MainActor
    func testAreasOutsideDhakaStillResolveByCentre() async throws {
        let store = DengueStore()
        await store.apply(document: try FeedDecoder.document(
            from: try Data(contentsOf: try XCTUnwrap(
                Bundle.main.url(forResource: "dengue-feed", withExtension: "json")))),
                          source: .bundled)

        let expected: [(String, Double, Double, Division)] = [
            ("Chattogram city", 22.356, 91.783, .chattogram),
            ("Cox's Bazar",     21.427, 92.005, .chattogram),
            ("Khulna city",     22.845, 89.540, .khulna),
            ("Sylhet city",     24.895, 91.869, .sylhet),
            ("Rangpur city",    25.744, 89.275, .rangpur),
            ("Barishal city",   22.701, 90.353, .barishal),
        ]
        for (name, lat, lon, division) in expected {
            let here = CLLocation(latitude: lat, longitude: lon)
            XCTAssertEqual(store.nearestArea(to: here)?.division, division, "\(name)")
        }
    }

    @MainActor
    func testNearestAreaNamesAnAreaOnlyInsideTheCountry() async throws {
        let store = DengueStore()
        await store.apply(document: try decoded(), source: .bundled)

        let dhaka = CLLocation(latitude: 23.78, longitude: 90.40)
        XCTAssertEqual(store.nearestArea(to: dhaka)?.division, .dhaka)

        // Closer to the Khulna centre than St Martin's is to Chattogram's, and
        // still not in Bangladesh.
        let kolkata = CLLocation(latitude: 22.57, longitude: 88.36)
        XCTAssertNil(store.nearestArea(to: kolkata))
    }
}
