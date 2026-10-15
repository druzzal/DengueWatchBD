import XCTest
import PDFKit
@testable import DengueWatchBD

/// Which way a reading strayed, and carrying a typed temperature across units.
final class MeasureSideTests: XCTestCase {

    // MARK: - Low, normal, high

    func testTheUsualRangeIsInclusiveAtBothEnds() {
        XCTAssertEqual(MeasureSide.of(36.1, usual: 36.1...37.8), .normal)
        XCTAssertEqual(MeasureSide.of(37.8, usual: 36.1...37.8), .normal)
        XCTAssertEqual(MeasureSide.of(36.0, usual: 36.1...37.8), .low)
        XCTAssertEqual(MeasureSide.of(37.9, usual: 36.1...37.8), .high)
    }

    func testVitalSignsSayWhichWay() {
        XCTAssertEqual(VitalKind.temperature.side(39.2), .high, "a fever")
        XCTAssertEqual(VitalKind.temperature.side(35.8), .low)
        XCTAssertEqual(VitalKind.temperature.side(37.0), .normal)
        XCTAssertEqual(VitalKind.pulse.side(124), .high)
        XCTAssertEqual(VitalKind.oxygenSaturation.side(93), .low)
    }

    func testLabValuesSayWhichWay() {
        XCTAssertEqual(LabMeasure.platelets.side(40), .low, "the number dengue turns on")
        XCTAssertEqual(LabMeasure.platelets.side(250), .normal)
        XCTAssertEqual(LabMeasure.haematocrit.side(56), .high)
    }

    func testBloodPressureTakesTheHalfThatStrayedFurther() {
        XCTAssertEqual(MeasureSide.bloodPressure(systolic: 118, diastolic: 76).side, .normal)
        XCTAssertEqual(MeasureSide.bloodPressure(systolic: 150, diastolic: 80).side, .high)
        // Systolic a little high, diastolic far low: the diastolic is the story.
        XCTAssertEqual(MeasureSide.bloodPressure(systolic: 140, diastolic: 50).side, .low)
        // Both equally out: systolic wins the tie.
        XCTAssertEqual(MeasureSide.bloodPressure(systolic: 140, diastolic: 58).side, .high)
    }

    // MARK: - Switching the unit carries the reading across

    func testATypedCelsiusReadingBecomesFahrenheit() {
        let en = NumberStyle(language: .english)
        XCTAssertEqual(TemperatureUnit.celsius.retyped("38.5", in: .fahrenheit, style: en), "101.3")
        XCTAssertEqual(TemperatureUnit.fahrenheit.retyped("101.3", in: .celsius, style: en), "38.5")
    }

    func testBengaliDigitsGoInAndComeOutBengali() {
        let bn = NumberStyle(language: .bangla)
        XCTAssertEqual(TemperatureUnit.celsius.retyped("৩৮.৫", in: .fahrenheit, style: bn), "১০১.৩")
    }

    /// A Fahrenheit number typed under °C is not a Celsius temperature, so it
    /// is left alone: switching to °F is exactly what fixes it.
    func testANumberThatIsNoTemperatureInTheOldUnitIsLeftAlone() {
        let en = NumberStyle(language: .english)
        XCTAssertNil(TemperatureUnit.celsius.retyped("101", in: .fahrenheit, style: en))
        XCTAssertNil(TemperatureUnit.celsius.retyped("", in: .fahrenheit, style: en))
        XCTAssertNil(TemperatureUnit.celsius.retyped("abc", in: .fahrenheit, style: en))
    }

    /// Flipping back and forth must not walk the reading away from what was
    /// typed.
    func testFlippingTwiceReturnsWhatWasTyped() {
        let en = NumberStyle(language: .english)
        for tenths in 350...420 {
            let typed = en.decimal(Double(tenths) / 10, places: 1)
            let there = TemperatureUnit.celsius.retyped(typed, in: .fahrenheit, style: en)
            let back = there.flatMap { TemperatureUnit.fahrenheit.retyped($0, in: .celsius, style: en) }
            XCTAssertEqual(back, typed, "\(typed)°C → \(there ?? "nil")°F → \(back ?? "nil")°C")
        }
    }

    // MARK: - The printed log says it

    @MainActor
    func testThePrintedLogSaysWhichWayEachReadingWent() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.set("en", forKey: "appLanguage")
        defer { defaults.removePersistentDomain(forName: #function) }

        let vitals = [VitalsEntry(date: Date(), temperature: 39.4, pulse: 80,
                                  systolic: 118, diastolic: 76)]
        let labs = [LabReport(date: Date(), platelets: 40)]
        let url = try XCTUnwrap(HealthLogPDF.write(days: HealthLog.days(vitals: vitals, labs: labs),
                                                   loc: LocalizationManager(defaults: defaults),
                                                   unit: .celsius))
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try XCTUnwrap(PDFDocument(url: url)?.string)

        XCTAssertTrue(text.contains("39.4"), text)
        XCTAssertTrue(text.contains("High"), "the fever: \(text)")
        XCTAssertTrue(text.contains("Low"), "the platelet count: \(text)")
        XCTAssertTrue(text.contains("Normal"), text)
        XCTAssertTrue(text.contains("Usual 36.1–37.8"), "the range the word was judged on: \(text)")
        XCTAssertTrue(text.contains("Page 1 of 1"), text)
    }
}
