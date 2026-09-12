import Foundation

/// A measurement someone records about themselves.
///
/// This app records and charts. It does not interpret: a reading outside the
/// usual range is flagged as worth showing to a clinician, never explained,
/// and no combination of readings here produces a diagnosis. That line matters
/// most exactly where it is most tempting to cross — a falling platelet count
/// with a rising haematocrit is a pattern a doctor acts on, and a pattern this
/// app must only ever display.
enum VitalKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case temperature
    case pulse
    case systolic
    case diastolic
    case oxygenSaturation

    var id: String { rawValue }
    var labelKey: String { "vital.\(rawValue)" }
    var unitKey: String { "vital.unit.\(rawValue)" }

    var symbol: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .pulse: "waveform.path.ecg"
        case .systolic, .diastolic: "heart"
        case .oxygenSaturation: "lungs"
        }
    }

    /// What a person could plausibly enter. Wide: a reading that is alarming is
    /// still a reading, and refusing to record it would lose the very number
    /// worth showing a doctor. This only catches typing slips.
    var enterableRange: ClosedRange<Double> {
        switch self {
        case .temperature: 30...45          // Celsius; conversion happens at entry
        case .pulse: 25...220
        case .systolic: 50...260
        case .diastolic: 30...160
        case .oxygenSaturation: 50...100
        }
    }

    /// The range most healthy adults sit in at rest.
    ///
    /// Used only to mark a reading for attention. Children, pregnancy and
    /// chronic conditions all shift these, which is why nothing here concludes
    /// anything — it points at a number and suggests a person to ask.
    var usualRange: ClosedRange<Double> {
        switch self {
        case .temperature: 36.1...37.8
        case .pulse: 60...100
        case .systolic: 90...130
        case .diastolic: 60...85
        case .oxygenSaturation: 95...100
        }
    }

    var decimals: Int { self == .temperature ? 1 : 0 }

    func isOutsideUsual(_ value: Double) -> Bool { !usualRange.contains(value) }
}

/// One moment's readings. Any field may be absent: someone with a home
/// thermometer and no blood-pressure cuff should still be able to keep a record.
struct VitalsEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    /// Always Celsius on disk, as with the case log.
    var temperature: Double?
    var pulse: Double?
    var systolic: Double?
    var diastolic: Double?
    var oxygenSaturation: Double?
    var note: String = ""

    func value(for kind: VitalKind) -> Double? {
        switch kind {
        case .temperature: temperature
        case .pulse: pulse
        case .systolic: systolic
        case .diastolic: diastolic
        case .oxygenSaturation: oxygenSaturation
        }
    }

    var isEmpty: Bool {
        VitalKind.allCases.allSatisfy { value(for: $0) == nil }
    }

    /// Readings that sit outside the usual range, for the "worth asking about"
    /// prompt. Order follows VitalKind so the prompt is stable between renders.
    var readingsOutsideUsualRange: [VitalKind] {
        VitalKind.allCases.filter { kind in
            guard let value = value(for: kind) else { return false }
            return kind.isOutsideUsual(value)
        }
    }
}
