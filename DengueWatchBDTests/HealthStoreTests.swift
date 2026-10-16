import XCTest
@testable import DengueWatchBD

/// The stores that hold the reader's own record, read back from disk.
///
/// The same promises Android's `HealthStoresTest` checks: what is written
/// comes back, an unreadable file is an empty record rather than a crash, an
/// empty entry is not kept, and the lab card can still find the last count
/// when the newest report carried only a test result.
@MainActor
final class HealthStoreTests: XCTestCase {

    private func url(_ filename: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    func testReadingsSurviveBeingReadBack() throws {
        let name = temporaryStoreFilename("vitals")
        VitalsStore(filename: name).add(VitalsEntry(temperature: 38.6, systolic: 100, diastolic: 70,
                                                    note: "after lunch"))
        let reloaded = try XCTUnwrap(VitalsStore(filename: name).entries.first)
        XCTAssertEqual(reloaded.temperature, 38.6)
        XCTAssertEqual(reloaded.systolic, 100)
        XCTAssertEqual(reloaded.diastolic, 70)
        XCTAssertEqual(reloaded.note, "after lunch")
    }

    func testAnEntryWithNoReadingsIsNotSaved() {
        let store = VitalsStore(filename: temporaryStoreFilename("vitals"))
        store.add(VitalsEntry(note: "felt fine"))
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testAnUnreadableFileLoadsAsEmpty() throws {
        let name = temporaryStoreFilename("vitals")
        try Data("[{\"id\":".utf8).write(to: url(name))
        XCTAssertTrue(VitalsStore(filename: name).entries.isEmpty)
    }

    func testTheLastCountIsFoundWhenTheNewestReportHasOnlyATest() throws {
        let store = LabStore(filename: temporaryStoreFilename("labs"))
        store.add(LabReport(date: Date().addingTimeInterval(-86_400), platelets: 96, haematocrit: 44))
        store.add(LabReport(date: Date(), ns1: .positive))

        XCTAssertNil(store.latest?.platelets, "the newest report has no count")
        XCTAssertEqual(try XCTUnwrap(store.mostRecent(.platelets)).value, 96)
        XCTAssertEqual(store.mostRecentResult(.ns1)?.result, .positive)
        XCTAssertNil(store.mostRecentResult(.igm))
    }

    func testAnEmptyReportIsNotSavedAndResultsSurviveAReload() throws {
        let name = temporaryStoreFilename("labs")
        let store = LabStore(filename: name)
        store.add(LabReport())
        XCTAssertTrue(store.reports.isEmpty)

        store.add(LabReport(whiteCells: 3.2, igm: .negative))
        let reloaded = try XCTUnwrap(LabStore(filename: name).reports.first)
        XCTAssertEqual(reloaded.igm, .negative)
        XCTAssertEqual(reloaded.ns1, .notDone)
        XCTAssertEqual(reloaded.whiteCells, 3.2)
    }

    func testAChecksWHOFieldsSurviveAReload() throws {
        let name = temporaryStoreFilename("checks")
        CaseLogStore(filename: name).add(CaseLogEntry(symptomIDs: ["fever", "abdominal"],
                                                      feverDaysAgo: 4, isPregnant: true))
        let latest = try XCTUnwrap(CaseLogStore(filename: name).entries.first)
        XCTAssertEqual(latest.symptomIDs, ["fever", "abdominal"])
        XCTAssertEqual(latest.feverDaysAgo, 4)
        XCTAssertTrue(latest.isPregnant)
    }
}
