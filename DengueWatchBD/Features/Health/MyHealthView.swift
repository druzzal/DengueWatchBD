import SwiftUI

/// The reader's own health, in one place: how they feel, what they measured,
/// and what the app last suggested they do.
///
/// It records and shows. It does not interpret. Every number here came from the
/// reader or from the triage engine's existing rules, and nothing on this
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
                    carePlanCard
                    vitalsCard
                    labCard
                    latestCheckCard
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
                    .foregroundStyle(done ? Palette.riskTint(.low) : Palette.accent)
                    .frame(width: 26)
                Text(title).typo(.callout)
                Spacer(minLength: 0)
                Text(loc.t(done ? "health.today.done" : "health.today.todo"))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: Hit.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(done ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Vitals

    private var vitalsCard: some View {
        CardSection(loc.t("vital.section"),
                    subtitle: vitals.latest.map { loc.t("vital.lastTaken", loc.dayAndTime($0.date)) }) {
            VStack(alignment: .leading, spacing: Space.row) {
                if vitals.entries.isEmpty {
                    Text(loc.t("vital.none"))
                        .typo(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.row),
                                        GridItem(.flexible(), spacing: Space.row)],
                              spacing: Space.row) {
                        VitalTile(kind: .temperature, store: vitals)
                        VitalTile(kind: .pulse, store: vitals)
                        VitalTile(kind: .systolic, store: vitals)
                        VitalTile(kind: .oxygenSaturation, store: vitals)
                    }

                    let temperaturePoints = vitals.series(for: .temperature)
                    if temperaturePoints.count >= 2 {
                        HealthTrendChart(
                            style: loc.style,
                            title: loc.t("trend.chart.temperature"),
                            points: temperaturePoints.map {
                                // Charted in the reader's chosen unit; stored Celsius.
                                (date: $0.date,
                                 value: preferences.temperatureUnit.fromCelsius($0.value))
                            },
                            trend: HealthTrend.direction(
                                of: temperaturePoints.map(\.value),
                                minimumChange: VitalKind.temperature.minimumMeaningfulChange),
                            tint: Palette.deaths,
                            usualRange: usualTemperatureRange,
                            format: { String(format: "%.1f", $0) })
                    }

                    if let outside = vitals.latest?.readingsOutsideUsualRange, !outside.isEmpty {
                        // Names the readings and stops. What they mean together
                        // is a clinical question, and this app does not answer
                        // clinical questions.
                        InlineNote(symbol: "exclamationmark.triangle.fill",
                                   detail: loc.t("vital.outsideUsual.detail"))
                    }
                }
                SecondaryActionButton(title: loc.t("vital.record"),
                                      systemImage: "plus.circle") { showingVitals = true }
            }
        }
    }

    /// The usual temperature band, converted into whatever unit is on screen.
    private var usualTemperatureRange: ClosedRange<Double> {
        let range = VitalKind.temperature.usualRange
        let unit = preferences.temperatureUnit
        return unit.fromCelsius(range.lowerBound)...unit.fromCelsius(range.upperBound)
    }

    // MARK: - Care plan

    /// What to do now, taken from the triage outcome the engine already
    /// produced.
    ///
    /// Driven by the symptom check and nothing else. It deliberately does not
    /// read the lab values: turning a platelet count into advice is the step
    /// from recording into practising medicine, and it is not a step an app
    /// should take on behalf of someone with a fever.
    @ViewBuilder
    private var carePlanCard: some View {
        if let latest = caseLog.entries.first {
            CardSection(loc.t("care.plan.title"),
                        subtitle: loc.t("care.plan.subtitle")) {
                VStack(alignment: .leading, spacing: Space.row) {
                    HStack(alignment: .top, spacing: Space.row) {
                        Image(systemName: latest.outcome.symbolName)
                            .font(.title3)
                            .foregroundStyle(Palette.riskTint(outcomeRisk(latest.outcome)))
                            .frame(width: 26)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(loc.t(latest.outcome.headlineKey))
                                .typo(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(loc.t(latest.outcome.summaryKey))
                                .typo(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    InlineNote(symbol: "info.circle", detail: loc.t("care.plan.note"))
                }
            }
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

    // MARK: - Lab reports

    private var labCard: some View {
        CardSection(loc.t("lab.section"),
                    subtitle: labs.latest.map { loc.t("lab.reported", loc.dayAndTime($0.date)) }) {
            VStack(alignment: .leading, spacing: Space.row) {
                if labs.reports.isEmpty {
                    Text(loc.t("lab.none")).typo(.callout).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.row),
                                        GridItem(.flexible(), spacing: Space.row)],
                              spacing: Space.row) {
                        ForEach(LabMeasure.allCases) { measure in
                            LabTile(measure: measure, store: labs)
                        }
                    }

                    let recorded = DengueTest.allCases.compactMap { test -> (DengueTest, TestResult)? in
                        labs.mostRecentResult(test).map { (test, $0.result) }
                    }
                    if !recorded.isEmpty {
                        VStack(alignment: .leading, spacing: Space.tight) {
                            ForEach(recorded, id: \.0) { test, result in
                                HStack(spacing: Space.tight) {
                                    Text(loc.t(test.labelKey)).typo(.caption)
                                    Spacer(minLength: Space.tight)
                                    Text(loc.t(result.labelKey))
                                        .typo(.caption).fontWeight(.semibold)
                                        .foregroundStyle(result == .positive
                                                         ? Palette.riskTint(.high) : .secondary)
                                }
                                Text(loc.t(test.usefulDaysKey))
                                    .typo(.micro).foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    let plateletPoints = labs.series(for: .platelets)
                    if plateletPoints.count >= 2 {
                        HealthTrendChart(
                            style: loc.style,
                            title: loc.t("trend.chart.platelets"),
                            points: plateletPoints,
                            trend: HealthTrend.direction(
                                of: plateletPoints.map(\.value),
                                minimumChange: LabMeasure.platelets.minimumMeaningfulChange),
                            tint: Palette.accent,
                            usualRange: LabMeasure.platelets.typicalRange,
                            format: { loc.style.num(Int($0.rounded())) })
                        InlineNote(symbol: "info.circle", detail: loc.t("trend.note"))
                    }

                    InlineNote(symbol: "info.circle", detail: loc.t("lab.rangeNote"))
                }
                SecondaryActionButton(title: loc.t("lab.add"),
                                      systemImage: "plus.circle") { showingLab = true }
            }
        }
    }

    // MARK: - Last check

    @ViewBuilder
    private var latestCheckCard: some View {
        if let latest = caseLog.entries.first {
            CardSection(loc.t("health.latest.title"),
                        subtitle: loc.t("health.checkedAt", loc.dayAndTime(latest.date))) {
                VStack(alignment: .leading, spacing: Space.row) {
                    Text(loc.t(latest.outcome.headlineKey))
                        .typo(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc.t(latest.outcome.summaryKey))
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SecondaryActionButton(title: loc.t("health.checkAgain"),
                                          systemImage: "stethoscope") { showingCheck = true }
                }
            }
        }
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
        let outside = reading.map { kind.isOutsideUsual($0.value) } ?? false

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(loc.t(kind.labelKey))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(displayValue(reading?.value))
                    .typo(.statValue)
                    .monospacedDigit()
                    .foregroundStyle(outside ? Palette.riskTint(.high) : Color.primary)
                Text(unitLabel)
                    .typo(.micro)
                    .foregroundStyle(.secondary)
            }
            if let taken = reading?.date {
                // Per tile, because a card can mix a temperature from this
                // morning with a blood pressure from two days ago.
                Text(loc.dayAndTime(taken))
                    .typo(.micro)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if outside {
                Text(loc.t("vital.outsideUsual"))
                    .typo(.micro)
                    .foregroundStyle(Palette.riskTint(.high))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.row)
        .background(Palette.plane, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var unitLabel: String {
        kind == .temperature ? preferences.temperatureUnit.symbol : loc.t(kind.unitKey)
    }

    private func displayValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        if kind == .temperature {
            return String(format: "%.1f", preferences.temperatureUnit.fromCelsius(value))
        }
        return loc.num(Int(value.rounded()))
    }
}

/// One lab measure's most recent value, with the typical range for context.
///
/// The range is shown so a reader can see where their number sits, and the
/// note beside it says ranges differ by lab. Neither is an interpretation.
private struct LabTile: View {
    @Environment(LocalizationManager.self) private var loc
    let measure: LabMeasure
    let store: LabStore

    var body: some View {
        let reading = store.mostRecent(measure)
        let outside = reading.map { measure.isOutsideTypical($0.value) } ?? false

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: measure.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(loc.t(measure.labelKey))
                    .typo(.micro).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(reading.map { format($0.value) } ?? "—")
                    .typo(.statValue)
                    .monospacedDigit()
                    .foregroundStyle(outside ? Palette.riskTint(.high) : Color.primary)
                Text(loc.t(measure.unitKey))
                    .typo(.micro).foregroundStyle(.secondary)
            }
            Text(loc.t("lab.typicalRange",
                       format(measure.typicalRange.lowerBound),
                       format(measure.typicalRange.upperBound)))
                .typo(.micro).foregroundStyle(.tertiary).lineLimit(1)
            if outside {
                Text(loc.t("lab.outsideTypical"))
                    .typo(.micro)
                    .foregroundStyle(Palette.riskTint(.high))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.row)
        .background(Palette.plane, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func format(_ value: Double) -> String {
        measure.decimals == 0 ? loc.num(Int(value.rounded())) : loc.decimal(value)
    }
}
