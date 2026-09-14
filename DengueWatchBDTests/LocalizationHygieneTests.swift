import XCTest
@testable import DengueWatchBD

/// Rules about *where* translated text lives, enforced against the source
/// itself rather than trusted to memory.
///
/// Bengali written inline in a view is invisible to the localisation tables:
/// it cannot be reviewed beside its English, it is missed when a string is
/// reworded, and it silently ignores the in-app language toggle.
final class LocalizationHygieneTests: XCTestCase {

    /// The source tree, found from this file rather than from a fixed path.
    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // DengueWatchBDTests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("DengueWatchBD")
    }

    /// Hospital names are data, not translation: a hospital's Bengali name is
    /// its name, and it belongs beside its English one in the directory.
    private let filesAllowedBengaliData = ["CareDirectory.swift"]

    private func swiftFiles() -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: sourceRoot, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func containsBengali(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0980...0x09FF).contains(Int($0.value)) }
    }

    func testNoBengaliOutsideTheLocalizationTables() throws {
        var offenders: [String] = []
        for file in swiftFiles() {
            let name = file.lastPathComponent
            if file.pathComponents.contains("Localization") { continue }
            if filesAllowedBengaliData.contains(name) { continue }
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }

            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // A comment may quote Bengali to explain a bug; only shipped
                // string literals are the problem.
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                if containsBengali(line) {
                    offenders.append("\(name):\(index + 1)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "Bengali belongs in the localisation tables, not in: \(offenders)")
    }

    func testTheSourceTreeWasActuallyFound() {
        // Guards the test above from passing because it read nothing at all.
        XCTAssertGreaterThan(swiftFiles().count, 40)
    }

    /// Every key the code asks for must exist.
    ///
    /// `loc.t` falls back to the key itself when it is missing, so a typo or a
    /// forgotten entry ships as a button labelled "common.save" rather than as
    /// a crash or a build error. That is exactly how `common.save` reached a
    /// rename dialog: the code compiled, the tests passed, and the string was
    /// simply not there.
    func testEveryKeyTheCodeAsksForExists() throws {
        let pattern = try NSRegularExpression(pattern: #"\bt\(\s*"([a-z][\w.]+)""#)
        var missing: Set<String> = []
        for file in swiftFiles() where !file.pathComponents.contains("Localization") {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let range = NSRange(source.startIndex..., in: source)
            for match in pattern.matches(in: source, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                let key = String(source[keyRange])
                if Strings.english[key] == nil { missing.insert(key) }
            }
        }
        XCTAssertTrue(missing.isEmpty, "used in code but never defined: \(missing.sorted())")
    }

    /// DGHS has a Bengali name, and the app uses it. Transliterating the
    /// English acronym in one string and not the rest reads as two different
    /// sources to someone reading in Bangla.
    func testDGHSIsNamedConsistentlyInBangla() {
        let transliterated = Strings.bangla.filter { $0.value.contains("ডিজিএইচএস") }
        XCTAssertTrue(transliterated.isEmpty,
                      "use স্বাস্থ্য অধিদপ্তর: \(transliterated.keys.sorted())")
    }

    /// Every key the English table defines is reachable from the Bangla one
    /// and vice versa — the parity tests cover that. This covers the third
    /// case: a key defined twice with different text, where which one wins
    /// depends on dictionary literal order.
    func testNoKeyIsDefinedTwice() throws {
        for (label, table) in [("English", Strings.english), ("Bangla", Strings.bangla)] {
            let file = sourceRoot.appendingPathComponent("Localization")
            let sources = (try? FileManager.default.contentsOfDirectory(at: file,
                includingPropertiesForKeys: nil)) ?? []
            var counts: [String: Int] = [:]
            for source in sources where source.pathExtension == "swift" {
                let text = (try? String(contentsOf: source, encoding: .utf8)) ?? ""
                for key in table.keys {
                    counts[key, default: 0] += text.components(separatedBy: "\"\(key)\":").count - 1
                }
            }
            let duplicated = counts.filter { $0.value > 2 }.keys.sorted()
            XCTAssertTrue(duplicated.isEmpty, "\(label) key defined more than once: \(duplicated)")
        }
    }
}
