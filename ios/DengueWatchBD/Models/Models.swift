import Foundation

// MARK: - Wire format (matches Resources/surveillance.json)

struct SurveillancePayload: Decodable {
    struct Meta: Decodable {
        let datasetName: String
        let isSampleData: Bool
        let disclaimer: String
        let attribution: String
        let seasonStart: String
        let lastUpdated: String
        let year: Int
    }

    /// Newer national figures from the DGHS dashboard, present only when the
    /// press-release series it accompanies has fallen behind.
    ///
    /// Optional so an older build of the app simply ignores it, and so its
    /// absence carries meaning: no block means the series is already current.
    struct Latest: Decodable {
        let reportDate: String
        let seasonCases: Int
        let seasonDeaths: Int
        let cases24h: Int?
        let deaths24h: Int?
        let source: String
        /// What the charts and the district map actually cover — always older
        /// than `reportDate` when this block exists.
        let seriesAsOf: String
    }

    struct NationalSeries: Decodable {
        let cases: [Int]
        let deaths: [Int]
        let admitted: [Int]
    }

    struct DistrictSeries: Decodable {
        let code: String
        let name: String
        let division: String
        let latitude: Double
        let longitude: Double
        let populationThousands: Int
        let cases: [Int]
        let deaths: [Int]
    }

    let meta: Meta
    let dates: [String]
    let national: NationalSeries
    let districts: [DistrictSeries]
    let history: [YearSummary]
    let latest: Latest?
}

struct YearSummary: Decodable, Identifiable, Hashable {
    let year: Int
    let cases: Int
    let deaths: Int
    /// `false` marks a simulated year, so the UI can label it honestly.
    let verified: Bool

    var id: Int { year }
    var caseFatalityRate: Double { cases > 0 ? Double(deaths) / Double(cases) * 100 : 0 }
}

// MARK: - Domain

struct DailyPoint: Identifiable, Hashable {
    let date: Date
    let cases: Int
    let deaths: Int
    let admitted: Int

    var id: Date { date }
}

struct District: Identifiable, Hashable {
    let code: String
    let name: String
    let division: Division
    let latitude: Double
    let longitude: Double
    let populationThousands: Int
    let daily: [DailyPoint]

    var id: String { code }

    var seasonCases: Int { daily.reduce(0) { $0 + $1.cases } }
    var seasonDeaths: Int { daily.reduce(0) { $0 + $1.deaths } }

    var last7Cases: Int { Series.sum(daily.suffix(7).map(\.cases)) }
    var previous7Cases: Int { Series.sum(daily.dropLast(7).suffix(7).map(\.cases)) }
    var last14Cases: Int { Series.sum(daily.suffix(14).map(\.cases)) }

    /// Weekly change as a fraction, e.g. `0.18` for +18%. `nil` when the prior week is empty.
    var weeklyChange: Double? {
        guard previous7Cases > 0 else { return nil }
        return (Double(last7Cases) - Double(previous7Cases)) / Double(previous7Cases)
    }

    /// Two-week attack rate per 100,000 people — the field that drives risk banding.
    var incidencePer100k: Double {
        guard populationThousands > 0 else { return 0 }
        return Double(last14Cases) / Double(populationThousands) * 100
    }

    var risk: RiskLevel { RiskLevel(incidencePer100k: incidencePer100k) }

    func recent(_ days: Int) -> [DailyPoint] { Array(daily.suffix(days)) }
}

enum Division: String, CaseIterable, Identifiable, Hashable {
    case barishal = "Barishal"
    case chattogram = "Chattogram"
    case dhaka = "Dhaka"
    case khulna = "Khulna"
    case mymensingh = "Mymensingh"
    case rajshahi = "Rajshahi"
    case rangpur = "Rangpur"
    case sylhet = "Sylhet"

    var id: String { rawValue }
}

enum RiskLevel: Int, CaseIterable, Identifiable, Comparable {
    case low, moderate, high, severe

    init(incidencePer100k value: Double) {
        switch value {
        case ..<5: self = .low
        case ..<20: self = .moderate
        case ..<60: self = .high
        default: self = .severe
        }
    }

    var id: Int { rawValue }

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum Series {
    static func sum(_ values: [Int]) -> Int { values.reduce(0, +) }

    /// Centred-trailing moving average used to smooth the reporting-day sawtooth.
    static func movingAverage(_ values: [Int], window: Int) -> [Double] {
        guard window > 1 else { return values.map(Double.init) }
        var out: [Double] = []
        out.reserveCapacity(values.count)
        for index in values.indices {
            let start = max(0, index - window + 1)
            let slice = values[start...index]
            out.append(Double(slice.reduce(0, +)) / Double(slice.count))
        }
        return out
    }
}
