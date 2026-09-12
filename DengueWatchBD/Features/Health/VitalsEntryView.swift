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
                        .disabled(entry.isEmpty)
                }
            }
        }
    }

    private var temperatureUnit: Binding<TemperatureUnit> {
        @Bindable var preferences = preferences
        return $preferences.temperatureUnit
    }

    private func field(_ kind: VitalKind) -> some View {
        HStack {
            Text(loc.t(kind.labelKey))
            Spacer(minLength: Space.row)
            TextField("", text: binding(for: kind))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(kind == .temperature ? preferences.temperatureUnit.symbol : loc.t(kind.unitKey))
                .typo(.micro)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for kind: VitalKind) -> Binding<String> {
        Binding(get: { text[kind] ?? "" }, set: { text[kind] = $0 })
    }

    /// Parses what was typed. Values that are not numbers, or are outside what
    /// a person could record, are dropped rather than saved — but the range is
    /// wide, because an alarming reading is exactly the one worth keeping.
    private var entry: VitalsEntry {
        var result = VitalsEntry(note: note)
        for kind in VitalKind.allCases {
            let raw = (text[kind] ?? "").trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")
            guard let typed = Double(raw) else { continue }

            if kind == .temperature {
                // Stored in Celsius like everything else, converted on the way in.
                guard let celsius = preferences.temperatureUnit.celsiusValue(from: raw) else { continue }
                result.temperature = celsius
            } else {
                guard kind.enterableRange.contains(typed) else { continue }
                switch kind {
                case .pulse: result.pulse = typed
                case .systolic: result.systolic = typed
                case .diastolic: result.diastolic = typed
                case .oxygenSaturation: result.oxygenSaturation = typed
                case .temperature: break
                }
            }
        }
        return result
    }

    private func save() {
        vitals.add(entry)
        Haptic.selection()
        dismiss()
    }
}
