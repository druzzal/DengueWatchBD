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
    /// The edge worth marking, when the measure has one.
    let threshold: Threshold?
    let format: (Double) -> String

    /// A line on the chart, and which way a reading crosses it to matter.
    ///
    /// Temperature counts when it climbs above the line; a platelet count
    /// counts when it falls below one. The chart draws both the same way and
    /// only needs telling which side is the worrying one — marking the top of
    /// a platelet range would highlight exactly the readings nobody is
    /// worried about.
    struct Threshold {
        enum Concern { case above, below }

        let value: Double
        let concern: Concern
        /// Printed beside the line, so the mark is never only a colour.
        var word: String = ""

        func isCrossed(by reading: Double) -> Bool {
            switch concern {
            case .above: reading > value
            case .below: reading < value
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack(spacing: Space.tight) {
                Spacer(minLength: 0)
                Label(loc.t(trend.labelKey), systemImage: trend.symbol)
                    .typo(.micro)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.secondary)
                    .labelStyle(.titleAndIcon)
            }

            Chart {
                // The usual range as a band, so a reading can be seen sitting
                // inside or outside it without reading any numbers.
                if let threshold {
                    // A threshold line rather than a "you are fine" band: the
                    // edge a reader has crossed is the thing worth marking,
                    // and it is labelled in words as well as drawn.
                    RuleMark(y: .value("Threshold", threshold.value))
                        .foregroundStyle(Palette.riskTint(.high))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        // The label sits on the safe side of its own line, so
                        // it never lands on top of the readings that crossed.
                        .annotation(position: threshold.concern == .above ? .bottom : .top,
                                    alignment: .leading, spacing: 2) {
                            Text(thresholdLabel)
                                .typoStatic(.micro)
                                .foregroundStyle(Palette.riskInk(.high))
                                // The line sits inside the plot, so the label
                                // needs its own ground wherever a reading
                                // happens to cross it.
                                .padding(.horizontal, 3)
                                .background(Palette.card.opacity(0.9))
                        }
                }
                ForEach(points, id: \.date) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(isLatestAndOut(point) ? Palette.riskTint(.severe) : tint)
                        .symbolSize(isLatestAndOut(point) ? 90 : 50)
                }
            }
            .chartYScale(domain: yDomain)
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
                .foregroundStyle(Palette.mutedInk)
        }
    }

    /// The vertical range the line is drawn in.
    ///
    /// Left to Charts it rounds outward to tidy numbers, which for a platelet
    /// count meant a scale starting at zero: half the plot empty and a fall
    /// from 186 to 88 flattened into a gentle slope. The shape of that fall is
    /// the reason the chart is there, so the domain is the readings and the
    /// threshold and little else — padded enough that neither sits on an edge.
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        var low = values.min() ?? 0
        var high = values.max() ?? 1
        if let threshold {
            low = Swift.min(low, threshold.value)
            high = Swift.max(high, threshold.value)
        }
        // A flat line still needs a band to sit in.
        let pad = Swift.max((high - low) * 0.15, 0.5)
        return Swift.max(0, low - pad)...(high + pad)
    }

    /// True for the most recent reading when it has crossed the threshold —
    /// the one point a reader is actually asking about.
    private func isLatestAndOut(_ point: (date: Date, value: Double)) -> Bool {
        guard let last = points.last, let threshold,
              point.date == last.date else { return false }
        return threshold.isCrossed(by: point.value)
    }

    /// The threshold, in words as well as a line — colour is never the only
    /// signal here.
    private var thresholdLabel: String {
        guard let threshold else { return "" }
        return threshold.word.isEmpty
            ? format(threshold.value)
            : "\(format(threshold.value)) \(threshold.word)"
    }

    /// VoiceOver gets the direction and the endpoints, which is what the line
    /// conveys — reading out every point would be worse than useless.
    private var accessibilityDescription: String {
        guard let first = points.first, let last = points.last else { return title }
        return "\(title). \(loc.t(trend.labelKey)). \(format(first.value)) to \(format(last.value))."
    }
}
