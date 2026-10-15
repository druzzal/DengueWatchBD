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

    /// How loudly to colour this outcome, on the app's one risk palette.
    ///
    /// On the outcome rather than in a view, because Home and My Health both
    /// show the latest check and two private copies of this mapping would be
    /// two chances for the same outcome to appear in two colours.
    var risk: RiskLevel {
        switch self {
        case .selfCare: .low
        case .testAdvised: .moderate
        case .seeDoctorToday: .high
        case .emergency: .severe
        }
    }
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
        // WHO 2025 lists oral intolerance as a reason to admit in its own
        // right. It used to ride along in the vomiting row's small print, where
        // someone who simply cannot drink — without vomiting — would not find it.
        Symptom(id: "oralIntolerance", group: .warning),
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

    /// Higher-risk groups per WHO dengue guidance.
    ///
    /// Source: WHO, *Guidelines for clinical management of arboviral diseases:
    /// dengue, chikungunya, Zika and yellow fever* (2025), section 2.6.
    struct Context {
        var feverDaysAgo: Int?
        var isPregnant = false
        var isUnderFiveOrOverSixty = false
        var hasChronicCondition = false
        var hadDengueBefore = false

        /// The groups WHO 2025 names when it lists who is admitted: pregnancy
        /// outright, and the extremes of age and underlying conditions as
        /// patients clinicians "may elect to admit".
        ///
        /// Previous dengue is deliberately not here. WHO names a second
        /// infection as raising the risk of severe disease, not as a reason to
        /// admit, so it is shown as a reason to watch closely and changes no
        /// advice on its own.
        var isHigherRiskGroup: Bool {
            isPregnant || isUnderFiveOrOverSixty || hasChronicCondition
        }
    }

    static func evaluate(selected: Set<String>, context: Context) -> TriageOutcome {
        let chosen = symptoms.filter { selected.contains($0.id) }
        if chosen.contains(where: { $0.group == .severe }) { return .emergency }

        let warnings = chosen.filter { $0.group == .warning }.count
        if warnings >= 1 { return .seeDoctorToday }

        // Anyone in a group WHO would consider admitting is seen the same day,
        // whatever the symptoms. This keeps the result in step with the care
        // plan, which already sends these groups for hospital assessment — the
        // two used to disagree for a pregnant reader with a fever alone.
        if context.isHigherRiskGroup && !chosen.isEmpty { return .seeDoctorToday }

        let core = chosen.filter { $0.group == .core }.count
        if selected.contains("fever") || core >= 2 { return .testAdvised }
        return .selfCare
    }

    /// True when a same-day result came from the reader's risk group rather
    /// than from a warning sign they ticked, so the result can say which.
    /// "You reported a warning sign" to someone who reported none reads as the
    /// app not listening.
    static func isRaisedByRiskGroup(selected: Set<String>, context: Context) -> Bool {
        let chosen = symptoms.filter { selected.contains($0.id) }
        return evaluate(selected: selected, context: context) == .seeDoctorToday
            && !chosen.contains { $0.group == .warning }
    }

    /// Which phase of illness the person is in. The critical phase is when
    /// plasma leak starts, and it is not when people feel worst.
    /// The phase of illness, as a value rather than a string key.
    ///
    /// Introduced so the sentence under the result and the fever timeline read
    /// the same boundaries from one place. The boundaries themselves are
    /// unchanged: this wraps the rule that was already here rather than
    /// restating it, so the two can never drift apart.
    enum FeverPhase: String, CaseIterable, Identifiable {
        case febrile
        case critical
        case recovery

        var id: String { rawValue }
        var key: String { "check.phase.\(rawValue)" }
        var nameKey: String { "phase.\(rawValue).name" }

        /// Days of fever this phase covers, counting the first day as day 1.
        /// `feverDaysAgo` is zero-based, so these run one higher.
        var dayRange: ClosedRange<Int> {
            switch self {
            case .febrile: 1...3
            case .critical: 4...7
            case .recovery: 8...10
            }
        }

        static func phase(feverDaysAgo: Int) -> FeverPhase {
            switch feverDaysAgo {
            case 0...2: .febrile
            case 3...6: .critical
            default: .recovery
            }
        }
    }

    static func phase(feverDaysAgo: Int?) -> FeverPhase? {
        feverDaysAgo.map(FeverPhase.phase(feverDaysAgo:))
    }

    static func phaseKey(feverDaysAgo: Int?) -> String? {
        phase(feverDaysAgo: feverDaysAgo)?.key
    }
}
