import SwiftUI

/// The Broadsheet component layer for the My Health tab.
///
/// Deliberately separate from the app's shared `Card`/`CardSection`: those
/// carry white fills, shadows and 16pt corners, and the surveillance screens
/// depend on them. Broadsheet is the opposite system — tints, no borders, no
/// shadows, 2pt corners — so it gets its own small set rather than a pile of
/// flags on the shared one.

/// The uppercase, widely tracked label above every section. The bundle calls
/// it "the system's signature device".
struct Kicker: View {
    let text: String
    var tint: Color = Broadsheet.neutral600

    var body: some View {
        Text(text)
            .font(Broadsheet.serif(11, relativeTo: .caption2))
            .textCase(.uppercase)
            .tracking(Broadsheet.kickerTracking(text))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A kicker row: context on the left, an action or status on the right.
struct KickerRow<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Broadsheet.Space.row) {
            Kicker(text: text)
            Spacer(minLength: Broadsheet.Space.tight)
            trailing
        }
    }
}

/// A flat tinted panel. "Fills are tints, never borders."
struct BroadsheetPanel<Content: View>: View {
    var fill: Color = Broadsheet.neutral100
    var padding: CGFloat = Broadsheet.Space.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Broadsheet.Radius.card))
    }
}

/// A section: kicker, then content, separated from its neighbours by
/// whitespace alone — no rules, no boxes.
struct BroadsheetSection<Content: View>: View {
    let kicker: String
    var detail: String?
    var detailTint: Color = Broadsheet.accent700
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.row) {
            KickerRow(text: kicker) {
                if let detail {
                    Text(detail)
                        .broadsheet(.secondary)
                        .foregroundStyle(detailTint)
                        .multilineTextAlignment(.trailing)
                }
            }
            content
        }
    }
}

/// The primary action: a solid cyan block, square-cornered.
struct BroadsheetButton: View {
    let title: String
    var tint: Color = Broadsheet.accent700
    var fills = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .broadsheet(.button)
                .foregroundStyle(fills ? Color.white : tint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Hit.minimum)      // 44pt, as the bundle requires
                .background(fills ? tint : Color.clear,
                            in: RoundedRectangle(cornerRadius: Broadsheet.Radius.card))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One measured value in a tinted card: kicker, value with its unit, and a
/// status line that is a *word* as well as a colour.
struct MeasureCard: View {
    let label: String
    let value: String
    var unit: String?
    let status: MeasureStatus?
    /// The words that carry the state when colour cannot.
    let statusText: String?
    var takenAt: String?

    var body: some View {
        BroadsheetPanel(padding: Broadsheet.Space.card) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: label, tint: Broadsheet.neutral700)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .broadsheet(.cardMetric)
                        .foregroundStyle(Broadsheet.valueInk(status))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit {
                        Text(unit)
                            .broadsheet(.secondary)
                            .foregroundStyle(Broadsheet.neutral700)
                    }
                }
                if let statusText {
                    Text(statusText)
                        .broadsheet(.secondary)
                        .foregroundStyle(status.map(Broadsheet.statusInk) ?? Broadsheet.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let takenAt {
                    Text(takenAt)
                        .broadsheet(.secondary)
                        .foregroundStyle(Broadsheet.neutral600)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row in a list: 1pt divider beneath, never around.
struct BroadsheetRow<Content: View>: View {
    var showsDivider = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.vertical, 11)
                .frame(minHeight: Hit.minimum, alignment: .leading)
            if showsDivider {
                Rectangle().fill(Broadsheet.divider).frame(height: 1)
            }
        }
    }
}
