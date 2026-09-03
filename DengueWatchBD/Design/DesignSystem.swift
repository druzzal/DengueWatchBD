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

/// A screen heading drawn inside the content column.
///
/// `.navigationTitle` is rendered by the navigation bar, which always spans the
/// full width. Once the content sits in a centred column that leaves the title
/// stranded against the screen edge, out of line with everything beneath it.
/// On regular width the bar title is dropped and the screen draws this instead,
/// so heading and content share one left edge.
struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .typo(.hero)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Keep the heading aligned with the column on wide screens.
    ///
    /// On compact width nothing changes: the system large title spans the same
    /// width as the content and already lines up.
    func columnAlignedTitle(_ title: String, isWide: Bool) -> some View {
        navigationTitle(isWide ? "" : title)
            .navigationBarTitleDisplayMode(isWide ? .inline : .large)
    }

    /// Constrain content to a comfortable reading column and centre it.
    ///
    /// Applied to every scrolling screen. Without it the iPhone layout simply
    /// expands on iPad: hospital rows a thousand points wide with the name at
    /// one edge and its button at the other, symptom rows trailing into empty
    /// space, single figures adrift in half-metre cards.
    ///
    /// iPhone is unaffected — it never reaches the cap.
    func readableColumn(_ width: CGFloat = Layout.readableWidth) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
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
