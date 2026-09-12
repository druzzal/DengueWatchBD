import Foundation

/// Which way a series of the reader's own readings has moved.
///
/// A direction is a fact about the numbers. What that direction means is not,
/// and nothing here attempts it: "your platelet count has fallen across these
/// three reports" is a description, while "your platelets are dropping, this
/// may be severe dengue" is a diagnosis. This type only ever produces the first.
enum HealthTrend: String, Equatable {
    case rising
    case falling
    case steady
    /// Fewer than two readings — a single point has no direction.
    case notEnoughData

    var labelKey: String { "trend.\(rawValue)" }

    var symbol: String {
        switch self {
        case .rising: "arrow.up.right"
        case .falling: "arrow.down.right"
        case .steady: "equal"
        case .notEnoughData: "minus"
        }
    }

    /// Direction of the reader's readings, first to last.
    ///
    /// - Parameter minimumChange: how much movement counts as a direction
    ///   rather than noise. Expressed in the measure's own units, because a
    ///   fraction does not travel between them: 5% of a temperature is a third
    ///   of a degree, while 5% of a platelet count is nothing at all.
    static func direction(of values: [Double], minimumChange: Double) -> HealthTrend {
        guard values.count >= 2, let first = values.first, let last = values.last else {
            return .notEnoughData
        }
        let change = last - first
        if abs(change) < minimumChange { return .steady }
        return change > 0 ? .rising : .falling
    }
}

extension VitalKind {
    /// Movement below this is thermometer scatter, not a change in condition.
    var minimumMeaningfulChange: Double {
        switch self {
        case .temperature: 0.3       // °C
        case .pulse: 8               // bpm
        case .systolic: 8            // mmHg
        case .diastolic: 6           // mmHg
        case .oxygenSaturation: 2    // percentage points
        }
    }
}

extension LabMeasure {
    /// Movement below this is within the run-to-run variation of the assay.
    var minimumMeaningfulChange: Double {
        switch self {
        case .platelets: 20          // ×10³/µL
        case .haematocrit: 2         // percentage points
        case .whiteCells: 0.8        // ×10³/µL
        case .haemoglobin: 0.8       // g/dL
        }
    }
}
