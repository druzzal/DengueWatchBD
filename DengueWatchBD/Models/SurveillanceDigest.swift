import Foundation

/// Plain-language statements about what moved in the latest DGHS update.
///
/// Every statement is derived from a value the feed actually carries. Nothing
/// is inferred, smoothed or filled in: when the data cannot support a claim the
/// statement is simply absent, which is why `items` returns a list that may be
/// short or empty rather than a fixed set of slots.
///
/// Deliberately free of SwiftUI and of the store, so the rules can be tested
/// directly on values. The view renders whatever comes back and decides nothing.
struct SurveillanceDigest {

    /// What a statement is about, so the view can weight it without parsing text.
    enum Kind: String {
        case nationalRise
        case nationalFall
        case nationalSteady
        case hotspots
        case steepestRises
        case noBreakdown
    }

    struct Item: Identifiable, Hashable {
        let kind: Kind
        /// Localization key; the view resolves it so nothing here is language-bound.
        let key: String
        let arguments: [String]
        var id: String { kind.rawValue }
    }

    /// A week-on-week move smaller than this is reporting noise, not a trend.
    /// DGHS figures wobble with reporting-day effects, and calling a 2% wobble a
    /// rise would cry wolf every other week.
    static let steadyBand = 0.05

    /// Only areas moving at least this much are worth naming individually.
    static let notableAreaRise = 0.20

    /// How many areas to name in one sentence before it stops being readable.
    static let maxNamedAreas = 2

    /// - Parameters:
    ///   - nationalChange: week-on-week fraction, or nil when the previous week
    ///     is missing and a ratio would be meaningless.
    ///   - hotspotCount: areas currently at high risk or worse.
    ///   - hasAreaBreakdown: whether per-area figures arrived at all. An empty
    ///     area list and "no areas are high risk" mean opposite things.
    ///   - risingAreas: (name, change) for areas that rose, steepest first.
    static func items(nationalChange: Double?,
                      hotspotCount: Int,
                      hasAreaBreakdown: Bool,
                      risingAreas: [(name: String, change: Double)]) -> [Item] {
        var items: [Item] = []

        if let change = nationalChange {
            let percent = abs(change) * 100
            if change > steadyBand {
                items.append(Item(kind: .nationalRise,
                                  key: "digest.national.rise",
                                  arguments: [percent.formatted(.number.precision(.fractionLength(0)))]))
            } else if change < -steadyBand {
                items.append(Item(kind: .nationalFall,
                                  key: "digest.national.fall",
                                  arguments: [percent.formatted(.number.precision(.fractionLength(0)))]))
            } else {
                items.append(Item(kind: .nationalSteady,
                                  key: "digest.national.steady",
                                  arguments: []))
            }
        }

        guard hasAreaBreakdown else {
            // Saying "0 areas are high risk" when no area figures arrived would
            // be a reassurance the data cannot support.
            items.append(Item(kind: .noBreakdown, key: "digest.noBreakdown", arguments: []))
            return items
        }

        items.append(Item(kind: .hotspots,
                          key: hotspotCount == 1 ? "digest.hotspots.one" : "digest.hotspots.many",
                          arguments: [String(hotspotCount)]))

        let notable = risingAreas
            .filter { $0.change >= notableAreaRise }
            .prefix(maxNamedAreas)
            .map(\.name)
        if !notable.isEmpty {
            items.append(Item(kind: .steepestRises,
                              key: notable.count == 1 ? "digest.rises.one" : "digest.rises.two",
                              arguments: Array(notable)))
        }

        return items
    }
}
