import Charts
import SwiftUI
import UIKit

// The page around the report: paper inks, the running header and footer,
// the report header, and the small marks every section uses.

extension HealthLogPDF {

    /// Ink and surfaces for paper. Light-mode steps of the app's own palette,
    /// fixed here so the document never depends on the phone's appearance.
    enum Paper {
        static let ink = Color(hex: "#1C1C1E")
        static let secondary = Color(hex: "#6B6B70")
        static let card = Color(hex: "#F6F7F9")
        static let hairline = Color(hex: "#E3E4E8")
        static let accent = Color(hex: "#007a9c")
        /// The accent at about a tenth, flattened onto white: a translucent
        /// colour inside a gradient prints as a dark band in PDF.
        static let accentSoft = Color(hex: "#E6F2F5")
        static let headerStart = Color(hex: "#DCEDF2")
        /// The accent at about forty per cent, flattened onto white, for a bar
        /// that is still being filled in.
        static let accentMuted = Color(hex: "#99CAD8")
        static let lab = Color(hex: "#2a78d6")
    }

    struct PageChrome: View {
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
    struct BrandMark: View {
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

    struct ReportHeader: View {
        @Environment(LocalizationManager.self) private var loc
        let first: Date
        let last: Date
        let readings: Int
        let labs: Int
        let fluidDays: Int
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
                        if fluidDays > 0 {
                            Chip(text: loc.t("pdf.fluidDays", loc.num(fluidDays)),
                                 symbol: "cup.and.saucer.fill")
                        }
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

    struct Chip: View {
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
    /// app marks a reading — green in the usual range, amber to red outside it.
    /// Always with its word and a mark, so the page still reads when printed in
    /// black and white.
    struct StatusPill: View {
        @Environment(LocalizationManager.self) private var loc
        let side: MeasureSide
        let status: MeasureStatus

        var body: some View {
            HStack(spacing: 3) {
                Image(systemName: status.symbol).font(.system(size: 6.5, weight: .bold))
                Text(loc.t(side.labelKey)).font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Palette.riskInk(status.risk))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Palette.riskTint(status.risk).opacity(0.14),
                        in: Capsule())
            .environment(\.colorScheme, .light)
        }
    }

    struct SectionTitle: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Paper.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - At a glance

    struct ReportFooter: View {
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
}
