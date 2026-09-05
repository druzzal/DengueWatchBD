import CoreLocation
import Foundation
import Observation

/// Loads the published feed and exposes the figures the UI reads.
///
/// Everything here is derived from one `FeedDocument`. The feed reports national
/// figures daily and geography at division level, so that is exactly what this
/// store offers — no interpolation, and no pretending to a finer grain than
/// DGHS publishes.
@MainActor
@Observable
final class DengueStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum Source { case bundled, network }

    private(set) var state: LoadState = .idle
    private(set) var source: Source = .bundled

    private(set) var meta: FeedDocument.Meta?
    private(set) var headline: FeedHeadline?
    private(set) var national: [DailyPoint] = []
    private(set) var areas: [Area] = []
    private(set) var history: [YearSummary] = []
    private(set) var epiWeeks: [String] = []
    private(set) var ageBandsCases: [AgeBand] = []
    private(set) var sexSplitCases: SexSplit?

    private let bundled: BundledFeedService

    init(bundled: BundledFeedService = BundledFeedService()) {
        self.bundled = bundled
    }

    // MARK: - Loading

    func load() async {
        guard state != .loading, state != .loaded else { return }
        state = .loading
        do {
            apply(try bundled.load())
            source = bundled.isServingDownloadedData ? .network : .bundled
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reload() async {
        state = .idle
        await load()
    }

    /// Refresh in place, for pull-to-refresh.
    ///
    /// Deliberately does not pass through `.loading`: dropping back would swap
    /// the whole dashboard for skeletons mid-gesture and blank figures the
    /// reader is looking at.
    func refresh() async {
        do {
            apply(try bundled.load())
            state = .loaded
        } catch {
            // A failed refresh is no reason to blank a screen that already has
            // yesterday's figures — only surface it when there is nothing to show.
            if areas.isEmpty {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Replace the in-memory dataset. Called by the sync layer when a newer
    /// document lands.
    func apply(document: FeedDocument, source: Source) async {
        apply(document)
        self.source = source
        state = .loaded
    }

    // MARK: - Mapping the feed onto the domain

    private func apply(_ document: FeedDocument) {
        meta = document.meta
        headline = document.summary

        national = Self.dailySeries(from: document)
        epiWeeks = document.chart(.divisionCasesByWeek)?.categories ?? []
        areas = Self.areas(from: document, weekCount: epiWeeks.count)
        history = Self.history(from: document)
        ageBandsCases = Self.ageBands(in: document, titled: "affected cases from 1 January")
        sexSplitCases = Self.sexSplit(document.chart(.casesByGender))
    }

    /// Daily national cases, with deaths joined on by date.
    ///
    /// The two series are not parallel in the feed: cases are published for
    /// every day of the season, deaths only for days a death occurred. Zipping
    /// them by index would file deaths under the wrong dates entirely, so they
    /// are matched on the parsed date instead.
    private static func dailySeries(from document: FeedDocument) -> [DailyPoint] {
        guard let cases = document.chart(.dailyCases) else { return [] }
        let caseValues = cases.primaryValues

        var deathsByDate: [Date: Int] = [:]
        if let deaths = document.chart(.dailyDeaths) {
            let values = deaths.primaryValues
            for (index, label) in deaths.categories.enumerated() {
                guard let date = FeedDate.day(from: label) else { continue }
                deathsByDate[date, default: 0] += values[safe: index] ?? 0
            }
        }

        return cases.categories.enumerated().compactMap { index, label in
            guard let date = FeedDate.day(from: label) else { return nil }
            return DailyPoint(date: date,
                              cases: caseValues[safe: index] ?? 0,
                              deaths: deathsByDate[date] ?? 0)
        }
    }

    private static func areas(from document: FeedDocument, weekCount: Int) -> [Area] {
        let seasonCases = document.chart(.areaSeasonCases)
        let seasonDeaths = document.chart(.areaSeasonDeaths)
        let weekly = document.chart(.divisionCasesByWeek)

        func cases(_ definition: Geography.Definition) -> Int {
            seasonCases?.value(for: definition.feedCategory) ?? 0
        }

        // The area list is built from a fixed table of ten places, so without
        // this it is never empty: a feed that dropped or renamed the breakdown
        // would render ten areas reporting zero cases next to a national total
        // in the tens of thousands, and the map's "no area data" state could
        // never appear. Recognising none of our categories means no data, not
        // a quiet season.
        guard let seasonCases,
              Geography.definitions.contains(where: {
                  seasonCases.value(for: $0.feedCategory) != nil
              }) else { return [] }

        // Dhaka's three feed rows share one weekly series, so each week is split
        // between them by their share of the division's season cases. Split once
        // for all three, and exactly: apportioning them independently let
        // rounding drift, so the parts no longer summed to the division's own
        // weekly figure — which is precisely what the area page promises.
        let dhaka = Geography.definitions.filter { Geography.apportionedCodes.contains($0.code) }
        let dhakaWeights = dhaka.map(cases)
        var dhakaSeries: [String: [Int]] = [:]
        if let divisionWeeks = dhaka.first.flatMap({ weekly?.series(named: $0.weeklySeriesName)?.values }) {
            for week in divisionWeeks {
                let parts = Series.apportion(week, across: dhakaWeights)
                for (index, definition) in dhaka.enumerated() {
                    dhakaSeries[definition.code, default: []].append(parts[index])
                }
            }
        }

        return Geography.definitions.map { definition in
            let apportioned = Geography.apportionedCodes.contains(definition.code)
            var series = apportioned
                ? (dhakaSeries[definition.code] ?? [])
                : (weekly?.series(named: definition.weeklySeriesName)?.values ?? [])
            if weekCount > 0, series.count > weekCount {
                series = Array(series.prefix(weekCount))
            }

            return Area(
                code: definition.code,
                name: definition.name,
                division: definition.division,
                latitude: definition.latitude,
                longitude: definition.longitude,
                populationThousands: definition.populationThousands,
                seasonCases: cases(definition),
                seasonDeaths: seasonDeaths?.value(for: definition.feedCategory) ?? 0,
                weeklyCases: series,
                weeklyIsApportioned: apportioned,
                geofenceRadiusMeters: definition.geofenceRadiusMeters
            )
        }
    }

    private static func history(from document: FeedDocument) -> [YearSummary] {
        guard let chart = document.chart(.casesByYear) else { return [] }
        let values = chart.primaryValues
        let currentYear = document.meta.year
        let seasonDeaths = document.summary.ytdDeaths ?? 0
        return chart.categories.enumerated().compactMap { index, label in
            guard let year = Int(label) else { return nil }
            // The feed publishes yearly case totals but not yearly deaths, so
            // only the current season's death count is known here.
            return YearSummary(year: year,
                               cases: values[safe: index] ?? 0,
                               deaths: year == currentYear ? seasonDeaths : nil)
        }
        .sorted { $0.year < $1.year }
    }

    /// Age bands come from the tables rather than the age charts: the charts
    /// ship empty categories and negative male values (they are drawn as
    /// population pyramids), so the labels only exist in the tables.
    private static func ageBands(in document: FeedDocument, titled fragment: String) -> [AgeBand] {
        guard let table = document.tables.first(where: {
            ($0.title ?? "").localizedCaseInsensitiveContains(fragment)
        }) else { return [] }

        return table.rows.compactMap { row in
            guard let label = row["Age Group"]?.text, Self.isAgeBand(label) else { return nil }
            return AgeBand(label: label,
                           male: row["Male"]?.number ?? 0,
                           female: row["Female"]?.number ?? 0)
        }
    }

    /// DGHS's age tables occasionally carry a row where a date was typed into
    /// the age column ("42309" — an Excel serial) or left blank. Those are
    /// dropped rather than rendered as an age band.
    private static func isAgeBand(_ label: String) -> Bool {
        if label == "80+" { return true }
        let parts = label.split(separator: "-")
        guard parts.count == 2,
              let low = Int(parts[0]), let high = Int(parts[1]),
              low <= high, high <= 120 else { return false }
        return true
    }

    private static func sexSplit(_ chart: FeedChart?) -> SexSplit? {
        guard let points = chart?.series.first?.labelled, !points.isEmpty else { return nil }
        let male = points.first { $0.name.localizedCaseInsensitiveContains("male")
                                 && !$0.name.localizedCaseInsensitiveContains("female") }?.value
        let female = points.first { $0.name.localizedCaseInsensitiveContains("female") }?.value
        guard let male, let female else { return nil }
        return SexSplit(male: male, female: female)
    }


    // MARK: - Freshness

    /// The newest DGHS report date the feed carries.
    var lastUpdated: Date? {
        guard let iso = meta?.lastUpdated else { return national.last?.date }
        return FeedDate.iso(from: iso) ?? national.last?.date
    }


    var dataAgeInDays: Int? {
        guard let lastUpdated else { return nil }
        return Calendar.current.dateComponents([.day], from: lastUpdated, to: Date()).day
    }

    enum DataFreshness { case fresh, stale, outdated }

    var freshness: DataFreshness {
        guard let lastUpdated else { return .fresh }
        let age = Date().timeIntervalSince(lastUpdated)
        if age > FeedConfig.outdatedThreshold { return .outdated }
        if age > FeedConfig.stalenessThreshold { return .stale }
        return .fresh
    }

    /// True when the figures are old enough that showing them without comment
    /// would misrepresent them as current.
    var isStale: Bool { freshness != .fresh }

    // MARK: - National roll-ups

    var latest: DailyPoint? { national.last }

    /// Season totals come from the headline block, which is what DGHS puts at
    /// the top of the press release. It agrees with the daily series to the
    /// case, but the headline is the figure of record.
    var seasonCases: Int { headline?.ytdCases ?? Series.sum(national.map(\.cases)) }
    var seasonDeaths: Int { headline?.ytdDeaths ?? Series.sum(national.map(\.deaths)) }

    var cases24h: Int { headline?.last24Cases ?? national.last?.cases ?? 0 }
    var deaths24h: Int { headline?.last24Deaths ?? national.last?.deaths ?? 0 }


    var last7Cases: Int { Series.sum(national.suffix(7).map(\.cases)) }
    var previous7Cases: Int { Series.sum(national.dropLast(7).suffix(7).map(\.cases)) }

    var weeklyCaseChange: Double? { Series.change(from: previous7Cases, to: last7Cases) }

    func nationalRecent(_ days: Int) -> [DailyPoint] { Array(national.suffix(days)) }


    /// National risk band, over the same two-week window as the areas.
    var nationalRisk: RiskLevel {
        let population = areas.reduce(0) { $0 + $1.populationThousands }
        guard population > 0 else { return .low }
        let cases = areas.reduce(0) { $0 + $1.recentCases }
        return RiskLevel(incidencePer100k: Double(cases) / Double(population) * 100)
    }

    var nationalIncidencePer100k: Double {
        let population = areas.reduce(0) { $0 + $1.populationThousands }
        guard population > 0 else { return 0 }
        return Double(areas.reduce(0) { $0 + $1.recentCases }) / Double(population) * 100
    }

    var nationalRecentCases: Int { areas.reduce(0) { $0 + $1.recentCases } }

    // MARK: - Area roll-ups

    func area(code: String) -> Area? { areas.first { $0.code == code } }

    /// The reporting area a coordinate falls in.
    ///
    /// Two steps, because neither alone is right. Containment rejects
    /// coordinates outside Bangladesh — a distance test cannot, since the area
    /// centres are nearer to Shillong and Kolkata than to St Martin's Island.
    /// Nearest centre then picks the area, which is an approximation that
    /// degrades gracefully near an internal boundary.
    ///
    /// `within` is only a backstop against a wildly wrong fix; 250 km clears the
    /// 198 km worst case inside the country.
    func nearestArea(to location: CLLocation,
                     within maxDistance: CLLocationDistance = 250_000) -> Area? {
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        guard Geography.containsBangladesh(latitude: latitude, longitude: longitude) else {
            return nil
        }
        // Dhaka's three areas share one metro, so a centroid cannot tell them
        // apart: the city corporations are small polygons inside the region
        // they are carved out of. Ask the boundaries directly, and let anywhere
        // else in the division fall through to the nearest centre.
        if let code = Geography.cityCorporationCode(latitude: latitude, longitude: longitude),
           let city = area(code: code) {
            return city
        }
        let ranked = areas
            .filter { !Geography.apportionedCodes.contains($0.code) || $0.code == "DHAKA_OUT_CC" }
            .map { area -> (Area, CLLocationDistance) in
                let centre = CLLocation(latitude: area.latitude, longitude: area.longitude)
                return (area, centre.distance(from: location))
            }
            .min { $0.1 < $1.1 }
        guard let ranked, ranked.1 <= maxDistance else { return nil }
        return ranked.0
    }

    var areasByCases: [Area] { areas.sorted { $0.seasonCases > $1.seasonCases } }
    var areasByRisk: [Area] { areas.sorted { $0.incidencePer100k > $1.incidencePer100k } }

    var hotspots: [Area] { areasByRisk.filter { $0.risk >= .high } }

    /// The hotspots to arm geofences against, or `nil` when there is no area
    /// data at all.
    ///
    /// An empty hotspot list and a missing breakdown look identical from the
    /// outside but mean opposite things: the first says disarm, nothing is high
    /// right now; the second says we cannot tell, so leave the geofences alone
    /// rather than silently switching off a working alert on a bad feed day.
    var hotspotsToMonitor: [Area]? { areas.isEmpty ? nil : hotspots }


    func areas(in division: Division) -> [Area] {
        areas.filter { $0.division == division }.sorted { $0.seasonCases > $1.seasonCases }
    }

    var peakAreaCases: Int { max(areas.map(\.seasonCases).max() ?? 1, 1) }

    /// Division-level roll-up, folding the Dhaka city corporations back into
    /// their division.
    struct DivisionSummary: Identifiable, Hashable {
        let division: Division
        let cases: Int
        let deaths: Int
        let recentCases: Int
        let populationThousands: Int

        var id: String { division.rawValue }
        var incidencePer100k: Double {
            populationThousands > 0 ? Double(recentCases) / Double(populationThousands) * 100 : 0
        }
        var risk: RiskLevel { RiskLevel(incidencePer100k: incidencePer100k) }
    }

    var divisionSummaries: [DivisionSummary] {
        Division.allCases.map { division in
            let members = areas.filter { $0.division == division }
            return DivisionSummary(
                division: division,
                cases: members.reduce(0) { $0 + $1.seasonCases },
                deaths: members.reduce(0) { $0 + $1.seasonDeaths },
                recentCases: members.reduce(0) { $0 + $1.recentCases },
                populationThousands: members.reduce(0) { $0 + $1.populationThousands }
            )
        }
        .sorted { $0.cases > $1.cases }
    }
}

/// Date parsing for the two formats the feed uses: `05-Sep-2026` style labels on
/// chart categories (`01-Jan-26`) and ISO dates in the metadata.
enum FeedDate {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Dhaka")
        formatter.dateFormat = "dd-MMM-yy"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "Asia/Dhaka") ?? .gmt
        return formatter
    }()

    /// `01-Jan-26` → that day.
    static func day(from label: String) -> Date? {
        dayFormatter.date(from: label)
    }

    /// `2026-09-05` → that day.
    static func iso(from label: String) -> Date? {
        isoFormatter.date(from: label)
    }
}
