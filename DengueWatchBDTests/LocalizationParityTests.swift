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

    /// Format specifiers must survive translation: a string that takes one
    /// argument in English and none in Bangla crashes or silently drops data.
    func testFormatPlaceholdersMatchBetweenLanguages() {
        for (key, english) in Strings.english {
            guard let bangla = Strings.bangla[key] else { continue }
            XCTAssertEqual(english.components(separatedBy: "%@").count,
                           bangla.components(separatedBy: "%@").count,
                           "placeholder count differs for \(key)")
        }
    }
}
