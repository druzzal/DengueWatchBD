import SwiftUI

/// One entry from the log, in full.
///
/// The list gives a line each — enough to find the day and the moment. This
/// is the whole record of that moment: every reading with its range, every
/// symptom, every test that was done, and whatever note was written at the
/// time. It is also the screen a reader is most likely to hold up to a
/// doctor, so nothing is abbreviated here.
struct LogEntryDetailView: View {
    @Environment(LocalizationManager.self) private var loc
    let item: HealthLogDay.Item

    /// The record itself, without the screen around it, so the day view can
    /// stack several of them without a second implementation.
    @ViewBuilder
    static func content(for item: HealthLogDay.Item) -> some View {
        switch item {
        case .vitals(let entry): VitalsDetail(entry: entry)
        case .lab(let report): LabDetail(report: report)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.stack) {
                Card { Self.content(for: item) }
                InlineNote(symbol: "lock", detail: loc.t("log.privacyFooter"))
            }
            .padding(.horizontal, Space.screen)
            .padding(.vertical, Space.row)
            .readableColumn()
        }
        .background(Palette.plane)
        .navigationTitle(loc.dayAndTime(item.date))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct VitalsDetail: View {
    @Environment(LocalizationManager.self) private var loc
    let entry: VitalsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.accent)
                    .frame(width: 3, height: 14)
                Text(loc.t("vital.section"))
                    .typo(.subheadline).fontWeight(.medium)
                Spacer(minLength: 6)
                Text(loc.time(entry.date))
                    .typo(.micro).foregroundStyle(.secondary).monospacedDigit()
            }

            FlowReadings(entry: entry)

            if !entry.note.isEmpty {
                Text(entry.note).typo(.caption).italic()
            }
        }
        .padding(.vertical, 5)
    }
}

private struct FlowReadings: View {
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    let entry: VitalsEntry

    var body: some View {
        // Adaptive columns so a row of readings wraps instead of truncating at
        // large Dynamic Type.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                  alignment: .leading, spacing: 6) {
            if let systolic = entry.systolic, let diastolic = entry.diastolic {
                let pair = MeasureSide.bloodPressure(systolic: systolic, diastolic: diastolic)
                ReadingCell(label: loc.t("vital.bloodPressure"),
                            value: "\(loc.num(Int(systolic)))/\(loc.num(Int(diastolic)))",
                            status: pair.status,
                            side: pair.side)
            }
            ForEach(VitalKind.allCases.filter(shouldShow)) { kind in
                if let value = entry.value(for: kind) {
                    ReadingCell(label: loc.t(kind.labelKey),
                                value: kind == .temperature
                                    ? preferences.temperatureUnit.display(celsius: value, style: loc.style)
                                    : "\(loc.decimal(value, places: kind.decimals)) \(loc.t(kind.unitKey))",
                                status: kind.status(value),
                                side: kind.side(value))
                }
            }
        }
    }

    /// Systolic and diastolic are shown as one blood-pressure reading above,
    /// unless only one of the pair was recorded.
    private func shouldShow(_ kind: VitalKind) -> Bool {
        switch kind {
        case .systolic: entry.diastolic == nil
        case .diastolic: entry.systolic == nil
        default: true
        }
    }

}

/// One reading: the number, what it is, and whether it was low, normal or
/// high.
///
/// The word is on screen, not only the mark beside the number: the mark said
/// a reading was out of range without saying which way, and a log is read for
/// exactly that — a platelet count that fell, a fever that rose. A normal
/// reading is green, as it is in My health, and colour is still never the only
/// signal: the word and the mark say the same thing.
///
/// Spoken as one label: combining the children would read the number and its
/// name and stop, leaving a low count sounding exactly like a normal one.
private struct ReadingCell: View {
    @Environment(LocalizationManager.self) private var loc
    let label: String
    let value: String
    let status: MeasureStatus
    let side: MeasureSide

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .typo(.caption).fontWeight(.semibold).monospacedDigit()
                // A mark on every reading, a tick for a normal one: green and
                // red side by side must never be the only thing telling them
                // apart, which for a red-green colour-blind reader they are not.
                Image(systemName: status.symbol).font(.caption2)
            }
            .foregroundStyle(Palette.riskInk(status.risk))
            Text(label)
                .typo(.micro).foregroundStyle(.secondary)
                .lineLimit(2)
            Text(loc.t(side.labelKey))
                .typo(.micro).fontWeight(.semibold)
                .foregroundStyle(Palette.riskInk(status.risk))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status == .normal
            ? "\(label), \(value), \(loc.t(side.labelKey))"
            : "\(label), \(value), \(loc.t(side.labelKey)), \(loc.t("status.\(status.rawValue)"))")
    }
}

/// One lab report: the blood count coloured the way the readings are, and the
/// dengue tests as they were reported. Recorded, never interpreted — what the
/// values mean is the doctor's to say.
private struct LabDetail: View {
    @Environment(LocalizationManager.self) private var loc
    let report: LabReport

    private var testsDone: [DengueTest] {
        DengueTest.allCases.filter { report.result(for: $0) != .notDone }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.accent)
                    .frame(width: 3, height: 14)
                Text(loc.t("lab.report"))
                    .typo(.subheadline).fontWeight(.medium)
                Spacer(minLength: 6)
                Text(loc.time(report.date))
                    .typo(.micro).foregroundStyle(.secondary).monospacedDigit()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                      alignment: .leading, spacing: 6) {
                ForEach(LabMeasure.allCases) { measure in
                    if let value = report.value(for: measure) {
                        ReadingCell(
                            label: loc.t(measure.labelKey),
                            value: "\(loc.decimal(value, places: measure.decimals)) \(loc.t(measure.unitKey))",
                            status: measure.status(value),
                            side: measure.side(value))
                    }
                }
            }

            if !testsDone.isEmpty {
                // A positive antigen or antibody test is a finding worth
                // seeing at a glance; it is still not this app's diagnosis.
                FlowTests(results: testsDone.map { ($0, report.result(for: $0)) })
            }

            if !report.note.isEmpty {
                Text(report.note).typo(.caption).italic()
            }
        }
        .padding(.vertical, 5)
    }
}

private struct FlowTests: View {
    @Environment(LocalizationManager.self) private var loc
    let results: [(test: DengueTest, result: TestResult)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)],
                  alignment: .leading, spacing: 6) {
            ForEach(results, id: \.test) { item in
                HStack(spacing: 5) {
                    Image(systemName: item.result == .positive
                          ? "exclamationmark.circle.fill" : "checkmark.circle")
                        .typo(.micro)
                        .foregroundStyle(item.result == .positive
                                         ? Palette.riskInk(.high) : Palette.mutedInk)
                    Text("\(loc.t(item.test.labelKey)) \(loc.t(item.result.labelKey))")
                        .typo(.micro)
                        .foregroundStyle(item.result == .positive
                                         ? Palette.riskInk(.high) : Color.secondary)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
