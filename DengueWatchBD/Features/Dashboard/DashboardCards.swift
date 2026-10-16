import SwiftUI
import MapKit

/// A still map with the worst areas marked, standing in for the full map.
struct MapPreviewCard: View {
    @Environment(LocalizationManager.self) private var loc
    let areas: [Area]
    let onTap: () -> Void

    private var marked: [Area] { Array(areas.prefix(12)) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Map(initialPosition: .region(.bangladesh), interactionModes: []) {
                    ForEach(marked) { area in
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: area.latitude, longitude: area.longitude)) {
                            Circle()
                                .fill(area.risk.tint.opacity(0.85))
                                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 190)
                .allowsHitTesting(false)

                HStack(spacing: Space.tight) {
                    RiskScaleLegend()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(Space.row)
            }
            .cardSurface()
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .pressable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.t("map.preview.a11y"))
        .accessibilityAddTraits(.isButton)
    }
}

/// One line telling the user how fresh the data is and why.
struct SyncStatusRow: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(FeedSync.self) private var sync

    private var text: String {
        switch sync.status {
        case .syncing: loc.t("sync.updating")
        case .updated: loc.t("sync.justUpdated")
        case .upToDate(let date): loc.t("sync.lastChecked", loc.relative(date))
        case .offline: loc.t("sync.offline")
        case .failed: loc.t("sync.failed")
        case .bundledOnly, .idle: loc.t("sync.bundled")
        }
    }

    private var symbol: String {
        switch sync.status {
        case .syncing: "arrow.triangle.2.circlepath"
        case .updated, .upToDate: "checkmark.circle"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle"
        case .bundledOnly, .idle: "shippingbox"
        }
    }

    var body: some View {
        HStack(spacing: Space.hair + 2) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
            Text(text).typo(.micro).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// The language switch, shown on the home screen as the brief requires.
struct LanguageToggle: View {
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        Button {
            withAnimation(Motion.interactive) { loc.toggle() }
            Haptic.selection()
        } label: {
            Text(loc.language.shortLabel)
                .typo(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loc.t("lang.toggle.a11y"))
    }
}
