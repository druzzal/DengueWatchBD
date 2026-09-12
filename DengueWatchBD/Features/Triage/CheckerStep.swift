import Foundation

/// The stages of the symptom check.
///
/// Split up because the single form asked fourteen symptom questions, a date,
/// and four risk questions on one screen, which is a lot to face when you feel
/// ill. One question at a time also lets the warning signs get a screen of
/// their own, which is the part that most needs to be read rather than skimmed.
///
/// No clinical rule lives here. The steps only decide what is asked and in what
/// order; `TriageEngine.evaluate` still decides what the answers mean.
enum CheckerStep: Int, CaseIterable, Identifiable, Comparable {
    case fever
    case symptoms
    case warningSigns
    case timeline
    case riskFactors

    var id: Int { rawValue }

    var titleKey: String { "step.\(name).title" }
    var subtitleKey: String { "step.\(name).subtitle" }

    private var name: String {
        switch self {
        case .fever: "fever"
        case .symptoms: "symptoms"
        case .warningSigns: "warning"
        case .timeline: "timeline"
        case .riskFactors: "risk"
        }
    }

    static func < (lhs: CheckerStep, rhs: CheckerStep) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The steps actually shown for this answer set.
    ///
    /// The timeline step is skipped when there is no fever: asking which day of
    /// a fever someone is on when they have said they have none is nonsense,
    /// and a step that cannot be answered is a step that gets guessed at.
    static func sequence(hasFever: Bool) -> [CheckerStep] {
        allCases.filter { $0 != .timeline || hasFever }
    }
}
