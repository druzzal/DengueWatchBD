import SwiftUI

/// The spacing, radius and motion scale everything else is built from.
///
/// Values are named by role rather than by size, so a screen asks for
/// `Space.section` instead of `24` and the rhythm stays consistent when the
/// scale is tuned.
enum Space {
    /// Inside a chip or between an icon and its label.
    static let hair: CGFloat = 4
    static let tight: CGFloat = 8
    /// Between related rows inside a card.
    static let row: CGFloat = 12
    /// Default padding inside a card.
    static let card: CGFloat = 16
    /// Between stacked cards.
    static let stack: CGFloat = 14
    /// Between major sections of a screen.
    static let section: CGFloat = 28
    /// Screen edge inset.
    static let screen: CGFloat = 20
}

enum Radius {
    static let chip: CGFloat = 999
    static let control: CGFloat = 12
    static let card: CGFloat = 18
    /// The hero risk card sits a step above everything else.
    static let hero: CGFloat = 24
}

enum Motion {
    /// State changes the user caused — taps, toggles, selection.
    static let interactive = Animation.snappy(duration: 0.26)
    /// Content arriving or transitioning.
    static let content = Animation.smooth(duration: 0.35)
    /// The slow pulse on the live status dot.
    static let pulse = Animation.easeInOut(duration: 1.8).repeatForever(autoreverses: true)
}

/// Minimum comfortable hit target. Apple's guidance is 44pt.
enum Hit {
    static let minimum: CGFloat = 44
}

enum Layout {
    /// Cap on the content column. Beyond roughly this width a line of body text
    /// becomes tiring to read and cards turn into mostly-empty rectangles, so
    /// the extra space on iPad becomes margin rather than stretch.
    static let readableWidth: CGFloat = 820
}

// MARK: - Surfaces

extension View {
    /// The standard card surface: soft fill, hairline edge, no drop shadow.
    /// Depth comes from the plane behind it rather than from shadows.
    func cardSurface(radius: CGFloat = Radius.card,
                     fill: Color = Palette.card,
                     border: Color = Palette.hairline) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.5)
            )
    }

    /// Press feedback for a whole card acting as a button.
    func pressable() -> some View {
        buttonStyle(PressableCardStyle())
    }
}

struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.interactive, value: configuration.isPressed)
    }
}

/// Haptics, kept in one place so usage stays sparing and consistent.
enum Haptic {
    @MainActor
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
