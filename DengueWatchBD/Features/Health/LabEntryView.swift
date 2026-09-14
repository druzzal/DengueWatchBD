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
    @State private var showingScanner = false
    @State private var scanFoundNothing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        Label(loc.t("lab.scan"), systemImage: "doc.text.viewfinder")
                    }
                    if scanFoundNothing {
                        Text(loc.t("lab.scan.nothing"))
                            .typo(.micro)
                            .foregroundStyle(Palette.riskTint(.high))
                    }
                } footer: {
                    Text(loc.t("lab.scan.note"))
                }

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
                                // See VitalsEntryView: the label is beside the
                                // field, so the field itself has none to speak.
                                .accessibilityLabel("\(loc.t(measure.labelKey)), \(loc.t(measure.unitKey))")
                            Text(loc.t(measure.unitKey))
                                .typo(.micro)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
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
            .fullScreenCover(isPresented: $showingScanner) {
                LabScannerView(
                    onScan: { draft in
                        apply(draft)
                        showingScanner = false
                    },
                    onCancel: { showingScanner = false }
                )
                .ignoresSafeArea()
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

    /// Fills the form from a scan, leaving anything already typed alone.
    ///
    /// Deliberately does not save. The reader sees every value in the same
    /// fields they would have typed, and corrects whatever the camera misread
    /// before it becomes a record.
    private func apply(_ draft: LabReport) {
        var found = false
        for measure in LabMeasure.allCases {
            guard let value = draft.value(for: measure),
                  (text[measure] ?? "").isEmpty else { continue }
            text[measure] = measure.decimals == 0
                ? String(Int(value.rounded()))
                : String(format: "%.1f", value)
            found = true
        }
        for test in DengueTest.allCases {
            let result = draft.result(for: test)
            guard result != .notDone, (results[test] ?? .notDone) == .notDone else { continue }
            results[test] = result
            found = true
        }
        scanFoundNothing = !found
        if found { Haptic.selection() }
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
