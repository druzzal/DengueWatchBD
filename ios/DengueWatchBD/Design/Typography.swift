import SwiftUI

/// The app's type scale, mapped onto Apple's native text styles.
///
/// Every style resolves to a `Font.TextStyle`, so the whole interface scales
/// with Dynamic Type instead of being pinned to fixed point sizes. Weight and
/// tracking are applied on top; the size itself always comes from the system.
///
/// Bengali and Latin share the scale but not the vertical rhythm — Bengali
/// carries the matra headline and deeper descenders, so it gets extra leading
/// at the same size. That is why views ask for `.typo(_:)` rather than
/// `.font(_:)` directly.
enum Typo {
    /// The one number a screen is about — a case count, a risk word.
    case hero
    case title
    case sectionTitle
    case headline
    case body
    case callout
    case subheadline
    case caption
    case micro
    /// Large figures inside a stat card.
    case statValue
    case statUnit

    var textStyle: Font.TextStyle {
        switch self {
        case .hero: .largeTitle
        case .title: .title
        case .sectionTitle: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .caption: .footnote
        case .micro: .caption
        case .statValue: .title
        case .statUnit: .footnote
        }
    }

    var weight: Font.Weight {
        switch self {
        case .hero: .bold
        case .title, .statValue: .semibold
        case .sectionTitle: .semibold
        case .headline: .semibold
        case .subheadline, .statUnit: .medium
        case .body, .callout, .caption, .micro: .regular
        }
    }

    /// Tighter tracking on large text, looser on small — the usual optical fix.
    var tracking: CGFloat {
        switch self {
        case .hero: -0.8
        case .title, .statValue: -0.4
        case .sectionTitle, .headline: -0.2
        case .micro: 0.2
        default: 0
        }
    }

    var font: Font { .system(textStyle, weight: weight) }

    /// Extra leading Bengali needs so the matra line clears the row above.
    func lineSpacing(for language: AppLanguage) -> CGFloat {
        guard language == .bangla else { return 0 }
        switch self {
        case .hero, .title, .statValue: return 4
        case .sectionTitle, .headline, .body, .subheadline, .callout: return 3
        default: return 2
        }
    }
}

private struct TypoModifier: ViewModifier {
    let typo: Typo
    @Environment(LocalizationManager.self) private var localization

    func body(content: Content) -> some View {
        content
            .font(typo.font)
            .tracking(typo.tracking)
            .lineSpacing(typo.lineSpacing(for: localization.language))
    }
}

extension View {
    /// Apply an app type style. Prefer this over `.font(...)` so Bengali gets
    /// its own leading and everything scales with Dynamic Type.
    func typo(_ style: Typo) -> some View {
        modifier(TypoModifier(typo: style))
    }
}

extension Text {
    /// For text rendered outside the view hierarchy — chart axis labels, which
    /// cannot read the environment.
    func typoStatic(_ style: Typo) -> Text {
        font(style.font).tracking(style.tracking)
    }
}

/// Big figures line up in columns only if their digits do.
extension View {
    func tabularFigures() -> some View {
        monospacedDigit()
    }
}
