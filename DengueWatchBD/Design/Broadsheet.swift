import SwiftUI

/// The Broadsheet palette, from the "My Health" design bundle: newsprint —
/// near-black ink on paper, with the two process inks used sparingly as spot
/// colour.
///
/// Colour only, and only the clinical part of it. The tab's type, components
/// and interaction colour are the app's own, so it reads as the same app as
/// the surveillance screens. What Broadsheet supplies is what those screens'
/// palette cannot: a system with exactly one alarm colour and no success
/// colour, so a reading that needs attention is the only coloured thing on
/// the screen.
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

    /// Ink for the value itself, which is heavier than its status line.
    static func valueInk(_ status: MeasureStatus?) -> Color {
        guard let status, status != .normal else { return ink }
        return alarm700
    }
}
