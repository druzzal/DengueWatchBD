import SwiftUI
import UIKit

/// Renders the health log to a PDF the reader can hand to a doctor.
///
/// The file is written to the app's own temporary directory and goes no
/// further than the share sheet the reader opens themselves. Nothing is
/// uploaded: this is the same local-only promise the stores make, and the
/// share sheet is the reader deciding, once, to break it deliberately.
@MainActor
enum HealthLogPDF {

    /// A4 at 72dpi, the size a Bangladeshi clinic will print on.
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 36

    static func write(days: [HealthLogDay],
                      loc: LocalizationManager,
                      unit: TemperatureUnit,
                      generatedAt: Date = Date()) -> URL? {
        guard !days.isEmpty else { return nil }

        let document = HealthLogDocument(days: days, loc: loc, unit: unit,
                                         generatedAt: generatedAt)
            .frame(width: pageSize.width - margin * 2)
            .padding(margin)
            .background(.white)
            .environment(loc)

        let renderer = ImageRenderer(content: document)
        renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: nil)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename(loc: loc), conformingTo: .pdf)

        var wrote = false
        renderer.render { contentSize, draw in
            var box = CGRect(origin: .zero, size: pageSize)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }

            // The content is one tall view; each page is a window onto it.
            // `draw` lays the content out top-down inside a box of
            // `contentSize`, so shifting the origin down by a page height per
            // page walks that window from top to bottom.
            let pages = max(1, Int(ceil(contentSize.height / pageSize.height)))
            for page in 0..<pages {
                context.beginPDFPage(nil)
                context.saveGState()
                // PDF space is bottom-up: the content box's bottom sits below
                // the page's, and each page lifts it by one page height.
                context.translateBy(x: 0,
                                    y: pageSize.height - contentSize.height
                                        + CGFloat(page) * pageSize.height)
                draw(context)
                context.restoreGState()
                context.endPDFPage()
            }
            context.closePDF()
            wrote = true
        }

        return wrote ? url : nil
    }

    /// Dated, so a reader who exports twice does not overwrite the first file
    /// in their share target.
    private static func filename(loc: LocalizationManager) -> String {
        let stamp = Date().formatted(.iso8601.year().month().day()
            .dateSeparator(.dash).locale(Locale(identifier: "en_US_POSIX")))
        return "DengueWatch-health-log-\(stamp)"
    }
}

/// The printed document. Deliberately plain: this is read on paper, under
/// clinic lighting, possibly photocopied.
private struct HealthLogDocument: View {
    let days: [HealthLogDay]
    let loc: LocalizationManager
    let unit: TemperatureUnit
    let generatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ForEach(days) { day in
                dayBlock(day)
            }
            footer
        }
        .foregroundStyle(.black)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loc.t("log.pdf.title"))
                .font(.system(size: 22, weight: .bold))
            Text(loc.t("log.pdf.generated", loc.dayAndTime(generatedAt)))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Rectangle().fill(.black.opacity(0.25)).frame(height: 1).padding(.top, 6)
        }
    }

    private func dayBlock(_ day: HealthLogDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.fullDate(day.date))
                .font(.system(size: 13, weight: .semibold))

            ForEach(day.itemsNewestFirst) { item in
                switch item {
                case .check(let entry): checkRow(entry)
                case .vitals(let entry): vitalsRow(entry)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func checkRow(_ entry: CaseLogEntry) -> some View {
        let names = TriageEngine.symptoms
            .filter { entry.symptomIDs.contains($0.id) }
            .map { loc.t($0.titleKey) }
        return VStack(alignment: .leading, spacing: 3) {
            row(time: entry.date,
                label: loc.t("log.pdf.symptoms"),
                detail: names.isEmpty ? loc.t("log.pdf.noSymptoms") : loc.style.list(names))
            Text(loc.t(entry.outcome.headlineKey))
                .font(.system(size: 10, weight: .medium))
                .padding(.leading, 74)
            if !entry.note.isEmpty {
                Text(entry.note).font(.system(size: 10)).italic().padding(.leading, 74)
            }
        }
    }

    private func vitalsRow(_ entry: VitalsEntry) -> some View {
        // Blood pressure is one reading written as a pair, not two readings.
        var parts: [String] = []
        if let systolic = entry.systolic, let diastolic = entry.diastolic {
            parts.append("\(loc.t("vital.bloodPressure")) \(loc.num(Int(systolic)))/\(loc.num(Int(diastolic))) \(loc.t("vital.unit.systolic"))")
        }
        for kind in VitalKind.allCases where !(kind == .systolic || kind == .diastolic) {
            guard let value = entry.value(for: kind) else { continue }
            let shown = kind == .temperature
                ? unit.display(celsius: value)
                : "\(loc.decimal(value, places: kind.decimals)) \(loc.t(kind.unitKey))"
            parts.append("\(loc.t(kind.labelKey)) \(shown)")
        }
        if entry.systolic != nil && entry.diastolic == nil, let systolic = entry.systolic {
            parts.append("\(loc.t("vital.systolic")) \(loc.num(Int(systolic)))")
        }
        if entry.diastolic != nil && entry.systolic == nil, let diastolic = entry.diastolic {
            parts.append("\(loc.t("vital.diastolic")) \(loc.num(Int(diastolic)))")
        }

        return VStack(alignment: .leading, spacing: 3) {
            row(time: entry.date,
                label: loc.t("log.pdf.vitals"),
                detail: parts.joined(separator: "   ·   "))
            if !entry.note.isEmpty {
                Text(entry.note).font(.system(size: 10)).italic().padding(.leading, 74)
            }
        }
    }

    private func row(time: Date, label: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(loc.time(time))
                .font(.system(size: 10, weight: .medium))
                .frame(width: 52, alignment: .leading)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 14, alignment: .leading)
            Text(detail)
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(.black.opacity(0.25)).frame(height: 1).padding(.bottom, 4)
            // The one thing this document must not be mistaken for.
            Text(loc.t("log.pdf.disclaimer"))
                .font(.system(size: 9))
            Text(loc.t("log.privacyFooter"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}
