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
            source = bundled.isServingDownloadedData ? .network : .bundled
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
        areas = Self.areas(from: document, weekCount: epiWeeks.count,
                           latestWeekIsPartial: Self.latestWeekIsPartial(document, daily: national))
        history = Self.history(from: document)
        ageBandsCases = Self.ageBands(in: document, titled: "affected cases from 1 January")
        sexSplitCases = Self.sexSplit(document.chart(.casesByGender))
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

    /// The home screen's national snapshot, with "unknown" kept distinct from
    /// "zero". See `NationalSnapshot`.
    var snapshot: NationalSnapshot {
        NationalSnapshot.from(headline: headline,
                              national: national,
                              areas: areas,
                              lastUpdated: lastUpdated)
    }

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
