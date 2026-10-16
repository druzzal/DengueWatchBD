import Charts
import SwiftUI
import UIKit

/// Renders the health log to a PDF the reader can hand to a doctor.
///
/// The file is written to the app's own temporary directory and goes no
/// further than the share sheet the reader opens themselves. Nothing is
/// uploaded: this is the same local-only promise the stores make, and the
/// share sheet is the reader deciding, once, to break it deliberately.
///
/// Laid out as blocks — header, summary, charts, one card per record — and
/// paginated by block. It used to be one tall view sliced every 842 points,
/// which was invisible while the page was plain text and would cut a card,
/// a chart or a reading in half the moment the page had any design at all.
@MainActor
enum HealthLogPDF {

    /// A4 at 72dpi, the size a Bangladeshi clinic will print on.
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 36
    static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    /// Room kept clear at the top and bottom of every page for the running
    /// header and the page number.
    private static let chromeTop: CGFloat = 30
    private static let chromeBottom: CGFloat = 34
    private static let gap: CGFloat = 10

    /// - Parameters:
    ///   - numbers: each day's "Day N", counted across the whole log. Passed in
    ///     when exporting part of it, so the third day of an illness is still
    ///     "Day 3" on its own page rather than "Day 1".
    static func write(days: [HealthLogDay],
                      loc: LocalizationManager,
                      unit: TemperatureUnit,
                      names: [Date: String] = [:],
                      numbers: [Date: Int]? = nil,
                      generatedAt: Date = Date()) -> URL? {
        guard !days.isEmpty else { return nil }

        let report = HealthLogReport(days: days, unit: unit, names: names,
                                     numbers: numbers ?? HealthLog.numbers(for: days))
        let blocks = report.blocks(loc: loc, generatedAt: generatedAt)
            .map { Block(view: $0.view, keepWithNext: $0.keepWithNext, loc: loc) }
        let pages = paginate(blocks)

        // One day is named for that day; the whole log for the day it left.
        let name = days.count == 1
            ? filename(on: days[0].date, day: report.numbers[days[0].date])
            : filename(on: generatedAt)
        guard let url = exportURL(named: name) else { return nil }
        var box = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: loc.t("log.pdf.title"),
            kCGPDFContextCreator: loc.t("dash.title"),
        ]
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            return nil
        }

        for (index, page) in pages.enumerated() {
            context.beginPDFPage(nil)
            for placed in page {
                placed.block.draw(in: context, x: margin, top: placed.top)
            }
            let chrome = Block(view: AnyView(PageChrome(page: index + 1, of: pages.count,
                                                         generatedAt: generatedAt,
                                                         showsTitle: index > 0)),
                               keepWithNext: false, loc: loc,
                               height: pageSize.height)
            chrome.draw(in: context, x: 0, top: 0, width: pageSize.width)
            context.setFillColor(UIColor(hex: "#E3E4E8").cgColor)
            context.fill(CGRect(x: margin, y: margin + 10, width: contentWidth, height: 0.75))
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    // MARK: - Pagination

    private struct Placed {
        let block: Block
        let top: CGFloat
    }

    /// Greedy, block by block. A block that would cross the bottom margin
    /// starts the next page; a day's heading is never left alone at the foot
    /// of a page without its first record.
    private static func paginate(_ blocks: [Block]) -> [[Placed]] {
        // Page 1 opens with the report's own header, not the running one.
        let firstTop = margin
        let top = margin + chromeTop
        let bottom = pageSize.height - margin - chromeBottom
        var pages: [[Placed]] = [[]]
        var cursor = firstTop

        for (index, block) in blocks.enumerated() {
            var needed = block.size.height
            if block.keepWithNext, index + 1 < blocks.count {
                needed += gap + blocks[index + 1].size.height
            }
            if cursor + needed > bottom, cursor > (pages.count == 1 ? firstTop : top) {
                pages.append([])
                cursor = top
            }
            pages[pages.count - 1].append(Placed(block: block, top: cursor))
            cursor += block.size.height + gap
        }
        return pages
    }

    // MARK: - Files

    /// A fresh folder per export, cleared each time: a reader who exports a
    /// dozen times should not be carrying a dozen PDFs of their health in
    /// the app's temporary directory.
    private static func exportURL(named name: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthLogExport", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return folder.appendingPathComponent(name, conformingTo: .pdf)
    }

    /// Dated, so a reader who shares twice does not overwrite the first file
    /// in their share target.
    static func filename(on date: Date = Date(), day: Int? = nil) -> String {
        let stamp = date.formatted(.iso8601.year().month().day()
            .dateSeparator(.dash).locale(Locale(identifier: "en_US_POSIX")))
        guard let day else { return "DengueWatch-health-log-\(stamp)" }
        return "DengueWatch-health-log-day-\(day)-\(stamp)"
    }

    /// Lay the PDF out, then hand the finished file to the share sheet.
    static func share(days: [HealthLogDay], loc: LocalizationManager, unit: TemperatureUnit,
                      names: [Date: String], numbers: [Date: Int]) async {
        // Layout runs on the main actor; give the caller's spinner a frame first.
        try? await Task.sleep(for: .milliseconds(60))
        if let url = write(days: days, loc: loc, unit: unit, names: names, numbers: numbers) {
            ShareSheet.present(url)
        }
    }
}

// MARK: - One block of the page

extension HealthLogPDF {

    /// A view measured once at the content width, and drawable anywhere on a page.
    @MainActor
    struct Block {
        let renderer: ImageRenderer<AnyView>
        let size: CGSize
        let keepWithNext: Bool

