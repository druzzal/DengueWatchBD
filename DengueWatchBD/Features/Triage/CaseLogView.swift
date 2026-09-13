import SwiftUI
import Charts

/// The reader's own record: symptom checks, vital-sign readings and lab
/// reports, grouped by the day they were taken.
///
/// They are three stores because they are three different kinds of record, but
/// a person looking back at an illness thinks in days, not in stores.
struct CaseLogView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(CaseLogStore.self) private var log
    @Environment(VitalsStore.self) private var vitals
    @Environment(LabStore.self) private var labs
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    @State private var showingClearConfirmation = false
    @State private var exportURL: URL?

    private var days: [HealthLogDay] {
        HealthLog.days(checks: log.entries, vitals: vitals.entries, labs: labs.reports)
    }

    /// Temperature now comes from Vital signs, which is where it is recorded.
    private var temperatureSeries: [(date: Date, value: Double)] {
        vitals.series(for: .temperature)
    }

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    ContentUnavailableView {
                        Label(loc.t("log.empty.title"), systemImage: "list.clipboard")
                    } description: {
                        Text(loc.t("log.empty.detail"))
                    }
                } else {
                    List {
                        if temperatureSeries.count >= 2 {
                            Section(loc.t("log.temperature")) { temperatureChart }
                        }

                        ForEach(days) { day in
                            Section(dayTitle(day.date)) {
                                ForEach(day.itemsNewestFirst) { item in
                                    row(for: item)
                                        .swipeActions {
                                            Button(loc.t("common.delete"), role: .destructive) {
                                                delete(item)
                                            }
                                        }
                                }
                            }
                        }

                        Section {
                            Button(loc.t("common.deleteAll"), role: .destructive) {
                                showingClearConfirmation = true
                            }
                        } footer: {
                            Text(loc.t("log.privacyFooter"))
                        }
                    }
                }
            }
            .readableColumn()
            .navigationTitle(loc.t("log.title"))
            .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LanguageToggle() }
                ToolbarItem(placement: .topBarTrailing) { exportButton }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t("common.done")) { dismiss() }
                }
            }
            .confirmationDialog(loc.t("log.confirmDelete"),
                                isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                Button(loc.t("common.deleteAll"), role: .destructive) {
                    log.clear()
                    vitals.clear()
                    labs.clear()
                }
                Button(loc.t("common.cancel"), role: .cancel) {}
            }
            .task(id: days.count) { refreshExport() }
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if let exportURL {
            ShareLink(item: exportURL,
                      preview: SharePreview(loc.t("log.pdf.title"))) {
                Label(loc.t("log.export"), systemImage: "square.and.arrow.up")
            }
        }
    }

    /// Rebuilt when the log changes, so the shared file is never a stale copy
    /// of an earlier version of the record.
    private func refreshExport() {
        exportURL = HealthLogPDF.write(days: days, loc: loc,
                                       unit: preferences.temperatureUnit)
    }

    @ViewBuilder
    private func row(for item: HealthLogDay.Item) -> some View {
        switch item {
        case .check(let entry): CaseLogRow(entry: entry)
        case .vitals(let entry): VitalsLogRow(entry: entry)
        case .lab(let report): LabLogRow(report: report)
        }
    }

    private func delete(_ item: HealthLogDay.Item) {
        switch item {
        case .check(let entry): log.delete(id: entry.id)
        case .vitals(let entry): vitals.delete(id: entry.id)
        case .lab(let report): labs.delete(id: report.id)
        }
    }

    /// "Today" and "Yesterday" read faster than a date when that is what they
    /// are; anything older gets the date it happened.
    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return loc.t("common.today") }
        if calendar.isDateInYesterday(date) { return loc.t("common.yesterday") }
        return loc.fullDate(date)
    }

    /// Days covered by the temperature readings.
    private var temperatureSpanInDays: Int {
        guard let first = temperatureSeries.first?.date,
              let last = temperatureSeries.last?.date else { return 0 }
        return Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
    }

    private var temperatureChart: some View {
        // Read outside the axis builders: those are nonisolated and cannot
        // touch the stores or the environment.
        let style = loc.style
        let shortSpan = temperatureSpanInDays <= 2
        return Chart(temperatureSeries, id: \.date) { item in
            LineMark(x: .value("Date", item.date), y: .value("C", item.value))
                .foregroundStyle(Palette.deaths)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", item.date), y: .value("C", item.value))
                .foregroundStyle(Palette.deaths)
                .symbolSize(60)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Palette.grid)
                AxisValueLabel {
                    if let temp = value.as(Double.self) {
                        // A fever moves in tenths. Whole degrees label a
                        // two-reading chart "39, 39, 39, 39, 39".
                        Text(style.decimal(temp, places: 1))
                            .typoStatic(.micro)
                            .foregroundStyle(Palette.mutedInk)
                    }
                }
            }
        }
        .chartXAxis {
            if shortSpan {
                // Over a day or two, "automatic" puts ticks inside a day and
                // the day-only label then prints the same date twice.
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(collisionResolution: .disabled) {
                        if let date = value.as(Date.self) {
                            Text(style.dayMonth(date))
                                .typoStatic(.micro)
                                .foregroundStyle(Palette.mutedInk)
                        }
                    }
                }
            } else {
                dateAxis(style, desiredCount: 3)
            }
        }
        .frame(height: 130)
        .padding(.trailing, 22)
        .padding(.vertical, 6)
    }
}

private struct CaseLogRow: View {
    @Environment(LocalizationManager.self) private var loc
    let entry: CaseLogEntry

    private var accent: Color {
        switch entry.outcome {
        case .selfCare: Palette.downIsGood
        case .testAdvised: Palette.riskTint(.moderate)
        case .seeDoctorToday: Palette.riskTint(.high)
        case .emergency: Palette.riskTint(.severe)
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
private struct VitalsLogRow: View {
    @Environment(LocalizationManager.self) private var loc
    let entry: VitalsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.cases)
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
private struct LabLogRow: View {
    @Environment(LocalizationManager.self) private var loc
    let report: LabReport

    private var testsDone: [DengueTest] {
        DengueTest.allCases.filter { report.result(for: $0) != .notDone }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.admitted)
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
                                         ? Palette.riskInk(.high) : .secondary)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
