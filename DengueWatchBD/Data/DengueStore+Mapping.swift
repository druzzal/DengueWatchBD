import Foundation

// Mapping the published feed onto the domain: the daily series, each area's
// weekly cases, the year totals and the age table. Pure functions of one
// FeedDocument, kept apart from the store's state so they can be read and
// tested on their own.

extension DengueStore {

    /// Daily national cases, with deaths joined on by date.
    ///
    /// The two series are not parallel in the feed: cases are published for
    /// every day of the season, deaths only for days a death occurred. Zipping
    /// them by index would file deaths under the wrong dates entirely, so they
    /// are matched on the parsed date instead.
    static func dailySeries(from document: FeedDocument) -> [DailyPoint] {
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

    /// Whether the newest EPI week in the weekly breakdown is still open.
    ///
    /// DGHS's EPI weeks run Sunday to Saturday (week 41 of 2026 is 11–17
    /// October), and the weekly series carries the current week as far as it
    /// has got. So unless the report is a Saturday's, the last entry is a few
    /// days of cases, not a week of them.
    ///
    /// The weekday alone would also drop a complete week on the day the
    /// weekly table lags the daily one, so the last week's national total is
    /// checked against the days reported so far: it is the open week only if
    /// it matches those days better than it matches the seven before them.
    static func latestWeekIsPartial(_ document: FeedDocument, daily: [DailyPoint]) -> Bool {
        guard let reportDay = daily.last?.date,
              let weekly = document.chart(.divisionCasesByWeek),
              !weekly.categories.isEmpty else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dhaka") ?? .gmt
        // Sunday is 1, so this is also how many days of the week are in.
        let daysIn = calendar.component(.weekday, from: reportDay)
        guard daysIn < 7 else { return false }

        let lastIndex = weekly.categories.count - 1
        let weekTotal = weekly.series.reduce(0) { $0 + ($1.values[safe: lastIndex] ?? 0) }
        let cases = daily.map(\.cases)
        let soFar = Series.sum(Array(cases.suffix(daysIn)))
        let weekBefore = Series.sum(Array(cases.dropLast(daysIn).suffix(7)))
        return abs(weekTotal - soFar) < abs(weekTotal - weekBefore)
    }

    static func areas(from document: FeedDocument, weekCount: Int,
                              latestWeekIsPartial: Bool = false) -> [Area] {
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
                geofenceRadiusMeters: definition.geofenceRadiusMeters,
                latestWeekIsPartial: latestWeekIsPartial && !series.isEmpty
            )
        }
    }

    static func history(from document: FeedDocument) -> [YearSummary] {
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
    static func ageBands(in document: FeedDocument, titled fragment: String) -> [AgeBand] {
        guard let table = document.tables.first(where: {
            ($0.title ?? "").localizedCaseInsensitiveContains(fragment)
        }) else { return [] }

        // Merged by range and then put in age order. DGHS spells one band two
        // ways — "06-10" and "6-10" — which arrive as separate rows, and their
        // sheet is sorted as text, so the unpadded spelling lands between
        // "56-60" and "61-65". Summing the pair is right rather than merely
        // tidy: they are the same ten-year-olds, and showing one row of 2,101
        // beside another of 1 invites the reader to treat the second as a
        // distinct group.
        // The published Total is carried, not recomputed. DGHS's table counts
        // cases whose sex was never recorded — they appear in Total and in
        // neither Male nor Female — so male plus female is smaller than the
        // band, and summing the two would quietly shrink every row.
        var merged: [AgeSpan: (male: Int, female: Int, total: Int)] = [:]
        for row in table.rows {
            guard let text = row["Age Group"]?.text, let range = Self.ageRange(text) else { continue }
            let male = row["Male"]?.number ?? 0
            let female = row["Female"]?.number ?? 0
            // A table without a Total column is not malformed, only older:
            // fall back to the two sexes rather than reporting the band empty.
            let total = row["Total"]?.number ?? (male + female)
            merged[range, default: (0, 0, 0)].male += male
            merged[range, default: (0, 0, 0)].female += female
            merged[range, default: (0, 0, 0)].total += total
        }
        let bands = merged
            .map { AgeBand(lowerAge: $0.key.low, upperAge: $0.key.high,
                           male: $0.value.male, female: $0.value.female,
                           total: $0.value.total) }

        // A row that spans bands the table already publishes is not a band.
        // DGHS's sheet carries "0-10" beside "0-5" and "06-10", and "21-30"
        // beside "21-25" and "26-30" — one case each, against thousands. They
        // cannot be placed among the bands they cover, and left in they sit
        // next to the real rows looking like real age groups, which is what a
        // reader sees as the same data listed twice.
        return bands
            .filter { band in !bands.contains { band.spans($0) } }
            .sorted { $0.lowerAge < $1.lowerAge }
    }

    /// An age band's span, for merging spellings of the same one.
    struct AgeSpan: Hashable {
        let low: Int
        /// Nil for the open-ended top band.
        let high: Int?
    }

    /// The span a label covers, or nil when the label is not an age band.
    ///
    /// DGHS's age tables occasionally carry a row where a date was typed into
    /// the age column ("42309" — an Excel serial, from a spreadsheet reading
    /// "6-10" as the sixth of October) or left blank. Those are dropped rather
    /// than rendered as an age band.
    static func ageRange(_ label: String) -> AgeSpan? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("+"), let low = Int(trimmed.dropLast()) {
            return AgeSpan(low: low, high: nil)
        }
        let parts = trimmed.split(separator: "-")
        guard parts.count == 2,
              let low = Int(parts[0]), let high = Int(parts[1]),
              low <= high, high <= 120 else { return nil }
        return AgeSpan(low: low, high: high)
    }

    static func sexSplit(_ chart: FeedChart?) -> SexSplit? {
        guard let points = chart?.series.first?.labelled, !points.isEmpty else { return nil }
        let male = points.first { $0.name.localizedCaseInsensitiveContains("male")
                                 && !$0.name.localizedCaseInsensitiveContains("female") }?.value
        let female = points.first { $0.name.localizedCaseInsensitiveContains("female") }?.value
        guard let male, let female else { return nil }
        return SexSplit(male: male, female: female)
    }
}
