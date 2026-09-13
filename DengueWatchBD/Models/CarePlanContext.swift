import Foundation

/// Whether the reader's recorded readings deserve a mention alongside the
/// advice their symptom check produced.
///
/// This is the join between the two records, and it is deliberately a narrow
/// one. The triage outcome still comes from symptoms alone — no reading here
/// changes it, upgrades it, or second-guesses it. All this decides is whether
/// to add a line saying some readings are well outside the usual range and
/// should be shown to someone.
///
/// The distinction matters. "Your platelets are low, you may have severe
/// dengue" is a diagnosis. "Some of your readings are well outside the usual
/// range, take them to a doctor" is a prompt to get the diagnosis from
/// somebody qualified to give it.
struct CarePlanContext: Equatable {
    /// Readings far enough out to be worth raising. Empty means say nothing.
    let notableVitals: [VitalKind]
    let notableLabs: [LabMeasure]

    var hasAnything: Bool { !notableVitals.isEmpty || !notableLabs.isEmpty }

    /// How recent a reading has to be to still be worth mentioning.
    ///
    /// A reading from last month says nothing about today, and raising it
    /// beside today's advice would be noise that teaches people to ignore the
    /// line entirely.
    static let recencyWindow: TimeInterval = 3 * 24 * 60 * 60

    static func from(vitals: [(kind: VitalKind, value: Double, date: Date)],
                     labs: [(measure: LabMeasure, value: Double, date: Date)],
                     now: Date = Date()) -> CarePlanContext {
        let cutoff = now.addingTimeInterval(-recencyWindow)

        // Only `farOutside`, not merely outside. A haemoglobin a fraction under
        // the line every week would make this permanent furniture.
        let vitalsOut = vitals
            .filter { $0.date >= cutoff && $0.kind.status($0.value) == .farOutside }
            .map(\.kind)
        let labsOut = labs
            .filter { $0.date >= cutoff && $0.measure.status($0.value) == .farOutside }
            .map(\.measure)

        return CarePlanContext(
            notableVitals: Array(Set(vitalsOut)).sorted { $0.rawValue < $1.rawValue },
            notableLabs: Array(Set(labsOut)).sorted { $0.rawValue < $1.rawValue }
        )
    }
}
