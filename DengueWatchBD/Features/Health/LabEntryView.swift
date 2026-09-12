import SwiftUI

/// Recording one lab report.
///
/// Fields are optional so a report that only carried a platelet count can be
/// entered as it stands. Nothing here works out what the numbers mean.
struct LabEntryView: View {
    @Environment(LabStore.self) private var labs
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dismiss) private var dismiss

    @State private var reportDate = Date()
    @State private var text: [LabMeasure: String] = [:]
    @State private var results: [DengueTest: TestResult] = [:]
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(loc.t("lab.reportDate"), selection: $reportDate,
                               in: Date().addingTimeInterval(-365 * 86_400)...Date(),
                               displayedComponents: .date)
                }

                Section {
                    ForEach(LabMeasure.allCases) { measure in
                        HStack {
                            Text(loc.t(measure.labelKey))
                            Spacer(minLength: Space.row)
                            TextField("", text: binding(for: measure))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 90)
                            Text(loc.t(measure.unitKey))
                                .typo(.micro)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(loc.t("lab.counts"))
                } footer: {
                    Text(loc.t("lab.rangeNote"))
                }

                Section {
                    ForEach(DengueTest.allCases) { test in
                        Picker(loc.t(test.labelKey), selection: resultBinding(for: test)) {
                            ForEach(TestResult.allCases) { result in
                                Text(loc.t(result.labelKey)).tag(result)
                            }
                        }
                    }
                } header: {
                    Text(loc.t("lab.serology"))
                } footer: {
                    Text(loc.t("lab.timingNote"))
                }

                Section {
                    TextField(loc.t("result.note"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(loc.t("lab.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t("lab.save")) {
                        labs.add(report)
                        Haptic.selection()
                        dismiss()
                    }
                    .disabled(report.isEmpty)
                }
            }
        }
    }

    private func binding(for measure: LabMeasure) -> Binding<String> {
        Binding(get: { text[measure] ?? "" }, set: { text[measure] = $0 })
    }

    private func resultBinding(for test: DengueTest) -> Binding<TestResult> {
        Binding(get: { results[test] ?? .notDone }, set: { results[test] = $0 })
    }

    private var report: LabReport {
        var result = LabReport(date: reportDate, note: note)
        for measure in LabMeasure.allCases {
            let raw = (text[measure] ?? "").trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")
            guard let typed = Double(raw), measure.enterableRange.contains(typed) else { continue }
            switch measure {
            case .platelets: result.platelets = typed
            case .haematocrit: result.haematocrit = typed
            case .whiteCells: result.whiteCells = typed
            case .haemoglobin: result.haemoglobin = typed
            }
        }
        result.ns1 = results[.ns1] ?? .notDone
        result.igm = results[.igm] ?? .notDone
        result.igg = results[.igg] ?? .notDone
        return result
    }
}
