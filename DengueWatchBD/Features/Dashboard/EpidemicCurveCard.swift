import SwiftUI
import Charts

enum TimeRange: String, CaseIterable, Identifiable {
    case month, quarter, season

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .month: "range.30"
        case .quarter: "range.90"
        case .season: "range.season"
        }
    }

    var days: Int {
        switch self {
        case .month: 30
        case .quarter: 90
        case .season: 400
        }
    }
}

/// Daily reported cases with a 7-day average over the top.
///
/// One measure, one y-axis. Deaths and hospital census live in their own cards
/// rather than a second scale on this one.
struct EpidemicCurveCard: View {
    @Environment(LocalizationManager.self) private var loc

    let points: [DailyPoint]
    @Binding var range: TimeRange

    @State private var selectedDate: Date?

    private var series: [DailyPoint] { Array(points.suffix(range.days)) }

    private var average: [(date: Date, value: Double)] {
        // Averaged over the full history so the left edge of a 30-day window is
        // a real 7-day mean, not a ramp from zero.
        let smoothed = Series.movingAverage(points.map(\.cases), window: 7)
        return Array(zip(series.map(\.date), smoothed.suffix(series.count)))
    }

    private var selected: (day: DailyPoint, average: Double)? {
        guard let selectedDate,
              let index = series.lastIndex(where: {
                  Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
              }) else { return nil }
        return (series[index], average[index].value)
    }

    private var peak: DailyPoint? { series.max { $0.cases < $1.cases } }

    var body: some View {
        CardSection(loc.t("dash.curve.title"),
                    subtitle: loc.t("dash.curve.subtitle"),
                    accessory: AnyView(RangePicker(range: $range, onChange: { selectedDate = nil }))) {
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
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }

                if let last = average.last {
                    PointMark(x: .value("Date", last.date), y: .value("Average", last.value))
                        .foregroundStyle(Palette.cases)
                        .symbolSize(70)
                        .annotation(position: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text(loc.num(Int(last.value.rounded())))
                                .typoStatic(.micro)
                                .fontWeight(.semibold)
                        }
                }

                if let selected {
                    RuleMark(x: .value("Date", selected.day.date))
                        .foregroundStyle(Palette.axis)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, spacing: 0,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(for: selected)
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis { countAxis(loc.style) }
            .chartXAxis { dateAxis(loc.style) }
            .frame(height: 190)
            .padding(.trailing, 22)
            .padding(.top, 14)

            if let peak {
                Text(loc.t("dash.curve.peak", loc.num(peak.cases), loc.fullDate(peak.date)))
                    .typo(.micro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tooltip(for selected: (day: DailyPoint, average: Double)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loc.fullDate(selected.day.date))
                .typo(.micro).fontWeight(.semibold)
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.casesMuted).frame(width: 8, height: 8)
                Text(loc.t("dash.curve.tooltip.reported", loc.num(selected.day.cases))).typo(.micro)
            }
            HStack(spacing: 5) {
                Capsule().fill(Palette.cases).frame(width: 12, height: 2.5)
                Text(loc.t("dash.curve.tooltip.average", loc.num(Int(selected.average.rounded())))).typo(.micro)
            }
            if selected.day.deaths > 0 {
                Text(loc.t("dash.curve.tooltip.deaths", loc.num(selected.day.deaths)))
                    .typo(.micro).foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Palette.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
    }
}

/// Shared range control, so every chart card offers the same three windows.
struct RangePicker: View {
    @Environment(LocalizationManager.self) private var loc
    @Binding var range: TimeRange
    var onChange: () -> Void = {}

    var body: some View {
        Picker("", selection: $range) {
            ForEach(TimeRange.allCases) { option in
                Text(loc.t(option.labelKey)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 196)
        .onChange(of: range) { _, _ in onChange() }
    }
}

// MARK: - Shared axes
//
// Free functions rather than `AxisContent` types: axis builders are nonisolated,
// so they take the `Sendable` `NumberStyle` instead of the localization object.

/// Y axis in compact, language-aware counts.
@AxisContentBuilder
func countAxis(_ style: NumberStyle) -> some AxisContent {
    AxisMarks(position: .leading) { value in
        AxisGridLine().foregroundStyle(Palette.grid)
        AxisValueLabel {
            if let count = value.as(Int.self) {
                Text(style.compact(count))
                    .typoStatic(.micro)
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}

/// X axis of dates. Collision resolution is off because it truncates the
/// right-most label ("Sep 1" → "Se…") rather than laying it out.
@AxisContentBuilder
func dateAxis(_ style: NumberStyle, desiredCount: Int = 4) -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: desiredCount)) { value in
        AxisValueLabel(collisionResolution: .disabled) {
            if let date = value.as(Date.self) {
                Text(style.dayMonth(date))
                    .typoStatic(.micro)
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}
