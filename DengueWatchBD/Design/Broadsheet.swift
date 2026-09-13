import SwiftUI

/// The Broadsheet design system, as specified in the "My Health" design
/// bundle: newsprint — near-black serif on paper, with the two process inks
/// used sparingly as spot colour.
///
/// Scoped to the My Health tab. The surveillance screens keep the app's own
/// palette, because their four-band risk scale (low → severe) is load-bearing
/// on the map and legend and does not survive a system with one alarm colour.
///
/// Two rules here are not decoration:
///
/// - **Cyan is interaction, magenta is alarm, and never both in one small
///   component.** Text-size cyan is always `accent700`; the base swatch only
///   clears 3:1 and is for icons and large type.
/// - **There is no success colour.** "In range" is stated in neutral ink and
///   in words. Only danger gets colour, so danger cannot be missed. This is
///   why a normal reading here is not green.
enum Broadsheet {

    // MARK: - Ground and ink

    static let paper = Color(hex: "#f3f2f2")
    static let surface = Color(hex: "#eae9e9")
    static let ink = Color(hex: "#201e1d")
    static let divider = Color(hex: "#201e1d").opacity(0.16)

    // MARK: - Ramps

    static let neutral100 = Color(hex: "#f8f4f4")
    static let neutral200 = Color(hex: "#eae7e7")
    static let neutral300 = Color(hex: "#d7d3d3")
    static let neutral500 = Color(hex: "#9b9797")
    static let neutral600 = Color(hex: "#7d7979")
    static let neutral700 = Color(hex: "#605d5d")
    static let neutral800 = Color(hex: "#444141")

    /// Cyan — the interactive ink.
    static let accent = Color(hex: "#0088b0")
    static let accent100 = Color(hex: "#e9f8ff")
    static let accent200 = Color(hex: "#cbeeff")
    static let accent600 = Color(hex: "#1186ac")
    static let accent700 = Color(hex: "#006786")
    static let accent800 = Color(hex: "#004961")

    /// Magenta — the clinical alarm ink.
    static let alarm200 = Color(hex: "#ffdee6")
    static let alarm100 = Color(hex: "#fff1f4")
    static let alarm400 = Color(hex: "#ff90b1")
    static let alarm600 = Color(hex: "#d82071")
    static let alarm700 = Color(hex: "#aa0b56")
    static let alarm800 = Color(hex: "#790e3d")
    static let alarm900 = Color(hex: "#4b1528")

    // MARK: - Geometry

    /// "Nothing is pill-shaped and nothing is heavily rounded — this is a
    /// print system."
    enum Radius {
        static let small: CGFloat = 1
        static let card: CGFloat = 2
        static let large: CGFloat = 4
    }

    /// Screen side padding, and the section rhythm above it.
    enum Space {
        static let screen: CGFloat = 22
        static let section: CGFloat = 18
        static let card: CGFloat = 14
        static let grid: CGFloat = 10
        static let row: CGFloat = 10
        static let tight: CGFloat = 5
    }

    // MARK: - Status colour

    /// The one place the no-green rule is enforced.
    ///
    /// A reading inside its usual range takes ordinary ink, never a colour of
    /// its own. Out of range takes the alarm ink — and, everywhere this is
    /// used, a word as well, because colour alone is never the signal.
    static func statusInk(_ status: MeasureStatus) -> Color {
        switch status {
        case .normal: neutral700
        case .outside, .farOutside: alarm700
        }
    }

    /// The kicker's tracking, which Latin wants and Bengali does not.
    ///
    /// Bengali is a connected script: letterspacing pulls its conjuncts apart
    /// and makes the label harder to read, not more deliberate. Decided from
    /// the string rather than the environment so it is safe to call anywhere,
    /// including inside a chart builder.
    static func kickerTracking(_ text: String) -> CGFloat {
        let bengali = 0x0980...0x09FF
        return text.unicodeScalars.contains { bengali.contains(Int($0.value)) } ? 0 : 2.0
    }

    /// Ink for the value itself, which is heavier than its status line.
    static func valueInk(_ status: MeasureStatus?) -> Color {
        guard let status, status != .normal else { return ink }
        return alarm700
    }
}

// MARK: - Typeface

extension Broadsheet {
    /// Source Serif 4, bundled. "No sans-serif anywhere, including UI chrome
    /// — the serif is the chrome."
    ///
    /// Sized with `relativeTo:` so Dynamic Type still scales the whole scale,
    /// which the bundle requires.
    static func serif(_ size: CGFloat,
                      semibold: Bool = false,
                      italic: Bool = false,
                      relativeTo style: Font.TextStyle = .body) -> Font {
        let name = italic ? "SourceSerif4-It"
            : (semibold ? "SourceSerif4-Semibold" : "SourceSerif4-Regular")
        return .custom(name, size: size, relativeTo: style)
    }

    /// The type roles from the bundle's mobile scale.
    enum Role {
        case screenTitle        // 34 / 600
        case screenTitleTwoLine // 32 / 600
        case heroMetric         // 46 / 600
        case cardMetric         // 27 / 600
        case bannerHeading      // 21 / 600
        case body               // 16 / 400
        case bodyLarge          // 17 / 400
        case secondary          // 13 / 400
        case button             // 15 / 400
        case kicker             // 10-11 / uppercase / tracked
        case tabLabel           // 10 / 400
    }
}

extension View {
    /// Applies one Broadsheet type role, including the kicker's tracking.
    @ViewBuilder
    func broadsheet(_ role: Broadsheet.Role) -> some View {
        switch role {
        case .screenTitle:
            font(Broadsheet.serif(34, semibold: true, relativeTo: .largeTitle))
                .tracking(-0.34).lineSpacing(0)
        case .screenTitleTwoLine:
            font(Broadsheet.serif(32, semibold: true, relativeTo: .title))
                .tracking(-0.32)
        case .heroMetric:
            font(Broadsheet.serif(46, semibold: true, relativeTo: .largeTitle))
        case .cardMetric:
            font(Broadsheet.serif(27, semibold: true, relativeTo: .title2))
        case .bannerHeading:
            font(Broadsheet.serif(21, semibold: true, relativeTo: .title3))
        case .bodyLarge:
            font(Broadsheet.serif(17, relativeTo: .body))
        case .body:
            font(Broadsheet.serif(16, relativeTo: .body))
        case .secondary:
            font(Broadsheet.serif(13, relativeTo: .footnote))
        case .button:
            font(Broadsheet.serif(15, relativeTo: .callout))
        case .kicker:
            // "Reads larger than its size" — uppercase and widely tracked.
            // Prefer `Kicker`, which drops the tracking for Bengali.
            font(Broadsheet.serif(11, relativeTo: .caption2))
                .textCase(.uppercase)
                .tracking(2.0)
        case .tabLabel:
            font(Broadsheet.serif(10, relativeTo: .caption2)).tracking(0.6)
        }
    }
}
