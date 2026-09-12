import SwiftUI

/// Where someone is in the course of a dengue fever, drawn as a track.
///
/// The point of showing this at all is one clinical fact that surprises people:
/// the dangerous window is when the fever *falls*, not when it is highest. A
/// reader who feels better on day five and stops paying attention is exactly
/// the reader this is for.
///
/// Phase boundaries come from `TriageEngine.FeverPhase`, so this cannot drift
/// away from the sentence shown under the triage result.
struct FeverTimelineView: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 1-based day of fever. Nil when the reader has not given a start date.
    let feverDay: Int?

    private var phase: TriageEngine.FeverPhase? {
        feverDay.map { TriageEngine.FeverPhase.phase(feverDaysAgo: $0 - 1) }
    }

    private var days: [Int] { Array(1...10) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            track
            phaseLegend
            if let phase, phase == .critical {
                // Only raised while it applies, so it stays a warning rather
                // than becoming background text people stop reading.
                InlineNote(symbol: "exclamationmark.triangle.fill",
                           detail: loc.t("phase.critical.note"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Track

    private var track: some View {
        HStack(spacing: 3) {
            ForEach(days, id: \.self) { day in
                let dayPhase = TriageEngine.FeverPhase.phase(feverDaysAgo: day - 1)
                let isCurrent = day == feverDay
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tint(for: dayPhase).opacity(isCurrent ? 1 : 0.28))
                        .frame(height: isCurrent ? 22 : 12)
                    Text(loc.num(day))
                        .typo(.micro)
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? Color.primary : .secondary)
                        .fontWeight(isCurrent ? .bold : .regular)
                }
                .frame(maxWidth: .infinity)
                // The current day is marked by height and weight as well as
                // colour, so it survives colour blindness and greyscale.
                .overlay(alignment: .top) {
                    if isCurrent {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(tint(for: dayPhase))
                            .offset(y: -9)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : Motion.content, value: feverDay)
    }

    private var phaseLegend: some View {
        // Wraps to two lines at accessibility sizes rather than truncating.
        let columns = [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 140 : 96),
                                spacing: Space.tight)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(TriageEngine.FeverPhase.allCases) { item in
                HStack(spacing: 5) {
                    Circle()
                        .fill(tint(for: item))
                        .frame(width: 8, height: 8)
                    Text(loc.t(item.nameKey))
                        .typo(.micro)
                        .foregroundStyle(item == phase ? Color.primary : .secondary)
                        .fontWeight(item == phase ? .semibold : .regular)
                        .lineLimit(1)
                }
            }
        }
    }

    private func tint(for phase: TriageEngine.FeverPhase) -> Color {
        switch phase {
        case .febrile: Palette.riskTint(.moderate)
        case .critical: Palette.riskTint(.severe)
        case .recovery: Palette.riskTint(.low)
        }
    }

    /// One sentence for VoiceOver, rather than ten unlabelled bars.
    private var accessibilityDescription: String {
        guard let feverDay, let phase else { return loc.t("phase.a11y.unknown") }
        return loc.t("phase.a11y.day", loc.num(feverDay), loc.t(phase.nameKey))
    }
}
