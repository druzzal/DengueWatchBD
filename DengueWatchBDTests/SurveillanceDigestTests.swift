import XCTest
@testable import DengueWatchBD

/// The digest states things about a dengue outbreak, so every rule here is
/// about not overclaiming.
final class SurveillanceDigestTests: XCTestCase {

    private func items(change: Double? = nil,
                       hotspots: Int = 0,
                       hasBreakdown: Bool = true,
                       rising: [(name: String, change: Double)] = []) -> [SurveillanceDigest.Item] {
        SurveillanceDigest.items(nationalChange: change,
                                 hotspotCount: hotspots,
                                 hasAreaBreakdown: hasBreakdown,
                                 risingAreas: rising)
    }

    private func kinds(_ items: [SurveillanceDigest.Item]) -> [SurveillanceDigest.Kind] {
        items.map(\.kind)
    }

    // MARK: - National direction

    func testAClearRiseIsReportedAsARise() {
        let item = try? XCTUnwrap(items(change: 0.31).first)
        XCTAssertEqual(item?.kind, .nationalRise)
        XCTAssertEqual(item?.arguments, ["31"], "the percentage is rounded, not invented")
    }

    func testAClearFallIsReportedAsAFall() {
        XCTAssertEqual(items(change: -0.22).first?.kind, .nationalFall)
        XCTAssertEqual(items(change: -0.22).first?.arguments, ["22"], "magnitude is unsigned in the sentence")
    }

    func testSmallMovesReadAsSteadyRatherThanATrend() {
        // Reporting-day wobble is not an outbreak signal. Calling a 2% move a
        // rise would cry wolf most weeks.
        for noise in [0.0, 0.02, -0.02, 0.05, -0.05] {
            XCTAssertEqual(items(change: noise).first?.kind, .nationalSteady, "\(noise)")
        }
    }

    func testTheBandIsExclusiveSoJustOverItCounts() {
        XCTAssertEqual(items(change: 0.051).first?.kind, .nationalRise)
        XCTAssertEqual(items(change: -0.051).first?.kind, .nationalFall)
    }

    func testAnAbsentChangeProducesNoNationalStatement() {
        // A missing previous week makes the ratio meaningless; say nothing.
        XCTAssertFalse(kinds(items(change: nil)).contains(where: {
            [.nationalRise, .nationalFall, .nationalSteady].contains($0)
        }))
    }

    // MARK: - Areas

    func testMissingAreaFiguresAreNotReportedAsZeroHighRiskAreas() {
        // The dangerous case: "no areas are high risk" is a reassurance, and an
        // empty breakdown must never be mistaken for one.
        let result = items(change: 0.3, hotspots: 0, hasBreakdown: false)
        XCTAssertTrue(kinds(result).contains(.noBreakdown))
        XCTAssertFalse(kinds(result).contains(.hotspots))
    }

    func testHotspotCountIsReportedWhenTheBreakdownExists() {
        XCTAssertEqual(items(hotspots: 12).first(where: { $0.kind == .hotspots })?.arguments, ["12"])
    }

    func testASingleHotspotUsesTheSingularSentence() {
        let one = items(hotspots: 1).first { $0.kind == .hotspots }
        let many = items(hotspots: 3).first { $0.kind == .hotspots }
        XCTAssertEqual(one?.key, "digest.hotspots.one")
        XCTAssertEqual(many?.key, "digest.hotspots.many")
    }

    func testZeroHotspotsIsStillStatedWhenTheBreakdownArrived() {
        // Genuinely zero is information, and differs from "we don't know".
        XCTAssertTrue(kinds(items(hotspots: 0, hasBreakdown: true)).contains(.hotspots))
    }

    // MARK: - Naming areas

    func testOnlyNotableRisesAreNamed() {
        let modest = items(rising: [("Sylhet", 0.05), ("Rangpur", 0.19)])
        XCTAssertFalse(kinds(modest).contains(.steepestRises), "a 19% move is not worth naming")
    }

    func testAtMostTwoAreasAreNamed() {
        let many = items(rising: [("Dhaka North", 0.9), ("Dhaka South", 0.8),
                                  ("Chattogram", 0.7), ("Khulna", 0.6)])
        let rises = try? XCTUnwrap(many.first { $0.kind == .steepestRises })
        XCTAssertEqual(rises?.arguments, ["Dhaka North", "Dhaka South"])
        XCTAssertEqual(rises?.key, "digest.rises.two")
    }

    func testOneNotableAreaUsesTheSingularSentence() {
        let rises = items(rising: [("Barishal", 0.44), ("Sylhet", 0.01)])
            .first { $0.kind == .steepestRises }
        XCTAssertEqual(rises?.key, "digest.rises.one")
        XCTAssertEqual(rises?.arguments, ["Barishal"])
    }

    func testOrderIsPreservedFromTheCaller() {
        let rises = items(rising: [("Khulna", 0.95), ("Rajshahi", 0.30)])
            .first { $0.kind == .steepestRises }
        XCTAssertEqual(rises?.arguments.first, "Khulna", "steepest is named first")
    }

    // MARK: - Shape

    func testNoDataAtAllStillSaysSomethingHonest() {
        let result = items(change: nil, hotspots: 0, hasBreakdown: false)
        XCTAssertEqual(kinds(result), [.noBreakdown])
    }

    func testItemsAreUniquelyIdentifiedForSwiftUI() {
        let result = items(change: 0.3, hotspots: 4, rising: [("Dhaka North", 0.5)])
        XCTAssertEqual(Set(result.map(\.id)).count, result.count, "duplicate ids would drop rows")
    }

    /// The build cannot catch this: "rose %@% nationwide" compiles fine and
    /// renders as "rose 25ationwide", because String(format:) eats the percent
    /// and the character after it. Only a rendered string shows it.
    @MainActor
    func testFormattedSentencesKeepTheirLiteralPercentSign() {
        let loc = LocalizationManager()
        for language in AppLanguage.allCases {
            loc.language = language
            for key in ["digest.national.rise", "digest.national.fall"] {
                let rendered = loc.t(key, arguments: ["25"])
                XCTAssertTrue(rendered.contains("25%"),
                              "\(language.rawValue)/\(key) lost its percent sign: \(rendered)")
                XCTAssertFalse(rendered.contains("25a") || rendered.contains("25 %"),
                               "\(language.rawValue)/\(key) mangled: \(rendered)")
            }
        }
    }

    func testEveryKeyUsedIsPresentInBothLanguages() {
        let all = items(change: 0.3, hotspots: 2, rising: [("A", 0.5), ("B", 0.4)])
            + items(change: -0.3, hotspots: 1)
            + items(change: 0.0)
            + items(hasBreakdown: false)
        for item in all {
            XCTAssertNotNil(Strings.english[item.key], "missing EN: \(item.key)")
            XCTAssertNotNil(Strings.bangla[item.key], "missing BN: \(item.key)")
        }
    }
}
