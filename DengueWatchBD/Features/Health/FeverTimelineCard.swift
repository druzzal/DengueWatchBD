import SwiftUI

/// The course of the illness as a strip of days, with the phase bands behind
/// it and today marked.
///
/// The one thing this screen exists to say is that dengue's dangerous days are
/// not its worst-feeling ones: the critical phase begins as the fever settles,
/// around day 4. A number on a card does not carry that. A band you can see
/// yourself approaching does.
///
/// Phase boundaries come from `TriageEngine.FeverPhase`, so the timeline and
/// the sentence under the symptom result can never disagree.
struct FeverTimelineCard: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(Preferences.self) private var preferences

    /// Day of illness, counting the first day of fever as day 1.
    let currentDay: Int
    /// Temperatures already recorded, to mark the days that have readings.
    let temperatures: [(date: Date, value: Double)]
    let feverStarted: Date

    private let lastDay = 10

    private var phase: TriageEngine.FeverPhase {
        TriageEngine.FeverPhase.phase(feverDaysAgo: max(0, currentDay - 1))
    }

    var body: some View {
        CardSection(loc.t("fever.timeline.title"),
                    subtitle: loc.t("fever.timeline.subtitle")) {
            VStack(alignment: .leading, spacing: Space.row) {
                dayHeadline
                strip
                legend
                InlineNote(symbol: "info.circle", detail: loc.t("fever.timeline.note"))
            }
        }
    }

    private var dayHeadline: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.tight) {
            Text(loc.t("fever.timeline.day", loc.num(currentDay)))
                .typo(.sectionTitle)
                .foregroundStyle(Palette.riskInk(phaseRisk(phase)))
            Text(loc.t(phase.nameKey))
                .typo(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.riskInk(phaseRisk(phase)))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.riskSoft(phaseRisk(phase)),
                            in: Capsule())
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// One column per day. The fill says which phase the day belongs to; the
    /// ring says it is today; a dot says a temperature was recorded.
    private var strip: some View {
        HStack(spacing: 4) {
            ForEach(1...lastDay, id: \.self) { day in
                let dayPhase = TriageEngine.FeverPhase.phase(feverDaysAgo: day - 1)
                let isToday = day == currentDay
                let isPast = day < currentDay

                VStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.riskTint(phaseRisk(dayPhase))
                                .opacity(isPast || isToday ? 0.9 : 0.22))
                            .frame(height: isToday ? 34 : 24)
                        if hasReading(day: day) {
                            Circle()
                                .fill(.white)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .overlay {
                        if isToday {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Palette.riskInk(phaseRisk(dayPhase)), lineWidth: 2)
                                .frame(height: 34)
                        }
                    }
                    Text(loc.num(day))
                        .typo(.micro)
                        .fontWeight(isToday ? .bold : .regular)
                        .foregroundStyle(isToday ? Color.primary : .secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 56, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stripDescription)
    }

    private var legend: some View {
        HStack(spacing: Space.row) {
            ForEach(TriageEngine.FeverPhase.allCases) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Palette.riskTint(phaseRisk(item)))
                        .frame(width: 10, height: 10)
                    Text(loc.t(item.nameKey))
                        .typo(.micro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    /// The critical phase is the one worth colouring as a caution. Recovery is
    /// not "low risk" in the surveillance sense, but on this card it is the
    /// good end, and the scale is the only one the app has.
    private func phaseRisk(_ phase: TriageEngine.FeverPhase) -> RiskLevel {
        switch phase {
        case .febrile: .moderate
        case .critical: .high
        case .recovery: .low
        }
    }

    private func hasReading(day: Int) -> Bool {
        let calendar = Calendar.current
        guard let dayStart = calendar.date(byAdding: .day, value: day - 1,
                                           to: calendar.startOfDay(for: feverStarted))
        else { return false }
        return temperatures.contains { calendar.isDate($0.date, inSameDayAs: dayStart) }
    }

    private var stripDescription: String {
        "\(loc.t("fever.timeline.day", loc.num(currentDay))). \(loc.t(phase.nameKey))."
    }
}
