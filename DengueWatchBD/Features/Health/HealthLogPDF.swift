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

/// A view measured once at the content width, and drawable anywhere on a page.
@MainActor
private struct Block {
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
private struct HealthLogReport {
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

    func blocks(loc: LocalizationManager, generatedAt: Date) -> [Piece] {
        var pieces: [Piece] = []
        let dates = days.map(\.date).sorted()
        pieces.append(Piece(view: AnyView(ReportHeader(
            first: dates.first ?? generatedAt, last: dates.last ?? generatedAt,
            readings: vitals.count, labs: labs.count, generatedAt: generatedAt))))

        let glance = GlanceTiles(vitals: vitals, labs: labs, unit: unit)
        if glance.hasAny {
            pieces.append(Piece(view: AnyView(glance)))
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

        for day in days {
            pieces.append(Piece(view: AnyView(DayHeading(
                date: day.date, number: numbers[day.date], name: names[day.date])),
                keepWithNext: true))
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

/// Ink and surfaces for paper. Light-mode steps of the app's own palette,
/// fixed here so the document never depends on the phone's appearance.
private enum Paper {
    static let ink = Color(hex: "#1C1C1E")
    static let secondary = Color(hex: "#6B6B70")
    static let card = Color(hex: "#F6F7F9")
    static let hairline = Color(hex: "#E3E4E8")
    static let accent = Color(hex: "#007a9c")
    /// The accent at about a tenth, flattened onto white: a translucent
    /// colour inside a gradient prints as a dark band in PDF.
    static let accentSoft = Color(hex: "#E6F2F5")
    static let headerStart = Color(hex: "#DCEDF2")
    static let lab = Color(hex: "#2a78d6")
}

private struct PageChrome: View {
    @Environment(LocalizationManager.self) private var loc
    let page: Int
    let of: Int
    let generatedAt: Date
    let showsTitle: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showsTitle {
                    BrandMark(size: 14)
                    Text("\(loc.t("dash.title")) · \(loc.t("log.pdf.title"))")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Paper.secondary)
                }
                Spacer()
            }
            .frame(height: 16)
            .padding(.top, HealthLogPDF.margin - 4)
            Spacer()
            HStack {
                Text(loc.t("log.pdf.generated", loc.dayAndTime(generatedAt)))
                Spacer()
                Text(loc.t("pdf.page", loc.num(page), loc.num(of)))
                    .monospacedDigit()
            }
            .font(.system(size: 8))
            .foregroundStyle(Paper.secondary)
            .padding(.bottom, HealthLogPDF.margin - 8)
        }
        .padding(.horizontal, HealthLogPDF.margin)
    }
}

/// The app's mark, drawn rather than loaded: a droplet in the theme colour.
private struct BrandMark: View {
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Paper.accent)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "drop.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

private struct ReportHeader: View {
    @Environment(LocalizationManager.self) private var loc
    let first: Date
    let last: Date
    let readings: Int
    let labs: Int
    let generatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                BrandMark(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(loc.t("dash.title"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Paper.accent)
                    Text(loc.t("pdf.subtitle"))
                        .font(.system(size: 9))
                        .foregroundStyle(Paper.secondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.t("log.pdf.title"))
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Paper.ink)
                HStack(spacing: 8) {
                    Chip(text: first == last
                         ? loc.fullDate(first)
                         : loc.t("pdf.period", loc.fullDate(first), loc.fullDate(last)),
                         symbol: "calendar")
                    Chip(text: loc.t("pdf.counts", loc.num(readings), loc.num(labs)),
                         symbol: "list.bullet.clipboard")
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Paper.headerStart, Paper.card],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct Chip: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8, weight: .semibold))
            Text(text).font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(Paper.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(Paper.hairline, lineWidth: 0.75))
    }
}

/// Normal / Low / High, as a pill: risk ink on its own soft wash, the way the
/// app marks a reading. A normal reading stays neutral — there is no success
/// colour, so only what needs attention is coloured.
private struct StatusPill: View {
    @Environment(LocalizationManager.self) private var loc
    let side: MeasureSide
    let status: MeasureStatus

    var body: some View {
        HStack(spacing: 3) {
            if status != .normal {
                Image(systemName: status.symbol).font(.system(size: 6.5, weight: .bold))
            }
            Text(loc.t(side.labelKey)).font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(status == .normal ? Paper.secondary : Palette.riskInk(status.risk))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(status == .normal ? Paper.hairline.opacity(0.6) : Palette.riskTint(status.risk).opacity(0.14),
                    in: Capsule())
        .environment(\.colorScheme, .light)
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Paper.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - At a glance

private struct GlanceTiles: View {
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
                                .foregroundStyle(tile.status == .normal ? Paper.ink : Palette.riskInk(tile.status.risk))
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

// MARK: - Trends

private struct TrendChart: View {
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
                        .foregroundStyle(point.status == .normal ? Paper.accent : Palette.riskTint(point.status.risk))
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

private struct DayHeading: View {
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
private struct RecordCard<Content: View>: View {
    @Environment(LocalizationManager.self) private var loc
    let title: String
    let symbol: String
    let tint: Color
    let date: Date
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
                Text(loc.time(date))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Paper.secondary)
                    .monospacedDigit()
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
private struct ReadingCellPDF: View {
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
                    .foregroundStyle(status == .normal ? Paper.ink : Palette.riskInk(status.risk))
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

private let readingColumns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 4)

private struct VitalsCard: View {
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

private struct LabCard: View {
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

private struct ReportFooter: View {
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        // The one thing this document must not be mistaken for.
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Paper.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("pdf.disclaimer"))
                    .font(.system(size: 8.5))
                    .foregroundStyle(Paper.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(loc.t("log.privacyFooter"))
                    .font(.system(size: 8))
                    .foregroundStyle(Paper.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Paper.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, 6)
    }
}
