import Foundation
import Observation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case bangla = "bn"

    var id: String { rawValue }

    /// The language's name written in that language — never translated.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .bangla: "বাংলা"
        }
    }

    /// Short badge for the compact toggle.
    var shortLabel: String {
        switch self {
        case .english: "EN"
        case .bangla: "বাং"
        }
    }

    var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_BD")
        case .bangla: Locale(identifier: "bn_BD")
        }
    }

    /// Bengali readers expect Bengali digits; English readers expect Latin.
    var usesBengaliDigits: Bool { self == .bangla }
}

/// Locale-aware formatting, kept separate from `LocalizationManager` because it
/// is pure and `Sendable`: Swift Charts axis builders are nonisolated and cannot
/// touch a `@MainActor` object, but they still need Bengali digits and dates.
struct NumberStyle: Sendable, Equatable {
    let language: AppLanguage

    var locale: Locale { language.locale }

    private func digits(_ text: String) -> String {
        guard language.usesBengaliDigits else { return text }
        let map: [Character: Character] = [
            "0": "০", "1": "১", "2": "২", "3": "৩", "4": "৪",
            "5": "৫", "6": "৬", "7": "৭", "8": "৮", "9": "৯"
        ]
        return String(text.map { map[$0] ?? $0 })
    }

    func num(_ value: Int) -> String {
        digits(value.formatted(.number.grouping(.automatic).locale(locale)))
    }

    func decimal(_ value: Double, places: Int = 1) -> String {
        digits(value.formatted(.number.precision(.fractionLength(places)).locale(locale)))
    }

    /// Bengali uses হাজার / লাখ rather than k / M, because "১০১k" is not how
    /// anyone reads a number in Bengali.
    func compact(_ value: Int) -> String {
        switch language {
        case .english:
            if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
            if value >= 10_000 { return String(format: "%.0fk", Double(value) / 1_000) }
            if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
            return num(value)
        case .bangla:
            if value >= 10_000_000 { return digits(String(format: "%.1f", Double(value) / 10_000_000)) + " কোটি" }
            if value >= 100_000 { return digits(String(format: "%.1f", Double(value) / 100_000)) + " লাখ" }
            if value >= 1_000 { return digits(String(format: "%.0f", Double(value) / 1_000)) + " হাজার" }
            return num(value)
        }
    }

    func percentChange(_ value: Double?) -> String {
        guard let value else { return "—" }
        let sign = value >= 0 ? "+" : "−"
        return sign + digits(abs(value * 100).formatted(.number.precision(.fractionLength(0)).locale(locale))) + "%"
    }

    func fullDate(_ date: Date) -> String {
        digits(date.formatted(.dateTime.day().month(.wide).year().locale(locale)))
    }

    func dayMonth(_ date: Date) -> String {
        digits(date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
    }

    func dateTime(_ date: Date) -> String {
        digits(date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale)))
    }

    func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return digits(formatter.localizedString(for: date, relativeTo: Date()))
    }
}

/// Holds the chosen language and hands out the formatter that depends on it.
/// Views read strings and numbers through this, so switching language redraws
/// everything at once.
@MainActor
@Observable
final class LocalizationManager {
    private static let storageKey = "appLanguage"

    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        if let raw = defaults.string(forKey: Self.storageKey),
           let stored = AppLanguage(rawValue: raw) {
            language = stored
        } else {
            // First run follows the device, so a phone set to Bengali opens in Bengali.
            let preferred = Locale.preferredLanguages.first ?? "en"
            language = preferred.hasPrefix("bn") ? .bangla : .english
        }
    }

    func toggle() {
        language = language == .english ? .bangla : .english
    }

    var locale: Locale { language.locale }

    /// Hand this to anything nonisolated that needs to format — chart axes most of all.
    var style: NumberStyle { NumberStyle(language: language) }

    // MARK: - Strings

    /// Look up a key in the current language.
    ///
    /// A missing key trips an assertion in debug builds and falls back to
    /// English (then to the key itself) in release, so a gap in the Bengali
    /// table degrades to readable English rather than a blank label.
    func t(_ key: String) -> String {
        if let value = Strings.table(for: language)[key] { return value }
        assertionFailure("Missing \(language.rawValue) string for key: \(key)")
        return Strings.table(for: .english)[key] ?? key
    }

    /// Look up a key and substitute positional arguments (`%@`).
    func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: arguments)
    }

    // MARK: - Numbers and dates (delegated, so there is one implementation)

    func num(_ value: Int) -> String { style.num(value) }
    func decimal(_ value: Double, places: Int = 1) -> String { style.decimal(value, places: places) }
    func compact(_ value: Int) -> String { style.compact(value) }
    func percentChange(_ value: Double?) -> String { style.percentChange(value) }
    func fullDate(_ date: Date) -> String { style.fullDate(date) }
    func dayMonth(_ date: Date) -> String { style.dayMonth(date) }
    func dateTime(_ date: Date) -> String { style.dateTime(date) }
    func relative(_ date: Date) -> String { style.relative(date) }
}
