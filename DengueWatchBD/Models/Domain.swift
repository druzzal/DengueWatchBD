import Foundation

// MARK: - Geography
//
// The feed reports geography at division level plus the two Dhaka city
// corporations — ten reporting areas, which is as fine as DGHS publishes on the
// HEOC dashboard. There is no area breakdown to be had from this source.

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

/// One reporting area: a division, or a Dhaka city corporation.
struct Area: Identifiable, Hashable {
    let code: String
    /// Name as the app shows it. `feedCategory` is what DGHS calls it.
    let name: String
    let division: Division
    let latitude: Double
    let longitude: Double
    let populationThousands: Int

    let seasonCases: Int
    let seasonDeaths: Int
    /// Cases per EPI week, aligned to `DengueStore.epiWeeks`.
    let weeklyCases: [Int]
    /// True when `weeklyCases` was apportioned from the parent division rather
    /// than reported for this area directly — see `Geography.areas`.
    let weeklyIsApportioned: Bool
    /// Roughly half the area's extent, for the entry geofence.
    let geofenceRadiusMeters: Double

    var id: String { code }

    var lastWeekCases: Int { weeklyCases.last ?? 0 }
    var previousWeekCases: Int { weeklyCases.dropLast().last ?? 0 }

    /// Two most recent EPI weeks — the window the risk bands are calibrated for.
    var recentCases: Int { Series.sum(Array(weeklyCases.suffix(2))) }

    /// Week-on-week change as a fraction, e.g. `0.18` for +18%.
    /// `nil` when the prior week is empty and a ratio would be meaningless.
    var weeklyChange: Double? {
        guard previousWeekCases > 0 else { return nil }
        return (Double(lastWeekCases) - Double(previousWeekCases)) / Double(previousWeekCases)
    }

    /// Two-week attack rate per 100,000 people — what drives the risk band.
    var incidencePer100k: Double {
        guard populationThousands > 0 else { return 0 }
        return Double(recentCases) / Double(populationThousands) * 100
    }

    var risk: RiskLevel { RiskLevel(incidencePer100k: incidencePer100k) }


    func recentWeeks(_ count: Int) -> [Int] { Array(weeklyCases.suffix(count)) }
}

/// Where each reporting area sits and how many people live there.
///
/// Coordinates are division centroids (city corporation centres for DNCC and
/// DSCC) — good enough to drop a pin and to answer "which area am I in", and
/// they degrade gracefully near a boundary.
///
/// Populations are 2022 BBS census figures in thousands. They are only used as
/// the denominator for incidence, so approximation costs a band boundary at
/// worst, never a headline number.
enum Geography {
    struct Definition {
        let code: String
        /// Exactly the category string DGHS uses in the feed.
        let feedCategory: String
        let name: String
        let division: Division
        let latitude: Double
        let longitude: Double
        let populationThousands: Int
        /// The series name in `affected_in_division_by_week`, which is spelled
        /// differently again ("Barisal") and has no city-corporation rows.
        let weeklySeriesName: String
        /// Roughly half the area's extent, used for the entry geofence.
        ///
        /// A single radius cannot serve both kinds of area: a city corporation
        /// is about 12 km across where Chattogram division runs nearly 200 km
        /// north to south. One circle per area is still an approximation — the
        /// areas are not round — but a division-sized area now gets a
        /// division-sized circle instead of a district-sized one.
        let geofenceRadiusMeters: Double
    }

    /// Dhaka's three feed rows share one weekly series, so their weekly numbers
    /// are apportioned by each one's share of the division's season cases.
    static let apportionedCodes: Set<String> = ["DHAKA_OUT_CC", "DNCC", "DSCC"]

    static let definitions: [Definition] = [
        .init(code: "BARISHAL", feedCategory: "Barishal", name: "Barishal",
              division: .barishal, latitude: 22.70, longitude: 90.35,
              populationThousands: 9325, weeklySeriesName: "Barisal",
              geofenceRadiusMeters: 55_000),
        .init(code: "CHATTOGRAM", feedCategory: "Chattogram", name: "Chattogram",
              division: .chattogram, latitude: 22.35, longitude: 91.83,
              populationThousands: 33202, weeklySeriesName: "Chattogram",
              geofenceRadiusMeters: 90_000),
        .init(code: "DHAKA_OUT_CC", feedCategory: "Dhaka (Out of CC)",
              name: "Dhaka (outside city)", division: .dhaka,
              latitude: 23.95, longitude: 90.15,
              populationThousands: 33935, weeklySeriesName: "Dhaka",
              geofenceRadiusMeters: 55_000),
        .init(code: "DNCC", feedCategory: "DNCC", name: "Dhaka North City",
              division: .dhaka, latitude: 23.80, longitude: 90.40,
              populationThousands: 5980, weeklySeriesName: "Dhaka",
              geofenceRadiusMeters: 12_000),
        .init(code: "DSCC", feedCategory: "DSCC", name: "Dhaka South City",
              division: .dhaka, latitude: 23.71, longitude: 90.41,
              populationThousands: 4300, weeklySeriesName: "Dhaka",
              geofenceRadiusMeters: 12_000),
        .init(code: "KHULNA", feedCategory: "Khulna", name: "Khulna",
              division: .khulna, latitude: 22.85, longitude: 89.50,
              populationThousands: 17417, weeklySeriesName: "Khulna",
              geofenceRadiusMeters: 75_000),
        .init(code: "MYMENSINGH", feedCategory: "Mymensingh", name: "Mymensingh",
              division: .mymensingh, latitude: 24.75, longitude: 90.40,
              populationThousands: 12368, weeklySeriesName: "Mymensingh",
              geofenceRadiusMeters: 55_000),
        .init(code: "RAJSHAHI", feedCategory: "Rajshahi", name: "Rajshahi",
              division: .rajshahi, latitude: 24.37, longitude: 88.60,
              populationThousands: 20353, weeklySeriesName: "Rajshahi",
              geofenceRadiusMeters: 70_000),
        .init(code: "RANGPUR", feedCategory: "Rangpur", name: "Rangpur",
              division: .rangpur, latitude: 25.75, longitude: 89.25,
              populationThousands: 17610, weeklySeriesName: "Rangpur",
              geofenceRadiusMeters: 65_000),
        .init(code: "SYLHET", feedCategory: "Sylhet", name: "Sylhet",
              division: .sylhet, latitude: 24.90, longitude: 91.87,
              populationThousands: 11048, weeklySeriesName: "Sylhet",
              geofenceRadiusMeters: 60_000),
    ]

