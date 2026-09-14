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
    @Environment(LogNameStore.self) private var logNames
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    @State private var showingClearConfirmation = false
    /// Days chosen for deletion while editing. Keyed by the day itself: the
    /// list is rebuilt from three stores on every change, so holding the
    /// values would go stale the moment one record in a day is removed.
    @State private var selection: Set<Date> = []
    @State private var isEditing = false
    /// Oldest first when true. The log is always ordered by date; this only
    /// decides which end the reader starts from.
    @AppStorage("log.oldestFirst") private var oldestFirst = false
    /// The record being renamed, and the text as it is typed.
    @State private var renaming: HealthLogDay?
    @State private var draftName = ""

    private var days: [HealthLogDay] {
        let ordered = HealthLog.days(checks: log.entries, vitals: vitals.entries,
                                     labs: labs.reports)
        return oldestFirst ? ordered.reversed() : ordered
    }

    /// Each day's number, counted from the oldest so it stays put.
    private var numbers: [Date: Int] {
        HealthLog.numbers(for: days)
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

                        Section {
                            ForEach(days) { day in
                                NavigationLink {
                                    LogDayDetailView(day: day, title: title(for: day))
                                } label: {
                                    LogDaySummaryRow(day: day, title: title(for: day))
                                }
                                .swipeActions {
                                    Button(loc.t("common.delete"), role: .destructive) {
                                        deleteDay(day)
                                    }
                                }
                                .contextMenu {
                                    Button(loc.t("log.rename"), systemImage: "pencil") {
                                        draftName = logNames.name(for: day.date) ?? ""
                                        renaming = day
                                    }
                                }
                            }
                        } header: {
                            Text(loc.t("log.entries"))
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
                    logNames.clear()
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
        logNames.rename(day: renaming.date, to: draftName)
        self.renaming = nil
    }

    /// The reader's name for the day, or its number.
    private func title(for day: HealthLogDay) -> String {
        if let given = logNames.name(for: day.date) { return given }
        guard let number = numbers[day.date] else { return dayTitle(day.date) }
        return loc.t("log.defaultName", loc.num(number))
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
            deleteSelectedDays()
        } label: {
            Text(selection.isEmpty
                 ? loc.t("common.delete")
                 : loc.t("log.delete.selected", loc.num(selection.count)))
        }
        .disabled(selection.isEmpty)
    }




    private func deleteDay(_ day: HealthLogDay) {
        withAnimation {
            day.itemsNewestFirst.forEach(delete)
            // A name must not outlive the day it belonged to, or tomorrow's
            // records would inherit it.
            logNames.forget(day: day.date)
        }
        selection.remove(day.id)
    }

    private func deleteSelectedDays() {
        days.filter { selection.contains($0.id) }.forEach(deleteDay)
        selection.removeAll()
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


/// One day of the record, as a single line.
///
/// A day is the unit here: a temperature at nine, a blood pressure at three
/// and a blood count from the clinic are one day of an illness, not three
/// unrelated events. The line says what the day holds; the detail holds it.
private struct LogDaySummaryRow: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(Preferences.self) private var preferences
    let day: HealthLogDay
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.row) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .typo(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(loc.fullDate(day.date))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let figures {
                    Text(figures)
                        .typo(.micro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.tight)
            Text(loc.num(day.itemsNewestFirst.count))
                .typo(.micro)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    /// Red when the day carries an urgent outcome, so a bad day is visible
    /// without opening it.
    private var accent: Color {
        let worst = day.checks.map(\.outcome).max()
        switch worst {
        case .emergency: return Palette.riskInk(.severe)
        case .seeDoctorToday: return Palette.riskInk(.high)
        case .testAdvised: return Palette.riskInk(.moderate)
        default: return Palette.accent
        }
    }

    /// The day at a glance: its highest temperature, its latest blood
    /// pressure, and whether a lab result landed.
    private var figures: String? {
        var parts: [String] = []
        let temperatures = day.vitals.compactMap(\.temperature)
        if let peak = temperatures.max() {
            parts.append(preferences.temperatureUnit.display(celsius: peak, style: loc.style))
        }
        if let latest = day.vitals.first(where: { $0.systolic != nil && $0.diastolic != nil }),
           let systolic = latest.systolic, let diastolic = latest.diastolic {
            parts.append("\(loc.num(Int(systolic)))/\(loc.num(Int(diastolic)))")
        }
        if let platelets = day.labs.compactMap({ $0.platelets }).min() {
            parts.append("\(loc.t("lab.platelets")) \(loc.num(Int(platelets)))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
