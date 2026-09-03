import SwiftUI
import Charts

struct CaseLogView: View {
    @Environment(CaseLogStore.self) private var log
    @Environment(LocalizationManager.self) private var loc

    @State private var showingClearConfirmation = false

    private var temperatureSeries: [(date: Date, value: Double)] {
        log.entries
            .compactMap { entry in entry.temperature.map { (entry.date, $0) } }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        NavigationStack {
            Group {
                if log.entries.isEmpty {
                    ContentUnavailableView {
                        Label(loc.t("log.empty.title"), systemImage: "list.clipboard")
                    } description: {
                        Text(loc.t("log.empty.detail"))
                    }
                } else {
                    List {
                        if temperatureSeries.count >= 2 {
                            Section(loc.t("log.temperature")) {
                                Chart(temperatureSeries, id: \.date) { item in
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
                                                Text(loc.decimal(temp, places: 0))
                                                    .typoStatic(.micro)
                                                    .foregroundStyle(Palette.mutedInk)
                                            }
                                        }
                                    }
                                }
                                .chartXAxis { dateAxis(loc.style, desiredCount: 3) }
                                .frame(height: 130)
                                .padding(.trailing, 22)
                                .padding(.vertical, 6)
                            }
                        }

                        Section(loc.t("log.checkins")) {
                            ForEach(log.entries) { entry in
                                CaseLogRow(entry: entry)
                            }
                            .onDelete { log.delete(at: $0) }
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LanguageToggle() }
            }
            .confirmationDialog(loc.t("log.confirmDelete"),
                                isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                Button(loc.t("common.deleteAll"), role: .destructive) { log.clear() }
                Button(loc.t("common.cancel"), role: .cancel) {}
            }
        }
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
                if let temperature = entry.temperature {
                    Text("\(loc.decimal(temperature)) °C")
                        .typo(.caption).fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Text(loc.dateTime(entry.date))
                .typo(.micro).foregroundStyle(.secondary)

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
