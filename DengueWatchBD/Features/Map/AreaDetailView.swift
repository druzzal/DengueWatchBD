import SwiftUI
import Charts

struct AreaDetailView: View {
    let area: Area

    @Environment(DengueStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    private var isHome: Bool { preferences.homeAreaCode == area.code }

    /// DGHS publishes area figures by epidemiological week, not by day, so this
    /// chart is weekly where the national one is daily.
    private var weekly: [EpiWeekPoint] {
        zip(store.epiWeeks, area.weeklyCases).map(EpiWeekPoint.init)
    }

    /// Three-week trailing mean, to steady the week-to-week reporting jitter.
    private var average: [(week: String, value: Double)] {
        Array(zip(store.epiWeeks, Series.movingAverage(area.weeklyCases, window: 3)))
    }

    private var shareOfNational: Double {
        store.seasonCases > 0 ? Double(area.seasonCases) / Double(store.seasonCases) * 100 : 0
    }

    private var rank: Int? { store.areasByCases.firstIndex(of: area).map { $0 + 1 } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    StatCard(label: loc.t("area.stat.season"),
                             value: loc.compact(area.seasonCases),
                             change: area.weeklyChange,
                             caption: loc.t("dash.stat.vsLastWeek"),
                             accent: Palette.cases,
                             series: area.recentWeeks(12).map(Double.init))
                    StatCard(label: loc.t("area.stat.last7"),
                             value: loc.num(area.lastWeekCases),
                             caption: rank.map { loc.t("area.rank", loc.num($0)) },
                             accent: Palette.cases)
                    StatCard(label: loc.t("area.stat.rate"),
                             value: loc.decimal(area.incidencePer100k),
                             unit: loc.t("common.per100k"),
                             caption: loc.t("area.riskBand", loc.t(area.risk.labelKey)),
                             accent: Palette.deaths)
                    StatCard(label: loc.t("area.stat.deaths"),
                             value: loc.num(area.seasonDeaths),
                             caption: loc.t("area.share", loc.decimal(shareOfNational)),
                             accent: Palette.deaths)
                }

                CardSection(loc.t("area.chart.title", area.displayName(loc.language)),
                            subtitle: loc.t("area.chart.subtitle")) {
                    ChartLegend(items: [
                        .init(label: loc.t("dash.legend.daily"), color: Palette.casesMuted),
                        .init(label: loc.t("dash.legend.average"), color: Palette.cases, isLine: true)
                    ])

                    Chart {
                        ForEach(weekly) { point in
                            BarMark(x: .value("Week", point.week),
                                    y: .value("Cases", point.cases))
                                .foregroundStyle(Palette.casesMuted)
                                .cornerRadius(2)
                        }
                        ForEach(average, id: \.week) { item in
                            LineMark(x: .value("Week", item.week),
                                     y: .value("Average", item.value),
                                     series: .value("s", "avg"))
                                .foregroundStyle(Palette.cases)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartYAxis { countAxis(loc.style) }
                    .chartXAxis { weekAxis() }
                    .frame(height: 170)
                    .padding(.trailing, 22)
                }

                CardSection(loc.t("area.peers.title", area.division.displayName(loc.language)),
                            subtitle: loc.t("area.peers.subtitle")) {
                    let peers = store.areas(in: area.division)
                    let peak = peers.map(\.seasonCases).max() ?? 1
                    VStack(spacing: 0) {
                        ForEach(Array(peers.enumerated()), id: \.element.id) { index, peer in
                            NavigationLink(value: peer) {
                                AreaRow(area: peer, peak: peak)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            if index < peers.count - 1 { Divider().overlay(Palette.hairline) }
                        }
                    }
                }

                if area.weeklyIsApportioned {
                    InlineNote(symbol: "chart.bar.doc.horizontal",
                               detail: loc.t("area.apportioned.note"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Palette.plane)
        .navigationTitle(area.displayName(loc.language))
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.t("area.division", area.division.displayName(loc.language)))
                            .typo(.subheadline).fontWeight(.semibold)
                        Text(loc.t("area.population",
                                   loc.compact(area.populationThousands * 1000)))
                            .typo(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    RiskBadge(risk: area.risk)
                }

                Text(loc.t(area.risk.guidanceKey))
                    .typo(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    preferences.homeAreaCode = isHome ? nil : area.code
                } label: {
                    Label(loc.t(isHome ? "area.isHome" : "area.setHome"),
                          systemImage: isHome ? "checkmark.circle.fill" : "mappin.and.ellipse")
                        .typo(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isHome ? Palette.downIsGood : Palette.accent)
            }
        }
    }
}
