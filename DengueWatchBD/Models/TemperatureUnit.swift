import Foundation

/// How a temperature is shown and typed. Not how it is stored.
///
/// Readings are kept in Celsius in the case log, always, and converted only at
/// the edges. Entries written before this existed are Celsius, so letting the
/// unit change storage would silently reinterpret them — a logged 38.5 would
/// become 38.5°F, which is 3.6°C, a number that reads as a corpse rather than
/// a fever.
enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    var labelKey: String { "temp.unit.\(rawValue)" }

    /// What a person could plausibly type for their own temperature.
    ///
    /// Wide enough to accept genuine extremes — hypothermia and hyperpyrexia
    /// both happen — but narrow enough to catch the common slip of typing a
    /// Fahrenheit number while the unit says Celsius, which would otherwise be
    /// stored as a reading no living person has.
    var plausibleRange: ClosedRange<Double> {
        switch self {
        case .celsius: 30...45
        case .fahrenheit: 86...113
        }
    }

    func toCelsius(_ value: Double) -> Double {
        switch self {
        case .celsius: value
        case .fahrenheit: (value - 32) * 5 / 9
        }
    }

    func fromCelsius(_ celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
    }

    /// Accepts what someone typed, in this unit, and returns Celsius to store.
    /// Nil when the text is not a number or is not a temperature a person has.
    func celsiusValue(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let typed = Double(trimmed), plausibleRange.contains(typed) else { return nil }
        return toCelsius(typed)
    }

    /// One decimal place: thermometers report tenths, and more would imply a
    /// precision the reading does not have.
    func display(celsius: Double) -> String {
        String(format: "%.1f%@", fromCelsius(celsius), symbol)
    }

    /// The same reading in the reader's own numerals. `String(format:)` always
    /// writes Western digits, which put "38.4" beside "৯৬/৬৪" on the same card.
    func display(celsius: Double, style: NumberStyle) -> String {
        style.decimal(fromCelsius(celsius), places: 1) + symbol
    }
}
