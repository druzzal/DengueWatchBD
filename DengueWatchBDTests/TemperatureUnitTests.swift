import XCTest
@testable import DengueWatchBD

/// Temperatures are stored in Celsius and shown in whatever the reader picked.
/// The tests that matter are the ones proving storage never changes meaning.
final class TemperatureUnitTests: XCTestCase {

    // MARK: - Conversion

    func testKnownFixedPoints() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.toCelsius(98.6), 37, accuracy: 0.01)
        XCTAssertEqual(TemperatureUnit.fahrenheit.toCelsius(212), 100, accuracy: 0.01)
        XCTAssertEqual(TemperatureUnit.fahrenheit.toCelsius(32), 0, accuracy: 0.01)
        XCTAssertEqual(TemperatureUnit.celsius.fromCelsius(37), 37, accuracy: 0.01)
        XCTAssertEqual(TemperatureUnit.fahrenheit.fromCelsius(37), 98.6, accuracy: 0.01)
    }

    func testAFeverConvertsBothWays() {
        // 38.5°C is 101.3°F — a number a Bangladeshi home thermometer shows.
        XCTAssertEqual(TemperatureUnit.fahrenheit.fromCelsius(38.5), 101.3, accuracy: 0.05)
        XCTAssertEqual(TemperatureUnit.fahrenheit.toCelsius(101.3), 38.5, accuracy: 0.05)
    }

    func testConversionRoundTripsWithoutDrift() {
        for celsius in stride(from: 30.0, through: 45.0, by: 0.1) {
            let round = TemperatureUnit.fahrenheit.toCelsius(
                TemperatureUnit.fahrenheit.fromCelsius(celsius))
            XCTAssertEqual(round, celsius, accuracy: 0.0001)
        }
    }

    func testCelsiusIsAPassThrough() {
        XCTAssertEqual(TemperatureUnit.celsius.toCelsius(38.5), 38.5)
        XCTAssertEqual(TemperatureUnit.celsius.fromCelsius(38.5), 38.5)
    }

    // MARK: - Storage stays Celsius

    func testTypingInFahrenheitStoresCelsius() {
        // The whole safety property: what is saved does not depend on the unit
        // the reader happened to have selected when reading it back.
        let stored = TemperatureUnit.fahrenheit.celsiusValue(from: "101.3")
        XCTAssertEqual(try XCTUnwrap(stored), 38.5, accuracy: 0.05)
    }

    func testTypingInCelsiusStoresTheSameNumber() {
        XCTAssertEqual(try XCTUnwrap(TemperatureUnit.celsius.celsiusValue(from: "38.5")),
                       38.5, accuracy: 0.001)
    }

    func testAnEntryWrittenBeforeUnitsExistedStillReadsAsAFever() {
        // Logs written earlier are Celsius. Displaying one in Fahrenheit must
        // convert it, never relabel it: 38.5 shown as "38.5°F" would be 3.6°C.
        let legacy = 38.5
        XCTAssertEqual(TemperatureUnit.celsius.display(celsius: legacy), "38.5°C")
        XCTAssertEqual(TemperatureUnit.fahrenheit.display(celsius: legacy), "101.3°F")
    }

    // MARK: - Rejecting what is not a temperature

    func testAFahrenheitNumberTypedUnderCelsiusIsRejected() {
        // The common slip. 101 is a fever in Fahrenheit and a fatal reading in
        // Celsius, so it must not be silently stored.
        XCTAssertNil(TemperatureUnit.celsius.celsiusValue(from: "101"))
    }

    func testACelsiusNumberTypedUnderFahrenheitIsRejected() {
        XCTAssertNil(TemperatureUnit.fahrenheit.celsiusValue(from: "38.5"))
    }

    func testGenuineExtremesAreStillAccepted() {
        // Hypothermia and hyperpyrexia both happen; the guard must not reject
        // a real emergency reading.
        XCTAssertNotNil(TemperatureUnit.celsius.celsiusValue(from: "30"))
        XCTAssertNotNil(TemperatureUnit.celsius.celsiusValue(from: "45"))
        XCTAssertNotNil(TemperatureUnit.fahrenheit.celsiusValue(from: "86"))
        XCTAssertNotNil(TemperatureUnit.fahrenheit.celsiusValue(from: "113"))
    }

    func testNonsenseIsRejectedRatherThanStoredAsZero() {
        for text in ["", " ", "abc", "-", "37.5.5", "1e9"] {
            XCTAssertNil(TemperatureUnit.celsius.celsiusValue(from: text), text)
        }
    }

    func testACommaDecimalIsAccepted() {
        // Some keyboards produce a comma; rejecting it would look like the app
        // ignoring a perfectly good reading.
        XCTAssertEqual(try XCTUnwrap(TemperatureUnit.celsius.celsiusValue(from: "38,5")),
                       38.5, accuracy: 0.001)
    }

    func testSurroundingSpacesAreTolerated() {
        XCTAssertNotNil(TemperatureUnit.celsius.celsiusValue(from: "  38.5 "))
    }

    // MARK: - Display and content

    func testDisplayShowsOneDecimalAndTheUnit() {
        XCTAssertEqual(TemperatureUnit.celsius.display(celsius: 38.456), "38.5°C")
        XCTAssertTrue(TemperatureUnit.fahrenheit.display(celsius: 37).hasSuffix("°F"))
    }

    func testBothUnitsAreNamedInBothLanguages() {
        for unit in TemperatureUnit.allCases {
            XCTAssertNotNil(Strings.english[unit.labelKey], "missing EN: \(unit.labelKey)")
            XCTAssertNotNil(Strings.bangla[unit.labelKey], "missing BN: \(unit.labelKey)")
        }
        for key in ["temp.unit.label", "temp.outOfRange"] {
            XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
            XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
        }
    }
}

/// Unit labels are looked up with the no-argument `t(_:)`, which does not run
/// String(format:). An escaped `%%` there is rendered literally.
@MainActor
final class UnitLabelTests: XCTestCase {
    func testUnitLabelsAreNotFormatEscaped() {
        let loc = LocalizationManager()
        for language in AppLanguage.allCases {
            loc.language = language
            for kind in VitalKind.allCases {
                let label = loc.t(kind.unitKey)
                XCTAssertFalse(label.contains("%%"),
                               "\(language.rawValue)/\(kind.unitKey) renders as \(label)")
            }
        }
    }

    func testOxygenSaturationShowsASinglePercentSign() {
        let loc = LocalizationManager()
        for language in AppLanguage.allCases {
            loc.language = language
            XCTAssertEqual(loc.t(VitalKind.oxygenSaturation.unitKey), "%", language.rawValue)
        }
    }
}
