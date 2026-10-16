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
    @State private var takenAt = Date()
    @State private var note = ""

    /// Everything typed so far, for `keepsDraft`.
    private struct Draft: Codable, Equatable {
        var text: [String: String]
        var takenAt: Date
        var note: String
    }

    private var draft: Binding<Draft> {
        Binding(
            get: {
                Draft(text: Dictionary(uniqueKeysWithValues: text.map { ($0.key.rawValue, $0.value) }),
                      takenAt: takenAt, note: note)
            },
            set: { draft in
                text = Dictionary(uniqueKeysWithValues: draft.text.compactMap { key, value in
                    VitalKind(rawValue: key).map { ($0, value) }
                })
                takenAt = draft.takenAt
                note = draft.note
            })
    }

    var body: some View {
        form.keepsDraft("draft.vitals", draft)
    }

    private var form: some View {
        NavigationStack {
            Form {
                // Readings are often written down after the fact — a fever
                // taken at three in the morning and entered at nine. Stamping
                // them "now" would put the spike on the wrong day and in the
                // wrong place on the chart, so the reader says when.
                Section {
                    DatePicker(loc.t("vital.takenAt"), selection: $takenAt,
                               in: recordableRange,
                               displayedComponents: [.date, .hourAndMinute])
                        // A DatePicker follows the device's locale, not the
                        // app's, so a Bengali screen was showing "28 Sep, 2026"
                        // in Western numerals beside its own Bengali labels.
                        .environment(\.locale, loc.pickerLocale)
                }

                Section {
                    field(.temperature)
                    Picker(loc.t("temp.unit.label"), selection: temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    // A reading already typed is carried across rather than
                    // reinterpreted: 38.5 typed in °C became "38.5°F" — no
                    // living temperature — and had to be typed again.
                    .onChange(of: preferences.temperatureUnit) { old, new in
                        convertTypedTemperature(from: old, to: new)
                    }
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

    /// Any time up to now, back as far as a year.
    ///
    /// The future is excluded because a reading that has not been taken yet is
    /// not a reading; the year back is generous on purpose, since someone
    /// entering an old fever into a new record is doing something reasonable.
    private var recordableRange: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-365 * 86_400)...now
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
                    .keyboardType(numberKeyboard)
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
            InvalidReadingNote(reading: reading)
            if kind == .temperature, let celsius = reading.storedValue {
                // The same reading in the other scale, so a Fahrenheit
                // thermometer and a Celsius prescription can be read together.
                Text("= " + otherUnit.display(celsius: celsius, style: loc.style))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        // Said as one thing, so the problem is read out with the field it
        // belongs to rather than as a stray line after it.
        .accessibilityElement(children: .combine)
    }

    private func reading(_ kind: VitalKind) -> MeasureInput.Reading {
        MeasureInput.read(text[kind] ?? "", as: kind, unit: preferences.temperatureUnit)
    }

    private var otherUnit: TemperatureUnit {
        preferences.temperatureUnit == .celsius ? .fahrenheit : .celsius
    }

    /// Rewrite the typed temperature in the new unit. Left alone when it does
    /// not read as a temperature in the old one — most often a Fahrenheit
    /// number typed while the switch said °C, which the switch is fixing.
    private func convertTypedTemperature(from old: TemperatureUnit, to new: TemperatureUnit) {
        guard old != new,
              let typed = text[.temperature],
              let converted = old.retyped(typed, in: new, style: loc.style) else { return }
        text[.temperature] = converted
    }

    private func unitLabel(_ kind: VitalKind) -> String {
        kind == .temperature ? preferences.temperatureUnit.symbol : loc.t(kind.unitKey)
    }

    /// A decimal pad cannot type Bengali numerals — it has no globe key, so a
    /// reader whose numbers are ৩৯.৫ could not enter them at all. In Bengali
    /// the field offers a keyboard that can be switched instead; English keeps
    /// the pad, which is faster and loses nothing.
    private var numberKeyboard: UIKeyboardType {
        loc.language.usesBengaliDigits ? .numbersAndPunctuation : .decimalPad
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
        var result = VitalsEntry(date: takenAt, note: note)
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
