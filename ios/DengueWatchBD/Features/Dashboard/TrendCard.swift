import SwiftUI
import Charts

/// The windows offered on the home trend chart. Short by design — the home
/// screen answers "what is happening now", and the long season view lives on
/// the area detail screen.
enum TrendRange: String, CaseIterable, Identifiable {
    case week, fortnight, month

    var id: String { rawValue }
    var days: Int {
        switch self {
        case .week: 7
        case .fortnight: 14
        case .month: 30
        }
    }

    var labelKey: String { "trend.range.\(rawValue)" }
}

/// A compact epidemiological curve: daily reports as bars, a smoothed average
/// over the top, and a scrubbable read-out.
///
/// One measure, one axis. Deaths and hospital census have their own cards
/// rather than a second scale here.
struct TrendCard: View {
    @Environment(LocalizationManager.self) private var loc

    /// The full series; the card slices it to the selected window.
    let points: [DailyPoint]
    @Binding var range: TrendRange

    @State private var selectedDate: Date?

    private var series: [DailyPoint] { Array(points.suffix(range.days)) }

    private var average: [(date: Date, value: Double)] {
        // Smoothed over the whole history, so the left edge of a 7-day window
        // is a real average rather than a ramp from zero.
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

    private var windowTotal: Int { series.reduce(0) { $0 + $1.cases } }

    private var windowChange: Double? {
        let previous = Array(points.dropLast(range.days).suffix(range.days))
        let before = previous.reduce(0) { $0 + $1.cases }
        guard before > 0 else { return nil }
        return (Double(windowTotal) - Double(before)) / Double(before)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.row) {
                header
                rangePicker
                chart
                caption
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.tight) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("trend.title")).typo(.headline)
                Text(loc.t("trend.subtitle"))
                    .typo(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.hair)
            if let selected {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(loc.num(selected.day.cases))
                        .typo(.headline).tabularFigures()
                    Text(loc.dayMonth(selected.day.date))
                        .typo(.micro).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(loc.num(windowTotal)).typo(.headline).tabularFigures()
                    Text(loc.t("trend.windowTotal", loc.t(range.labelKey)))
                        .typo(.micro)
                        .foregroundStyle(.secondary)
                    TrendIndicator(change: windowChange)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .animation(Motion.interactive, value: selected?.day.id)
    }

    private var rangePicker: some View {
        Picker("", selection: $range) {
            ForEach(TrendRange.allCases) { option in
                Text(loc.t(option.labelKey)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: range) { _, _ in
            selectedDate = nil
            Haptic.selection()
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { point in
                BarMark(x: .value("Date", point.date, unit: .day),
                        y: .value("Cases", point.cases),
                        width: .inset(range == .week ? 6 : 1))
                    .foregroundStyle(Palette.casesMuted.opacity(selected == nil ? 1 : 0.45))
                    .cornerRadius(3)
            }

            ForEach(average, id: \.date) { item in
                LineMark(x: .value("Date", item.date),
                         y: .value("Average", item.value),
                         series: .value("s", "avg"))
                    .foregroundStyle(Palette.cases)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }

            if let selected {
                RuleMark(x: .value("Date", selected.day.date))
                    .foregroundStyle(Palette.axis)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: []))
                PointMark(x: .value("Date", selected.day.date),
                          y: .value("Cases", selected.day.cases))
                    .foregroundStyle(Palette.cases)
                    .symbolSize(90)
            }
        }
        .chartXSelection(value: $selectedDate.animation(Motion.interactive))
        .chartYAxis { countAxis(loc.style) }
        .chartXAxis { dateAxis(loc.style, desiredCount: range == .month ? 4 : 3) }
        .frame(height: 168)
        .padding(.trailing, 20)
        .animation(Motion.content, value: range)
    }

    private var caption: some View {
        HStack(spacing: Space.tight) {
            ChartLegend(items: [
                .init(label: loc.t("dash.legend.daily"), color: Palette.casesMuted),
                .init(label: loc.t("dash.legend.average"), color: Palette.cases, isLine: true)
            ])
            Spacer(minLength: 0)
        }
    }
}
