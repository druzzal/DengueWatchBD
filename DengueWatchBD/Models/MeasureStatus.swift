import Foundation

/// How far a reading sits from the usual range, for colouring it.
///
/// Three steps, because two are not enough: a haemoglobin a fraction under the
/// line and a platelet count at a third of it are both "outside the range", and
/// showing them identically wastes the one thing colour is good at. What this
/// does not do is say what any of it means — the wording beside the number is
/// unchanged, and still sends the reader to their report and their doctor.
enum MeasureStatus: String, CaseIterable, Equatable {
    case normal
    case outside
    case farOutside

    /// Maps onto the app's existing risk palette, which is already checked for
    /// colour-vision separation, so these colours mean what they mean elsewhere.
    var risk: RiskLevel {
        switch self {
        case .normal: .low
        case .outside: .high
        case .farOutside: .severe
        }
    }

    /// Colour is never the only signal.
    var symbol: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .outside: "exclamationmark.triangle.fill"
        case .farOutside: "exclamationmark.octagon.fill"
        }
    }

    static func of(_ value: Double,
                   usual: ClosedRange<Double>,
                   far: ClosedRange<Double>) -> MeasureStatus {
        if usual.contains(value) { return .normal }
        if far.contains(value) { return .outside }
        return .farOutside
    }
}

extension VitalKind {
    /// Beyond this, a reading stops being "a bit off".
    ///
    /// Set per measure rather than as a percentage of the usual range: a
    /// proportional rule works for a pulse and is meaningless for a Celsius
    /// temperature, whose zero is arbitrary.
    var markedlyAbnormalRange: ClosedRange<Double> {
        switch self {
        case .temperature: 35.5...39.0     // beyond: hypothermia, or a high fever
        case .pulse: 50...120
        case .systolic: 85...160
        case .diastolic: 55...100
        case .oxygenSaturation: 92...100   // below 92 is not "slightly low"
        }
    }

    func status(_ value: Double) -> MeasureStatus {
        MeasureStatus.of(value, usual: usualRange, far: markedlyAbnormalRange)
    }
}

extension LabMeasure {
    var markedlyAbnormalRange: ClosedRange<Double> {
        switch self {
        case .platelets: 100...600         // below 100 is the one that matters in dengue
        case .haematocrit: 30...60
        case .whiteCells: 2...20
        case .haemoglobin: 9...20
        }
    }

    func status(_ value: Double) -> MeasureStatus {
        MeasureStatus.of(value, usual: typicalRange, far: markedlyAbnormalRange)
    }
}

/// Which side of the usual range a reading fell on, in words.
///
/// `MeasureStatus` says how far out a reading is, which is what the colour
/// carries; it cannot say which way. "Outside the usual range" reads the same
/// for a platelet count of 40 and a temperature of 39.5, and a log handed to a
/// doctor should say "Low" for one and "High" for the other.
enum MeasureSide: String, CaseIterable, Equatable {
    case low
    case normal
    case high

    /// The same three words the lab table already uses.
    var labelKey: String {
        switch self {
        case .low: "lab.flag.low"
        case .normal: "lab.flag.ok"
        case .high: "lab.flag.high"
        }
    }

    static func of(_ value: Double, usual: ClosedRange<Double>) -> MeasureSide {
        if value < usual.lowerBound { return .low }
        if value > usual.upperBound { return .high }
        return .normal
    }

    /// A blood pressure is one reading written as a pair, so it gets one
    /// word: whichever half strayed further, systolic on a tie.
    static func bloodPressure(systolic: Double, diastolic: Double)
        -> (side: MeasureSide, status: MeasureStatus) {
        let top = (VitalKind.systolic.side(systolic), VitalKind.systolic.status(systolic))
        let bottom = (VitalKind.diastolic.side(diastolic), VitalKind.diastolic.status(diastolic))
        return bottom.1.risk > top.1.risk ? bottom : top
    }
}

extension VitalKind {
    func side(_ value: Double) -> MeasureSide { .of(value, usual: usualRange) }
}

extension LabMeasure {
    func side(_ value: Double) -> MeasureSide { .of(value, usual: typicalRange) }
}
