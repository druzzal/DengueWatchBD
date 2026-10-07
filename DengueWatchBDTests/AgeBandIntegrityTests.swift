import XCTest
@testable import DengueWatchBD

/// The age table, against the feed that actually ships.
///
/// Every fault this guards against has happened. DGHS's sheet spells one band
/// two ways, carries rows that span the bands they cover, turns "6-10" into an
/// Excel date serial, leaves a label blank, and counts cases whose sex was
/// never filled in. Each of those reached the card before it was caught: as a
/// row listed twice, as the largest band vanishing, as a one-case group
/// sitting beside thousands, and as every row quietly printing a smaller
/// number than its source.
///
/// So these do not test a fixture. They parse the shipped feed and reconcile
/// what the card shows against what DGHS published, which is the only check
/// that catches a kind of dirt nobody has thought of yet.
@MainActor
final class AgeBandIntegrityTests: XCTestCase {

    private func feedDocument() throws -> FeedDocument {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "dengue-feed", withExtension: "json"),
            "the bundled feed is missing from the app")
        return try FeedDecoder.document(from: Data(contentsOf: url))
    }

    private func store() async throws -> DengueStore {
        let store = DengueStore()
        await store.apply(document: try feedDocument(), source: .bundled)
        return store
    }

    /// The season table as DGHS wrote it, so the tests can compare against the
    /// source rather than against themselves.
    private func sourceRows() throws -> [(label: String, male: Int, female: Int, total: Int)] {
        let document = try feedDocument()
        let table = try XCTUnwrap(document.tables.first {
            ($0.title ?? "").localizedCaseInsensitiveContains("affected cases from 1 January")
        })
        return table.rows.compactMap { row in
            guard let label = row["Age Group"]?.text else { return nil }
            return (label,
                    row["Male"]?.number ?? 0,
                    row["Female"]?.number ?? 0,
                    row["Total"]?.number ?? 0)
        }
    }

    // MARK: - No duplication

    func testNoTwoBandsShareAnIdentity() async throws {
        let ids = try await store().ageBandsCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count,
                       "a ForEach given one id twice draws one row twice and drops another")
    }

    func testNoTwoBandsCoverTheSameAges() async throws {
        let bands = try await store().ageBandsCases
        for band in bands {
            for other in bands where other != band {
                XCTAssertFalse(band.spans(other),
                               "\(band.id) covers \(other.id); they cannot both be rows")
            }
        }
    }

    func testBandsReadInAscendingAgeOrder() async throws {
        let lows = try await store().ageBandsCases.map(\.lowerAge)
        XCTAssertEqual(lows, lows.sorted(), "the source sorts its rows as text; the card must not")
        XCTAssertEqual(Set(lows).count, lows.count, "two bands starting at the same age is a duplicate")
    }

    // MARK: - Aligned with the source

    /// Each band prints the number DGHS published for it, not a number the app
    /// worked out. Recomputing the total as male plus female dropped every
    /// case whose sex was never recorded.
    func testEachBandMatchesThePublishedTotal() async throws {
        let bands = try await store().ageBandsCases
        let rows = try sourceRows()

        for band in bands {
            let expected = rows
                .filter { row in
                    guard let range = Self.rangeOf(row.label) else { return false }
                    return range.0 == band.lowerAge && range.1 == band.upperAge
                }
                .reduce(0) { $0 + $1.total }
            XCTAssertEqual(band.total, expected,
                           "band \(band.id) prints \(band.total), DGHS published \(expected)")
        }
    }

    func testTheSexesNeverExceedTheBandTheyAreIn() async throws {
        for band in try await store().ageBandsCases {
            XCTAssertLessThanOrEqual(band.male + band.female, band.total,
                                     "band \(band.id) has more sexed cases than cases")
            XCTAssertEqual(band.unrecordedSex, band.total - band.male - band.female)
        }
    }

    /// The whole point: nothing DGHS counted may go missing unnoticed. Every
    /// case is either in a band on the card or in a row the app deliberately
    /// refused, and the two together must come to the published grand total.
    func testEveryPublishedCaseIsEitherShownOrDeliberatelyDropped() async throws {
        let shown = try await store().ageBandsCases.reduce(0) { $0 + $1.total }
        let rows = try sourceRows()

        let grandTotal = rows.first { $0.label == "Grand Total" }?.total ?? 0
        XCTAssertGreaterThan(grandTotal, 0, "the source has no grand total to reconcile against")

        let body = rows.filter { $0.label != "Grand Total" }
        let published = body.reduce(0) { $0 + $1.total }
        XCTAssertEqual(published, grandTotal,
                       "DGHS's own rows no longer add up to its own total")

        let dropped = published - shown
        XCTAssertGreaterThanOrEqual(dropped, 0, "the card shows more cases than were published")

        // Dirt is a rounding error on a season; anything more is a parsing
        // fault dressed up as bad data.
        XCTAssertLessThan(Double(dropped) / Double(published), 0.01,
                          "\(dropped) of \(published) cases are not on the card — too many to be stray rows")
    }

    private static func rangeOf(_ label: String) -> (Int, Int?)? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("+"), let low = Int(trimmed.dropLast()) { return (low, nil) }
        let parts = trimmed.split(separator: "-")
        guard parts.count == 2, let low = Int(parts[0]), let high = Int(parts[1]),
              low <= high, high <= 120 else { return nil }
        return (low, high)
    }
}
