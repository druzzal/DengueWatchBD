import SwiftUI

/// "Map data current as of 5 September" — sits beneath the area map.
///
/// Placed under the map rather than over it so it never covers an area, and
/// rendered as quiet secondary text because it qualifies the map without
/// competing with it.
///
/// Shown unconditionally. Every figure on the map is only as current as the
/// DGHS report behind it, and a reader deciding whether to act on it deserves
/// that date whether or not anything is wrong.
struct MapAsOfFooter: View {
    @Environment(DengueStore.self) private var store
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        if let reportDate = store.lastUpdated {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle")
                    .typo(.caption)
                Text(loc.t("map.asOf", loc.fullDate(reportDate)))
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
