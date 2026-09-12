import XCTest
@testable import DengueWatchBD

/// These are medical claims shown to people who may be ill, so the tests are
/// about the content being present, consistent with the rest of the app, and
/// not contradicting advice given elsewhere in it.
final class MythFactTests: XCTestCase {

    func testEveryMythAndFactIsWrittenInBothLanguages() {
        for item in MythFact.all {
            for key in [item.mythKey, item.factKey] {
                XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
                XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
                XCTAssertFalse((Strings.english[key] ?? "").isEmpty, key)
                XCTAssertFalse((Strings.bangla[key] ?? "").isEmpty, key)
            }
        }
    }

    func testTheSectionLabelsExist() {
        for key in ["myth.section", "myth.section.subtitle", "myth.label", "myth.fact.label"] {
            XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
            XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
        }
    }

    func testIdentifiersAreUnique() {
        XCTAssertEqual(Set(MythFact.all.map(\.id)).count, MythFact.all.count)
    }

    func testTheFeverMythAgreesWithTheFeverTimeline() {
        // Two places in the app now make this claim. If one were edited to say
        // something different, a reader would get contradictory advice about
        // the single most dangerous moment in dengue.
        let myth = (Strings.english["myth.feverGone.fact"] ?? "").lowercased()
        let timeline = (Strings.english["phase.critical.note"] ?? "").lowercased()
        XCTAssertTrue(myth.contains("fall"), myth)
        XCTAssertTrue(timeline.contains("fall"), timeline)
    }

    func testTheBitingMythAgreesWithThePreventionAdvice() {
        let myth = (Strings.english["myth.nightOnly.fact"] ?? "").lowercased()
        let prevention = (Strings.english["prevent.bites.summary"] ?? "").lowercased()
        XCTAssertTrue(myth.contains("daylight"), myth)
        XCTAssertTrue(prevention.contains("daylight"), prevention)
    }

    func testThePainkillerFactNamesTheDrugsAndSendsThemToAsk() {
        // The one entry that could cause harm if half-remembered: it must name
        // what to avoid and must not name a dose.
        let fact = (Strings.english["myth.painkillers.fact"] ?? "").lowercased()
        XCTAssertTrue(fact.contains("aspirin"), fact)
        XCTAssertTrue(fact.contains("ibuprofen"), fact)
        XCTAssertTrue(fact.contains("doctor") || fact.contains("pharmacist"), fact)
        for dose in ["mg", "500", "tablet", "twice a day"] {
            XCTAssertFalse(fact.contains(dose), "must not give dosing advice: \(fact)")
        }
    }

    func testNoFactClaimsACure() {
        // Dengue has no specific cure, and nothing here should imply one.
        for item in MythFact.all {
            let fact = (Strings.english[item.factKey] ?? "").lowercased()
            XCTAssertFalse(fact.contains("cures dengue") && !fact.contains("no "),
                           "\(item.id) appears to claim a cure: \(fact)")
        }
    }

    func testTheListStaysShortEnoughToBeRead() {
        XCTAssertLessThanOrEqual(MythFact.all.count, 8)
    }
}
