import SwiftUI
import Charts

/// Deaths get their own card and their own axis. Plotting them against cases on
/// a second y-scale would invent a relationship the data does not show.
struct DeathsCard: View {
    @Environment(LocalizationManager.self) private var loc
    let points: [DailyPoint]

    private var average: [(date: Date, value: Double)] {
        Array(zip(points.map(\.date), Series.movingAverage(points.map(\.deaths), window: 7)))
    }

    var body: some View {
        CardSection(loc.t("dash.deaths.title"), subtitle: loc.t("dash.deaths.subtitle")) {
            ChartLegend(items: [
                .init(label: loc.t("dash.legend.daily"), color: Palette.deaths.opacity(0.35)),
                .init(label: loc.t("dash.legend.average"), color: Palette.deaths, isLine: true)
            ])

            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Date", point.date, unit: .day),
                            y: .value("Deaths", point.deaths),
                            width: .inset(1))
                        .foregroundStyle(Palette.deaths.opacity(0.35))
                        .cornerRadius(2)
                }
                ForEach(average, id: \.date) { item in
                    LineMark(x: .value("Date", item.date),
                             y: .value("Average", item.value),
                             series: .value("s", "avg"))
                        .foregroundStyle(Palette.deaths)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartYAxis { countAxis(loc.style) }
            .chartXAxis { dateAxis(loc.style) }
            .frame(height: 120)
            .padding(.trailing, 22)
        }
    }
}

/// Season-on-season totals. Years are an ordered category, so one hue is enough:
/// a second colour would read as a second series.
struct SeasonComparisonCard: View {
    @Environment(LocalizationManager.self) private var loc
    let history: [YearSummary]
    let currentYear: Int

    private var maxCases: Int { history.map(\.cases).max() ?? 1 }

    var body: some View {
        CardSection(loc.t("dash.history.title"), subtitle: loc.t("dash.history.subtitle")) {
            VStack(spacing: 9) {
                ForEach(history.reversed()) { year in
                    row(for: year)
                }
            }
            Text(loc.t("dash.history.footnote"))
                .typo(.micro)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(for year: YearSummary) -> some View {
        HStack(spacing: 10) {
            Text(loc.num(year.year).replacingOccurrences(of: ",", with: ""))
                .typo(.caption)
                .fontWeight(year.year == currentYear ? .bold : .regular)
                .monospacedDigit()
                .frame(width: 42, alignment: .leading)
                .foregroundStyle(year.year == currentYear ? .primary : .secondary)

            GeometryReader { geometry in
                let width = max(3, geometry.size.width * CGFloat(year.cases) / CGFloat(maxCases))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.cases)
                        .frame(width: width, height: 16)
                }
                .frame(height: geometry.size.height, alignment: .center)
            }
            .frame(height: 18)

            Text(loc.compact(year.cases))
                .typo(.caption).fontWeight(.medium)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)

            Text(year.deaths.map(loc.compact) ?? "—")
                .typo(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.deaths)
                .frame(width: 46, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(loc.t("dash.history.a11y",
                                  loc.num(year.year).replacingOccurrences(of: ",", with: ""),
                                  loc.num(year.cases),
                                  year.deaths.map(loc.num) ?? loc.t("common.unknown")))
    }
}

