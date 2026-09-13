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
    /// The word printed beside the threshold line, so the mark is never only
    /// a colour. Empty prints the number alone.
    var thresholdWord: String = ""
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack(spacing: Space.tight) {
                Spacer(minLength: 0)
                Label(loc.t(trend.labelKey), systemImage: trend.symbol)
                    .broadsheet(.secondary)
                    .foregroundStyle(Broadsheet.neutral700)
                    .labelStyle(.titleAndIcon)
            }

            Chart {
                // The usual range as a band, so a reading can be seen sitting
                // inside or outside it without reading any numbers.
                if let usualRange {
                    // The bundle's threshold rule, not a "you are fine" band:
                    // Broadsheet has no success colour, so the line marks the
                    // edge that matters and is labelled in words.
                    RuleMark(y: .value("Threshold", usualRange.upperBound))
                        .foregroundStyle(Broadsheet.alarm400)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .annotation(position: .bottom, alignment: .leading, spacing: 2) {
                            Kicker(text: thresholdLabel, tint: Broadsheet.alarm700)
                                // The line sits inside the plot, so the label
                                // needs its own ground wherever a reading
                                // happens to cross it.
                                .padding(.horizontal, 3)
                                .background(Broadsheet.neutral100.opacity(0.9))
                        }
                }
                ForEach(points, id: \.date) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(isLatestAndOut(point) ? Broadsheet.alarm600 : tint)
                        .symbolSize(isLatestAndOut(point) ? 90 : 50)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { dateAxis(style, desiredCount: 3) }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Broadsheet.neutral300)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(format(number))
                                .font(Broadsheet.serif(10, relativeTo: .caption2))
                                .foregroundStyle(Broadsheet.neutral600)
                        }
                    }
                }
            }
            .frame(height: 132)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)

            Text(loc.t("trend.readings", loc.num(points.count)))
                .broadsheet(.secondary)
                .foregroundStyle(Broadsheet.neutral600)
        }
    }

    /// True for the most recent reading when it has crossed the threshold —
    /// the one point a reader is actually asking about.
    private func isLatestAndOut(_ point: (date: Date, value: Double)) -> Bool {
        guard let last = points.last, let usualRange,
              point.date == last.date else { return false }
        return !usualRange.contains(point.value)
    }

    /// The threshold, in words as well as a line — colour is never the only
    /// signal here.
    private var thresholdLabel: String {
        guard let usualRange else { return "" }
        return thresholdWord.isEmpty
            ? format(usualRange.upperBound)
            : "\(format(usualRange.upperBound)) \(thresholdWord)"
    }

    /// VoiceOver gets the direction and the endpoints, which is what the line
    /// conveys — reading out every point would be worse than useless.
    private var accessibilityDescription: String {
        guard let first = points.first, let last = points.last else { return title }
        return "\(title). \(loc.t(trend.labelKey)). \(format(first.value)) to \(format(last.value))."
    }
}
