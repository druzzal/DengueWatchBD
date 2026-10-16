import Charts
import SwiftUI
import UIKit

// The report day by day: each day's heading and a card for every record.

extension HealthLogPDF {

    struct DayHeading: View {
        @Environment(LocalizationManager.self) private var loc
        let date: Date
        let number: Int?
        let name: String?

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let number {
                    Text(loc.t("fever.timeline.day", loc.num(number)))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Paper.accent, in: Capsule())
                }
                Text(loc.fullDate(date))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paper.ink)
                if let name {
                    Text(name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Paper.secondary)
                }
                Spacer()
            }
            .padding(.top, 6)
        }
    }

    /// One record as the app shows it: a card with a coloured edge, its kind
    /// and time, and a grid of readings.
    struct RecordCard<Content: View>: View {
        @Environment(LocalizationManager.self) private var loc
        let title: String
        let symbol: String
        let tint: Color
        /// Nil for a card that sums a whole day rather than recording a moment.
        let date: Date?
        let note: String
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                    Spacer()
                    if let date {
                        Text(loc.time(date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Paper.secondary)
                            .monospacedDigit()
                    }
                }
                content
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 9).italic())
                        .foregroundStyle(Paper.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .padding(.leading, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Paper.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 11, style: .continuous)
                    .fill(tint)
                    .frame(width: 3.5)
            }
        }
    }

    /// A reading cell: name, value and unit, Normal / Low / High, and the usual
    /// range it was judged against — so the word is never a verdict out of
    /// nowhere, and a doctor can apply their own range instead.
    struct ReadingCellPDF: View {
        @Environment(LocalizationManager.self) private var loc
        let label: String
        let value: String
        let unit: String
        let side: MeasureSide
        let status: MeasureStatus
        let usual: String

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Paper.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.riskInk(status.risk))
                        .monospacedDigit()
                    Text(unit).font(.system(size: 7.5)).foregroundStyle(Paper.secondary)
                }
                StatusPill(side: side, status: status)
                Text(loc.t("pdf.usual", usual))
                    .font(.system(size: 6.5))
                    .foregroundStyle(Paper.secondary)
                    .lineLimit(1)
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    static let readingColumns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 4)

    struct VitalsCard: View {
        @Environment(LocalizationManager.self) private var loc
        let entry: VitalsEntry
        let unit: TemperatureUnit

        private func range(_ range: ClosedRange<Double>, places: Int) -> String {
            "\(loc.decimal(range.lowerBound, places: places))–\(loc.decimal(range.upperBound, places: places))"
        }

        var body: some View {
            RecordCard(title: loc.t("vital.section"), symbol: "heart.text.square.fill",
                       tint: Paper.accent, date: entry.date, note: entry.note) {
                LazyVGrid(columns: readingColumns, alignment: .leading, spacing: 6) {
                    if let value = entry.temperature {
                        let usual = VitalKind.temperature.usualRange
                        ReadingCellPDF(label: loc.t("vital.temperature"),
                                       value: loc.decimal(unit.fromCelsius(value), places: 1),
                                       unit: unit.symbol,
                                       side: VitalKind.temperature.side(value),
                                       status: VitalKind.temperature.status(value),
                                       usual: range(unit.fromCelsius(usual.lowerBound)...unit.fromCelsius(usual.upperBound), places: 1))
                    }
                    if let systolic = entry.systolic, let diastolic = entry.diastolic {
                        let pair = MeasureSide.bloodPressure(systolic: systolic, diastolic: diastolic)
                        ReadingCellPDF(label: loc.t("vital.bloodPressure"),
                                       value: "\(loc.num(Int(systolic)))/\(loc.num(Int(diastolic)))",
                                       unit: loc.t("vital.unit.systolic"),
                                       side: pair.side, status: pair.status,
                                       usual: "\(range(VitalKind.systolic.usualRange, places: 0))/\(range(VitalKind.diastolic.usualRange, places: 0))")
                    } else {
                        single(.systolic)
                        single(.diastolic)
                    }
                    single(.pulse)
                    single(.oxygenSaturation)
                }
            }
        }

        @ViewBuilder
        private func single(_ kind: VitalKind) -> some View {
            if let value = entry.value(for: kind) {
                ReadingCellPDF(label: loc.t(kind.labelKey),
                               value: loc.decimal(value, places: kind.decimals),
                               unit: loc.t(kind.unitKey),
                               side: kind.side(value), status: kind.status(value),
                               usual: range(kind.usualRange, places: kind.decimals))
            }
        }
    }

    struct LabCard: View {
        @Environment(LocalizationManager.self) private var loc
        let report: LabReport

        private var testsDone: [DengueTest] {
            DengueTest.allCases.filter { report.result(for: $0) != .notDone }
        }

        var body: some View {
            RecordCard(title: loc.t("lab.report"), symbol: "testtube.2",
                       tint: Paper.lab, date: report.date, note: report.note) {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: readingColumns, alignment: .leading, spacing: 6) {
                        ForEach(LabMeasure.allCases) { measure in
                            if let value = report.value(for: measure) {
                                ReadingCellPDF(label: loc.t(measure.labelKey),
                                               value: loc.decimal(value, places: measure.decimals),
                                               unit: loc.t(measure.unitKey),
                                               side: measure.side(value), status: measure.status(value),
                                               usual: "\(loc.decimal(measure.typicalRange.lowerBound, places: measure.decimals))–\(loc.decimal(measure.typicalRange.upperBound, places: measure.decimals))")
                            }
                        }
                    }
                    // Tests that were not done are left out: "NS1 not done" is not
                    // a result, and a doctor reading this wants the ones that were.
                    if !testsDone.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(testsDone) { test in
                                let result = report.result(for: test)
                                let positive = result == .positive
                                HStack(spacing: 4) {
                                    Text(loc.t(test.labelKey)).font(.system(size: 8.5, weight: .medium))
                                    Text(loc.t(result.labelKey)).font(.system(size: 8.5, weight: .bold))
                                }
                                .foregroundStyle(positive ? Palette.riskInk(.severe) : Paper.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(positive ? Palette.riskTint(.severe).opacity(0.12) : .white, in: Capsule())
                                .overlay(Capsule().stroke(positive ? .clear : Paper.hairline, lineWidth: 0.75))
                            }
                        }
                    }
                }
            }
        }
    }

    /// A day's fluids as WHO asks for them to be reviewed: the total drunk, how
    /// many drinks, and how many times urine was passed against WHO's aim. No
    /// Normal / Low word: there is no volume target to judge it against, and the
    /// urine aim is printed for the doctor to read rather than graded here.
    struct FluidCardPDF: View {
        @Environment(LocalizationManager.self) private var loc
        let entries: [FluidEntry]

        var body: some View {
            let day = FluidLog.day(entries.first?.date ?? Date(), entries: entries)
            RecordCard(title: loc.t("fluid.log.title"), symbol: "cup.and.saucer.fill",
                       tint: Paper.accent, date: nil, note: "") {
                LazyVGrid(columns: readingColumns, alignment: .leading, spacing: 6) {
                    cell(loc.t("fluid.drunk"), loc.num(day.drunkMillilitres), loc.t("fluid.unit.ml"))
                    cell(loc.t("fluid.drinks"), loc.num(day.drinks), "")
                    cell(loc.t("fluid.urine"), loc.num(day.urinations), loc.t("fluid.unit.times"),
                         detail: loc.t("fluid.urine.aim",
                                       loc.num(FluidLog.urinationAim.lowerBound),
                                       loc.num(FluidLog.urinationAim.upperBound)))
                }
            }
        }

        private func cell(_ label: String, _ value: String, _ unit: String,
                          detail: String? = nil) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Paper.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Paper.ink)
                        .monospacedDigit()
                    Text(unit).font(.system(size: 7.5)).foregroundStyle(Paper.secondary)
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 6.5))
                        .foregroundStyle(Paper.secondary)
                        .lineLimit(2)
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
