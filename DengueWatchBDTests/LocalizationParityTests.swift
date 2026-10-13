import XCTest
@testable import DengueWatchBD

/// A key present in one language and missing from the other fails silently at
/// runtime — the screen shows the fallback, or the raw key, and only in the
/// language the author was not looking at.
final class LocalizationParityTests: XCTestCase {

    func testEveryEnglishKeyHasABanglaTranslation() {
        let missing = Set(Strings.english.keys).subtracting(Strings.bangla.keys)
        XCTAssertTrue(missing.isEmpty, "no Bangla for: \(missing.sorted())")
    }

    func testEveryBanglaKeyHasAnEnglishOriginal() {
        let orphaned = Set(Strings.bangla.keys).subtracting(Strings.english.keys)
        XCTAssertTrue(orphaned.isEmpty, "Bangla with no English: \(orphaned.sorted())")
    }

    /// A translation that still reads as the English string is usually a
    /// forgotten paste rather than a word Bangla shares.
    ///
    /// Two things are legitimately identical and are skipped: names and units
    /// that are written the same way in both, and values with no letters at
    /// all — "%@%%" is a format string, not a sentence, and there is nothing
    /// in it to translate.
    func testTranslationsAreNotCopiesOfTheEnglish() {
        let sharedTerms = ["DGHS", "NS1", "IgM", "IgG", "SpO2", "mmHg", "bpm",
                           "g/dL", "×10³/µL", "EN"]
        let copies = Strings.english.filter { key, value in
            guard let bangla = Strings.bangla[key], bangla == value else { return false }
            guard value.contains(where: \.isLetter) else { return false }
            return !sharedTerms.contains(value)
        }
        XCTAssertTrue(copies.isEmpty, "untranslated: \(copies.keys.sorted())")
    }

    /// Bangla sets this date month-first, which CLDR does not: both bn_BD and
    /// en_BD order it day-first, so chaining `.month(.wide).day()` yields
    /// "১২ সেপ্টেম্বর". The explicit pattern is the whole point of the
    /// formatter, and this is what would silently revert it.
    func testTheReportedDateIsMonthFirstInBangla() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 12
        let date = Calendar(identifier: .gregorian).date(from: parts)!

        let bangla = NumberStyle(language: .bangla).reportedDate(date)
        XCTAssertTrue(bangla.hasPrefix("সেপ্টেম্বর"), bangla)
        XCTAssertTrue(bangla.contains("১২"), "Bangla numerals expected: \(bangla)")

        // English keeps its own locale's order.
        let english = NumberStyle(language: .english).reportedDate(date)
        XCTAssertTrue(english.hasPrefix("12"), english)
    }

    /// Format specifiers must survive translation: a string that takes one
    /// argument in English and none in Bangla crashes or silently drops data.
    ///
    /// Counted with or without a position, because Bangla sometimes needs its
    /// arguments the other way round: "৫টির মধ্যে ২টি" is total first.
    func testFormatPlaceholdersMatchBetweenLanguages() {
        let placeholder = /%(\d+\$)?@/
        for (key, english) in Strings.english {
            guard let bangla = Strings.bangla[key] else { continue }
            XCTAssertEqual(english.matches(of: placeholder).count,
                           bangla.matches(of: placeholder).count,
                           "placeholder count differs for \(key)")
        }
    }

    /// The checklist counter reads total first in Bangla. Unnumbered, it took
    /// the arguments in English order and told the reader "5 done out of 0".
    @MainActor
    func testTheChecklistCounterKeepsDoneAndTotalApartInBangla() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.set("bn", forKey: "appLanguage")
        defer { defaults.removePersistentDomain(forName: #function) }
        let loc = LocalizationManager(defaults: defaults)
        XCTAssertEqual(loc.t("checklist.progress", loc.num(2), loc.num(5)), "৫টির মধ্যে ২টি হয়েছে")
    }
}
