import XCTest
@testable import DengueWatchBD

/// Checks this app's string tables against `shared-strings.json`.
///
/// The Android app runs the same file. A key both apps carry must have the
/// same English and Bangla wording in both; a key only one carries must be
/// written down as such. So a feature added on one platform only — the way
/// Android once lacked "where you are now" on the home card — or a phrase
/// reworded on one side, fails here until the other catches up or the
/// difference is recorded on purpose.
final class SharedStringsTests: XCTestCase {

    private var shared: [String: Any] = [:]

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "shared-strings", withExtension: "json"),
            "shared-strings.json is missing from the test bundle")
        shared = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func list(_ key: String) -> Set<String> { Set(shared[key] as? [String] ?? []) }
    private func wording(_ key: String) -> [String: String] { shared[key] as? [String: String] ?? [:] }

    func testSharedWordingMatches() {
        for (language, table) in [("en", Strings.english), ("bn", Strings.bangla)] {
            let expected = wording(language)
            XCTAssertFalse(expected.isEmpty)
            for (key, value) in expected {
                XCTAssertEqual(table[key], value, "\(language) \(key)")
            }
        }
    }

    func testEveryKeyIsSharedOrRecordedAsIOSOnly() {
        let known = Set(wording("en").keys).union(list("platformWording")).union(list("iosOnly"))
        let ours = Set(Strings.english.keys).union(Strings.bangla.keys)
        XCTAssertEqual(ours.subtracting(known).sorted(), [],
                       "keys only iOS has; add them to Android, or to iosOnly in shared-strings.json")
        XCTAssertEqual(known.subtracting(ours).sorted(), [],
                       "keys the shared file expects that iOS lacks")
    }

    func testAndroidOnlyKeysAreNotHere() {
        let ours = Set(Strings.english.keys).union(Strings.bangla.keys)
        XCTAssertEqual(list("androidOnly").intersection(ours).sorted(), [],
                       "now on both platforms; move them into the shared wording")
    }

    func testPlatformWordingIsInBothLanguages() {
        for key in list("platformWording") {
            XCTAssertNotNil(Strings.english[key], "en \(key)")
            XCTAssertNotNil(Strings.bangla[key], "bn \(key)")
        }
    }
}
