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
    /// Chosen for deletion while editing. Ids, not entries: the list is
    /// rebuilt from three stores on every change, so holding the values would
    /// go stale the moment one is removed.
    @State private var selection: Set<UUID> = []
    @State private var isEditing = false
    /// Oldest first when true. The log is always ordered by date; this only
    /// decides which end the reader starts from.
    @AppStorage("log.oldestFirst") private var oldestFirst = false
    /// The record being renamed, and the text as it is typed.
    @State private var renaming: HealthLogDay.Item?
    @State private var draftName = ""

    private var days: [HealthLogDay] {
        let ordered = HealthLog.days(checks: log.entries, vitals: vitals.entries,
                                     labs: labs.reports)
        return oldestFirst ? ordered.reversed() : ordered
    }

    /// Each record's number, counted from the oldest so it stays put.
    private var numbers: [UUID: Int] {
        HealthLog.numbers(checks: log.entries, vitals: vitals.entries, labs: labs.reports)
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
                    List(selection: $selection) {
                        if temperatureSeries.count >= 2 {
                            Section(loc.t("log.temperature")) { temperatureChart }
                        }

                        ForEach(days) { day in
                            Section {
                                ForEach(day.itemsNewestFirst) { item in
                                    NavigationLink {
                                        LogEntryDetailView(item: item)
                                    } label: {
                                        LogSummaryRow(item: item, number: numbers[item.id])
                                    }
                                    .contextMenu {
                                        Button(loc.t("log.rename"), systemImage: "pencil") {
                                            draftName = item.name
                                            renaming = item
                                        }
                                    }
                                    .swipeActions {
                                        Button(loc.t("common.delete"), role: .destructive) {
                                            delete(item)
                                        }
                                    }
                                }
                            } header: {
                                dayHeader(day)
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
            .environment(\.editMode, .constant(isEditing ? .active : .inactive))
            .readableColumn()
            .navigationTitle(loc.t("log.title"))
            .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LanguageToggle() }
                ToolbarItem(placement: .topBarTrailing) { exportButton }
                ToolbarItem(placement: .topBarTrailing) { editButton }
                ToolbarItem(placement: .topBarLeading) { sortMenu }
                if isEditing {
                    ToolbarItem(placement: .bottomBar) { deleteSelectedButton }
                }
                if !isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(loc.t("common.done")) { dismiss() }
                    }
                }
            }
            .alert(loc.t("log.rename"), isPresented: renamingBinding) {
                TextField(loc.t("log.rename.placeholder"), text: $draftName)
                Button(loc.t("common.save")) { commitRename() }
                Button(loc.t("common.cancel"), role: .cancel) { renaming = nil }
            } message: {
                Text(loc.t("log.rename.detail"))
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

        }
    }

    /// The PDF is built when the reader actually shares, not when the screen
    /// opens.
    ///
    /// It used to be rendered eagerly on appear: opening the log laid out and
    /// rasterised every page of the document — four pages for a month of
    /// entries — on the main actor, for a file most readers never ask for. The
    /// export is also always current this way, with no cached copy to go stale
    /// behind a later entry.
    /// Which end of the record to start from. The order itself is never in
    /// question — it is the date — only the direction.
    private var sortMenu: some View {
        Menu {
            Picker("", selection: $oldestFirst) {
                Text(loc.t("log.sort.newest")).tag(false)
                Text(loc.t("log.sort.oldest")).tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel(loc.t("log.sort"))
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func commitRename() {
        guard let renaming else { return }
        switch renaming {
        case .check(let entry): log.rename(id: entry.id, to: draftName)
        case .vitals(let entry): vitals.rename(id: entry.id, to: draftName)
        case .lab(let report): labs.rename(id: report.id, to: draftName)
        }
        self.renaming = nil
    }

    /// Our own control rather than `EditButton`, whose title follows the
    /// device language and would read "Edit" on a screen the reader has set
    /// to Bangla.
    @ViewBuilder
    private var editButton: some View {
        if !days.isEmpty {
            Button(loc.t(isEditing ? "common.done" : "common.edit")) {
                withAnimation(Motion.interactive) {
                    isEditing.toggle()
                    if !isEditing { selection.removeAll() }
                }
            }
        }
    }

    /// Deletes what is ticked. Disabled rather than hidden when nothing is,
    /// so the row does not appear and vanish as the reader selects.
    private var deleteSelectedButton: some View {
        Button(role: .destructive) {
            deleteSelected()
        } label: {
            Text(selection.isEmpty
                 ? loc.t("common.delete")
                 : loc.t("log.delete.selected", loc.num(selection.count)))
        }
        .disabled(selection.isEmpty)
    }

    /// Every entry of a day, for readers who want the day gone rather than
    /// each line of it.
    private func dayHeader(_ day: HealthLogDay) -> some View {
        HStack {
            Text(dayTitle(day.date))
            Spacer(minLength: Space.tight)
            if isEditing {
                Button(loc.t("log.delete.day")) {
                    withAnimation { deleteDay(day) }
                }
                .font(.caption)
                .foregroundStyle(Palette.riskInk(.severe))
                .textCase(nil)
            }
        }
    }

    private func deleteSelected() {
        let chosen = days.flatMap(\.itemsNewestFirst).filter { selection.contains($0.id) }
        withAnimation { chosen.forEach(delete) }
        selection.removeAll()
    }

    private func deleteDay(_ day: HealthLogDay) {
        day.itemsNewestFirst.forEach(delete)
        selection.subtract(Set(day.itemsNewestFirst.map(\.id)))
    }

    @ViewBuilder
    private var exportButton: some View {
        if !days.isEmpty {
            ShareLink(item: exportDocument,
                      preview: SharePreview(loc.t("log.pdf.title"))) {
                Label(loc.t("log.export"), systemImage: "square.and.arrow.up")
            }
        }
    }

    private var exportDocument: HealthLogDocumentFile {
        HealthLogDocumentFile(days: days, loc: loc, unit: preferences.temperatureUnit)
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
                .foregroundStyle(Palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", item.date), y: .value("C", item.value))
                .foregroundStyle(Palette.accent)
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

/// One line in the log: what kind of record it is, the figures worth seeing
/// at a glance, and when. Everything else is a tap away.
private struct LogSummaryRow: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(Preferences.self) private var preferences
    let item: HealthLogDay.Item
    /// Its place in the record, counted from the oldest.
    let number: Int?

    var body: some View {
        HStack(alignment: .top, spacing: Space.row) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .typo(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(titleTint)
                    .lineLimit(1)
                Text(subtitle)
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.tight)
            Text(loc.time(item.date))
                .typo(.micro)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var accent: Color {
        switch item {
        case .check(let entry): Palette.riskInk(outcomeRisk(entry.outcome))
        case .vitals: Palette.accent
        case .lab: Palette.accent
        }
    }

    private var titleTint: Color {
        if case .check(let entry) = item, entry.outcome >= .seeDoctorToday {
            return Palette.riskInk(outcomeRisk(entry.outcome))
        }
        return .primary
    }

    /// The reader's own name for the record, or its number.
    private var displayName: String {
        let given = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !given.isEmpty { return given }
        guard let number else { return kind }
        return loc.t("log.defaultName", loc.num(number))
    }

    /// What it is, and the figures worth scanning, under the name.
    private var subtitle: String {
        guard let summary else { return kind }
        return "\(kind) · \(summary)"
    }

    private var kind: String {
        switch item {
        case .check(let entry): loc.t(entry.outcome.headlineKey)
        case .vitals: loc.t("vital.section")
        case .lab: loc.t("lab.section")
        }
    }

    /// The figures a reader scans for, in the order they would read them.
    private var summary: String? {
        switch item {
        case .check(let entry):
            let names = TriageEngine.symptoms
                .filter { entry.symptomIDs.contains($0.id) }
                .map { loc.t($0.titleKey) }
            return names.isEmpty ? nil : loc.style.list(names)

        case .vitals(let entry):
            var parts: [String] = []
            if let temperature = entry.temperature {
                parts.append(preferences.temperatureUnit.display(celsius: temperature,
                                                                 style: loc.style))
            }
            if let systolic = entry.systolic, let diastolic = entry.diastolic {
                parts.append("\(loc.num(Int(systolic)))/\(loc.num(Int(diastolic)))")
            }
            if let pulse = entry.pulse {
                parts.append("\(loc.num(Int(pulse))) \(loc.t("vital.unit.pulse"))")
            }
            if let oxygen = entry.oxygenSaturation {
                parts.append("\(loc.num(Int(oxygen)))\(loc.t("vital.unit.oxygenSaturation"))")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")

        case .lab(let report):
            var parts: [String] = []
            for measure in LabMeasure.allCases {
                guard let value = report.value(for: measure) else { continue }
                let shown = measure.decimals == 0
                    ? loc.num(Int(value.rounded())) : loc.decimal(value)
                parts.append("\(loc.t(measure.labelKey)) \(shown)")
            }
            for test in DengueTest.allCases where report.result(for: test) != .notDone {
                parts.append("\(loc.t(test.labelKey)) \(loc.t(report.result(for: test).labelKey))")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    private func outcomeRisk(_ outcome: TriageOutcome) -> RiskLevel {
        switch outcome {
        case .selfCare: .low
        case .testAdvised: .moderate
        case .seeDoctorToday: .high
        case .emergency: .severe
        }
    }
}
