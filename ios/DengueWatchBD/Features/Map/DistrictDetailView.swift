import SwiftUI
import Charts

struct DistrictDetailView: View {
    let district: District

    @Environment(SurveillanceStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(LocalizationManager.self) private var loc
    @State private var range: TimeRange = .quarter

    private var isHome: Bool { preferences.homeDistrictCode == district.code }
    private var series: [DailyPoint] { Array(district.daily.suffix(range.days)) }

    private var average: [(date: Date, value: Double)] {
        let smoothed = Series.movingAverage(district.daily.map(\.cases), window: 7)
        return Array(zip(series.map(\.date), smoothed.suffix(series.count)))
    }

    private var shareOfNational: Double {
        store.seasonCases > 0 ? Double(district.seasonCases) / Double(store.seasonCases) * 100 : 0
    }

    private var rank: Int? { store.districtsByCases.firstIndex(of: district).map { $0 + 1 } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    StatCard(label: loc.t("district.stat.season"),
                             value: loc.compact(district.seasonCases),
                             change: district.weeklyChange,
                             caption: loc.t("dash.stat.vsLastWeek"),
                             accent: Palette.cases,
                             series: district.recent(30).map { Double($0.cases) })
                    StatCard(label: loc.t("district.stat.last7"),
                             value: loc.num(district.last7Cases),
                             caption: rank.map { loc.t("district.rank", loc.num($0)) },
                             accent: Palette.cases)
                    StatCard(label: loc.t("district.stat.rate"),
                             value: loc.decimal(district.incidencePer100k),
                             unit: loc.t("common.per100k"),
                             caption: loc.t("district.riskBand", loc.t(district.risk.labelKey)),
                             accent: Palette.deaths)
                    StatCard(label: loc.t("district.stat.deaths"),
                             value: loc.num(district.seasonDeaths),
                             caption: loc.t("district.share", loc.decimal(shareOfNational)),
                             accent: Palette.deaths)
                }

                CardSection(loc.t("district.chart.title", district.displayName(loc.language)),
                            subtitle: loc.t("district.chart.subtitle"),
                            accessory: AnyView(RangePicker(range: $range))) {
                    ChartLegend(items: [
                        .init(label: loc.t("dash.legend.daily"), color: Palette.casesMuted),
                        .init(label: loc.t("dash.legend.average"), color: Palette.cases, isLine: true)
                    ])

                    Chart {
                        ForEach(series) { point in
                            BarMark(x: .value("Date", point.date, unit: .day),
                                    y: .value("Cases", point.cases),
                                    width: .inset(1))
                                .foregroundStyle(Palette.casesMuted)
                                .cornerRadius(2)
                        }
                        ForEach(average, id: \.date) { item in
                            LineMark(x: .value("Date", item.date),
                                     y: .value("Average", item.value),
                                     series: .value("s", "avg"))
                                .foregroundStyle(Palette.cases)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartYAxis { countAxis(loc.style) }
                    .chartXAxis { dateAxis(loc.style) }
                    .frame(height: 170)
                    .padding(.trailing, 22)
                }

                CardSection(loc.t("district.peers.title", district.division.displayName(loc.language)),
                            subtitle: loc.t("district.peers.subtitle")) {
                    let peers = store.districts(in: district.division)
                    let peak = peers.map(\.seasonCases).max() ?? 1
                    VStack(spacing: 0) {
                        ForEach(Array(peers.enumerated()), id: \.element.id) { index, peer in
                            NavigationLink(value: peer) {
                                DistrictRow(district: peer, peak: peak)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            if index < peers.count - 1 { Divider().overlay(Palette.hairline) }
                        }
                    }
                }

                if let meta = store.meta, meta.isSampleData {
                    InlineNote(symbol: "flask.fill", detail: meta.disclaimer)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Palette.plane)
        .navigationTitle(district.displayName(loc.language))
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc.t("district.division", district.division.displayName(loc.language)))
                            .typo(.subheadline).fontWeight(.semibold)
                        Text(loc.t("district.population",
                                   loc.compact(district.populationThousands * 1000)))
                            .typo(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    RiskBadge(risk: district.risk)
                }

                Text(loc.t(district.risk.guidanceKey))
                    .typo(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    preferences.homeDistrictCode = isHome ? nil : district.code
                } label: {
                    Label(loc.t(isHome ? "district.isHome" : "district.setHome"),
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
