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
        return HealthLog.days(vitals: vitals, labs: [])
    }

    /// A single day — header, summary and one record — is one sheet, with no
    /// blank page trailing after it. Two days no longer fit on one since the
    /// report carries a summary, trend charts and every usual range.
    func testAShortLogProducesOnePage() throws {
        let url = try XCTUnwrap(HealthLogPDF.write(days: days(1),
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

    /// One day exported on its own keeps the number it has in the whole log,
    /// and is named for that day rather than for the day it was shared.
    func testOneDayExportsAsItsOwnReport() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.set("en", forKey: "appLanguage")
        defer { defaults.removePersistentDomain(forName: #function) }

        let all = days(5)
        let third = all[2]
        let url = try XCTUnwrap(HealthLogPDF.write(days: [third],
                                                   loc: LocalizationManager(defaults: defaults),
                                                   unit: .celsius,
                                                   names: [third.date: "Fever broke"],
                                                   numbers: HealthLog.numbers(for: all)))
        defer { try? FileManager.default.removeItem(at: url) }

        let stamp = third.date.formatted(.iso8601.year().month().day()
            .dateSeparator(.dash).locale(Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(url.lastPathComponent, "DengueWatch-health-log-day-3-\(stamp).pdf")

        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        let text = try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains("Day 3"), "the day keeps its place in the illness: \(text)")
        XCTAssertFalse(text.contains("Day 1"), text)
        XCTAssertTrue(text.contains("Fever broke"), text)
    }
}
