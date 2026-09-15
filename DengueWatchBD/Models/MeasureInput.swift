import Foundation

/// Checking what someone typed into a reading field.
///
/// Kept out of the form so the rules can be tested directly, and because they
/// are the rules that decide whether a reading becomes part of somebody's
/// medical record.
///
/// The old behaviour was to drop whatever would not parse and save the rest.
/// That is the wrong failure: someone who means 39.5 and types 395 gets a
/// saved entry with no temperature in it at all, and every sign that the
/// reading was recorded. Refusing is safer than forgetting — a reader who is
/// stopped will look at the number again, and a reader who is not will believe
/// they wrote down a fever they did not.
enum MeasureInput {

    /// What a field currently holds.
    enum Reading: Equatable {
        /// Nothing typed. Every field is optional, so this is not a problem.
        case empty
        /// Good, in the unit the app stores (Celsius for temperature).
        case value(Double)
        /// Something that is not a number at all: letters, or "39.5.5".
        case notANumber
        /// A number no thermometer or cuff would produce, with the range that
        /// would be accepted — in the unit the reader is typing in, so the
        /// message matches what is on screen rather than what is on disk.
        case outOfRange(ClosedRange<Double>)

        var isProblem: Bool {
            switch self {
            case .empty, .value: false
            case .notANumber, .outOfRange: true
            }
        }

        var storedValue: Double? {
            if case .value(let value) = self { return value }
            return nil
        }
    }

    /// Reads one vital-sign field.
    ///
    /// Temperature is typed in whichever unit is selected, so both the check
    /// and the range quoted back have to be in that unit — 39.5 is an ordinary
    /// fever in Celsius and far too cold to be a person in Fahrenheit.
    static func read(_ text: String, as kind: VitalKind, unit: TemperatureUnit) -> Reading {
        if kind == .temperature {
            return read(text, within: unit.plausibleRange, converting: unit.toCelsius)
        }
        return read(text, within: kind.enterableRange)
    }

    /// Reads one blood-count field.
    ///
    /// Same rules as a vital sign, and for the same reason: a platelet count
    /// silently dropped is a platelet count the reader believes they recorded.
    static func read(_ text: String, as measure: LabMeasure) -> Reading {
        read(text, within: measure.enterableRange)
    }

    /// A comma is accepted as a decimal separator: Bangladeshi keyboards and
    /// habits produce both, and rejecting "38,5" as "not a number" would be
    /// pedantry rather than safety.
    private static func read(_ text: String,
                             within range: ClosedRange<Double>,
                             converting: (Double) -> Double = { $0 }) -> Reading {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let normalised = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let typed = Double(normalised), typed.isFinite else { return .notANumber }
        guard range.contains(typed) else { return .outOfRange(range) }
        return .value(converting(typed))
    }
}
