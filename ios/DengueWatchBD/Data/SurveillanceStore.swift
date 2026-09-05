import CoreLocation
import Foundation
import Observation

/// Loads the surveillance dataset and exposes the derived figures the UI reads.
///
/// The bundled JSON stands in for a live feed: `SurveillanceService` is the only
/// place that knows where bytes come from, so swapping in a network call later
/// touches nothing else.
@MainActor
@Observable
final class SurveillanceStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var meta: SurveillancePayload.Meta?
    private(set) var dates: [Date] = []
    private(set) var national: [DailyPoint] = []
    private(set) var districts: [District] = []
    private(set) var history: [YearSummary] = []

    private let service: SurveillanceService

    init(service: SurveillanceService = LocalSurveillanceService()) {
        self.service = service
    }

    func load() async {
        guard state != .loading, state != .loaded else { return }
        state = .loading
        do {
            let payload = try await service.fetch()
            apply(payload)
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
    /// Deliberately does not pass through `.loading` the way `reload()` does.
    /// Dropping back to `.loading` swapped the whole dashboard for skeletons
    /// mid-gesture, which blanked figures the reader was looking at and, because
    /// the scroll content changed identity while the refresh control was live,
    /// left the large title stranded instead of letting it animate back up.
    /// Keeping the current figures on screen until new ones land fixes both.
    func refresh() async {
        do {
            let payload = try await service.fetch()
            apply(payload)
            state = .loaded
        } catch {
            // A failed refresh is no reason to blank a screen that already has
            // yesterday's figures — only surface it when there is nothing to show.
            if districts.isEmpty {
                state = .failed(error.localizedDescription)
            }
        }
    }

    enum Source { case local, network }

    private(set) var source: Source = .local

    /// Replace the in-memory dataset. Called by the sync layer when a newer
    /// download lands, as well as on first load.
    func apply(payload: SurveillancePayload, source: Source) async {
        apply(payload)
        self.source = source
        state = .loaded
    }

    private func apply(_ payload: SurveillancePayload) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let parsed = payload.dates.compactMap { formatter.date(from: $0) }

        dates = parsed
        national = zip(parsed.indices, parsed).map { index, date in
            DailyPoint(
                date: date,
                cases: payload.national.cases[safe: index] ?? 0,
                deaths: payload.national.deaths[safe: index] ?? 0,
                admitted: payload.national.admitted[safe: index] ?? 0
            )
        }
        districts = payload.districts.map { series in
            District(
                code: series.code,
                name: series.name,
                division: Division(rawValue: series.division) ?? .dhaka,
                latitude: series.latitude,
                longitude: series.longitude,
                populationThousands: series.populationThousands,
                daily: zip(parsed.indices, parsed).map { index, date in
                    DailyPoint(
                        date: date,
                        cases: series.cases[safe: index] ?? 0,
                        deaths: series.deaths[safe: index] ?? 0,
                        admitted: 0
                    )
                }
            )
        }
        history = payload.history.sorted { $0.year < $1.year }
        meta = payload.meta
    }

    // MARK: - National roll-ups

    var lastUpdated: Date? { dates.last }

    /// How old the newest report is, in days.
    var dataAgeInDays: Int? {
        guard let lastUpdated else { return nil }
        return Calendar.current.dateComponents([.day], from: lastUpdated, to: Date()).day
    }

    /// True when the figures are old enough that showing them without comment
    /// would misrepresent them as current.
    var isStale: Bool {
        guard let lastUpdated else { return false }
        return Date().timeIntervalSince(lastUpdated) > AppConfig.stalenessThreshold
    }
    var latest: DailyPoint? { national.last }

    var seasonCases: Int { Series.sum(national.map(\.cases)) }
    var seasonDeaths: Int { Series.sum(national.map(\.deaths)) }
    var currentlyAdmitted: Int { national.last?.admitted ?? 0 }

    var caseFatalityRate: Double {
        seasonCases > 0 ? Double(seasonDeaths) / Double(seasonCases) * 100 : 0
    }

    var last7Cases: Int { Series.sum(national.suffix(7).map(\.cases)) }
    var previous7Cases: Int { Series.sum(national.dropLast(7).suffix(7).map(\.cases)) }
    var last7Deaths: Int { Series.sum(national.suffix(7).map(\.deaths)) }
    var previous7Deaths: Int { Series.sum(national.dropLast(7).suffix(7).map(\.deaths)) }

    var weeklyCaseChange: Double? { Self.change(from: previous7Cases, to: last7Cases) }
    var weeklyDeathChange: Double? { Self.change(from: previous7Deaths, to: last7Deaths) }

    var admittedChange: Double? {
        let current = national.last?.admitted ?? 0
        let weekAgo = national.dropLast(7).last?.admitted ?? 0
        return Self.change(from: weekAgo, to: current)
    }

    private static func change(from old: Int, to new: Int) -> Double? {
        guard old > 0 else { return nil }
        return (Double(new) - Double(old)) / Double(old)
    }

    func nationalRecent(_ days: Int) -> [DailyPoint] { Array(national.suffix(days)) }

    /// National risk band, weighted by the ~171 million people the districts cover.
    var nationalRisk: RiskLevel {
        let population = districts.reduce(0) { $0 + $1.populationThousands }
        guard population > 0 else { return .low }
        let cases = districts.reduce(0) { $0 + $1.last14Cases }
        return RiskLevel(incidencePer100k: Double(cases) / Double(population) * 100)
    }

    // MARK: - District roll-ups

    func district(code: String) -> District? { districts.first { $0.code == code } }

    /// The district whose centre is closest to a coordinate.
    ///
    /// Districts are polygons and this compares against their centres, so it is
    /// an approximation — good enough to tell someone which district they are
    /// standing in, and it degrades gracefully near a boundary.
    ///
    /// `within` stops the app claiming a user in Kolkata or Dubai is "in"
    /// Bangladesh: no district centre is more than about 80 km from anywhere
    /// inside the country, so beyond 120 km the answer is that they are outside
    /// the covered area, not that they are in the nearest district.
    func nearestDistrict(to location: CLLocation,
                         within maxDistance: CLLocationDistance = 120_000) -> District? {
        let ranked = districts
            .map { district -> (District, CLLocationDistance) in
                let centre = CLLocation(latitude: district.latitude, longitude: district.longitude)
                return (district, centre.distance(from: location))
            }
            .min { $0.1 < $1.1 }
        guard let ranked, ranked.1 <= maxDistance else { return nil }
        return ranked.0
    }

    var districtsByCases: [District] { districts.sorted { $0.seasonCases > $1.seasonCases } }
    var districtsByRisk: [District] { districts.sorted { $0.incidencePer100k > $1.incidencePer100k } }

    var hotspots: [District] {
        districtsByRisk.filter { $0.risk >= .high }
    }

    /// Districts whose last week rose at least 25% on the week before, worst first.
    var risingDistricts: [District] {
        districts
            .filter { ($0.weeklyChange ?? 0) >= 0.25 && $0.last7Cases >= 20 }
            .sorted { ($0.weeklyChange ?? 0) > ($1.weeklyChange ?? 0) }
    }

    func districts(in division: Division) -> [District] {
        districts.filter { $0.division == division }.sorted { $0.seasonCases > $1.seasonCases }
    }

    struct DivisionSummary: Identifiable, Hashable {
        let division: Division
        let cases: Int
        let deaths: Int
        let last14Cases: Int
        let populationThousands: Int

        var id: String { division.rawValue }
        var incidencePer100k: Double {
            populationThousands > 0 ? Double(last14Cases) / Double(populationThousands) * 100 : 0
        }
        var risk: RiskLevel { RiskLevel(incidencePer100k: incidencePer100k) }
    }

    var divisionSummaries: [DivisionSummary] {
        Division.allCases.map { division in
            let members = districts.filter { $0.division == division }
            return DivisionSummary(
                division: division,
                cases: members.reduce(0) { $0 + $1.seasonCases },
                deaths: members.reduce(0) { $0 + $1.seasonDeaths },
                last14Cases: members.reduce(0) { $0 + $1.last14Cases },
                populationThousands: members.reduce(0) { $0 + $1.populationThousands }
            )
        }
        .sorted { $0.cases > $1.cases }
    }

    var peakDistrictCases: Int { districts.map(\.seasonCases).max() ?? 1 }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
