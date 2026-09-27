import XCTest
@testable import DengueWatchBD

/// Recording a reading or a report for a time other than now.
///
/// Readings are often written down after the fact — a fever taken at three in
/// the morning and entered at nine — so the forms let the reader say when. That
/// turns insertion order and time order into two different things, and every
/// screen that says "latest" means the newest reading, never the one most
/// recently typed.
@MainActor
final class BackdatedEntryTests: XCTestCase {

    private func stores() -> (VitalsStore, LabStore) {
        let suffix = UUID().uuidString
        return (VitalsStore(filename: "vitals-\(suffix).json"),
                LabStore(filename: "labs-\(suffix).json"))
    }

    private func at(_ day: Int, _ hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = day; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    // MARK: - Vital signs

    func testAnOlderReadingAddedLaterSortsIntoPlace() {
        let (vitals, _) = stores()
        vitals.add(VitalsEntry(date: at(14, 9), temperature: 38.0))
        vitals.add(VitalsEntry(date: at(12, 9), temperature: 39.0))   // back-dated

        XCTAssertEqual(vitals.entries.map(\.date), [at(14, 9), at(12, 9)],
                       "the log reads newest first by time, not by typing order")
    }

    /// The card's "Last taken" and its tiles read `latest`. Typing an old
    /// reading must not make it the one on display.
    func testLatestIsTheNewestReadingNotTheNewestTyped() {
        let (vitals, _) = stores()
        vitals.add(VitalsEntry(date: at(14, 9), temperature: 38.0))
        vitals.add(VitalsEntry(date: at(12, 9), temperature: 39.0))

        XCTAssertEqual(vitals.latest?.temperature, 38.0)
        XCTAssertEqual(vitals.latest?.date, at(14, 9))
    }

    /// Two readings in one day is the ordinary case during a fever.
    func testTwoReadingsOnOneDayKeepTheirOrder() {
        let (vitals, _) = stores()
        vitals.add(VitalsEntry(date: at(14, 21), temperature: 38.9))
        vitals.add(VitalsEntry(date: at(14, 9), temperature: 39.4))

        XCTAssertEqual(vitals.entries.map(\.temperature), [38.9, 39.4])
        XCTAssertEqual(vitals.latest?.date, at(14, 21), "the evening one is the latest")
    }

    /// The chart runs oldest first, whatever order things were entered in.
    func testTheSeriesRunsForwardsInTimeAfterBackdating() {
        let (vitals, _) = stores()
        vitals.add(VitalsEntry(date: at(14, 9), temperature: 38.0))
        vitals.add(VitalsEntry(date: at(12, 9), temperature: 39.0))
        vitals.add(VitalsEntry(date: at(13, 9), temperature: 40.0))

        let series = vitals.series(for: .temperature)
        XCTAssertEqual(series.map(\.date), [at(12, 9), at(13, 9), at(14, 9)])
        XCTAssertEqual(series.map(\.value), [39.0, 40.0, 38.0])
    }

    // MARK: - Lab reports

    func testAnOlderReportAddedLaterSortsIntoPlace() {
        let (_, labs) = stores()
        labs.add(LabReport(date: at(14, 12), platelets: 96))
        labs.add(LabReport(date: at(12, 12), platelets: 150))

        XCTAssertEqual(labs.reports.map(\.date), [at(14, 12), at(12, 12)])
        XCTAssertEqual(labs.latest?.platelets, 96)
    }

    /// A morning count and an evening one on the same day is exactly what
    /// watching a platelet count fall looks like, so the time has to separate
    /// them — a date alone could not say which came first.
    func testTwoReportsOnOneDayAreOrderedByTime() {
        let (_, labs) = stores()
        labs.add(LabReport(date: at(14, 9), platelets: 120))
        labs.add(LabReport(date: at(14, 20), platelets: 96))

        XCTAssertEqual(labs.reports.map(\.platelets), [96, 120])
        XCTAssertEqual(labs.latest?.date, at(14, 20))
    }

    // MARK: - Symptom checks

    /// "The latest check" decides the care plan, the day of illness the fever
    /// timeline counts from, and what My Health and Home report. Read from a
    /// file whose order did not match its dates, every one of them described a
    /// check the reader had already replaced.
    func testTheLatestCheckIsTheNewestOneWhateverOrderTheFileIsIn() throws {
        let filename = "case-\(UUID().uuidString).json"
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent(filename)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        // Oldest written first, which is the wrong way round for this store.
        let old = CaseLogEntry(date: at(12, 8), symptomIDs: ["fever"], outcomeRawValue: 1)
        let recent = CaseLogEntry(date: at(14, 8), symptomIDs: ["fever"], outcomeRawValue: 3)
        try JSONEncoder().encode([old, recent]).write(to: url)

        let store = CaseLogStore(filename: filename)
        XCTAssertEqual(store.entries.first?.date, at(14, 8),
                       "the newest check, not the first line of the file")
        XCTAssertEqual(store.entries.map(\.date), [at(14, 8), at(12, 8)])
    }

    // MARK: - The merged log

    /// A back-dated reading belongs to the day it was taken, not the day it
    /// was typed — otherwise the log would show a fever on the wrong date.
    func testABackdatedReadingJoinsTheDayItWasTaken() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dhaka")!

        let days = HealthLog.days(
            vitals: [VitalsEntry(date: at(14, 9), temperature: 38.0),
                     VitalsEntry(date: at(12, 9), temperature: 39.0)],
            labs: [LabReport(date: at(12, 14), platelets: 96)],
            calendar: calendar)

        XCTAssertEqual(days.count, 2)
        let older = days.last
        XCTAssertEqual(older?.vitals.count, 1)
        XCTAssertEqual(older?.labs.count, 1, "both belong to the 12th")
    }
}
