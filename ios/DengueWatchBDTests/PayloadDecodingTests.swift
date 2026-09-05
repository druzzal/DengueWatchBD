import XCTest
@testable import DengueWatchBD

/// Decoding the two shapes the server publishes.
///
/// The `latest` block is optional, and its absence carries meaning: it is
/// omitted precisely when the press-release series has caught up. So both
/// shapes are real, and both have to decode — a build that could only read one
/// of them would break on an ordinary day.
final class PayloadDecodingTests: XCTestCase {

    // MARK: - Fixtures

    /// Small but structurally complete: two dates, one district, matching
    /// series lengths, exactly as the pipeline emits.
    private func payloadJSON(includingLatest: Bool) -> Data {
        let latest = """
        ,"latest":{"reportDate":"2026-09-05","seasonCases":41032,\
        "seasonDeaths":113,"cases24h":988,"deaths24h":2,\
        "source":"DGHS dashboard","seriesAsOf":"2026-09-03"}
        """
        let json = """
        {"meta":{"datasetName":"DGHS daily dengue press releases, 2026 season",\
        "isSampleData":false,"disclaimer":"d","attribution":"a",\
        "seasonStart":"2026-01-19","lastUpdated":"2026-09-03","year":2026},\
        "dates":["2026-09-02","2026-09-03"],\
        "national":{"cases":[1110,1252],"deaths":[4,2],"admitted":[900,950]},\
        "districts":[{"code":"DHAKA","name":"Dhaka","division":"Dhaka",\
        "latitude":23.81,"longitude":90.41,"populationThousands":10000,\
        "cases":[400,420],"deaths":[1,0]}],\
        "history":[{"year":2026,"cases":39532,"deaths":111,"verified":true}]\
        \(includingLatest ? latest : "")}
        """
        return Data(json.utf8)
    }

    private func decode(includingLatest: Bool) throws -> SurveillancePayload {
        try JSONDecoder().decode(SurveillancePayload.self,
                                 from: payloadJSON(includingLatest: includingLatest))
    }

    // MARK: - Dashboard ahead of the series

    func testLatestBlockDecodesWhenPresent() throws {
        let payload = try decode(includingLatest: true)
        let latest = try XCTUnwrap(payload.latest,
                                   "the block was in the JSON and must survive decoding")
        XCTAssertEqual(latest.reportDate, "2026-09-05")
        XCTAssertEqual(latest.seasonCases, 41032)
        XCTAssertEqual(latest.seasonDeaths, 113)
        XCTAssertEqual(latest.source, "DGHS dashboard")
    }

    func testSeriesAsOfIsOlderThanTheHeadline() throws {
        let latest = try XCTUnwrap(try decode(includingLatest: true).latest)
        XCTAssertEqual(latest.seriesAsOf, "2026-09-03")
        XCTAssertLessThan(latest.seriesAsOf, latest.reportDate,
                          "the block exists only when the series trails the headline")
    }

    func testTheSeriesItselfIsUntouchedByTheBlock() throws {
        let payload = try decode(includingLatest: true)
        XCTAssertEqual(payload.dates.last, "2026-09-03",
                       "the newer national figure must not be appended to the series")
        XCTAssertEqual(payload.national.cases.count, payload.dates.count)
        for district in payload.districts {
            XCTAssertEqual(district.cases.count, payload.dates.count,
                           "district arrays must stay parallel to dates")
            XCTAssertEqual(district.deaths.count, payload.dates.count)
        }
    }

    func testOptionalTwentyFourHourFiguresSurvive() throws {
        let latest = try XCTUnwrap(try decode(includingLatest: true).latest)
        XCTAssertEqual(latest.cases24h, 988)
        XCTAssertEqual(latest.deaths24h, 2)
    }

    // MARK: - PDFs caught up

    func testPayloadWithoutLatestDecodes() throws {
        let payload = try decode(includingLatest: false)
        XCTAssertNil(payload.latest,
                     "no block is the healthy case, not a decoding failure")
        XCTAssertEqual(payload.dates.count, 2)
        XCTAssertEqual(payload.history.first?.cases, 39532)
    }

    func testAbsentBlockStillLeavesAUsablePayload() throws {
        let payload = try decode(includingLatest: false)
        XCTAssertEqual(payload.national.cases, [1110, 1252])
        XCTAssertEqual(payload.districts.first?.name, "Dhaka")
    }

    // MARK: - Partial and malformed blocks

    func testBlockMissingOptionalFiguresStillDecodes() throws {
        let json = """
        {"meta":{"datasetName":"n","isSampleData":false,"disclaimer":"d",\
        "attribution":"a","seasonStart":"2026-01-19","lastUpdated":"2026-09-03",\
        "year":2026},"dates":["2026-09-03"],\
        "national":{"cases":[1],"deaths":[0],"admitted":[0]},"districts":[],\
        "history":[],\
        "latest":{"reportDate":"2026-09-05","seasonCases":41032,\
        "seasonDeaths":113,"source":"DGHS dashboard","seriesAsOf":"2026-09-03"}}
        """
        let payload = try JSONDecoder().decode(SurveillancePayload.self, from: Data(json.utf8))
        let latest = try XCTUnwrap(payload.latest)
        XCTAssertNil(latest.cases24h, "an absent 24h figure is unknown, not zero")
        XCTAssertNil(latest.deaths24h)
        XCTAssertEqual(latest.seasonCases, 41032)
    }

    func testBlockMissingARequiredFieldFailsRatherThanDecodingHalfway() {
        // seasonCases removed. Decoding a partial headline would put a wrong
        // total on screen, so failing is the correct outcome.
        let json = """
        {"meta":{"datasetName":"n","isSampleData":false,"disclaimer":"d",\
        "attribution":"a","seasonStart":"2026-01-19","lastUpdated":"2026-09-03",\
        "year":2026},"dates":["2026-09-03"],\
        "national":{"cases":[1],"deaths":[0],"admitted":[0]},"districts":[],\
        "history":[],\
        "latest":{"reportDate":"2026-09-05","seasonDeaths":113,\
        "source":"DGHS dashboard","seriesAsOf":"2026-09-03"}}
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(SurveillancePayload.self, from: Data(json.utf8))
        )
    }
}
