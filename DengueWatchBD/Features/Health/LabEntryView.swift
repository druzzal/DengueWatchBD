import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
    @State private var showingSourceChoice = false
    @State private var showingImporter = false
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isReadingFile = false
    @State private var fileUnreadable = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        Label(loc.t("lab.scan"), systemImage: "doc.text.viewfinder")
                    }
                    .disabled(isReadingFile)

                    // For the report that arrived as a file rather than on
                    // paper — diagnostic centres increasingly email a PDF, and
                    // photographing a screen reads far worse than reading the
                    // file itself.
                    Button {
                        fileUnreadable = false
                        showingSourceChoice = true
                    } label: {
                        if isReadingFile {
                            HStack(spacing: Space.tight) {
                                ProgressView().controlSize(.small)
                                Text(loc.t("lab.upload.reading"))
                            }
                        } else {
                            Label(loc.t("lab.upload"), systemImage: "doc.badge.plus")
                        }
                    }
                    .disabled(isReadingFile)

                    if fileUnreadable {
                        Text(loc.t("lab.upload.unreadable"))
                            .typo(.micro)
                            .foregroundStyle(Palette.riskTint(.high))
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
                        field(measure)
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
            // Asked rather than assumed. A report is either a photo someone
            // took, which lives in Photos, or a file a diagnostic centre sent,
            // which lives in Files — and the Files picker opening on Recents
            // gives no hint that the photo route exists at all.
            .confirmationDialog(loc.t("lab.upload.source"),
                                isPresented: $showingSourceChoice,
                                titleVisibility: .visible) {
                Button(loc.t("lab.upload.photos")) { showingPhotoPicker = true }
                Button(loc.t("lab.upload.files")) { showingImporter = true }
                Button(loc.t("common.cancel"), role: .cancel) {}
            }
            // Images only: Photos holds no PDFs, and offering the filter would
            // promise something the library cannot return.
            .photosPicker(isPresented: $showingPhotoPicker,
                          selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await read(item) }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.jpeg, .png, .heic, .heif, .pdf]) { result in
                guard case .success(let url) = result else { return }
                Task { await read(url) }
            }
            .navigationTitle(loc.t("lab.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t("lab.save")) {
                        // Belt and braces, as in VitalsEntryView: the button is
                        // disabled in this state, but a report must not be able
                        // to arrive half-dropped by some later refactor.
                        guard !hasInvalidField else { return }
                        labs.add(report)
                        Haptic.selection()
                        dismiss()
                    }
                    .disabled(report.isEmpty || hasInvalidField)
                }
            }
        }
    }

    /// Reads a picture chosen from the photo library.
    ///
    /// No security scope and no file URL: the picker hands the bytes over
    /// directly, out of process, which is also why this needs no photo-library
    /// permission and never sees the rest of the library.
    private func read(_ item: PhotosPickerItem) async {
        isReadingFile = true
        defer {
            isReadingFile = false
            // Cleared so choosing the same picture twice still reads it.
            photoItem = nil
        }

        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            fileUnreadable = true
            return
        }
        await extract(from: data)
    }

    /// Reads a picked file and fills the form from it.
    ///
    /// The file lives outside the app's container, so it has to be opened
    /// inside a security-scoped access — without it the read returns nothing
    /// and the reader would be told the file was unreadable, which is a lie.
    /// The work runs off the main actor: a multi-page PDF takes long enough
    /// that doing it here would freeze the form.
    private func read(_ url: URL) async {
        isReadingFile = true
        defer { isReadingFile = false }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            fileUnreadable = true
            return
        }
        await extract(from: data)
    }

    /// The half both routes share: read the bytes off the main actor, and put
    /// whatever was found into the form for the reader to check.
    private func extract(from data: Data) async {
        let text = await Task.detached(priority: .userInitiated) {
            LabDocumentReader.text(from: data)
        }.value

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fileUnreadable = true
            return
        }
        apply(LabReportParser.draft(from: text))
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

    private func field(_ measure: LabMeasure) -> some View {
        let reading = reading(measure)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loc.t(measure.labelKey))
                Spacer(minLength: Space.row)
                TextField("", text: binding(for: measure))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    // See VitalsEntryView: the label is beside the field, so
                    // the field itself has none to speak.
                    .accessibilityLabel("\(loc.t(measure.labelKey)), \(loc.t(measure.unitKey))")
                    .foregroundStyle(reading.isProblem ? Palette.riskInk(.severe) : .primary)
                Text(loc.t(measure.unitKey))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            InvalidReadingNote(reading: reading)
        }
        .accessibilityElement(children: .combine)
    }

    private func reading(_ measure: LabMeasure) -> MeasureInput.Reading {
        MeasureInput.read(text[measure] ?? "", as: measure)
    }

    /// True while any count holds something that will not save as typed.
    private var hasInvalidField: Bool {
        LabMeasure.allCases.contains { reading($0).isProblem }
    }

    /// What would be saved. Only counts that read cleanly reach it, and saving
    /// is blocked whenever one does not — a platelet count quietly dropped is
    /// a platelet count the reader believes is in their record.
    private var report: LabReport {
        var result = LabReport(date: reportDate, note: note)
        for measure in LabMeasure.allCases {
            guard let value = reading(measure).storedValue else { continue }
            switch measure {
            case .platelets: result.platelets = value
            case .haematocrit: result.haematocrit = value
            case .whiteCells: result.whiteCells = value
            case .haemoglobin: result.haemoglobin = value
            }
        }
        result.ns1 = results[.ns1] ?? .notDone
        result.igm = results[.igm] ?? .notDone
        result.igg = results[.igg] ?? .notDone
        return result
    }
}
