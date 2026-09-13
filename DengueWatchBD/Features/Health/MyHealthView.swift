import SwiftUI

/// The reader's own health, in one place: how they feel, what they measured,
/// and what the app last suggested they do.
///
/// Drawn in the Broadsheet system — newsprint, serif, tints not borders, and
/// only one colour for alarm. See `Broadsheet` for why a normal reading here
/// is not green.
///
/// It records and shows. It does not interpret. Every number here came from
/// the reader or from the triage engine's existing rules, and nothing on this
/// screen turns a set of readings into a conclusion about what is wrong.
struct MyHealthView: View {
    @Environment(CaseLogStore.self) private var caseLog
    @Environment(VitalsStore.self) private var vitals
    @Environment(LabStore.self) private var labs
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc

    @State private var showingCheck = false
    @State private var showingVitals = false
    @State private var showingLab = false
    @State private var showingLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Broadsheet.Space.section) {
                    header
                    carePlanBanner
                    todaySection
                    temperatureSection
                    vitalsSection
                    labSection
                    actions
                    disclaimer
                }
                .padding(.horizontal, Broadsheet.Space.screen)
                .padding(.top, Broadsheet.Space.row)
                .padding(.bottom, 40)
                .readableColumn()
            }
            .background(Broadsheet.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingLog) { CaseLogView() }
            .sheet(isPresented: $showingCheck) { SymptomCheckerView() }
            .sheet(isPresented: $showingVitals) { VitalsEntryView() }
            .sheet(isPresented: $showingLab) { LabEntryView() }
        }
        // Broadsheet is a printed page: it has one appearance, not two.
        .environment(\.colorScheme, .light)
        .tint(Broadsheet.accent700)
    }

    // MARK: - Header

    /// The bundle's header pattern: a row of kicker metadata, then the screen
    /// title flush left.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            KickerRow(text: loc.style.weekdayDate(Date())) {
                HStack(spacing: 14) {
                    Button {
                        withAnimation(Motion.interactive) { loc.toggle() }
                        Haptic.selection()
                    } label: {
                        Kicker(text: loc.language.shortLabel, tint: Broadsheet.accent700)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(loc.t("lang.toggle.a11y"))

                    Button { showingLog = true } label: {
                        Text(loc.t("log.title"))
                            .broadsheet(.secondary)
                            .foregroundStyle(Broadsheet.accent700)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(loc.t("tab.health"))
                .broadsheet(.screenTitle)
                .foregroundStyle(Broadsheet.ink)
        }
    }

    // MARK: - Care plan

    /// The design's severity banner, driven by the symptom check alone.
    ///
    /// The bundle stages the illness out loud — "Dengue with warning signs",
    /// reasoned from platelets. This app does not: the outcome here is the
    /// triage engine's existing advice about what to do, not a claim about
    /// what the reader has. The banner takes the alarm ink only when that
    /// advice is urgent.
    @ViewBuilder
    private var carePlanBanner: some View {
        if let latest = caseLog.entries.first {
            let urgent = latest.outcome >= .seeDoctorToday
            let severe = latest.outcome == .emergency
            let fill = severe ? Broadsheet.alarm700 : (urgent ? Broadsheet.alarm100 : Broadsheet.neutral100)
            let heading = severe ? Color.white : (urgent ? Broadsheet.alarm700 : Broadsheet.ink)
            let body = severe ? Color.white : (urgent ? Broadsheet.alarm900 : Broadsheet.neutral800)

            BroadsheetPanel(fill: fill, padding: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: urgent ? "exclamationmark.triangle.fill" : "info.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(heading)
                            .accessibilityHidden(true)
                        Kicker(text: loc.t("care.plan.title"), tint: heading)
                    }
                    Text(loc.t(latest.outcome.headlineKey))
                        .broadsheet(.bannerHeading)
                        .foregroundStyle(heading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc.t(latest.outcome.summaryKey))
                        .broadsheet(.body)
                        .foregroundStyle(body)
                        .fixedSize(horizontal: false, vertical: true)

                    let context = carePlanContext
                    if context.hasAnything {
                        Text(loc.t("care.plan.readings", readingNames(context)))
                            .broadsheet(.secondary)
                            .foregroundStyle(body)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    HStack(spacing: 8) {
                        Text(loc.t("care.plan.recheck"))
                            .broadsheet(.secondary)
                            .foregroundStyle(severe ? Broadsheet.alarm700 : .white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(severe ? Color.white : (urgent ? Broadsheet.alarm700 : Broadsheet.accent700),
                                        in: RoundedRectangle(cornerRadius: Broadsheet.Radius.card))
                            .onTapGesture { showingCheck = true }
                    }
                    .padding(.top, 4)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Today

    private var todaySection: some View {
        let checkedToday = caseLog.entries.first.map {
            Calendar.current.isDateInToday($0.date)
        } ?? false
        let vitalsToday = vitals.latest.map {
            Calendar.current.isDateInToday($0.date)
        } ?? false

        return BroadsheetSection(kicker: loc.t("health.today.title")) {
            VStack(spacing: 0) {
                todayRow(title: loc.t("health.today.symptoms"),
                         done: checkedToday) { showingCheck = true }
                todayRow(title: loc.t("health.today.vitals"),
                         done: vitalsToday, isLast: true) { showingVitals = true }
            }
        }
    }

    private func todayRow(title: String, done: Bool, isLast: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BroadsheetRow(showsDivider: !isLast) {
                HStack(spacing: Broadsheet.Space.row) {
                    Text(title)
                        .broadsheet(.bodyLarge)
                        .foregroundStyle(Broadsheet.ink)
                    Spacer(minLength: 0)
                    Text(loc.t(done ? "health.today.done" : "health.today.todo"))
                        .broadsheet(.secondary)
                        .foregroundStyle(Broadsheet.neutral700)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Broadsheet.neutral500)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(done ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Temperature

    @ViewBuilder
    private var temperatureSection: some View {
        let points = vitals.series(for: .temperature)
        if points.count >= 2 {
            let latest = points.last
            let status = latest.map { VitalKind.temperature.status($0.value) }
            BroadsheetSection(
                kicker: loc.t("trend.chart.temperature"),
                detail: latest.map {
                    loc.t("vital.nowReading",
                          preferences.temperatureUnit.display(celsius: $0.value, style: loc.style))
                },
                detailTint: status.map(Broadsheet.statusInk) ?? Broadsheet.accent700
            ) {
                BroadsheetPanel(padding: 12) {
                    HealthTrendChart(
                        style: loc.style,
                        title: loc.t("trend.chart.temperature"),
                        points: points.map {
                            (date: $0.date,
                             value: preferences.temperatureUnit.fromCelsius($0.value))
                        },
                        trend: HealthTrend.direction(
                            of: points.map(\.value),
                            minimumChange: VitalKind.temperature.minimumMeaningfulChange),
                        tint: Broadsheet.accent700,
                        usualRange: usualTemperatureRange,
                        thresholdWord: loc.t("trend.threshold.fever"),
                        format: { String(format: "%.1f", $0) })
                }
            }
        }
    }

    private var usualTemperatureRange: ClosedRange<Double> {
        let range = VitalKind.temperature.usualRange
        let unit = preferences.temperatureUnit
        return unit.fromCelsius(range.lowerBound)...unit.fromCelsius(range.upperBound)
    }

    // MARK: - Vitals

    private var vitalsSection: some View {
        BroadsheetSection(
            kicker: loc.t("vital.section"),
            detail: vitals.latest.map { loc.dayAndTime($0.date) },
            detailTint: Broadsheet.neutral600
        ) {
            if vitals.entries.isEmpty {
                Text(loc.t("vital.none"))
                    .broadsheet(.body)
                    .foregroundStyle(Broadsheet.neutral700)
            } else {
                LazyVGrid(columns: cardColumns, spacing: Broadsheet.Space.grid) {
                    bloodPressureCard
                    vitalCard(.pulse)
                    vitalCard(.oxygenSaturation)
                    vitalCard(.temperature)
                }
            }
        }
    }

    private var cardColumns: [GridItem] {
        [GridItem(.flexible(), spacing: Broadsheet.Space.grid),
         GridItem(.flexible(), spacing: Broadsheet.Space.grid)]
    }

    /// Blood pressure is one reading written as a pair, so it gets one card.
    private var bloodPressureCard: some View {
        let systolic = vitals.mostRecent(.systolic)
        let diastolic = vitals.mostRecent(.diastolic)
        let status: MeasureStatus? = {
            guard let s = systolic?.value, let d = diastolic?.value else { return nil }
            let a = VitalKind.systolic.status(s), b = VitalKind.diastolic.status(d)
            return a.risk >= b.risk ? a : b
        }()
        let value = (systolic?.value).flatMap { s in
            (diastolic?.value).map { d in "\(loc.num(Int(s)))/\(loc.num(Int(d)))" }
        }
        return MeasureCard(
            label: loc.t("vital.bloodPressure"),
            value: value ?? "—",
            unit: value == nil ? nil : loc.t("vital.unit.systolic"),
            status: status,
            statusText: status.map { loc.t("status.\($0.rawValue)") },
            takenAt: systolic.map { loc.dayAndTime($0.date) })
    }

    private func vitalCard(_ kind: VitalKind) -> some View {
        let reading = vitals.mostRecent(kind)
        let status = reading.map { kind.status($0.value) }
        let value: String = {
            guard let value = reading?.value else { return "—" }
            return kind == .temperature
                ? loc.decimal(preferences.temperatureUnit.fromCelsius(value), places: 1)
                : loc.num(Int(value.rounded()))
        }()
        return MeasureCard(
            label: loc.t(kind.labelKey),
            value: value,
            unit: reading == nil ? nil
                : (kind == .temperature ? preferences.temperatureUnit.symbol : loc.t(kind.unitKey)),
            status: status,
            statusText: status.map { loc.t("status.\($0.rawValue)") },
            takenAt: reading.map { loc.dayAndTime($0.date) })
    }

    // MARK: - Labs

    private var labSection: some View {
        BroadsheetSection(
            kicker: loc.t("lab.section"),
            detail: labs.latest.map { loc.dayAndTime($0.date) },
            detailTint: Broadsheet.neutral600
        ) {
            VStack(alignment: .leading, spacing: Broadsheet.Space.grid) {
                if labs.reports.isEmpty {
                    Text(loc.t("lab.none"))
                        .broadsheet(.body)
                        .foregroundStyle(Broadsheet.neutral700)
                } else {
                    serologyChips
                    labTable
                    Text(loc.t("lab.rangeNote"))
                        .broadsheet(.secondary)
                        .foregroundStyle(Broadsheet.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Serology as chips. A dengue-positive result takes the alarm tint; every
    /// other result is neutral. The chip always says which it is.
    @ViewBuilder
    private var serologyChips: some View {
        let results = DengueTest.allCases.compactMap { test -> (DengueTest, TestResult)? in
            guard let latest = labs.mostRecentResult(test) else { return nil }
            return (test, latest.result)
        }
        if !results.isEmpty {
            FlowChips(results: results.map {
                (text: "\(loc.t($0.0.labelKey)) \(loc.t($0.1.labelKey))",
                 positive: $0.1 == .positive)
            })
        }
    }

    /// The bundle's CBC table: analyte, value, flag. Three columns, a hairline
    /// under each row but the last, no header row and no outer border.
    ///
    /// The flag follows the bundle's two-tier rule, which happens to be
    /// exactly the distinction `MeasureStatus` already draws: a reading far
    /// enough out to matter takes the alarm ink, one merely outside its range
    /// takes neutral. Both still say which they are, in a word.
    private var labTable: some View {
        let rows = LabMeasure.allCases.compactMap { measure -> (LabMeasure, Double)? in
            labs.mostRecent(measure).map { (measure, $0.value) }
        }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                let status = row.0.status(row.1)
                BroadsheetRow(showsDivider: index < rows.count - 1) {
                    HStack(alignment: .firstTextBaseline, spacing: Broadsheet.Space.row) {
                        Text(loc.t(row.0.labelKey))
                            .broadsheet(.body)
                            .foregroundStyle(Broadsheet.ink)
                        Spacer(minLength: Broadsheet.Space.tight)
                        Text("\(format(row.1, row.0)) \(loc.t(row.0.unitKey))")
                            .font(Broadsheet.serif(15, semibold: true, relativeTo: .body))
                            .foregroundStyle(Broadsheet.ink)
                            .monospacedDigit()
                        Kicker(text: flag(row.1, row.0),
                               tint: status == .farOutside
                                   ? Broadsheet.alarm700 : Broadsheet.neutral700)
                            .frame(width: 54, alignment: .trailing)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The table's flag: which side of the printed range the value falls, in
    /// a word. Saying a platelet count is low is reading the range, not
    /// reading the patient.
    private func flag(_ value: Double, _ measure: LabMeasure) -> String {
        let range = measure.typicalRange
        if value < range.lowerBound { return loc.t("lab.flag.low") }
        if value > range.upperBound { return loc.t("lab.flag.high") }
        return loc.t("lab.flag.ok")
    }

    private func format(_ value: Double, _ measure: LabMeasure) -> String {
        measure.decimals == 0 ? loc.num(Int(value.rounded())) : loc.decimal(value)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Broadsheet.Space.grid) {
            BroadsheetButton(title: loc.t("vital.record")) { showingVitals = true }
            HStack(spacing: Broadsheet.Space.grid) {
                BroadsheetButton(title: loc.t("lab.add"), fills: false) { showingLab = true }
                    .background(Broadsheet.accent100,
                                in: RoundedRectangle(cornerRadius: Broadsheet.Radius.card))
                BroadsheetButton(title: loc.t("health.check"), fills: false) { showingCheck = true }
                    .background(Broadsheet.accent100,
                                in: RoundedRectangle(cornerRadius: Broadsheet.Radius.card))
            }
        }
    }

    /// "Required on every screen that outputs a stage."
    private var disclaimer: some View {
        Text(loc.t("care.plan.note"))
            .broadsheet(.secondary)
            .foregroundStyle(Broadsheet.neutral700)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The readings worth raising

    private var carePlanContext: CarePlanContext {
        CarePlanContext.from(
            vitals: vitals.entries.flatMap { entry in
                VitalKind.allCases.compactMap { kind in
                    entry.value(for: kind).map { (kind: kind, value: $0, date: entry.date) }
                }
            },
            labs: labs.reports.flatMap { report in
                LabMeasure.allCases.compactMap { measure in
                    report.value(for: measure).map { (measure: measure, value: $0, date: report.date) }
                }
            }
        )
    }

    private func readingNames(_ context: CarePlanContext) -> String {
        let names = context.notableVitals.map { loc.t($0.labelKey) }
            + context.notableLabs.map { loc.t($0.labelKey) }
        return loc.style.list(names)
    }
}

/// Wrapping chips. Alarm tint for a dengue-positive result, neutral otherwise.
private struct FlowChips: View {
    let results: [(text: String, positive: Bool)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(results, id: \.text) { chip in
                Kicker(text: chip.text,
                       tint: chip.positive ? Broadsheet.alarm800 : Broadsheet.neutral800)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(chip.positive ? Broadsheet.alarm200 : Broadsheet.neutral200,
                                in: RoundedRectangle(cornerRadius: Broadsheet.Radius.card))
            }
        }
    }
}
