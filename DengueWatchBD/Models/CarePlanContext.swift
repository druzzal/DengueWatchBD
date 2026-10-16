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

        // In the measures' own order — platelets first, the one that matters
        // in dengue — not alphabetically, which put haematocrit ahead of it.
        // The same order Android uses, so both say the same sentence.
        return CarePlanContext(
            notableVitals: VitalKind.allCases.filter(vitalsOut.contains),
            notableLabs: LabMeasure.allCases.filter(labsOut.contains)
        )
    }

    /// Whether the haematocrit has gone up on each of the last two reports.
    ///
    /// WHO 2025 lists a "progressive increase in haematocrit on at least two
    /// consecutive measurements" among the reasons clinicians admit someone
    /// with dengue. Read here as two rises in a row — three reports, each
    /// higher than the one before — because one rise is a single comparison,
    /// not a progression.
    ///
    /// It is raised beside the plan and never moves the group, for the same
    /// reason no lab value does: this is a pattern for a doctor to act on, and
    /// the app only points at it. A rise smaller than the assay's own scatter
    /// does not count, or two readings a fraction apart would flag every week.
    /// The newest report has to be recent: a rise that ended a week ago says
    /// nothing about today.
    static func haematocritIsRising(_ series: [(date: Date, value: Double)],
                                    now: Date = Date()) -> Bool {
        let ordered = series.sorted { $0.date < $1.date }
        guard ordered.count >= 3, let newest = ordered.last,
              now.timeIntervalSince(newest.date) <= recencyWindow else { return false }
        let lastThree = ordered.suffix(3).map(\.value)
        let step = LabMeasure.haematocrit.minimumMeaningfulChange
        return lastThree[1] - lastThree[0] >= step && lastThree[2] - lastThree[1] >= step
    }
}
