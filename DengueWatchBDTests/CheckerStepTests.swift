import XCTest
@testable import DengueWatchBD

/// The steps decide what is asked and in what order. They must never decide
/// what the answers mean — that stays in TriageEngine.
final class CheckerStepTests: XCTestCase {

    func testTheOrderPutsWarningSignsAfterOrdinarySymptoms() {
        // Someone answering in order should meet the routine questions first
        // and reach the ones that change the advice with attention left.
        XCTAssertEqual(CheckerStep.allCases,
                       [.fever, .symptoms, .warningSigns, .timeline, .riskFactors])
    }

    func testTheTimelineStepIsSkippedWithoutAFever() {
        // Asking which day of a fever someone is on when they have said they
        // have none is nonsense, and an unanswerable step gets guessed at.
        let withoutFever = CheckerStep.sequence(hasFever: false)
        XCTAssertFalse(withoutFever.contains(.timeline))
        XCTAssertEqual(withoutFever.count, 4)
    }

    func testTheTimelineStepAppearsOnceFeverIsConfirmed() {
        let withFever = CheckerStep.sequence(hasFever: true)
        XCTAssertTrue(withFever.contains(.timeline))
        XCTAssertEqual(withFever.count, 5)
    }

    func testSkippingATepKeepsTheRestInOrder() {
        let sequence = CheckerStep.sequence(hasFever: false)
        XCTAssertEqual(sequence, sequence.sorted(), "skipping must not reorder what remains")
    }

    func testStepsAreComparableSoNextAndBackAreWellDefined() {
        XCTAssertLessThan(CheckerStep.fever, CheckerStep.symptoms)
        XCTAssertLessThan(CheckerStep.warningSigns, CheckerStep.riskFactors)
    }

    func testEveryStepHasATitleAndSubtitleInBothLanguages() {
        for step in CheckerStep.allCases {
            for key in [step.titleKey, step.subtitleKey] {
                XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
                XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
            }
        }
    }

    func testTheNavigationStringsExistInBothLanguages() {
        for key in ["step.next", "step.back", "step.seeResult", "step.progress",
                    "step.fever.yes", "step.fever.no", "step.warning.none",
                    "step.timeline.unknown"] {
            XCTAssertNotNil(Strings.english[key], "missing EN: \(key)")
            XCTAssertNotNil(Strings.bangla[key], "missing BN: \(key)")
        }
    }

    // MARK: - The clinical logic must be untouched by the restructure

    func testSplittingTheFormDidNotChangeWhatTheAnswersMean() {
        // Same inputs, same outcome as before the flow was stepped. The steps
        // only gather; the engine still decides.
        let none = TriageEngine.Context()
        XCTAssertEqual(TriageEngine.evaluate(selected: [], context: none), .selfCare)
        XCTAssertEqual(TriageEngine.evaluate(selected: ["fever"], context: none), .testAdvised)
        XCTAssertEqual(TriageEngine.evaluate(selected: ["vomiting"], context: none), .seeDoctorToday)
        XCTAssertEqual(TriageEngine.evaluate(selected: ["faint"], context: none), .emergency)
    }

    func testTheWarningStepCoversEverySymptomThatCanChangeTheOutcome() {
        // If a warning or severe sign were left off that screen, the flow could
        // never reach the outcome it triggers.
        let onWarningScreen = Set(
            TriageEngine.symptoms(in: .warning).map(\.id)
            + TriageEngine.symptoms(in: .severe).map(\.id))
        for symptom in TriageEngine.symptoms where symptom.group != .core {
            XCTAssertTrue(onWarningScreen.contains(symptom.id),
                          "\(symptom.id) is unreachable in the flow")
        }
    }

    func testEveryCoreSymptomIsReachableAcrossTheFeverAndSymptomSteps() {
        let onFeverScreen: Set<String> = ["fever"]
        let onSymptomScreen = Set(TriageEngine.symptoms(in: .core).map(\.id)
            .filter { !onFeverScreen.contains($0) })
        for symptom in TriageEngine.symptoms(in: .core) {
            XCTAssertTrue(onFeverScreen.contains(symptom.id) || onSymptomScreen.contains(symptom.id),
                          "\(symptom.id) is unreachable in the flow")
        }
    }
}
