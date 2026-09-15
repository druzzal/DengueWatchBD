import XCTest
@testable import DengueWatchBD

/// What gets accepted into a vital-sign field.
///
/// The rule these tests hold down is that a field is either empty, or good, or
/// refused — never silently dropped. Dropping is the dangerous outcome: a
/// reader who types 395 for 39.5 and is not stopped saves an entry with no
/// temperature in it and every reason to believe they recorded a fever.
final class VitalsInputTests: XCTestCase {

    private func read(_ text: String, _ kind: VitalKind,
                      _ unit: TemperatureUnit = .celsius) -> VitalsInput.Reading {
        VitalsInput.read(text, as: kind, unit: unit)
    }

    // MARK: - Nothing typed

    func testAnEmptyFieldIsNotAProblem() {
        XCTAssertEqual(read("", .pulse), .empty)
        XCTAssertFalse(read("", .pulse).isProblem, "every field is optional")
    }

    func testWhitespaceAloneIsEmpty() {
        XCTAssertEqual(read("   ", .pulse), .empty)
    }

    // MARK: - Not numbers

    func testLettersAreRefused() {
        XCTAssertEqual(read("ninety", .pulse), .notANumber)
        XCTAssertEqual(read("98.6f", .temperature), .notANumber)
    }

    func testATypoWithTwoDecimalPointsIsRefused() {
        // Reachable on the decimal pad, and "39.5.5" is not a temperature.
        XCTAssertEqual(read("39.5.5", .temperature), .notANumber)
    }

    func testInfinityAndNaNAreRefused() {
        // Double("inf") and Double("nan") both parse. Neither is a reading.
        XCTAssertEqual(read("inf", .pulse), .notANumber)
        XCTAssertEqual(read("nan", .pulse), .notANumber)
    }

    func testAnEmptyDecimalPointIsRefused() {
        XCTAssertEqual(read(".", .pulse), .notANumber)
    }

    // MARK: - Numbers nobody could measure

    func testAWildlyHighPulseIsRefused() {
        guard case .outOfRange = read("900", .pulse) else {
            return XCTFail("900 bpm is not a pulse")
        }
    }

    func testANegativeReadingIsRefused() {
        guard case .outOfRange = read("-5", .pulse) else {
            return XCTFail("a pulse cannot be negative")
        }
    }

    func testZeroIsRefused() {
        guard case .outOfRange = read("0", .systolic) else {
            return XCTFail("nobody records a systolic of zero")
        }
    }

    func testOxygenSaturationAboveOneHundredIsRefused() {
        guard case .outOfRange = read("101", .oxygenSaturation) else {
            return XCTFail("saturation cannot exceed 100%")
        }
    }

    /// The classic decimal-point slip, and the reason this exists.
    func testTheMissingDecimalPointIsRefusedRatherThanDropped() {
        guard case .outOfRange = read("395", .temperature) else {
            return XCTFail("395 must be refused, not quietly discarded")
        }
    }

    // MARK: - Readings that are alarming but real

    /// The range is deliberately wide. A reading that is frightening is exactly
    /// the one worth keeping, so validation must not become a second opinion.
    func testAnAlarmingButPossibleReadingIsAccepted() {
        XCTAssertEqual(read("41.5", .temperature), .value(41.5))
        XCTAssertEqual(read("210", .pulse), .value(210))
        XCTAssertEqual(read("55", .oxygenSaturation), .value(55))
        XCTAssertEqual(read("250", .systolic), .value(250))
    }

    func testTheEdgesOfTheRangeAreAccepted() {
        XCTAssertEqual(read("25", .pulse), .value(25))
        XCTAssertEqual(read("220", .pulse), .value(220))
    }

    // MARK: - Temperature units

    func testFahrenheitIsCheckedInFahrenheitAndStoredInCelsius() throws {
        let reading = read("98.6", .temperature, .fahrenheit)
        let celsius = try XCTUnwrap(reading.storedValue)
        XCTAssertEqual(celsius, 37, accuracy: 0.05, "stored in Celsius")
    }

    /// 39.5 is an ordinary fever in Celsius and far too cold to be a person in
    /// Fahrenheit. Checking against the wrong unit's range would accept one of
    /// those and refuse the other.
    func testTheRangeFollowsTheUnitOnScreen() {
        XCTAssertEqual(read("39.5", .temperature, .celsius), .value(39.5))
        guard case .outOfRange = read("39.5", .temperature, .fahrenheit) else {
            return XCTFail("39.5°F is not a body temperature")
        }
    }

    func testTheRangeQuotedBackIsInTheUnitTyped() {
        guard case .outOfRange(let range) = read("500", .temperature, .fahrenheit) else {
            return XCTFail("expected a range")
        }
        XCTAssertEqual(range, TemperatureUnit.fahrenheit.plausibleRange,
                       "a reader typing °F must be told the °F range")
    }

    // MARK: - Separators

    /// Both separators are typed in Bangladesh; refusing one as "not a number"
    /// would be pedantry rather than safety.
    func testACommaWorksAsADecimalPoint() {
        XCTAssertEqual(read("38,5", .temperature), .value(38.5))
    }

    func testSurroundingSpaceIsIgnored() {
        XCTAssertEqual(read("  72  ", .pulse), .value(72))
    }

    // MARK: - The shape the form relies on

    func testOnlyGoodReadingsCarryAValue() {
        XCTAssertNil(read("abc", .pulse).storedValue)
        XCTAssertNil(read("900", .pulse).storedValue)
        XCTAssertNil(read("", .pulse).storedValue)
        XCTAssertEqual(read("72", .pulse).storedValue, 72)
    }

    func testOnlyRefusalsCountAsProblems() {
        XCTAssertTrue(read("abc", .pulse).isProblem)
        XCTAssertTrue(read("900", .pulse).isProblem)
        XCTAssertFalse(read("", .pulse).isProblem)
        XCTAssertFalse(read("72", .pulse).isProblem)
    }

    func testEveryKindRefusesSomething() {
        // No field may be left unguarded.
        for kind in VitalKind.allCases {
            XCTAssertTrue(read("banana", kind).isProblem, "\(kind) accepted letters")
            XCTAssertTrue(read("99999", kind).isProblem, "\(kind) accepted 99999")
        }
    }
}
