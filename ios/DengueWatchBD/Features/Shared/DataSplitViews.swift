import SwiftUI

/// The headline national figure, with the caveat attached to it rather than
/// floating elsewhere on the screen.
///
/// The two exist together because they are one claim. When the DGHS dashboard
/// has run ahead of the press releases, the number above is newer than the
/// district breakdown beneath it, and a reader who sees only the number will
/// reasonably assume the whole screen is that current.
struct HeadlineTotal: View {
    @Environment(SurveillanceStore.self) private var store
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dynamicTypeSize) private var typeSize

    let title: String
    let value: Int
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .typo(.caption)
                    .foregroundStyle(.secondary)
                Text(loc.num(value))
                    .typo(.statValue)
                    .contentTransition(.numericText())
                    .animation(Motion.interactive, value: value)
                if let caption {
                    Text(caption).typo(.caption).foregroundStyle(.secondary)
                }
            }

            if store.breakdownTrailsHeadline {
                SourceSplitNote()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Says, in one line, that the headline and the breakdown come from different
/// days and different DGHS surfaces.
///
/// Deliberately not an `AlertCard`: nothing is wrong and nothing needs doing.
/// Dressing a provenance note as a warning would teach people to dismiss the
/// warnings that do matter.
struct SourceSplitNote: View {
    @Environment(SurveillanceStore.self) private var store
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let latest = store.latestNational {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))

            layout {
                Image(systemName: "clock.arrow.circlepath")
                    .typo(.caption)
                    .foregroundStyle(.secondary)
                Text(loc.t("split.headline.note", latest.source))
                    .typo(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
        }
    }
}

/// "Map data current as of 3 September" — sits beneath the district map.
///
/// Placed under the map rather than over it so it never covers a district, and
/// rendered as quiet secondary text because it qualifies the map without
/// competing with it.
struct MapAsOfFooter: View {
    @Environment(SurveillanceStore.self) private var store
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        if store.breakdownTrailsHeadline, let seriesDate = store.seriesLastUpdated {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle")
                    .typo(.caption)
                Text(loc.t("map.asOf", loc.fullDate(seriesDate)))
                    .typo(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.screen)
            .padding(.vertical, Space.row)
            .accessibilityElement(children: .combine)
        }
    }
}
