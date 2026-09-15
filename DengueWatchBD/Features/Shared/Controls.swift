import SwiftUI

/// The one prominent button style, so "the main action" looks the same
/// everywhere and nothing else competes with it.
struct PrimaryActionButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = Palette.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.tight) {
                if let systemImage {
                    Image(systemName: systemImage).font(.body.weight(.semibold))
                }
                Text(title).typo(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Hit.minimum + 6)
            .foregroundStyle(.white)
            .background(tint, in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
        }
        .pressable()
    }
}

/// Secondary action: same footprint, quieter treatment.
struct SecondaryActionButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = Palette.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.tight) {
                if let systemImage {
                    Image(systemName: systemImage).font(.body.weight(.medium))
                }
                Text(title).typo(.subheadline).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Hit.minimum)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
        }
        .pressable()
    }
}

/// An advisory banner: icon, title, one line of explanation, one action.
/// Deliberately calm — no flashing, no full-bleed red.
struct AlertCard: View {
    let risk: RiskLevel
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Space.row) {
            Image(systemName: risk.symbolName)
                .font(.title3)
                .foregroundStyle(risk.ink)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.hair + 2) {
                Text(title).typo(.headline)
                Text(message)
                    .typo(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            Text(actionTitle).typo(.caption).fontWeight(.semibold)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(risk.ink)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(risk.soft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(risk.tint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Quiet inline note — disclosures and caveats that must be visible but must
/// not compete with the data.
struct InlineNote: View {
    var symbol: String = "info.circle"
    var title: String?
    var detail: String
    /// Nil keeps the quiet grey of a footnote. A tint marks the note as
    /// something to act on — never louder than the thing it refers to.
    var tint: Color?

    /// The symbol sits in a column of its own width rather than its glyph's.
    ///
    /// SF Symbols are not one width: a triangle, a droplet and an info circle
    /// each start the text in a different place, and the care plan stacks four
    /// of these notes with four different symbols. Scaled, so the column still
    /// holds at the largest type sizes.
    @ScaledMetric(relativeTo: .caption) private var symbolWidth: CGFloat = 17

    var body: some View {
        HStack(alignment: .top, spacing: Space.tight + 2) {
            Image(systemName: symbol)
                .typo(.caption)
                .foregroundStyle(tint ?? Palette.mutedInk)
                .frame(width: symbolWidth)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title).typo(.caption).fontWeight(.semibold)
                }
                Text(detail)
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((tint ?? Palette.mutedInk).opacity(tint == nil ? 0.07 : 0.12),
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A row in a list of places you can go for help.
struct FacilityRow: View {
    @Environment(LocalizationManager.self) private var loc
    let name: String
    var subtitle: String?
    var distanceText: String?
    var symbol: String = "cross.case.fill"
    var onDirections: (() -> Void)?
    var onCall: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Space.row) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34)
                .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .typo(.subheadline)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .typo(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let distanceText {
                    Text(distanceText)
                        .typo(.micro)
                        .foregroundStyle(Palette.accent)
                }
            }

            Spacer(minLength: Space.hair)

            HStack(spacing: Space.tight) {
                if let onCall {
                    Button(action: onCall) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.downIsGood)
                            .frame(width: Hit.minimum - 8, height: Hit.minimum - 8)
                            .background(Palette.downIsGood.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(loc.t("care.call"))
                }
                if let onDirections {
                    Button(action: onDirections) {
                        Image(systemName: "arrow.triangle.turn.up.right.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: Hit.minimum - 8, height: Hit.minimum - 8)
                            .background(Palette.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(loc.t("care.directions"))
                }
            }
        }
        .padding(.vertical, Space.row)
    }
}

/// A line of small print with a symbol in front of it.
///
/// Shared so that a stack of them lines up. Written out by hand, each line
/// chose its own spacing and let the glyph set the text's left edge, so a bell
/// and a crossed-out location arrow began their sentences in two different
/// places.
struct NoticeLine: View {
    @ScaledMetric(relativeTo: .caption) private var symbolWidth: CGFloat = 14

    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.hair + 2) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: symbolWidth)
                .accessibilityHidden(true)
            Text(text)
                .typo(.micro)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// The line under a reading field that will not save as typed.
///
/// Shared by the vital-sign and blood-count forms so the two refuse in the
/// same words. Renders nothing at all when the field is empty or good, so it
/// can sit in either form unconditionally.
struct InvalidReadingNote: View {
    @Environment(LocalizationManager.self) private var loc

    let reading: MeasureInput.Reading

    var body: some View {
        if let message {
            Text(message)
                .typo(.micro)
                .foregroundStyle(Palette.riskInk(.severe))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var message: String? {
        switch reading {
        case .empty, .value:
            return nil
        case .notANumber:
            return loc.t("measure.invalid.number")
        case .outOfRange(let range):
            return loc.t("measure.invalid.range",
                         bound(range.lowerBound), bound(range.upperBound))
        }
    }

    /// A decimal place only where the bound has one. White cells start at 0.1,
    /// and rounding that to "0" would quote back a range that includes a value
    /// the field refuses.
    private func bound(_ value: Double) -> String {
        loc.decimal(value, places: value == value.rounded() ? 0 : 1)
    }
}

