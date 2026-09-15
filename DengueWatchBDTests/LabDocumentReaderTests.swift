import XCTest
import PDFKit
import UIKit
@testable import DengueWatchBD

/// Reading a lab report out of a file the reader picked.
///
/// The PDF path is the one worth testing hardest, because it has two very
/// different halves: a report emailed by a diagnostic centre carries real text
/// and can be read exactly, while a scanned one is a picture and has to go
/// through Vision like a photograph. Getting the first case wrong would send
/// perfectly good text through OCR and invent misreadings in a document that
/// had none.
final class LabDocumentReaderTests: XCTestCase {

    /// A PDF with a real text layer, as a lab's own export would have.
    private func textPDF(_ lines: [String], pageSize: CGSize = CGSize(width: 595, height: 842)) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14)
            ]
            var y: CGFloat = 40
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: attributes)
                y += 24
            }
        }
    }

    func testReadsAPDFsOwnTextLayer() {
        let data = textPDF(["Platelet Count 96,000 /cumm", "Haemoglobin 13.2 g/dL"])
        let text = LabDocumentReader.text(fromPDF: data)

        XCTAssertTrue(text.contains("Platelet"), "got: \(text)")
        XCTAssertTrue(text.contains("96,000"))
    }

    /// End to end: the file the reader picked becomes the draft they check.
    func testAPDFBecomesADraftReport() {
        let data = textPDF(["Platelet Count 96,000 /cumm",
                            "Haematocrit 44 %",
                            "Dengue NS1 Antigen: Positive"])
        let draft = LabReportParser.draft(from: LabDocumentReader.text(from: data, kind: .pdf))

        XCTAssertEqual(draft.platelets, 96)
        XCTAssertEqual(draft.haematocrit, 44)
        XCTAssertEqual(draft.ns1, .positive)
    }

    func testEveryPageOfAPDFIsRead() {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { context in
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14)]
            context.beginPage()
            ("Platelet Count 96,000 /cumm" as NSString)
                .draw(at: CGPoint(x: 40, y: 40), withAttributes: attributes)
            context.beginPage()
            ("Dengue IgM: Positive" as NSString)
                .draw(at: CGPoint(x: 40, y: 40), withAttributes: attributes)
        }
        // A CBC and a serology result are often two sheets from one visit, so
        // stopping at the first page would silently drop half the report.
        let draft = LabReportParser.draft(from: LabDocumentReader.text(fromPDF: data))
        XCTAssertEqual(draft.platelets, 96)
        XCTAssertEqual(draft.igm, .positive)
    }

    /// A JPEG of a printed report, which is the other half of the feature and
    /// the half that can quietly return nothing. Renders text large and clean,
    /// so a failure here means Vision is not being reached at all rather than
    /// that the image was hard to read.
    func testReadsValuesOffAJPEG() throws {
        let size = CGSize(width: 1000, height: 400)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 56),
                .foregroundColor: UIColor.black
            ]
            ("Platelet Count 96000" as NSString)
                .draw(at: CGPoint(x: 40, y: 60), withAttributes: attributes)
            ("Haemoglobin 13.2" as NSString)
                .draw(at: CGPoint(x: 40, y: 200), withAttributes: attributes)
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.95))

        let text = LabDocumentReader.text(from: data, kind: .image)
        XCTAssertTrue(text.lowercased().contains("platelet"),
                      "Vision read nothing usable. got: \(text)")
    }

    /// A scanned PDF: a page with no text layer at all, only a picture of one.
    /// This is the fallback that has to render the page and read the pixels,
    /// and it is what a photocopied report from a small clinic looks like.
    func testReadsAScannedPDFThatHasNoTextLayer() throws {
        let size = CGSize(width: 1000, height: 400)
        let picture = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            ("Platelet Count 96000" as NSString).draw(
                at: CGPoint(x: 40, y: 120),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 64),
                                 .foregroundColor: UIColor.black])
        }
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
            .pdfData { context in
                context.beginPage()
                picture.draw(in: CGRect(origin: .zero, size: size))
            }

        let page = try XCTUnwrap(PDFDocument(data: pdf)?.page(at: 0))
        XCTAssertTrue((page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "this fixture is meant to have no text layer")

        let text = LabDocumentReader.text(fromPDF: pdf)
        XCTAssertTrue(text.lowercased().contains("platelet"),
                      "the scanned-PDF fallback read nothing. got: \(text)")
    }

    func testSomethingThatIsNotAPDFReadsAsNothing() {
        XCTAssertTrue(LabDocumentReader.text(fromPDF: Data("not a pdf".utf8)).isEmpty)
    }

    func testAnEmptyPDFReadsAsNothing() {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let blank = renderer.pdfData { $0.beginPage() }
        XCTAssertTrue(LabDocumentReader.text(fromPDF: blank)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Bytes that are not an image must come back empty rather than crash —
    /// the picker hands over whatever the reader chose.
    func testRubbishImageDataReadsAsNothing() {
        XCTAssertTrue(LabDocumentReader.text(from: Data([0x00, 0x01, 0x02]), kind: .image).isEmpty)
    }

    func testEmptyDataReadsAsNothing() {
        XCTAssertTrue(LabDocumentReader.text(from: Data(), kind: .pdf).isEmpty)
        XCTAssertTrue(LabDocumentReader.text(from: Data(), kind: .image).isEmpty)
    }
}
