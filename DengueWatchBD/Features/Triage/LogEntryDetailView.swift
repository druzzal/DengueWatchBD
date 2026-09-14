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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.stack) {
                Card {
                    switch item {
                    case .check(let entry): CheckDetail(entry: entry)
                    case .vitals(let entry): VitalsDetail(entry: entry)
                    case .lab(let report): LabDetail(report: report)
                    }
                }
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

private struct CheckDetail: View {
    @Environment(LocalizationManager.self) private var loc
    let entry: CaseLogEntry

    private var accent: Color {
        switch entry.outcome {
        case .selfCare, .testAdvised: Palette.mutedInk
        case .seeDoctorToday, .emergency: Palette.riskInk(.high)
        }
    }

    private var symptoms: [Symptom] {
        TriageEngine.symptoms.filter { entry.symptomIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3, height: 14)
                Text(loc.t(entry.outcome.headlineKey))
                    .typo(.subheadline).fontWeight(.medium)
                Spacer(minLength: 6)
                Text(loc.time(entry.date))
                    .typo(.micro).foregroundStyle(.secondary).monospacedDigit()
            }

            if !symptoms.isEmpty {
                HStack(spacing: 6) {
                    ForEach(symptoms.prefix(6)) { symptom in
                        SymptomIllustration(symptomID: symptom.id, group: symptom.group, size: 28)
                    }
                    if symptoms.count > 6 {
                        Text("+\(loc.num(symptoms.count - 6))")
                            .typo(.micro).foregroundStyle(.secondary)
                    }
                }
            }

            if !entry.note.isEmpty {
                Text(entry.note).typo(.caption).italic()
            }
        }
        .padding(.vertical, 5)
    }
}

/// One set of readings, coloured the way the tiles in My health are: green
/// while normal, orange then red as they move out of range.
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
                reading(label: loc.t("vital.bloodPressure"),
                        value: "\(loc.num(Int(systolic)))/\(loc.num(Int(diastolic)))",
                        status: worse(VitalKind.systolic.status(systolic),
                                      VitalKind.diastolic.status(diastolic)))
            }
            ForEach(VitalKind.allCases.filter(shouldShow)) { kind in
                if let value = entry.value(for: kind) {
                    reading(label: loc.t(kind.labelKey),
                            value: kind == .temperature
                                ? preferences.temperatureUnit.display(celsius: value, style: loc.style)
                                : "\(loc.decimal(value, places: kind.decimals)) \(loc.t(kind.unitKey))",
                            status: kind.status(value))
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

    private func worse(_ a: MeasureStatus, _ b: MeasureStatus) -> MeasureStatus {
        a.risk >= b.risk ? a : b
    }

    private func reading(label: String, value: String, status: MeasureStatus) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .typo(.caption).fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(Palette.riskInk(status.risk))
            Text(label)
                .typo(.micro).foregroundStyle(.secondary)
                .lineLimit(2)
        }
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
                Text(loc.t("lab.section"))
                    .typo(.subheadline).fontWeight(.medium)
                Spacer(minLength: 6)
                Text(loc.time(report.date))
                    .typo(.micro).foregroundStyle(.secondary).monospacedDigit()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                      alignment: .leading, spacing: 6) {
                ForEach(LabMeasure.allCases) { measure in
                    if let value = report.value(for: measure) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(loc.decimal(value, places: measure.decimals)) \(loc.t(measure.unitKey))")
                                .typo(.caption).fontWeight(.semibold).monospacedDigit()
                                .foregroundStyle(Palette.riskInk(measure.status(value).risk))
                            Text(loc.t(measure.labelKey))
                                .typo(.micro).foregroundStyle(.secondary).lineLimit(2)
                        }
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