    static func definition(code: String) -> Definition? {
        definitions.first { $0.code == code }
    }

    /// A coarse outline of Bangladesh, used only to decide whether a coordinate
    /// is in the country at all.
    ///
    /// Nearest-centroid alone cannot answer that. The reporting areas are large,
    /// so their centres sit closer to several Indian border cities than to parts
    /// of Bangladesh itself: Shillong is 75 km from the Sylhet centre and
    /// Kolkata 121 km from Khulna's, while St Martin's Island — which *is* in
    /// Bangladesh — is 198 km from Chattogram's. No distance threshold separates
    /// those, so containment is tested first and distance only guards against a
    /// wildly wrong fix.
    ///
    /// Simplified to about thirty vertices, so it is right to a few kilometres
    /// rather than exactly. A town sitting directly on the border can fall the
    /// wrong side of it; anywhere further in is classified correctly.
    private static let outline: [(lat: Double, lon: Double)] = [
        (26.63, 88.35), (26.35, 88.90), (26.20, 89.45), (26.10, 89.80),
        (25.30, 89.90), (25.35, 90.60), (25.20, 91.30), (25.20, 92.00),
        (24.30, 92.35), (24.00, 91.60), (23.70, 91.40), (23.20, 91.40),
        (23.00, 91.60), (22.60, 92.30), (21.80, 92.60), (20.75, 92.35),
        (21.40, 91.90), (22.20, 91.50), (22.00, 91.00), (21.80, 90.30),
        (21.75, 89.90), (21.60, 89.20), (21.90, 88.90), (22.60, 88.90),
        (23.20, 88.70), (23.70, 88.60), (24.40, 88.10), (24.90, 88.10),
        (25.60, 88.10),
    ]

    /// Ray casting against `outline`.
    static func containsBangladesh(latitude: Double, longitude: Double) -> Bool {
        var inside = false
        var j = outline.count - 1
        for i in outline.indices {
            let a = outline[i], b = outline[j]
            if (a.lat > latitude) != (b.lat > latitude) {
                let slope = (b.lon - a.lon) * (latitude - a.lat) / (b.lat - a.lat) + a.lon
                if longitude < slope { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

// MARK: - Series

struct DailyPoint: Identifiable, Hashable {
    let date: Date
    let cases: Int
    let deaths: Int

    var id: Date { date }
}

/// One epidemiological week of the current season.
struct EpiWeekPoint: Identifiable, Hashable {
    let week: String
    let cases: Int

    var id: String { week }
}

struct YearSummary: Identifiable, Hashable {
    let year: Int
    let cases: Int
    /// `nil` for past seasons: the feed publishes yearly case totals but no
    /// yearly death total, and rendering that absence as 0 would claim a year
    /// with 1,705 deaths had none.
    let deaths: Int?

    var id: Int { year }
}

/// One age band, split by sex. The feed publishes this for cases and deaths.
struct AgeBand: Identifiable, Hashable {
    let label: String
    let male: Int
    let female: Int

    var id: String { label }
    var total: Int { male + female }
}

struct SexSplit: Hashable {
    let male: Int
    let female: Int

    var total: Int { male + female }
    var maleShare: Double { total > 0 ? Double(male) / Double(total) : 0 }
}

// MARK: - Risk

enum RiskLevel: Int, CaseIterable, Identifiable, Comparable {
    case low, moderate, high, severe

    /// Bands are calibrated for a two-week attack rate per 100,000.
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

    /// Trailing moving average, used to smooth the reporting-day sawtooth.
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

    static func change(from old: Int, to new: Int) -> Double? {
        guard old > 0 else { return nil }
        return (Double(new) - Double(old)) / Double(old)
    }
}
