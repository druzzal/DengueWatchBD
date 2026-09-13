import Foundation

/// What WHO advises for someone who has recorded these symptoms and readings.
///
/// This is a lookup, not a judgement. WHO's dengue guidance sorts patients
/// into three management groups by criteria a person can report about
/// themselves — warning signs, the co-existing conditions that raise risk,
/// and the signs of severe disease. The app already collects exactly those in
/// the symptom check; this states which group WHO's guidance puts them in and
/// what that guidance says to do.
///
/// What it never does is diagnose. It does not say the reader has dengue, and
/// nothing here decides that from a lab value. Every line is traceable to a
/// criterion the reader themselves ticked or a number they themselves wrote
/// down, and each is named on screen so they can see what produced it.
///
/// Source: WHO, *Dengue: guidelines for diagnosis, treatment, prevention and
/// control* (2009), chapter 2 — the A / B / C management groups.
struct WHOCarePlan: Equatable {

    /// WHO's three management groups.
    enum Group: Int, Comparable, CaseIterable {
        /// May be managed at home, with daily review.
        case home
        /// Should be referred for in-hospital care.
        case referral
        /// Requires emergency treatment.
        case emergency

        static func < (lhs: Group, rhs: Group) -> Bool { lhs.rawValue < rhs.rawValue }

        /// WHO's own letter for the group, which is what a clinician here
        /// will recognise on a referral slip.
        var letter: String {
            switch self {
            case .home: "A"
            case .referral: "B"
            case .emergency: "C"
            }
        }

        private var slug: String {
            switch self {
            case .home: "home"
            case .referral: "referral"
            case .emergency: "emergency"
            }
        }

        var titleKey: String { "who.group.\(slug).title" }
        var detailKey: String { "who.group.\(slug).detail" }

        /// What WHO says to do, as a short list.
        var adviceKeys: [String] {
            let count = self == .emergency ? 3 : 4
            return (1...count).map { "who.group.\(slug).advice\($0)" }
        }

        var risk: RiskLevel {
            switch self {
            case .home: .low
            case .referral: .high
            case .emergency: .severe
            }
        }
    }

    /// Why the reader is in this group — shown so the plan is never a verdict
    /// out of nowhere.
    enum Reason: String, Identifiable, Equatable {
        case severeSign          // a sign of severe dengue was reported
        case warningSign         // one or more WHO warning signs
        case coMorbidity         // a co-existing condition WHO singles out
        case criticalPhase       // days 4-6, when plasma leak begins
        case narrowPulsePressure // systolic − diastolic ≤ 20 mmHg
        case lowBloodPressure
        case fastPulse
        case lowOxygen
        case noneOfThese

        var id: String { rawValue }
        var labelKey: String { "who.reason.\(rawValue)" }
    }

    let group: Group
    /// Ordered most serious first, so the first line is the one that matters.
    let reasons: [Reason]
    let phase: TriageEngine.FeverPhase?
    /// Day of illness, counting the first day of fever as day 1.
    let feverDay: Int?

    /// Reasons that came from measured numbers rather than ticked boxes.
    /// Separated because they carry a caveat: a home blood-pressure cuff is
    /// not a clinician's hands.
    var measuredReasons: [Reason] {
        reasons.filter {
            [.narrowPulsePressure, .lowBloodPressure, .fastPulse, .lowOxygen].contains($0)
        }
    }
}

extension WHOCarePlan {

    /// How long a plan still describes the person who made it.
    ///
    /// A symptom check is a snapshot. Dengue changes day to day — that is the
    /// whole reason the critical phase matters — so a plan from last week is a
    /// record of last week, not advice for today. Past this it is still shown,
    /// because it is the reader's own record, but it is labelled as old and
    /// asks to be run again.
    static let freshForDays = 2

    /// How long the fever timeline keeps describing a live illness.
    ///
    /// Dengue runs about ten days. Beyond a fortnight the card would be
    /// counting "day 41 of a fever" from a check nobody has updated, with no
    /// day of the strip marked as today — a timeline of an illness that ended.
    static let illnessWindowDays = 14

