import SwiftUI

/// The reader's own health, in one place: how they feel, what they measured,
/// and what the app last suggested they do.
///
/// Built from the app's own components and type scale, so it reads as the same
/// app as the surveillance tabs. What it keeps from the Broadsheet system is
/// the palette: cyan for interaction, magenta for alarm, and no success
/// colour — "in the usual range" is neutral ink and a word, never green, so
/// only the readings that need attention are coloured. See `Broadsheet`.
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
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showingCheck = false
    @State private var showingVitals = false
    @State private var showingLab = false
    @State private var showingLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.stack) {
                    if sizeClass == .regular {
                        ScreenTitle(text: loc.t("tab.health"))
                    }
                    todayCard
                    feverTimelineCard
                    carePlanCard
                    vitalsCard
                    labCard
                }
                .padding(.horizontal, Space.screen)
                .padding(.bottom, Space.section)
                .readableColumn()
            }
            .background(Palette.plane)
            .navigationTitle(loc.t("tab.health"))
            .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LanguageToggle() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingLog = true } label: {
                        Image(systemName: "list.clipboard")
                    }
                    .accessibilityLabel(loc.t("log.title"))
                }
            }
            .sheet(isPresented: $showingLog) { CaseLogView() }
            .sheet(isPresented: $showingCheck) { SymptomCheckerView() }
            .sheet(isPresented: $showingVitals) { VitalsEntryView() }
            .sheet(isPresented: $showingLab) { LabEntryView() }
        }
    }

    // MARK: - Today

    /// What has and has not been recorded today, so the card answers "am I up
    /// to date" without the reader counting entries themselves.
    private var todayCard: some View {
        let checkedToday = caseLog.entries.first.map {
            Calendar.current.isDateInToday($0.date)
        } ?? false
        let vitalsToday = vitals.latest.map {
            Calendar.current.isDateInToday($0.date)
        } ?? false

        return CardSection(loc.t("health.today.title"),
                           subtitle: loc.t("health.today.subtitle")) {
            VStack(spacing: Space.tight) {
                todayRow(title: loc.t("health.today.symptoms"),
                         symbol: "stethoscope",
                         done: checkedToday) { showingCheck = true }
                Divider()
                todayRow(title: loc.t("health.today.vitals"),
                         symbol: "heart.text.square",
                         done: vitalsToday) { showingVitals = true }
            }
        }
    }

    private func todayRow(title: String, symbol: String,
                          done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.row) {
                Image(systemName: done ? "checkmark.circle.fill" : symbol)
                    .font(.system(size: 20))
                    // Done is not an alarm and not a success colour: in this
                    // palette only what needs attention is coloured.
                    .foregroundStyle(done ? Palette.mutedInk : Palette.accent)
                    .frame(width: 26)
                Text(title).typo(.callout)
                Spacer(minLength: 0)
                Text(loc.t(done ? "health.today.done" : "health.today.todo"))
                    .typo(.micro)
                    .foregroundStyle(Color.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.mutedInk)
            }
            .frame(minHeight: Hit.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(done ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Care plan

    /// WHO's management group for what the reader recorded, with the readings
    /// folded in.
    ///
    /// The plan is still driven by what they reported about themselves. Vital
    /// signs can only raise the group, never lower it: a blood pressure inside
    /// its range is not evidence that someone reporting warning signs is fine,
    /// and must never be allowed to read as if it were.
    @ViewBuilder
    private var carePlanCard: some View {
        if let latest = caseLog.entries.first {
            WHOCarePlanCard(plan: whoPlan(for: latest),
                            checkedAt: latest.date,
                            isCurrent: WHOCarePlan.describesToday(
                                checkedDaysAgo: daysSince(latest.date)),
                            notableLabs: notableLabNames) {
                showingCheck = true
            }
        }
    }

    private func daysSince(_ date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: date),
                                       to: calendar.startOfDay(for: Date())).day ?? 0
    }

    private func whoPlan(for entry: CaseLogEntry) -> WHOCarePlan {
        WHOCarePlan.evaluate(symptoms: Set(entry.symptomIDs),
                             vitals: recentVitals,
                             context: entry.triageContext,
                             feverDaysAgo: currentFeverDaysAgo(entry))
    }

    /// Readings only count towards the plan while they still describe now.
    /// A blood pressure from last week says nothing about this afternoon.
    private var recentVitals: VitalsEntry? {
        guard let latest = vitals.latest else { return nil }
        let age = Date().timeIntervalSince(latest.date)
        return age <= CarePlanContext.recencyWindow ? latest : nil
    }

    /// Days of fever as of today, not as of the day the check was run — the
    /// illness moves on even when the reader does not open the app.
    private func currentFeverDaysAgo(_ entry: CaseLogEntry) -> Int? {
        guard let started = entry.feverStarted else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: started),
                                       to: calendar.startOfDay(for: Date())).day
    }

    // MARK: - Fever timeline

    @ViewBuilder
    private var feverTimelineCard: some View {
        if let entry = caseLog.entries.first,
           let started = entry.feverStarted,
           let daysAgo = currentFeverDaysAgo(entry),
           WHOCarePlan.showsTimeline(feverDaysAgo: daysAgo) {
            FeverTimelineCard(currentDay: daysAgo + 1,
                              temperatures: vitals.series(for: .temperature),
                              feverStarted: started)
        }
    }

    // MARK: - Vitals

    private var vitalsCard: some View {
        CardSection(loc.t("vital.section"),
                    subtitle: vitals.latest.map { loc.t("vital.lastTaken", loc.dayAndTime($0.date)) }) {
            VStack(alignment: .leading, spacing: Space.row) {
                if vitals.entries.isEmpty {
                    Text(loc.t("vital.none"))
                        .typo(.callout)
                        .foregroundStyle(Color.secondary)
                } else {
                    LazyVGrid(columns: tileColumns, spacing: Space.row) {
                        VitalTile(kind: .temperature, store: vitals)
                        VitalTile(kind: .pulse, store: vitals)
                        VitalTile(kind: .systolic, store: vitals)
                        VitalTile(kind: .oxygenSaturation, store: vitals)
                    }

                    let points = vitals.series(for: .temperature)
                    if points.count >= 2 {
                        HealthTrendChart(
                            style: loc.style,
                            title: loc.t("trend.chart.temperature"),
                            points: points.map {
                                // Charted in the reader's chosen unit; stored Celsius.
                                (date: $0.date,
                                 value: preferences.temperatureUnit.fromCelsius($0.value))
                            },
                            trend: HealthTrend.direction(
                                of: points.map(\.value),
                                minimumChange: VitalKind.temperature.minimumMeaningfulChange),
                            tint: Palette.accent,
                            usualRange: usualTemperatureRange,
                            thresholdWord: loc.t("trend.threshold.fever"),
                            format: { loc.decimal($0, places: 1) })
                    }

                    if let outside = vitals.latest?.readingsOutsideUsualRange, !outside.isEmpty {
                        // Names the readings and stops. What they mean together
                        // is a clinical question, and this app does not answer
                        // clinical questions.
                        InlineNote(symbol: "exclamationmark.triangle.fill",
                                   detail: loc.t("vital.outsideUsual.detail"),
                                   tint: Palette.riskInk(.high))
                    }
                }
                SecondaryActionButton(title: loc.t("vital.record"),
                                      systemImage: "plus.circle") { showingVitals = true }
            }
        }
    }

    private var tileColumns: [GridItem] {
        [GridItem(.flexible(), spacing: Space.row),
         GridItem(.flexible(), spacing: Space.row)]
    }

    /// The usual temperature band, converted into whatever unit is on screen.
    private var usualTemperatureRange: ClosedRange<Double> {
        let range = VitalKind.temperature.usualRange
        let unit = preferences.temperatureUnit
        return unit.fromCelsius(range.lowerBound)...unit.fromCelsius(range.upperBound)
    }

    // MARK: - Labs

    private var labCard: some View {
        CardSection(loc.t("lab.section"),
                    subtitle: labs.latest.map { loc.t("vital.lastTaken", loc.dayAndTime($0.date)) }) {
            VStack(alignment: .leading, spacing: Space.row) {
                if labs.reports.isEmpty {
                    Text(loc.t("lab.none"))
                        .typo(.callout)
                        .foregroundStyle(Color.secondary)
                } else {
                    serologyChips
                    labTable
                    Text(loc.t("lab.rangeNote"))
                        .typo(.micro)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SecondaryActionButton(title: loc.t("lab.add"),
                                      systemImage: "plus.circle") { showingLab = true }
            }
        }
    }

    /// Serology as chips. A dengue-positive result takes the alarm tint; every
    /// other result is neutral. The chip always says which it is.
    @ViewBuilder
    private var serologyChips: some View {
        let results = DengueTest.allCases.compactMap { test -> (DengueTest, TestResult)? in
            labs.mostRecentResult(test).map { (test, $0.result) }
        }
        if !results.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.tight)],
                      alignment: .leading, spacing: Space.tight) {
                ForEach(results, id: \.0) { test, result in
                    let positive = result == .positive
                    Text("\(loc.t(test.labelKey)) \(loc.t(result.labelKey))")
                        .typo(.micro)
                        .foregroundStyle(positive ? Palette.riskInk(.high) : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(positive ? Palette.riskSoft(.high) : Palette.hairline,
                                    in: RoundedRectangle(cornerRadius: Radius.control,
                                                         style: .continuous))
                        .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Analyte, value, flag. The flag takes its risk band's ink — the same
    /// scale the vital tiles and the map use — and says which side of the
    /// printed range it fell on, so the colour is never the only signal.
    private var labTable: some View {
        let rows = LabMeasure.allCases.compactMap { measure -> (LabMeasure, Double)? in
            labs.mostRecent(measure).map { (measure, $0.value) }
        }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                let status = row.0.status(row.1)
                HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                    Text(loc.t(row.0.labelKey))
                        .typo(.callout)
                    Spacer(minLength: Space.tight)
                    Text("\(format(row.1, row.0)) \(loc.t(row.0.unitKey))")
                        .typo(.callout)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(flag(row.1, row.0))
                        .typo(.micro)
                        // The same band the tiles use, so one status is never
                        // two colours on one screen.
                        .foregroundStyle(Palette.riskInk(status.risk))
                        .frame(width: 72, alignment: .trailing)
                }
                .frame(minHeight: Hit.minimum)
                .accessibilityElement(children: .combine)
                if index < rows.count - 1 { Divider() }
            }
        }
    }

    /// Which side of the printed range the value falls, in a word. Saying a
    /// platelet count is low is reading the range, not reading the patient.
    private func flag(_ value: Double, _ measure: LabMeasure) -> String {
        let range = measure.typicalRange
        if value < range.lowerBound { return loc.t("lab.flag.low") }
        if value > range.upperBound { return loc.t("lab.flag.high") }
        return loc.t("lab.flag.ok")
    }

    private func format(_ value: Double, _ measure: LabMeasure) -> String {
        measure.decimals == 0 ? loc.num(Int(value.rounded())) : loc.decimal(value)
    }

    // MARK: - The readings worth raising

    /// Lab values far enough out to be worth showing to a doctor.
    ///
    /// Deliberately kept out of the WHO group. That group is decided by what
    /// the reader reports and what a home monitor measures; a platelet count
    /// is neither, and letting one move someone between groups would be this
    /// app reading a lab report. It is raised beside the plan instead — which
    /// is where a lab result belongs, in the hands of whoever reads it.
    ///
    /// Vitals are passed as empty because the plan already speaks for them,
    /// through WHO's own thresholds. Naming them twice on one card would
    /// suggest two findings where there is one.
    private var notableLabNames: String? {
        let context = CarePlanContext.from(
            vitals: [],
            labs: labs.reports.flatMap { report in
                LabMeasure.allCases.compactMap { measure in
                    report.value(for: measure).map { (measure: measure, value: $0, date: report.date) }
                }
            })
        guard context.hasAnything else { return nil }
        return readingNames(context)
    }

    private func readingNames(_ context: CarePlanContext) -> String {
        let names = context.notableVitals.map { loc.t($0.labelKey) }
            + context.notableLabs.map { loc.t($0.labelKey) }
        return loc.style.list(names)
    }
}

