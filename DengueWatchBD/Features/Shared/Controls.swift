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

    var body: some View {
        HStack(alignment: .top, spacing: Space.tight + 2) {
            Image(systemName: symbol)
                .typo(.caption)
                .foregroundStyle(Palette.mutedInk)
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
        .background(Palette.mutedInk.opacity(0.07),
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
