import SwiftUI

// MARK: - Hex + dynamic colour plumbing

extension UIColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// A colour with separately chosen light and dark steps. Dark mode is a
    /// selected palette, never an automatic flip of the light one.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// MARK: - Palette
//
// Two separate jobs, deliberately kept apart:
//
//   * Risk — an ordered public-health scale, green through red. Semantic, and
//     the one thing a user must read correctly under stress.
//   * Series — chart identity for cases / admissions / deaths, which carry no
//     severity meaning and must not borrow the risk colours.
//
// Risk has two tokens per level. `tint` is for fills, marks and map symbols;
// `ink` is a darker step for text and icons that needs to clear 4.5:1. Amber in
// particular cannot do both jobs with one value — as a fill it is 1.9:1 on
// white, which is fine behind dark ink and unreadable as text.
//
// Measured with the data-viz palette validator, adjacent pairs (risk bands are
// ordered, so neighbours are what a reader compares):
//   light tints  CVD ΔE 15.8, normal-vision ΔE 19.7 — both PASS
//   dark tints   CVD ΔE 10.4, normal-vision ΔE 15.6 — both PASS
//   every ink    ≥ 5.5:1 light, ≥ 6.1:1 dark
//
// The validator also flags the dark tints as outside its lightness band. That
// check exists to stop one categorical series dominating its peers; a risk
// scale *wants* rising lightness and saturation as a second channel, so the
// rule is out of scope here rather than satisfied.
//
// Colour never carries risk alone — every presentation pairs it with an icon
// and the band's name.
enum Palette {
    // Chart series identity.
    static let cases = Color(light: "#2a78d6", dark: "#3987e5")
    static let casesMuted = Color(light: "#86b6ef", dark: "#256abf")
    static let admitted = Color(light: "#1baf7a", dark: "#199e70")
    static let deaths = Color(light: "#e34948", dark: "#e66767")

    // Chart chrome.
    static let grid = Color(light: "#e1e0d9", dark: "#2c2c2a")
    static let axis = Color(light: "#c3c2b7", dark: "#383835")
    static let mutedInk = Color(light: "#898781", dark: "#8e8e93")

    // Surfaces.
    static let card = Color(light: "#FFFFFF", dark: "#1C1C1E")
    static let raised = Color(light: "#FFFFFF", dark: "#262629")
    static let plane = Color(light: "#F5F5F7", dark: "#000000")
    static let hairline = Color(light: "#E6E6EB", dark: "#2C2C2E")

    static let accent = cases
    static let upIsBad = Color(light: "#b3261e", dark: "#f87171")
    static let downIsGood = Color(light: "#0f6b30", dark: "#4ade80")

    /// Fills, marks, map symbols.
    static func riskTint(_ level: RiskLevel) -> Color {
        switch level {
        case .low: Color(light: "#157f3b", dark: "#34a853")
        case .moderate: Color(light: "#f0b400", dark: "#f2b705")
        case .high: Color(light: "#e2600a", dark: "#f97316")
        case .severe: Color(light: "#9e1b13", dark: "#e11d48")
        }
    }

    /// Text and icons. Darker than the tint so it clears 4.5:1 on the card.
    static func riskInk(_ level: RiskLevel) -> Color {
        switch level {
        case .low: Color(light: "#0f6b30", dark: "#4ade80")
        case .moderate: Color(light: "#8a6100", dark: "#fbbf24")
        case .high: Color(light: "#9c3f00", dark: "#fb923c")
        case .severe: Color(light: "#8f1710", dark: "#f87171")
        }
    }

    /// A wash for tinted backgrounds behind risk ink.
    static func riskSoft(_ level: RiskLevel) -> Color {
        riskTint(level).opacity(0.14)
    }

    /// Ink that stays readable when placed *on* a solid risk tint.
    static func onRiskTint(_ level: RiskLevel) -> Color {
        switch level {
        // Amber is far too light to carry white text.
        case .moderate: Color(light: "#3a2a00", dark: "#2a1e00")
        case .low, .high, .severe: .white
        }
    }
}

extension RiskLevel {
    var tint: Color { Palette.riskTint(self) }
    var ink: Color { Palette.riskInk(self) }
    var soft: Color { Palette.riskSoft(self) }
    var onTint: Color { Palette.onRiskTint(self) }

    /// The icon half of the icon + label pairing risk colour always requires.
    var symbolName: String {
        switch self {
        case .low: "checkmark.shield.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .high: "exclamationmark.triangle.fill"
        case .severe: "exclamationmark.octagon.fill"
        }
    }

    /// How full the four-segment risk meter reads.
    var filledSegments: Int { rawValue + 1 }
}
