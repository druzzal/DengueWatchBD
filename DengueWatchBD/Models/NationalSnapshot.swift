import Foundation

/// The figures the home screen leads with, and — just as important — which of
/// them are actually known.
///
/// Every one of these can be missing on a bad feed day, and every one has a
/// zero that means something real. "No deaths in the last 24 hours" is good
/// news worth showing. "We could not read the deaths figure" is not news at
/// all, and rendering the second as the first is the one mistake a
/// surveillance app does not get to make. So each figure is optional, and the
/// view omits what it does not have instead of printing a confident zero.
///
/// The same distinction already exists in `DengueStore.hotspotsToMonitor` and
/// in `SurveillanceDigest.noBreakdown`; this puts it on the home screen too.
struct NationalSnapshot: Equatable {
    /// Cases since the start of the season.
    let seasonCases: Int?
    /// Deaths since the start of the season. The daily deaths series carries a
    /// row only for days a death occurred, so summing it is a season total.
    let seasonDeaths: Int?
    let seasonStart: Date?

    /// The last seven days, and how that compares with the seven before it.
    let weekCases: Int?
    /// Nil when there is no earlier week to compare against — a season three
    /// days old has no "last week", and 0 → 40 is not "up 100%".
    let weeklyChange: Double?

    /// What DGHS leads its daily release with.
    let last24Cases: Int?
    let last24Deaths: Int?

    /// Nil when there is no area breakdown at all, which is a different thing
    /// from no area being high risk. An empty breakdown says "we cannot tell";
    /// zero hotspots says "nothing is high right now". They print identically
    /// if you let them.
    let highRiskAreas: Int?
    /// The denominator the app can actually speak to: the reporting areas in
    /// the feed, not the 64 districts of Bangladesh.
    let reportingAreas: Int

    /// The day these figures describe, which is not necessarily today.
    let reportedFor: Date?

    /// How many tiles the snapshot will actually draw. Each is omitted when
    /// its figure is unknown, so the count is not a constant.
    var tileCount: Int {
        [last24Cases != nil, weekCases != nil, seasonCases != nil,
         seasonDeaths != nil, highRiskAreas != nil].filter { $0 }.count
    }

    var hasAnything: Bool {
        seasonCases != nil || seasonDeaths != nil || weekCases != nil || last24Cases != nil || highRiskAreas != nil
    }

    static let empty = NationalSnapshot(
        seasonCases: nil, seasonDeaths: nil, seasonStart: nil, weekCases: nil, weeklyChange: nil,
        last24Cases: nil, last24Deaths: nil, highRiskAreas: nil,
        reportingAreas: 0, reportedFor: nil)
}

extension NationalSnapshot {
    /// Built from the pieces rather than from the store, so the rules above can
    /// be tested without standing up a feed.
    ///
    /// - Parameters:
    ///   - headline: the DGHS summary block, which is the figure of record.
    ///   - national: the daily series, used only where the headline is silent.
    ///   - areas: the area breakdown; empty means "no breakdown", not "no hotspots".
    static func from(headline: FeedHeadline?,
                     national: [DailyPoint],
                     areas: [Area],
                     lastUpdated: Date?) -> NationalSnapshot {
        // The headline speaks first; the series is only a fallback for what the
        // headline leaves out. Summing an empty series gives 0, which would be
        // a figure we never received dressed up as a figure of none.
        let season = headline?.ytdCases ?? (national.isEmpty ? nil : Series.sum(national.map(\.cases)))
        let seasonDeaths = headline?.ytdDeaths ?? (national.isEmpty ? nil : Series.sum(national.map(\.deaths)))

        let last7 = national.isEmpty ? nil : Series.sum(national.suffix(7).map(\.cases))
        let previous7 = Series.sum(national.dropLast(7).suffix(7).map(\.cases))
        let change = Series.change(from: previous7, to: last7 ?? 0)

        let cases24 = headline?.last24Cases ?? national.last?.cases
        let deaths24 = headline?.last24Deaths ?? national.last?.deaths

        return NationalSnapshot(
            seasonCases: season,
            seasonDeaths: seasonDeaths,
            seasonStart: national.first?.date,
            weekCases: last7,
            weeklyChange: change,
            last24Cases: cases24,
            last24Deaths: deaths24,
            highRiskAreas: areas.isEmpty ? nil : areas.filter { $0.risk >= .high }.count,
            reportingAreas: areas.count,
            reportedFor: lastUpdated)
    }
}

/// Choosing how many columns a grid of stat tiles should use.
///
/// Four columns and five tiles leaves one stranded on a row of its own, which
/// is what the iPad was doing. Picking a width that divides the tiles more
/// evenly is a better answer than either stretching the last tile or padding
/// the row with an empty one.
enum StatGrid {
    static func columns(forTiles tiles: Int, wide: Bool) -> Int {
        let preferred = wide ? 4 : 2
        guard tiles > 0 else { return preferred }
        // Walk down from the preferred width to the first that does not leave
        // a single tile alone on the last row.
        for candidate in stride(from: preferred, through: 2, by: -1)
        where tiles % candidate != 1 {
            return candidate
        }
        return preferred
    }
}