/// One measure's most recent reading, marked when it sits outside the usual
/// range. The mark is an invitation to ask someone, not a verdict.
private struct VitalTile: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(Preferences.self) private var preferences
    let kind: VitalKind
    let store: VitalsStore

    var body: some View {
        let reading = store.mostRecent(kind)
        let status = reading.map { kind.status($0.value) }

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.mutedInk)
                Text(loc.t(kind.labelKey))
                    .typo(.micro)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(displayValue(reading?.value))
                    .typo(.statValue)
                    .monospacedDigit()
                    .foregroundStyle(status.map { Palette.riskInk($0.risk) } ?? Color.primary)
                Text(unitLabel)
                    .typo(.micro)
                    .foregroundStyle(Color.secondary)
            }
            if let taken = reading?.date {
                // Per tile, because a card can mix a temperature from this
                // morning with a blood pressure from two days ago.
                Text(loc.dayAndTime(taken))
                    .typo(.micro)
                    .foregroundStyle(Palette.mutedInk)
                    .lineLimit(1)
            }
            if let status {
                // The words carry the same grading as the colour, so the tile
                // still reads in greyscale and to a colour-blind reader.
                Text(loc.t("status.\(status.rawValue)"))
                    .typo(.micro)
                    .foregroundStyle(Palette.riskInk(status.risk))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.row)
        .background(Palette.plane,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var unitLabel: String {
        kind == .temperature ? preferences.temperatureUnit.symbol : loc.t(kind.unitKey)
    }

    private func displayValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        if kind == .temperature {
            return loc.decimal(preferences.temperatureUnit.fromCelsius(value), places: 1)
        }
        return loc.num(Int(value.rounded()))
    }
}
