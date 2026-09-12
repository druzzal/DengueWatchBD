import Foundation

/// Reads lab values out of the text recognised on a photographed report.
///
/// Everything this produces is a *suggestion*. It is shown in the normal entry
/// form for the reader to check and correct before anything is saved, because
/// a misread platelet count is worse than no platelet count: one is a number
/// somebody can see is wrong, the other is a number they will believe.
///
/// Pure text in, draft out. No Vision, no camera, no view — so the hard part,
/// which is the reading, can be tested against real report wording.
enum LabReportParser {

    /// How a value was written on the page, so it can be normalised to the
    /// units this app stores.
    private enum Scale {
        /// Already in ×10³/µL, e.g. "96" or "96 K/µL".
        case thousands
        /// Written out in full, e.g. "96,000 /cumm" — divide by 1,000.
        case absolute
        /// Bengali/South Asian convention: "1.5 lakh" is 150 ×10³/µL.
        case lakh
    }

    /// Words a Bangladeshi lab report is likely to use for each measure.
    /// Lowercased; matched as substrings so "platelet count (plt)" still hits.
    private static let synonyms: [LabMeasure: [String]] = [
        .platelets: ["platelet", "platelets", "plt"],
        .haematocrit: ["haematocrit", "hematocrit", "hct", "pcv"],
        .whiteCells: ["white blood cell", "white cell", "wbc", "total wbc", "tlc", "leucocyte"],
        .haemoglobin: ["haemoglobin", "hemoglobin", "hgb", "hb"],
    ]

    private static let testSynonyms: [DengueTest: [String]] = [
        .ns1: ["ns1", "ns-1", "dengue ns1", "ns1 antigen"],
        .igm: ["igm", "ig m", "dengue igm"],
        .igg: ["igg", "ig g", "dengue igg"],
    ]

    /// Builds a draft report from recognised text.
    ///
    /// Lines are considered one at a time: lab reports are tabular, and a value
    /// on the same line as its label is far more reliable than one found by
    /// searching the whole page.
    static func draft(from text: String) -> LabReport {
        var report = LabReport()

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.lowercased()
            guard !line.isEmpty else { continue }

            for (measure, words) in synonyms where report.value(for: measure) == nil {
                guard words.contains(where: { line.contains($0) }) else { continue }
                guard let value = firstNumber(in: line, for: measure) else { continue }
                assign(value, for: measure, to: &report)
            }

            for (test, words) in testSynonyms where report.result(for: test) == .notDone {
                guard words.contains(where: { line.contains($0) }) else { continue }
                if line.contains("positive") || line.contains("reactive") && !line.contains("non") {
                    report.setResult(.positive, for: test)
                } else if line.contains("negative") || line.contains("non reactive")
                            || line.contains("non-reactive") {
                    report.setResult(.negative, for: test)
                }
            }
        }
        return report
    }

    /// Finds a number on the line and converts it into the unit this app stores.
    ///
    /// Returns nil when the result would be outside what a person could have —
    /// a reference range printed beside the value ("150 - 450") or a stray date
    /// should not become somebody's platelet count.
    private static func firstNumber(in line: String, for measure: LabMeasure) -> Double? {
        let scale = self.scale(of: line, for: measure)
        let pattern = try? NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)"#)
        let range = NSRange(line.startIndex..., in: line)
        let matches = pattern?.matches(in: line, range: range) ?? []

        for match in matches {
            guard let swiftRange = Range(match.range(at: 1), in: line) else { continue }
            let raw = line[swiftRange].replacingOccurrences(of: ",", with: "")
            guard let number = Double(raw) else { continue }
            let normalised = normalise(number, scale: scale)
            if measure.enterableRange.contains(normalised) { return normalised }
        }
        return nil
    }

    private static func scale(of line: String, for measure: LabMeasure) -> Scale {
        guard measure == .platelets || measure == .whiteCells else { return .thousands }
        if line.contains("lakh") || line.contains("lac") { return .lakh }
        // "/cumm", "/cmm", "per cumm" and bare six-figure counts are absolute.
        if line.contains("cumm") || line.contains("cmm") || line.contains("/ul")
            || line.contains("µl") == false && line.contains("000") {
            return .absolute
        }
        return .thousands
    }

    private static func normalise(_ value: Double, scale: Scale) -> Double {
        switch scale {
        case .thousands: value
        case .absolute: value / 1_000
        case .lakh: value * 100      // 1 lakh = 100 ×10³
        }
    }

    private static func assign(_ value: Double, for measure: LabMeasure, to report: inout LabReport) {
        switch measure {
        case .platelets: report.platelets = value
        case .haematocrit: report.haematocrit = value
        case .whiteCells: report.whiteCells = value
        case .haemoglobin: report.haemoglobin = value
        }
    }
}

extension LabReport {
    mutating func setResult(_ result: TestResult, for test: DengueTest) {
        switch test {
        case .ns1: ns1 = result
        case .igm: igm = result
        case .igg: igg = result
        }
    }
}
