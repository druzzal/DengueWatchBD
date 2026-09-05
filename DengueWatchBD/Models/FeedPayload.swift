import Foundation

// MARK: - Wire format
//
// The published feed at druzzal.github.io/dengue-bd-dashboard is two documents
// of deliberately different sizes:
//
//   summary.json  ~350 bytes  headline figures and the DGHS report date
//   latest.json   ~40 KB      every chart series and table behind them
//
// The app asks the small one whether anything changed and only pays for the
// large one when the answer is yes. Both are decoded with
// `.convertFromSnakeCase`, so `ytd_cases` arrives as `ytdCases`.

/// Headline figures. Present in both documents, identically shaped.
struct FeedHeadline: Decodable, Equatable {
    let epiWeek: String?
    let weekCases: Int?
    let weekDeaths: Int?
    let ytdCases: Int?
    let ytdDeaths: Int?
    let last24Cases: Int?
    let last24Deaths: Int?
    let dischargedLast24: Int?
    let dischargedYtd: Int?
}

/// `summary.json` — the cheap freshness probe.
struct FeedSummaryDocument: Decodable {
    let schemaVersion: Int
    let fetchedAt: String?
    /// The report date DGHS itself stamps. This, not `fetchedAt`, decides
    /// whether the full document is worth downloading.
    let lastUpdated: String?
    let year: Int?
    let summary: FeedHeadline
}

/// `latest.json` — the full dataset.
struct FeedDocument: Decodable {
    struct Meta: Decodable {
        let sourceUrl: String?
        let sourceName: String?
        let lastUpdatedLabel: String?
        let lastUpdated: String?
        let year: Int?
    }

    let schemaVersion: Int
    let fetchedAt: String?
    let meta: Meta
    let summary: FeedHeadline
    let charts: [String: FeedChart]
    let tables: [FeedTable]

    func chart(_ id: FeedChartID) -> FeedChart? { charts[id.rawValue] }
}

/// The chart keys this app reads. Named rather than stringly-typed so a feed
/// that drops one fails somewhere the compiler and tests can point at.
enum FeedChartID: String {
    case dailyCases = "confirmed_case"
    case dailyDeaths = "death_case"
    case areaSeasonCases = "div_city_cor_case_in_year"
    case areaSeasonDeaths = "div_city_cor_death_in_year"
    case divisionCasesByWeek = "affected_in_division_by_week"
    case casesByYear = "year_case"
    case casesByGender = "dengue_affected_by_gender"
}

struct FeedChart: Decodable {
    let title: String?
    let categories: [String]
    let series: [FeedSeries]

    /// The first series' values. Most charts in the feed carry exactly one.
    var primaryValues: [Int] { series.first?.values ?? [] }

    /// Value for one category, matched by name. Feed category spellings are
    /// whatever DGHS typed, so callers pass the exact string.
    func value(for category: String) -> Int? {
        guard let index = categories.firstIndex(of: category) else { return nil }
        return series.first?.values[safe: index]
    }

    func series(named name: String) -> FeedSeries? {
        series.first { $0.name == name }
    }
}

struct FeedSeries: Decodable {
    let name: String?
    let type: String?
    let data: [FeedPoint]

    /// Missing points read as zero: in this feed a gap means "none reported",
    /// and a series of optionals would push that decision into every call site.
    var values: [Int] { data.map { $0.value ?? 0 } }

    /// Only named points (pie slices) carry labels.
    var labelled: [(name: String, value: Int)] {
        data.compactMap { point in
            guard let name = point.name, let value = point.value else { return nil }
            return (name, value)
        }
    }
}

/// One point, in either shape Highcharts emits: a bare number (column and line
/// charts) or `{"name": "Male", "y": 25367}` (pie charts). Nulls survive as nil.
struct FeedPoint: Decodable {
    let name: String?
    let value: Int?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if single.decodeNil() {
                name = nil
                value = nil
                return
            }
            if let number = try? single.decode(Int.self) {
                name = nil
                value = number
                return
            }
            if let number = try? single.decode(Double.self) {
                name = nil
                value = Int(number.rounded())
                return
            }
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        name = try keyed.decodeIfPresent(String.self, forKey: .name)
        if let number = try? keyed.decode(Int.self, forKey: .y) {
            value = number
        } else if let number = try? keyed.decode(Double.self, forKey: .y) {
            value = Int(number.rounded())
        } else {
            value = nil
        }
    }

    private enum CodingKeys: String, CodingKey { case name, y }
}

/// An age-by-sex table. Row keys are the header strings the source page uses.
struct FeedTable: Decodable {
    let title: String?
    let headers: [String]
    let rows: [[String: FeedCell]]
}

/// A table cell: a label, a number, or empty.
struct FeedCell: Decodable {
    let text: String?
    let number: Int?

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            text = nil
            number = nil
        } else if let value = try? single.decode(Int.self) {
            text = nil
            number = value
        } else if let value = try? single.decode(String.self) {
            text = value
            number = nil
        } else if let value = try? single.decode(Double.self) {
            text = nil
            number = Int(value.rounded())
        } else {
            text = nil
            number = nil
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
