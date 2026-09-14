import Foundation

/// A blood-count value from a lab report.
///
/// The ranges here are typical adult ranges, and they are shown as context, not
/// as a verdict. Real ranges vary with sex, age, altitude and the analyser the
/// lab used, which is why every printed report carries its own — the app says
/// so rather than pretending one number fits everyone.
enum LabMeasure: String, CaseIterable, Identifiable, Codable, Sendable {
    case platelets
    case haematocrit
    case whiteCells
    case haemoglobin

    var id: String { rawValue }
    var labelKey: String { "lab.\(rawValue)" }
    var unitKey: String { "lab.unit.\(rawValue)" }

    var symbol: String {
        switch self {
        case .platelets: "drop.triangle"
        case .haematocrit: "percent"
        case .whiteCells: "shield.lefthalf.filled"
        case .haemoglobin: "drop.fill"
        }
    }

    /// What a person could plausibly have. Deliberately wide: a platelet count
    /// of 15 is a medical emergency and exactly the number worth recording, so
    /// this catches typing slips only.
    var enterableRange: ClosedRange<Double> {
        switch self {
        case .platelets: 1...1_500        // thousands per microlitre
        case .haematocrit: 10...70        // percent
        case .whiteCells: 0.1...100       // thousands per microlitre
        case .haemoglobin: 2...25         // g/dL
        }
    }

    /// A typical adult range, for context only.
    var typicalRange: ClosedRange<Double> {
        switch self {
        case .platelets: 150...450
        case .haematocrit: 36...54
        case .whiteCells: 4...11
        case .haemoglobin: 12...17
        }
    }

    var decimals: Int {
        switch self {
        case .platelets: 0
        case .haematocrit, .whiteCells, .haemoglobin: 1
        }
    }

    func isOutsideTypical(_ value: Double) -> Bool { !typicalRange.contains(value) }
}

/// A dengue antibody or antigen test result.
///
/// Recorded as what the lab reported. The app does not decide what a result
/// means: a positive NS1 with a negative IgM on day two is a conversation with
/// a clinician, not a conclusion an app should reach on someone's behalf.
enum DengueTest: String, CaseIterable, Identifiable, Codable, Sendable {
    case ns1
    case igm
    case igg

    var id: String { rawValue }
    var labelKey: String { "lab.test.\(rawValue)" }

    /// When this test is usually informative, counting the first day of fever
    /// as day 1. This is test timing, which is a fact about the assay, not an
    /// interpretation of anybody's result.
    var usefulDaysKey: String { "lab.timing.\(rawValue)" }
}

enum TestResult: String, CaseIterable, Identifiable, Codable, Sendable {
    case notDone
    case negative
    case positive

    var id: String { rawValue }
    var labelKey: String { "lab.result.\(rawValue)" }
}

/// One lab report: whichever values and results it carried.
struct LabReport: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var platelets: Double?
    var haematocrit: Double?
    var whiteCells: Double?
    var haemoglobin: Double?
    var ns1: TestResult = .notDone
    var igm: TestResult = .notDone
    var igg: TestResult = .notDone
    var note: String = ""

    func value(for measure: LabMeasure) -> Double? {
        switch measure {
        case .platelets: platelets
        case .haematocrit: haematocrit
        case .whiteCells: whiteCells
        case .haemoglobin: haemoglobin
        }
    }

    func result(for test: DengueTest) -> TestResult {
        switch test {
        case .ns1: ns1
        case .igm: igm
        case .igg: igg
        }
    }

    var hasAnyValue: Bool {
        LabMeasure.allCases.contains { value(for: $0) != nil }
    }

    var hasAnyResult: Bool {
        DengueTest.allCases.contains { result(for: $0) != .notDone }
    }

    var isEmpty: Bool { !hasAnyValue && !hasAnyResult }

    var valuesOutsideTypicalRange: [LabMeasure] {
        LabMeasure.allCases.filter { measure in
            guard let value = value(for: measure) else { return false }
            return measure.isOutsideTypical(value)
        }
    }
}
