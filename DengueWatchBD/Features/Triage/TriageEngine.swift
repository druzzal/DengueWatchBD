import Foundation

/// One question in the symptom check. Text lives in the string tables; this
/// model carries only the identity and the clinical grouping.
struct Symptom: Identifiable, Hashable {
    enum Group: String, CaseIterable, Identifiable {
        case core, warning, severe

        var id: String { rawValue }
        var titleKey: String { "symptom.group.\(rawValue)" }
        var footnoteKey: String { "symptom.group.\(rawValue).footnote" }
    }

    let id: String
    let group: Group

    var titleKey: String { "symptom.\(id).title" }
    var detailKey: String { "symptom.\(id).detail" }
}

enum TriageOutcome: Int, Comparable, CaseIterable {
    case selfCare
    case testAdvised
    case seeDoctorToday
    case emergency

    static func < (lhs: TriageOutcome, rhs: TriageOutcome) -> Bool { lhs.rawValue < rhs.rawValue }

    private var slug: String {
        switch self {
        case .selfCare: "selfCare"
        case .testAdvised: "testAdvised"
        case .seeDoctorToday: "seeDoctor"
        case .emergency: "emergency"
        }
    }

    var headlineKey: String { "outcome.\(slug).headline" }
    var summaryKey: String { "outcome.\(slug).summary" }

    var actionKeys: [String] {
        let count: Int
        switch self {
        case .selfCare: count = 3
        case .testAdvised: count = 4
        case .seeDoctorToday: count = 4
        case .emergency: count = 3
        }
        return (1...count).map { "outcome.\(slug).action\($0)" }
    }

    var symbolName: String {
        switch self {
        case .selfCare: "checkmark.circle.fill"
        case .testAdvised: "cross.case.fill"
        case .seeDoctorToday: "stethoscope"
        case .emergency: "exclamationmark.octagon.fill"
        }
    }
}

enum TriageEngine {
    static let symptoms: [Symptom] = [
        Symptom(id: "fever", group: .core),
        Symptom(id: "headache", group: .core),
        Symptom(id: "aches", group: .core),
        Symptom(id: "rash", group: .core),
        Symptom(id: "nausea", group: .core),

        Symptom(id: "abdominal", group: .warning),
        Symptom(id: "vomiting", group: .warning),
        Symptom(id: "bleeding", group: .warning),
        Symptom(id: "fatigue", group: .warning),
        Symptom(id: "fluid", group: .warning),
        Symptom(id: "noUrine", group: .warning),

        Symptom(id: "faint", group: .severe),
        Symptom(id: "confusion", group: .severe),
        Symptom(id: "heavyBleed", group: .severe),
    ]

    static func symptoms(in group: Symptom.Group) -> [Symptom] {
        symptoms.filter { $0.group == group }
    }

    static func symptom(id: String) -> Symptom? {
        symptoms.first { $0.id == id }
    }

    /// Higher-risk groups per WHO dengue guidance — they shift borderline
    /// results up a level.
    struct Context {
        var feverDaysAgo: Int?
        var isPregnant = false
        var isUnderFiveOrOverSixty = false
        var hasChronicCondition = false
        var hadDengueBefore = false

        var hasCoMorbidity: Bool {
            isPregnant || isUnderFiveOrOverSixty || hasChronicCondition || hadDengueBefore
        }
    }

    static func evaluate(selected: Set<String>, context: Context) -> TriageOutcome {
        let chosen = symptoms.filter { selected.contains($0.id) }
        if chosen.contains(where: { $0.group == .severe }) { return .emergency }

        let warnings = chosen.filter { $0.group == .warning }.count
        if warnings >= 1 { return .seeDoctorToday }

        let core = chosen.filter { $0.group == .core }.count
        let hasFever = selected.contains("fever")

        if hasFever && core >= 2 {
            return context.hasCoMorbidity ? .seeDoctorToday : .testAdvised
        }
        if hasFever { return .testAdvised }
        if core >= 2 { return .testAdvised }
        return .selfCare
    }

    /// Which phase of illness the person is in. The critical phase is when
    /// plasma leak starts, and it is not when people feel worst.
    static func phaseKey(feverDaysAgo: Int?) -> String? {
        guard let day = feverDaysAgo else { return nil }
        switch day {
        case 0...2: return "check.phase.febrile"
        case 3...6: return "check.phase.critical"
        default: return "check.phase.recovery"
        }
    }
}
