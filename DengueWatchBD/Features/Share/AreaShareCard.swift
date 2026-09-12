import SwiftUI

/// Turns one area's real figures into a shareable image.
///
/// Every value comes from the `Area` the reader is looking at. Nothing is
/// rounded up for effect, and a figure the feed does not carry is left off the
/// card rather than filled in — a card is harder to correct than a screen,
/// because it travels without the app.
@MainActor
enum AreaShareCard {

    /// Fields resolved from live data, kept apart from the view so what the
    /// card says can be checked without rendering anything.
    struct Content: Equatable {
        var areaName: String
        var riskLabel: String
        var incidence: String
        var incidenceUnit: String
        var weeklyChange: String?
        var weeklyChangeIsUp: Bool
        var seasonCases: String
        var seasonCasesLabel: String
        var sourceLine: String
    }

    static func content(for area: Area,
                        lastUpdated: Date?,
                        loc: LocalizationManager) -> Content {
        // Only stated when the previous week exists; otherwise the ratio is
        // meaningless and the line is omitted entirely.
        let change: String? = area.weeklyChange.map { value in
            loc.t("share.change", loc.percentChange(abs(value)))
        }

        let source = lastUpdated.map {
            loc.t("share.source", loc.fullDate($0))
        } ?? loc.t("share.sourceNoDate")

        return Content(
            areaName: area.displayName(loc.language),
            riskLabel: loc.t(area.risk.labelKey),
            incidence: loc.decimal(area.incidencePer100k),
            incidenceUnit: loc.t("share.unit.incidence"),
            weeklyChange: change,
            weeklyChangeIsUp: (area.weeklyChange ?? 0) >= 0,
            seasonCases: loc.compact(area.seasonCases),
            seasonCasesLabel: loc.t("share.unit.season"),
            sourceLine: source
        )
    }

    static func view(_ content: Content, loc: LocalizationManager, risk: RiskLevel) -> ShareCardView {
        ShareCardView(
            areaName: content.areaName,
            riskLabel: content.riskLabel,
            riskTint: Palette.riskTint(risk),
            incidence: content.incidence,
            incidenceUnit: content.incidenceUnit,
            weeklyChange: content.weeklyChange,
            weeklyChangeIsUp: content.weeklyChangeIsUp,
            seasonCases: content.seasonCases,
            seasonCasesLabel: content.seasonCasesLabel,
            sourceLine: content.sourceLine,
            appName: loc.t("share.appName"),
            tagline: loc.t("share.tagline")
        )
    }

    /// Rasterise at 1x: the card is already authored at 1080 points wide, so a
    /// higher scale would produce a needlessly large file for a chat thread.
    static func image(for area: Area,
                      lastUpdated: Date?,
                      loc: LocalizationManager) -> Image? {
        let card = view(content(for: area, lastUpdated: lastUpdated, loc: loc),
                        loc: loc, risk: area.risk)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        guard let rendered = renderer.uiImage else { return nil }
        return Image(uiImage: rendered)
    }
}
