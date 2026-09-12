import XCTest
@testable import DengueWatchBD

/// The phase boundaries are clinical guidance, and the timeline now draws them.
/// These exist mainly to prove the refactor moved nothing.
final class FeverPhaseTests: XCTestCase {

    typealias Phase = TriageEngine.FeverPhase

    // MARK: - Boundaries, unchanged

    func testBoundariesMatchTheGuidanceTheAppAlreadyUsed() {
        // feverDaysAgo is zero-based: 0 is the first day of fever.
        let expected: [Int: Phase] = [
            0: .febrile, 1: .febrile, 2: .febrile,
            3: .critical, 4: .critical, 5: .critical, 6: .critical,
            7: .recovery, 8: .recovery, 30: .recovery,
        ]
        for (daysAgo, phase) in expected {
            XCTAssertEqual(Phase.phase(feverDaysAgo: daysAgo), phase, "day \(daysAgo)")
        }
    }

    func testPhaseKeyStillReturnsWhatItAlwaysReturned() {
        // The string keys are referenced by the existing result view and the
        // string tables; renaming one silently would blank that sentence.
        XCTAssertEqual(TriageEngine.phaseKey(feverDaysAgo: 0), "check.phase.febrile")
        XCTAssertEqual(TriageEngine.phaseKey(feverDaysAgo: 4), "check.phase.critical")
        XCTAssertEqual(TriageEngine.phaseKey(feverDaysAgo: 9), "check.phase.recovery")
        XCTAssertNil(TriageEngine.phaseKey(feverDaysAgo: nil))
    }

    func testNoFeverDateMeansNoPhase() {
        XCTAssertNil(TriageEngine.phase(feverDaysAgo: nil))
    }

    func testANegativeDayDoesNotCrashAndIsNotTreatedAsCritical() {
        // A clock change or a future date should never land someone in the
        // phase that tells them to watch for bleeding.
        XCTAssertEqual(Phase.phase(feverDaysAgo: -1), .recovery)
    }

    // MARK: - The timeline reads the same boundaries

    func testTheTimelineDayRangesAgreeWithThePhaseFunction() {
        // The view maps 1-based days onto phases; a mismatch here would colour
        // a day one phase while the sentence beneath called it another.
        for day in 1...10 {
            let fromRange = Phase.allCases.first { $0.dayRange.contains(day) }
            let fromFunction = Phase.phase(feverDaysAgo: day - 1)
            XCTAssertEqual(fromRange, fromFunction, "day \(day) disagrees")
        }
    }

    func testTheRangesAreContiguousAndDoNotOverlap() {
        let sorted = Phase.allCases.sorted { $0.dayRange.lowerBound < $1.dayRange.lowerBound }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            XCTAssertEqual(earlier.dayRange.upperBound + 1, later.dayRange.lowerBound,
                           "gap or overlap between \(earlier.rawValue) and \(later.rawValue)")
        }
    }

    func testTheCriticalPhaseCoversTheDaysFeverTypicallyFalls() {
        // The whole reason the timeline exists: days 4-7 must be the critical
        // window, because that is when people feel better and stop watching.
        XCTAssertEqual(Phase.critical.dayRange, 4...7)
    }

    // MARK: - Content

    func testEveryPhaseHasANameAndASentenceInBothLanguages() {
        for phase in Phase.allCases {
            for key in [phase.key, phase.nameKey] {
                XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
                XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
            }
        }
    }

    func testTheCriticalNoteWarnsThatFeelingBetterIsNotSafety() {
        // Wording can be edited, but this claim must survive editing.
        let english = Strings.english["phase.critical.note"] ?? ""
        XCTAssertTrue(english.lowercased().contains("fall"),
                      "the note should tie warning signs to the fever falling")
        XCTAssertNotNil(Strings.bangla["phase.critical.note"])
    }

    func testAccessibilityStringsExistForBothStates() {
        for key in ["phase.a11y.day", "phase.a11y.unknown"] {
            XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
            XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
        }
    }
}
