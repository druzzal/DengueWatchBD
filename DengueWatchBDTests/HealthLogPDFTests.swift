import XCTest
import PDFKit
@testable import DengueWatchBD

/// The PDF generator itself. It is now invoked lazily, when the reader
/// actually shares, so nothing on screen proves it still works — this does.
@MainActor
final class HealthLogPDFTests: XCTestCase {

    private func days(_ count: Int) -> [HealthLogDay] {
        let calendar = Calendar.current
        let vitals: [VitalsEntry] = (0..<count).map { offset in
            VitalsEntry(date: calendar.date(byAdding: .day, value: -offset, to: Date())!,
                        temperature: 38.4, pulse: 96, systolic: 112,
                        diastolic: 74, oxygenSaturation: 97)
        }
        return HealthLog.days(checks: [], vitals: vitals, labs: [])
    }

    func testAShortLogProducesOnePage() throws {
        let url = try XCTUnwrap(HealthLogPDF.write(days: days(2),
                                                   loc: LocalizationManager(),
                                                   unit: .celsius))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        try? FileManager.default.removeItem(at: url)
    }

    /// The slicing maths is the fragile part: a long record has to carry on
    /// across page boundaries rather than stop at the first page.
    func testALongLogPaginates() throws {
        let url = try XCTUnwrap(HealthLogPDF.write(days: days(40),
                                                   loc: LocalizationManager(),
                                                   unit: .celsius))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(document.pageCount, 1, "40 days should not fit on one page")
        let size = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox).size
        XCTAssertEqual(size.width, HealthLogPDF.pageSize.width, accuracy: 1)
        XCTAssertEqual(size.height, HealthLogPDF.pageSize.height, accuracy: 1)
        try? FileManager.default.removeItem(at: url)
    }

    func testAnEmptyLogProducesNoFile() {
        XCTAssertNil(HealthLogPDF.write(days: [], loc: LocalizationManager(), unit: .celsius))
    }

    /// Every page must carry text. A slicing error shows up as blank pages
    /// rather than as a crash.
    func testNoPageComesOutBlank() throws {
        let url = try XCTUnwrap(HealthLogPDF.write(days: days(40),
                                                   loc: LocalizationManager(),
                                                   unit: .celsius))
        let document = try XCTUnwrap(PDFDocument(url: url))
        for index in 0..<document.pageCount {
            let text = document.page(at: index)?.string ?? ""
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "page \(index + 1) is blank")
        }
        try? FileManager.default.removeItem(at: url)
    }
}
