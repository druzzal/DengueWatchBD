import Charts
import SwiftUI

/// A line through the reader's own readings, with the direction stated.
///
/// Reusable across measures so temperature and platelets are drawn the same
/// way — a reader comparing the two should not have to relearn the chart.
struct HealthTrendChart: View {
    @Environment(LocalizationManager.self) private var loc

    /// Passed in rather than read from the environment inside the axis
    /// builders: those are nonisolated, and reaching for the localization
    /// object there crashes the moment the chart draws. The app already
    /// solved this once, in ChartAxes.swift.
    let style: NumberStyle
    let title: String
    let points: [(date: Date, value: Double)]
    let trend: HealthTrend
    let tint: Color
    /// Range shown for context, when the measure has a meaningful one.
    let usualRange: ClosedRange<Double>?
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack(spacing: Space.tight) {
                Text(title).typo(.subheadline)
                Spacer(minLength: Space.tight)
                Label(loc.t(trend.labelKey), systemImage: trend.symbol)
                    .typo(.micro)
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
                    .labelStyle(.titleAndIcon)
            }

            Chart {
                // The usual range as a band, so a reading can be seen sitting
                // inside or outside it without reading any numbers.
                if let usualRange {
                    RectangleMark(
                        yStart: .value("Low", usualRange.lowerBound),
                        yEnd: .value("High", usualRange.upperBound)
                    )
                    .foregroundStyle(Palette.riskTint(.low).opacity(0.10))
                }
                ForEach(points, id: \.date) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(tint)
                        .symbolSize(50)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { dateAxis(style, desiredCount: 3) }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Palette.grid)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(format(number))
                                .typoStatic(.micro)
                                .foregroundStyle(Palette.mutedInk)
                        }
                    }
                }
            }
            .frame(height: 132)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)

            Text(loc.t("trend.readings", loc.num(points.count)))
                .typo(.micro)
                .foregroundStyle(.tertiary)
        }
    }

    /// VoiceOver gets the direction and the endpoints, which is what the line
    /// conveys — reading out every point would be worse than useless.
    private var accessibilityDescription: String {
        guard let first = points.first, let last = points.last else { return title }
        return "\(title). \(loc.t(trend.labelKey)). \(format(first.value)) to \(format(last.value))."
    }
}