    /// Whether a plan made this many days ago still speaks for today.
    static func describesToday(checkedDaysAgo: Int) -> Bool {
        checkedDaysAgo >= 0 && checkedDaysAgo <= freshForDays
    }

    /// Whether a fever that began this many days ago is still a live illness
    /// worth charting. Negative days mean a clock that moved backwards, and
    /// are no more chartable than a fever from last month.
    static func showsTimeline(feverDaysAgo: Int) -> Bool {
        feverDaysAgo >= 0 && feverDaysAgo < illnessWindowDays
    }

    /// The readings WHO's guidance actually speaks to, as thresholds.
    ///
    /// Deliberately conservative, and deliberately few. WHO's bedside signs of
    /// shock include cold clammy skin and capillary refill, which no phone can
    /// record; these four are the ones a home monitor gives honestly.
    enum Threshold {
        /// A narrowing pulse pressure is WHO's earliest measurable sign of
        /// compensated shock.
        static let narrowPulsePressure: Double = 20
        static let lowSystolic: Double = 90
        static let fastPulse: Double = 120
        static let lowOxygen: Double = 94
    }

    /// - Parameters:
    ///   - symptoms: ids ticked in the symptom check.
    ///   - vitals: the most recent set of readings, if any are recent enough
    ///     to speak to how the reader is now.
    ///   - context: the co-existing conditions WHO singles out.
    ///   - feverDaysAgo: days since fever began, zero-based as the checker
    ///     records it. Nil when there is no fever to date from.
    static func evaluate(symptoms: Set<String>,
                         vitals: VitalsEntry?,
                         context: TriageEngine.Context,
                         feverDaysAgo: Int?) -> WHOCarePlan {
        var reasons: [Reason] = []

        let chosen = TriageEngine.symptoms.filter { symptoms.contains($0.id) }
        let hasSevere = chosen.contains { $0.group == .severe }
        let hasWarning = chosen.contains { $0.group == .warning }

        if hasSevere { reasons.append(.severeSign) }
        if hasWarning { reasons.append(.warningSign) }

        // Measured signs. Order matters: pulse pressure first, because it is
        // the one that changes before the others do.
        let measured = measuredConcerns(vitals)
        reasons.append(contentsOf: measured)

        if context.hasCoMorbidity { reasons.append(.coMorbidity) }

        let phase = TriageEngine.phase(feverDaysAgo: feverDaysAgo)
        if phase == .critical { reasons.append(.criticalPhase) }

        // The group is WHO's, and the measured signs only ever raise it.
        var group: Group = .home
        if hasWarning || context.hasCoMorbidity { group = .referral }
        if !measured.isEmpty { group = max(group, .referral) }
        if hasSevere || measured.contains(.narrowPulsePressure)
            || measured.contains(.lowBloodPressure) {
            group = .emergency
        }

        if reasons.isEmpty { reasons = [.noneOfThese] }

        return WHOCarePlan(group: group,
                           reasons: reasons,
                           phase: phase,
                           feverDay: feverDaysAgo.map { $0 + 1 })
    }

    /// Readings that cross a threshold WHO's guidance names.
    ///
    /// Nil readings are not concerns: a blood pressure never taken is not a
    /// normal blood pressure, and a missing number must never quietly move
    /// someone into a calmer group.
    private static func measuredConcerns(_ vitals: VitalsEntry?) -> [Reason] {
        guard let vitals else { return [] }
        var found: [Reason] = []

        if let systolic = vitals.systolic, let diastolic = vitals.diastolic,
           systolic - diastolic <= Threshold.narrowPulsePressure {
            found.append(.narrowPulsePressure)
        }
        if let systolic = vitals.systolic, systolic < Threshold.lowSystolic {
            found.append(.lowBloodPressure)
        }
        if let pulse = vitals.pulse, pulse > Threshold.fastPulse {
            found.append(.fastPulse)
        }
        if let oxygen = vitals.oxygenSaturation, oxygen < Threshold.lowOxygen {
            found.append(.lowOxygen)
        }
        return found
    }
}
