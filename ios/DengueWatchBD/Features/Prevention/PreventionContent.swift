import Foundation

struct PreventionTopic: Identifiable, Hashable {
    let id: String
    let symbol: String
    let stepCount: Int

    var titleKey: String { "prevent.\(id).title" }
    var summaryKey: String { "prevent.\(id).summary" }
    var stepKeys: [String] { (1...stepCount).map { "prevent.\(id).step\($0)" } }
}

enum PreventionContent {
    /// Aedes aegypti is a day-biting, clean-water breeder that lives indoors and
    /// rarely flies more than about 100 metres. Every topic follows from that.
    static let topics: [PreventionTopic] = [
        PreventionTopic(id: "breeding", symbol: "drop.triangle", stepCount: 6),
        PreventionTopic(id: "bites", symbol: "shield.lefthalf.filled", stepCount: 5),
        PreventionTopic(id: "care", symbol: "bed.double", stepCount: 6),
        PreventionTopic(id: "community", symbol: "building.2", stepCount: 5),
        PreventionTopic(id: "testing", symbol: "cross.case", stepCount: 5),
    ]

    struct SeasonMonth: Identifiable {
        let id: String
        let level: RiskLevel
        var labelKey: String { "prevent.month.\(id)" }
        var noteKey: String { "prevent.note.\(id)" }
    }

    /// Typical transmission through the year in Bangladesh. Months are an
    /// ordered category, so they take the ordinal risk ramp.
    static let seasonalPattern: [SeasonMonth] = [
        SeasonMonth(id: "jan", level: .low),
        SeasonMonth(id: "feb", level: .low),
        SeasonMonth(id: "mar", level: .low),
        SeasonMonth(id: "apr", level: .low),
        SeasonMonth(id: "may", level: .moderate),
        SeasonMonth(id: "jun", level: .moderate),
        SeasonMonth(id: "jul", level: .high),
        SeasonMonth(id: "aug", level: .severe),
        SeasonMonth(id: "sep", level: .severe),
        SeasonMonth(id: "oct", level: .severe),
        SeasonMonth(id: "nov", level: .high),
        SeasonMonth(id: "dec", level: .moderate),
    ]
}

extension RiskLevel {
    var labelKey: String {
        switch self {
        case .low: "risk.low"
        case .moderate: "risk.moderate"
        case .high: "risk.high"
        case .severe: "risk.severe"
        }
    }

    var guidanceKey: String {
        switch self {
        case .low: "risk.guidance.low"
        case .moderate: "risk.guidance.moderate"
        case .high: "risk.guidance.high"
        case .severe: "risk.guidance.severe"
        }
    }

    var headlineKey: String {
        switch self {
        case .low: "risk.headline.low"
        case .moderate: "risk.headline.moderate"
        case .high: "risk.headline.high"
        case .severe: "risk.headline.severe"
        }
    }
}
