import XCTest
@testable import DengueWatchBD

/// What gets accepted into a vital-sign field.
///
/// The rule these tests hold down is that a field is either empty, or good, or
/// refused — never silently dropped. Dropping is the dangerous outcome: a
/// reader who types 395 for 39.5 and is not stopped saves an entry with no
/// temperature in it and every reason to believe they recorded a fever.
final class MeasureInputTests: XCTestCase {

    private func read(_ text: String, _ kind: VitalKind,
                      _ unit: TemperatureUnit = .celsius) -> MeasureInput.Reading {
        MeasureInput.read(text, as: kind, unit: unit)
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

    /// A comma groups digits in Bangladesh; it does not separate the decimal.
    /// Read as a decimal point this was a platelet count wrong by a factor of
    /// a thousand, inside the range, and saved without a murmur.
    func testACommaGroupsDigitsRatherThanSeparatingTheDecimal() {
        XCTAssertEqual(read("1,234", .platelets), .value(1234))
        XCTAssertEqual(read("96,000", .platelets).storedValue, nil,
                       "96000 is still out of range, comma or no comma")
    }

    /// Someone carrying a comma-decimal habit from elsewhere is asked again
    /// rather than quietly recorded as 385.
    func testACommaDecimalHabitIsRefusedRatherThanGuessed() {
        guard case .outOfRange = read("38,5", .temperature) else {
            return XCTFail("38,5 reads as 385, which is not a temperature")
        }
    }

    func testSurroundingSpaceIsIgnored() {
        XCTAssertEqual(read("  72  ", .pulse), .value(72))
    }

    // MARK: - Bengali numerals

    /// The app prints ৩৯.৫ on every tile, so a reader on a Bangla keyboard is
    /// typing the app's own digits back at it. Refusing them would be the app
    /// failing to read its own output.
    func testBengaliNumeralsAreRead() {
        XCTAssertEqual(read("৩৯.৫", .temperature), .value(39.5))
        XCTAssertEqual(read("৭২", .pulse), .value(72))
        XCTAssertEqual(read("১১২", .pulse), .value(112))
    }

    func testBengaliNumeralsWorkForBloodCountsToo() {
        XCTAssertEqual(read("৯৬", .platelets), .value(96))
        XCTAssertEqual(read("১৩.২", .haemoglobin), .value(13.2))
    }

    func testBengaliNumeralsAreRangeCheckedLikeAnyOther() {
        guard case .outOfRange = read("৯০০", .pulse) else {
            return XCTFail("৯০০ is 900, and 900 is not a pulse")
        }
        guard case .outOfRange = read("৯৬০০০", .platelets) else {
            return XCTFail("the decimal slip must be caught in either script")
        }
    }

    func testBengaliAndWesternDigitsMixedInOneNumber() {
        // A reader switching keyboards mid-number is unusual but not wrong.
        XCTAssertEqual(read("৩9.৫", .temperature), .value(39.5))
    }

    func testABengaliNumeralWithAGroupingComma() {
        XCTAssertEqual(read("১,২৩৪", .platelets), .value(1234))
    }

    func testBengaliTemperatureIsCheckedAgainstTheUnitOnScreen() {
        XCTAssertEqual(read("৯৮.৬", .temperature, .fahrenheit).storedValue.map {
            ($0 * 10).rounded() / 10
        }, 37.0)
    }

    func testLettersInBengaliScriptAreStillNotNumbers() {
        XCTAssertEqual(read("জ্বর", .temperature), .notANumber)
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

    // MARK: - Blood counts

    private func read(_ text: String, _ measure: LabMeasure) -> MeasureInput.Reading {
        MeasureInput.read(text, as: measure)
    }

    func testAnEmptyCountIsNotAProblem() {
        XCTAssertEqual(read("", .platelets), .empty)
    }

    func testLettersInACountAreRefused() {
        XCTAssertEqual(read("low", .platelets), .notANumber)
    }

    /// The slip this is really for. A lab prints 96,000 and the reader types
    /// the whole thing into a field that wants thousands. Dropped silently,
    /// the report saves with no platelet count at all — the one number in
    /// dengue that a reader would most believe they had written down.
    func testAPlateletCountTypedInFullIsRefusedRatherThanDropped() {
        guard case .outOfRange = read("96000", .platelets) else {
            return XCTFail("96000 must be refused, not quietly discarded")
        }
    }

    func testAFallingPlateletCountIsAccepted() {
        // Low is the point. Validation must not refuse the alarming readings.
        XCTAssertEqual(read("12", .platelets), .value(12))
        XCTAssertEqual(read("96", .platelets), .value(96))
    }

    func testHaematocritOutsideWhatBloodDoesIsRefused() {
        guard case .outOfRange = read("95", .haematocrit) else {
            return XCTFail("a haematocrit of 95% is not a measurement")
        }
    }

    func testDecimalCountsAreKept() {
        XCTAssertEqual(read("3.4", .whiteCells), .value(3.4))
        XCTAssertEqual(read("13.2", .haemoglobin), .value(13.2))
    }

    /// White cells start at 0.1, so the refusal message has to quote a decimal.
    /// Rounded to whole numbers it would offer a range starting at 0, which the
    /// field itself refuses.
    func testTheWhiteCellRangeKeepsItsDecimalBound() {
        guard case .outOfRange(let range) = read("0.05", .whiteCells) else {
            return XCTFail("0.05 is below the enterable range")
        }
        XCTAssertEqual(range.lowerBound, 0.1, accuracy: 0.0001)
        XCTAssertNotEqual(range.lowerBound, range.lowerBound.rounded(),
                          "this bound must not be a whole number, or the test proves nothing")
    }

    func testAGroupingCommaInACountToo() {
        // 13,2 reads as 132, which no haemoglobin is.
        guard case .outOfRange = read("13,2", .haemoglobin) else {
            return XCTFail("132 g/dL is not a haemoglobin")
        }
    }

    func testEveryCountRefusesSomething() {
        for measure in LabMeasure.allCases {
            XCTAssertTrue(read("banana", measure).isProblem, "\(measure) accepted letters")
            XCTAssertTrue(read("99999", measure).isProblem, "\(measure) accepted 99999")
            XCTAssertTrue(read("-1", measure).isProblem, "\(measure) accepted a negative")
        }
    }

    func testEveryKindRefusesSomething() {
        // No field may be left unguarded.
        for kind in VitalKind.allCases {
            XCTAssertTrue(read("banana", kind).isProblem, "\(kind) accepted letters")
            XCTAssertTrue(read("99999", kind).isProblem, "\(kind) accepted 99999")
        }
    }
}
