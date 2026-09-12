import XCTest
import SwiftUI
@testable import DengueWatchBD

/// A shared card travels without the app, so a wrong number on one cannot be
/// corrected later. These tests are about what the card is allowed to claim.
@MainActor
final class AreaShareCardTests: XCTestCase {

    private func area(weeklyCases: [Int] = [100, 130],
                      populationThousands: Int = 1_000,
                      seasonCases: Int = 5_432) -> Area {
        Area(code: "TEST", name: "Testville", division: .dhaka,
             latitude: 23.8, longitude: 90.4,
             populationThousands: populationThousands,
             seasonCases: seasonCases, seasonDeaths: 7,
             weeklyCases: weeklyCases, weeklyIsApportioned: false,
             geofenceRadiusMeters: 12_000)
    }

    private func content(_ area: Area, updated: Date? = Date(timeIntervalSince1970: 1_789_000_000))
        -> AreaShareCard.Content {
        AreaShareCard.content(for: area, lastUpdated: updated, loc: LocalizationManager())
    }

    // MARK: - What the card says

    func testFiguresComeFromTheArea() {
        let result = content(area())
        XCTAssertEqual(result.areaName, "Testville")
        XCTAssertFalse(result.incidence.isEmpty)
        XCTAssertFalse(result.seasonCases.isEmpty)
    }

    func testTheRiskLabelMatchesTheAreasOwnBand() {
        // 230 cases in 1,000k over two weeks is 23/100k — High.
        let subject = area(weeklyCases: [100, 130])
        XCTAssertEqual(subject.risk, .high)
        XCTAssertEqual(content(subject).riskLabel, LocalizationManager().t(RiskLevel.high.labelKey))
    }

    func testWeeklyChangeIsOmittedWhenThereIsNoPreviousWeek() {
        // One week of data makes the ratio meaningless; the line disappears
        // rather than showing a zero or a dash that reads like a real figure.
        XCTAssertNil(content(area(weeklyCases: [120])).weeklyChange)
    }

    func testWeeklyChangeIsShownWhenItCanBeComputed() {
        XCTAssertNotNil(content(area(weeklyCases: [100, 130])).weeklyChange)
    }

    func testRiseAndFallAreDistinguished() {
        XCTAssertTrue(content(area(weeklyCases: [100, 130])).weeklyChangeIsUp)
        XCTAssertFalse(content(area(weeklyCases: [130, 100])).weeklyChangeIsUp)
    }

    // MARK: - Attribution

    /// The attribution is language-specific: English uses the acronym, Bengali
    /// spells the directorate out. Asserting one against both would only pass
    /// by accident, depending on the default language.
    func testTheSourceLineCreditsTheDirectorateInEachLanguage() {
        let loc = LocalizationManager()
        let expected: [AppLanguage: String] = [
            .english: "DGHS",
            .bangla: "স্বাস্থ্য অধিদপ্তর",
        ]
        for (language, needle) in expected {
            loc.language = language
            let line = AreaShareCard.content(for: area(),
                                             lastUpdated: Date(timeIntervalSince1970: 1_789_000_000),
                                             loc: loc).sourceLine
            XCTAssertTrue(line.contains(needle), "\(language.rawValue): \(line)")
            XCTAssertTrue(line.contains("·"), "the report date should follow the source: \(line)")
        }
    }

    func testAMissingDateStillCreditsTheSourceWithoutInventingOne() {
        let loc = LocalizationManager()
        for language in AppLanguage.allCases {
            loc.language = language
            let line = AreaShareCard.content(for: area(), lastUpdated: nil, loc: loc).sourceLine
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("·"), "no date means no date separator: \(line)")
        }
    }

    // MARK: - Rendering

    func testTheCardActuallyRasterises() {
        let card = AreaShareCard.view(content(area()), loc: LocalizationManager(), risk: .high)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        let image = renderer.uiImage
        XCTAssertNotNil(image, "ImageRenderer produced nothing")
        XCTAssertEqual(image?.size.width, ShareCardView.size.width)
        XCTAssertEqual(image?.size.height, ShareCardView.size.height)
    }

    func testTheRenderedImageIsNotBlank() {
        // A card that renders as an empty rectangle still "succeeds", so check
        // that something was actually drawn.
        let card = AreaShareCard.view(content(area()), loc: LocalizationManager(), risk: .severe)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            return XCTFail("no image")
        }
        XCTAssertGreaterThan(data.count, 10_000, "a 1080x1350 card should not be a few bytes")
    }

    func testItRendersInBothLanguages() {
        let loc = LocalizationManager()
        for language in AppLanguage.allCases {
            loc.language = language
            let subject = area()
            let card = AreaShareCard.view(
                AreaShareCard.content(for: subject, lastUpdated: Date(), loc: loc),
                loc: loc, risk: subject.risk)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 1
            XCTAssertNotNil(renderer.uiImage, "failed to render \(language.rawValue)")
        }
    }

    func testEveryKeyTheCardUsesExistsInBothLanguages() {
        let keys = ["share.button", "share.appName", "share.tagline",
                    "share.unit.incidence", "share.unit.season", "share.change",
                    "share.source", "share.sourceNoDate"]
        for key in keys {
            XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
            XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
        }
    }
}
