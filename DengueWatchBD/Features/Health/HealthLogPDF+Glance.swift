import Charts
import SwiftUI
import UIKit

// The front of the report: the at-a-glance tiles, the fluid summary and its
// bars, and the trend charts.

extension HealthLogPDF {

    struct GlanceTiles: View {
        @Environment(LocalizationManager.self) private var loc
        let vitals: [VitalsEntry]
        let labs: [LabReport]
        let unit: TemperatureUnit

        private struct Tile: Identifiable {
            let id: String
            let label: String
            let value: String
            let unit: String
            let side: MeasureSide
            let status: MeasureStatus
            let when: Date
        }

        var hasAny: Bool {
            vitals.contains { $0.temperature != nil || $0.oxygenSaturation != nil
                || ($0.systolic != nil && $0.diastolic != nil) }
                || labs.contains { $0.platelets != nil }
        }

        private var tiles: [Tile] {
            var tiles: [Tile] = []
            if let peak = vitals.filter({ $0.temperature != nil }).max(by: { $0.temperature! < $1.temperature! }),
               let value = peak.temperature {
                tiles.append(Tile(id: "temp", label: loc.t("pdf.glance.peakTemp"),
                                  value: loc.decimal(unit.fromCelsius(value), places: 1), unit: unit.symbol,
                                  side: VitalKind.temperature.side(value),
                                  status: VitalKind.temperature.status(value), when: peak.date))
            }
            if let low = labs.filter({ $0.platelets != nil }).min(by: { $0.platelets! < $1.platelets! }),
               let value = low.platelets {
                tiles.append(Tile(id: "plt", label: loc.t("pdf.glance.lowestPlatelets"),
                                  value: loc.num(Int(value.rounded())), unit: loc.t("lab.unit.platelets"),
                                  side: LabMeasure.platelets.side(value),
                                  status: LabMeasure.platelets.status(value), when: low.date))
            }
            if let latest = vitals.last(where: { $0.systolic != nil && $0.diastolic != nil }),
               let systolic = latest.systolic, let diastolic = latest.diastolic {
                let pair = MeasureSide.bloodPressure(systolic: systolic, diastolic: diastolic)
                tiles.append(Tile(id: "bp", label: loc.t("pdf.glance.latestBP"),
                                  value: "\(loc.num(Int(systolic)))/\(loc.num(Int(diastolic)))",
                                  unit: loc.t("vital.unit.systolic"),
                                  side: pair.side, status: pair.status, when: latest.date))
            }
            if let low = vitals.filter({ $0.oxygenSaturation != nil })
                .min(by: { $0.oxygenSaturation! < $1.oxygenSaturation! }),
               let value = low.oxygenSaturation {
                tiles.append(Tile(id: "spo2", label: loc.t("pdf.glance.lowestOxygen"),
                                  value: loc.num(Int(value.rounded())), unit: "%",
                                  side: VitalKind.oxygenSaturation.side(value),
                                  status: VitalKind.oxygenSaturation.status(value), when: low.date))
            }
            return tiles
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: loc.t("pdf.glance"))
                HStack(alignment: .top, spacing: 8) {
                    ForEach(tiles) { tile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tile.label)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(Paper.secondary)
                                .lineLimit(2)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(tile.value)
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundStyle(Palette.riskInk(tile.status.risk))
                                    .monospacedDigit()
                                Text(tile.unit)
                                    .font(.system(size: 8))
                                    .foregroundStyle(Paper.secondary)
                            }
                            StatusPill(side: tile.side, status: tile.status)
                            Text(loc.dayMonth(tile.when))
                                .font(.system(size: 7.5))
                                .foregroundStyle(Paper.secondary)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Paper.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Paper.hairline, lineWidth: 0.75))
                    }
                }
            }
        }
    }

    // MARK: - Fluids at a glance

    /// The fluid log summed for the front page: how many days were logged, the
    /// average drunk on a whole day, and on how many days urine reached the bottom
    /// of WHO's aim. Plain figures in ink — no status colour, because there is no
    /// usual range for intake, and the urine aim is stated rather than graded.
    struct FluidGlancePDF: View {
        @Environment(LocalizationManager.self) private var loc
        let summary: FluidSummary

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: loc.t("fluid.log.title"))
                HStack(alignment: .top, spacing: 8) {
                    figure(loc.t("pdf.fluids.days"), loc.num(summary.daysLogged), "")
                    if let average = summary.averageMillilitres {
                        figure(loc.t("pdf.fluids.average"), loc.num(average), loc.t("fluid.unit.ml"))
                    }
                    if summary.daysWithUrineLogged > 0 {
                        figure(loc.t("pdf.fluids.aimMet", loc.num(FluidLog.urinationAim.lowerBound)),
                               loc.t("pdf.fluids.ofDays", loc.num(summary.daysUrineAimMet),
                                     loc.num(summary.daysWithUrineLogged)), "")
                    }
                }
                if summary.includesToday {
                    Text(loc.t("pdf.fluids.wholeDays"))
                        .font(.system(size: 7.5))
                        .foregroundStyle(Paper.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        private func figure(_ label: String, _ value: String, _ unit: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                // Two lines reserved on every tile, so one wrapping label does
                // not push its figure below the others'.
                Text(label)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Paper.secondary)
                    .lineLimit(2, reservesSpace: true)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Paper.ink)
                        .monospacedDigit()
                    Text(unit)
                        .font(.system(size: 8))
                        .foregroundStyle(Paper.secondary)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Paper.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Paper.hairline, lineWidth: 0.75))
        }
    }

    /// One bar per logged day. Today's bar is paler and labelled, because it is
    /// still being filled in and would otherwise read as a bad day. The urine
    /// chart carries WHO's aim as a dashed line, named in the legend.
    struct FluidBarChart: View {
        @Environment(LocalizationManager.self) private var loc
        let title: String
        let unitLabel: String
        let bars: [(date: Date, value: Double, isPartial: Bool)]
        let aim: Double?

        private var dayStride: Int {
            guard let first = bars.first?.date, let last = bars.last?.date else { return 1 }
            let span = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 1
            return max(1, Int((Double(span) / 6).rounded(.up)))
        }

        private var top: Double {
            max(bars.map(\.value).max() ?? 1, aim ?? 0, 1) * 1.15
        }

        var body: some View {
            // Read outside the axis builders, which cannot touch the environment.
            let style = loc.style
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Paper.ink)
                    Text(unitLabel).font(.system(size: 8.5)).foregroundStyle(Paper.secondary)
                    Spacer(minLength: 0)
                }
                // A line of its own: beside a half-width title, the legend
                // squeezed it onto three lines, and Bangla titles run longer still.
                HStack(spacing: 4) {
                    if let aim {
                        // The rule's own dash, so the legend matches the chart.
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 1))
                            path.addLine(to: CGPoint(x: 12, y: 1))
                        }
                        .stroke(Paper.ink, style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
                        .frame(width: 12, height: 2)
                        Text(loc.t("pdf.fluids.aim", style.num(Int(aim))))
                            .font(.system(size: 7.5)).foregroundStyle(Paper.secondary)
                    }
                    if bars.contains(where: \.isPartial) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Paper.accentMuted)
                            .frame(width: 8, height: 8)
                        Text(loc.t("pdf.fluids.today"))
                            .font(.system(size: 7.5)).foregroundStyle(Paper.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 10)
                Chart {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                        BarMark(x: .value("Day", bar.date, unit: .day),
                                y: .value("Value", bar.value))
                            .foregroundStyle(bar.isPartial ? Paper.accentMuted : Paper.accent)
                            .cornerRadius(2)
                    }
                    if let aim {
                        RuleMark(y: .value("Aim", aim))
                            .foregroundStyle(Paper.ink)
                            .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
                    }
                }
                .chartYScale(domain: 0...top)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Paper.hairline)
                        AxisValueLabel {
                            // Counts and millilitres are whole numbers; a tick at
                            // 2.5 urinations would label something that cannot happen.
                            if let number = value.as(Double.self), number == number.rounded() {
                                Text(style.num(Int(number))).font(.system(size: 7))
                                    .foregroundStyle(Paper.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: dayStride)) { value in
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(style.dayMonth(date)).font(.system(size: 7)).foregroundStyle(Paper.secondary)
                            }
                        }
                    }
                }
                .frame(height: 104)
            }
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Paper.hairline, lineWidth: 0.75))
        }
    }

    // MARK: - Trends

    struct TrendChart: View {
        @Environment(LocalizationManager.self) private var loc
        let title: String
        let unitLabel: String
        let points: [(date: Date, value: Double, status: MeasureStatus)]
        let usual: ClosedRange<Double>
        let decimals: Int

        /// Whole days, at most about six labels. Automatic ticks fell every
        /// twelve hours on a short log and printed each date twice.
        private var dayStride: Int {
            guard let first = points.first?.date, let last = points.last?.date else { return 1 }
            let span = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 1
            return max(1, Int((Double(span) / 6).rounded(.up)))
        }

        private var domain: ClosedRange<Double> {
            let values = points.map(\.value) + [usual.lowerBound, usual.upperBound]
            let low = values.min() ?? 0, high = values.max() ?? 1
            let pad = max((high - low) * 0.12, decimals == 0 ? 10 : 0.3)
            return (low - pad)...(high + pad)
        }

        var body: some View {
            // Read outside the axis builders, which cannot touch the environment.
            let style = loc.style
            let places = decimals
            let earliest = points.first?.date ?? Date(), latest = points.last?.date ?? Date()
            // Padded either side, or the last date's label is cut at the edge.
            let pad = max(6 * 3600, latest.timeIntervalSince(earliest) * 0.06)
            let first = earliest.addingTimeInterval(-pad), last = latest.addingTimeInterval(pad)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Paper.ink)
                    Text(unitLabel).font(.system(size: 8.5)).foregroundStyle(Paper.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Palette.riskTint(.low).opacity(0.16))
                            .frame(width: 12, height: 8)
                        Text(loc.t("pdf.band")).font(.system(size: 7.5)).foregroundStyle(Paper.secondary)
                    }
                }
                Chart {
                    RectangleMark(xStart: .value("From", first), xEnd: .value("To", last),
                                  yStart: .value("Low", usual.lowerBound), yEnd: .value("High", usual.upperBound))
                        .foregroundStyle(Palette.riskTint(.low).opacity(0.10))
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                            .foregroundStyle(Paper.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                            .foregroundStyle(Palette.riskTint(point.status.risk))
                            .symbolSize(22)
                    }
                }
                .chartYScale(domain: domain)
                .chartXScale(domain: first...last)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Paper.hairline)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(style.decimal(number, places: places)).font(.system(size: 7))
                                    .foregroundStyle(Paper.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: dayStride)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Paper.hairline)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(style.dayMonth(date)).font(.system(size: 7)).foregroundStyle(Paper.secondary)
                            }
                        }
                    }
                }
                .frame(height: 104)
            }
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Paper.hairline, lineWidth: 0.75))
        }
    }

    // MARK: - Day by day
}