        init(view: AnyView, keepWithNext: Bool, loc: LocalizationManager,
             width: CGFloat = HealthLogPDF.contentWidth, height: CGFloat? = nil) {
            let content = AnyView(view
                .frame(width: width, height: height, alignment: .top)
                .environment(loc)
                // Printed on white whatever the phone is set to.
                .environment(\.colorScheme, .light))
            renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: width, height: height)
            var measured = CGSize.zero
            renderer.render { size, _ in measured = size }
            size = measured
            self.keepWithNext = keepWithNext
        }

        /// `top` is measured down from the top of the page; PDF space runs up
        /// from the bottom, so the block's own bottom edge is what gets placed.
        func draw(in context: CGContext, x: CGFloat, top: CGFloat,
                  width: CGFloat = HealthLogPDF.contentWidth) {
            renderer.render { size, draw in
                context.saveGState()
                context.translateBy(x: x, y: HealthLogPDF.pageSize.height - top - size.height)
                draw(context)
                context.restoreGState()
            }
        }
    }

    // MARK: - What goes on the pages

    /// The log, reduced to what the document shows.
    @MainActor
    struct HealthLogReport {
        let days: [HealthLogDay]
        let unit: TemperatureUnit
        let names: [Date: String]
        let numbers: [Date: Int]

        struct Piece {
            let view: AnyView
            var keepWithNext = false
        }

        private var vitals: [VitalsEntry] { days.flatMap(\.vitals).sorted { $0.date < $1.date } }
        private var labs: [LabReport] { days.flatMap(\.labs).sorted { $0.date < $1.date } }
        private var fluids: [FluidEntry] { days.flatMap(\.fluids).sorted { $0.date < $1.date } }

        func blocks(loc: LocalizationManager, generatedAt: Date) -> [Piece] {
            var pieces: [Piece] = []
            let dates = days.map(\.date).sorted()
            pieces.append(Piece(view: AnyView(ReportHeader(
                first: dates.first ?? generatedAt, last: dates.last ?? generatedAt,
                readings: vitals.count, labs: labs.count,
                fluidDays: FluidLog.daily(fluids).count, generatedAt: generatedAt))))

            let glance = GlanceTiles(vitals: vitals, labs: labs, unit: unit)
            if glance.hasAny {
                pieces.append(Piece(view: AnyView(glance)))
            }
            // Its own block rather than more glance tiles: those grade each figure
            // Normal / Low / High, and fluids have no range to grade against.
            if !fluids.isEmpty {
                pieces.append(Piece(view: AnyView(FluidGlancePDF(
                    summary: FluidLog.summary(fluids, now: generatedAt)))))
            }

            let temperatures = vitals.compactMap { entry in
                entry.temperature.map { (date: entry.date, value: $0) }
            }
            let platelets = labs.compactMap { report in
                report.platelets.map { (date: report.date, value: $0) }
            }
            var charts: [TrendChart] = []
            if temperatures.count >= 2 {
                charts.append(TrendChart(
                    title: loc.t("vital.temperature"),
                    unitLabel: unit.symbol,
                    points: temperatures.map { ($0.date, unit.fromCelsius($0.value), VitalKind.temperature.status($0.value)) },
                    usual: unit.fromCelsius(VitalKind.temperature.usualRange.lowerBound)
                        ... unit.fromCelsius(VitalKind.temperature.usualRange.upperBound),
                    decimals: 1))
            }
            if platelets.count >= 2 {
                charts.append(TrendChart(
                    title: loc.t("lab.platelets"),
                    unitLabel: loc.t("lab.unit.platelets"),
                    points: platelets.map { ($0.date, $0.value, LabMeasure.platelets.status($0.value)) },
                    usual: LabMeasure.platelets.typicalRange,
                    decimals: 0))
            }
            // Side by side when there are two: stacked, a pair of charts took a
            // third of the first page and pushed the records it summarises off it.
            if !charts.isEmpty {
                pieces.append(Piece(view: AnyView(HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(charts.enumerated()), id: \.offset) { _, chart in chart }
                })))
            }

            // Intake and urine in two charts, never one: they are different units,
            // and this app draws no dual-axis chart. Two days are the least that
            // show a direction, as with the trend charts above.
            let daily = FluidLog.daily(fluids)
            if daily.count >= 2 {
                let today = Calendar.current.startOfDay(for: generatedAt)
                pieces.append(Piece(view: AnyView(HStack(alignment: .top, spacing: 8) {
                    FluidBarChart(title: loc.t("pdf.fluids.chart.intake"),
                                  unitLabel: loc.t("fluid.unit.ml"),
                                  bars: daily.map { ($0.date, Double($0.day.drunkMillilitres), $0.date == today) },
                                  aim: nil)
                    FluidBarChart(title: loc.t("pdf.fluids.chart.urine"),
                                  unitLabel: loc.t("fluid.unit.times"),
                                  bars: daily.map { ($0.date, Double($0.day.urinations), $0.date == today) },
                                  aim: Double(FluidLog.urinationAim.lowerBound))
                })))
            }

            for day in days {
                pieces.append(Piece(view: AnyView(DayHeading(
                    date: day.date, number: numbers[day.date], name: names[day.date])),
                    keepWithNext: true))
                if !day.fluids.isEmpty {
                    pieces.append(Piece(view: AnyView(FluidCardPDF(entries: day.fluids))))
                }
                for item in day.itemsNewestFirst {
                    switch item {
                    case .vitals(let entry):
                        pieces.append(Piece(view: AnyView(VitalsCard(entry: entry, unit: unit))))
                    case .lab(let report):
                        pieces.append(Piece(view: AnyView(LabCard(report: report))))
                    }
                }
            }

            pieces.append(Piece(view: AnyView(ReportFooter())))
            return pieces
        }
    }

    // MARK: - Page furniture
}
