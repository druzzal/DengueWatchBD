import Foundation
import PDFKit
import UIKit
import Vision

/// Reads the text off a lab report the reader picked from their files.
///
/// Everything happens on this device, like the camera path: a PDF of someone's
/// blood results never leaves the phone. What comes back is text, which
/// `LabReportParser` turns into a draft for the reader to check — nothing here
/// decides anything or saves anything.
///
/// Takes `Data` rather than a `UIImage` or a `PDFPage` so the whole thing can
/// run off the main actor and be tested without a camera or a file picker.
enum LabDocumentReader {

    /// What the reader picked: a picture of a report, or a PDF of one.
    enum Kind: Equatable {
        case image
        case pdf
    }

    /// Which of the two the bytes are.
    ///
    /// Read from the content, not from the file's name. An extension can be
    /// absent, upper-cased or simply wrong, and a PDF saved as "report" would
    /// otherwise go to the image decoder, decode to nothing, and be reported
    /// to the reader as unreadable when it was fine. Everything that is not a
    /// PDF is handed to the image decoder, which is what actually decides
    /// whether a JPEG, PNG or HEIC can be read — so no format needs naming
    /// here, and a new one needs no change.
    static func kind(of data: Data) -> Kind {
        data.starts(with: Array("%PDF-".utf8)) ? .pdf : .image
    }

    /// Text from whatever the reader picked, deciding for itself what it is.
    static func text(from data: Data) -> String {
        text(from: data, kind: kind(of: data))
    }

    static func text(from data: Data, kind: Kind) -> String {
        switch kind {
        case .image: return recognisedText(inImageData: data)
        case .pdf: return text(fromPDF: data)
        }
    }

    // MARK: - PDF

    /// A PDF's own text layer first, and only then the picture of it.
    ///
    /// A report emailed by a diagnostic centre is usually real text, and
    /// reading it directly is exact — no misread digits at all, which is the
    /// one failure this feature has to be most careful about. A PDF that is
    /// only a scan carries no text layer, and those pages are rendered and
    /// read the same way a photograph would be.
    static func text(fromPDF data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }

        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let embedded = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !embedded.isEmpty {
                pages.append(embedded)
            } else if let image = render(page) {
                pages.append(recognisedText(in: image))
            }
        }
        return pages.joined(separator: "\n")
    }

    /// A page drawn large enough to read.
    ///
    /// Vision works off pixels, and a page rendered at its natural size is
    /// roughly 72 dpi — small enough that a platelet count starts to blur into
    /// its neighbours. Scaled up to about 2,000 points on the long edge, and
    /// capped so a poster-sized page cannot exhaust memory.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(4, max(2, 2_000 / max(bounds.width, bounds.height)))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage
    }

    // MARK: - Images

    private static func recognisedText(inImageData data: Data) -> String {
        guard let image = UIImage(data: data)?.cgImage else { return "" }
        return recognisedText(in: image)
    }

    /// The same Vision settings the camera path uses, in one place so the two
    /// cannot drift apart: accuracy over speed, and no language correction,
    /// which would "correct" the numbers.
    static func recognisedText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
