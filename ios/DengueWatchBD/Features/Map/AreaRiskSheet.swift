import SwiftUI

/// What a tapped area shows before the user commits to the full page:
/// where, how bad, which way it is moving, how fresh, and from whom.
struct AreaRiskSheet: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    let area: Area
    let lastUpdated: Date?
    var onOpenDetail: (Area) -> Void

    private var isHome: Bool { preferences.homeAreaCode == area.code }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.stack) {
                    header

                    HStack(spacing: Space.row) {
                        MiniStat(value: loc.num(area.lastWeekCases),
                                 label: loc.t("map.area.recentCases"),
                                 accent: Palette.cases)
                        MiniStat(value: loc.decimal(area.incidencePer100k),
                                 label: loc.t("map.area.rate"),
                                 accent: area.risk.tint)
                        MiniStat(value: loc.compact(area.seasonCases),
                                 label: loc.t("map.area.seasonCases"),
                                 accent: Palette.cases)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.row) {
                            Text(loc.t(area.risk.guidanceKey))
                                .typo(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider().overlay(Palette.hairline)
                            HStack {
                                SourceBadge(kind: .official, detail: "DGHS")
                                Spacer(minLength: 0)
                                if let lastUpdated {
                                    Text(loc.t("risk.card.updated", loc.relative(lastUpdated)))
                                        .typo(.micro)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    VStack(spacing: Space.row) {
                        PrimaryActionButton(title: loc.t("map.area.viewDetail"),
                                            systemImage: "chart.xyaxis.line") {
                            dismiss()
                            onOpenDetail(area)
                        }
                        SecondaryActionButton(
                            title: loc.t(isHome ? "area.isHome" : "map.area.setHome"),
                            systemImage: isHome ? "checkmark.circle.fill" : "mappin.and.ellipse",
                            tint: isHome ? Palette.downIsGood : Palette.accent
                        ) {
                            preferences.homeAreaCode = isHome ? nil : area.code
                            Haptic.success()
                        }
                    }
                }
                .padding(.horizontal, Space.screen)
                .padding(.vertical, Space.card)
            }
            .background(Palette.plane)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t("common.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Text(area.displayName(loc.language))
                .typo(.title)
            Text(loc.t("area.division", area.division.displayName(loc.language)))
                .typo(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: Space.tight) {
                RiskBadge(risk: area.risk)
                TrendIndicator(change: area.weeklyChange)
                Spacer(minLength: 0)
            }
            .padding(.top, Space.hair)

            RiskMeter(risk: area.risk)
                .padding(.top, Space.hair)
        }
    }
}

/// A compact figure used three-across inside a sheet.
struct MiniStat: View {
    let value: String
    let label: String
    var accent: Color = Palette.cases

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Text(value)
                .typo(.headline)
                .tabularFigures()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .typo(.micro)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.row)
        .cardSurface(radius: Radius.control)
        .accessibilityElement(children: .combine)
    }
}

/// The map's key: what circle size means, and what each colour band is.
struct MapLegend<Header: View>: View {
    @Environment(LocalizationManager.self) private var loc
    let metricExplanation: String
    let sizeSamples: [(label: String, diameter: CGFloat)]
    @ViewBuilder var header: Header

    init(metricExplanation: String,
         sizeSamples: [(label: String, diameter: CGFloat)],
         @ViewBuilder header: () -> Header = { EmptyView() }) {
        self.metricExplanation = metricExplanation
        self.sizeSamples = sizeSamples
        self.header = header()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight + 2) {
            header
            Text(metricExplanation)
                .typo(.micro)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .bottom, spacing: Space.row) {
                ForEach(sizeSamples, id: \.label) { sample in
                    VStack(spacing: 3) {
                        Circle()
                            .fill(Palette.mutedInk.opacity(0.30))
                            .frame(width: sample.diameter, height: sample.diameter)
                        Text(sample.label).typo(.micro).foregroundStyle(.secondary)
                    }
                }

                Divider().frame(height: 30).overlay(Palette.hairline)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(loc.t("map.legend.risk"))
                        .typo(.micro).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    RiskScaleLegend()
                }
            }
        }
        .padding(Space.row)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
    }
}
