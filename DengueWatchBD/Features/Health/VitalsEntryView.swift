import SwiftUI

/// Recording one set of readings.
///
/// Every field is optional. Someone with a thermometer and no cuff should be
/// able to keep a useful record, and demanding a full set would mean they
/// record nothing at all.
struct VitalsEntryView: View {
    @Environment(VitalsStore.self) private var vitals
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dismiss) private var dismiss

    @State private var text: [VitalKind: String] = [:]
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field(.temperature)
                    Picker(loc.t("temp.unit.label"), selection: temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(loc.t("vital.temperature"))
                }

                Section(loc.t("vital.bloodPressure")) {
                    field(.systolic)
                    field(.diastolic)
                }

                Section {
                    field(.pulse)
                    field(.oxygenSaturation)
                }

                Section {
                    TextField(loc.t("result.note"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    // Said here, where readings are entered, rather than only
                    // where they are shown.
                    Text(loc.t("vital.outsideUsual.detail"))
                }
            }
            .navigationTitle(loc.t("vital.record"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t("vital.save")) { save() }
                        .disabled(entry.isEmpty || hasInvalidField)
                }
            }
        }
    }

    private var temperatureUnit: Binding<TemperatureUnit> {
        @Bindable var preferences = preferences
        return $preferences.temperatureUnit
    }

    private func field(_ kind: VitalKind) -> some View {
        let reading = reading(kind)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loc.t(kind.labelKey))
                Spacer(minLength: Space.row)
                TextField("", text: binding(for: kind))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    // The visible label sits beside the field rather than in it,
                    // so without this VoiceOver reaches five fields that all
                    // announce themselves as "text field" and nothing else.
                    .accessibilityLabel("\(loc.t(kind.labelKey)), \(unitLabel(kind))")
                    .foregroundStyle(reading.isProblem ? Palette.riskInk(.severe) : .primary)
                Text(unitLabel(kind))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let message = message(for: reading) {
                Text(message)
                    .typo(.micro)
                    .foregroundStyle(Palette.riskInk(.severe))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Said as one thing, so the problem is read out with the field it
        // belongs to rather than as a stray line after it.
        .accessibilityElement(children: .combine)
    }

    private func reading(_ kind: VitalKind) -> VitalsInput.Reading {
        VitalsInput.read(text[kind] ?? "", as: kind, unit: preferences.temperatureUnit)
    }

    /// What to say about a field that will not be saved as typed.
    private func message(for reading: VitalsInput.Reading) -> String? {
        switch reading {
        case .empty, .value:
            return nil
        case .notANumber:
            return loc.t("vital.invalid.number")
        case .outOfRange(let range):
            return loc.t("vital.invalid.range",
                         loc.decimal(range.lowerBound, places: 0),
                         loc.decimal(range.upperBound, places: 0))
        }
    }

    private func unitLabel(_ kind: VitalKind) -> String {
        kind == .temperature ? preferences.temperatureUnit.symbol : loc.t(kind.unitKey)
    }

    private func binding(for kind: VitalKind) -> Binding<String> {
        Binding(get: { text[kind] ?? "" }, set: { text[kind] = $0 })
    }

    /// True while any field holds something that will not save as typed.
    /// Saving is blocked rather than the field being quietly dropped.
    private var hasInvalidField: Bool {
        VitalKind.allCases.contains { reading($0).isProblem }
    }

    /// What would be saved. Only fields that read cleanly reach it — and the
    /// save button is unavailable whenever one does not, so nothing is ever
    /// silently left out of a record the reader believes they completed.
    private var entry: VitalsEntry {
        var result = VitalsEntry(note: note)
        for kind in VitalKind.allCases {
            guard let value = reading(kind).storedValue else { continue }
            switch kind {
            case .temperature: result.temperature = value    // already Celsius
            case .pulse: result.pulse = value
            case .systolic: result.systolic = value
            case .diastolic: result.diastolic = value
            case .oxygenSaturation: result.oxygenSaturation = value
            }
        }
        return result
    }

    private func save() {
        // Belt and braces: the button is disabled in this state, but a record
        // must not be able to arrive half-dropped by some later refactor.
        guard !hasInvalidField else { return }
        vitals.add(entry)
        Haptic.selection()
        dismiss()
    }
}
