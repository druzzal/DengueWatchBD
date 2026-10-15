import XCTest
@testable import DengueWatchBD

/// Deleting from the merged log.
///
/// The log draws from three stores at once, so a row's position says nothing
/// about where its entry lives. Deletion goes by id, and the risk it carries
/// is removing the right id from the wrong store — or, worse, matching an id
/// that belongs to another kind of record entirely.
@MainActor
final class LogDeletionTests: XCTestCase {

    private func stores() -> (CaseLogStore, VitalsStore, LabStore) {
        (CaseLogStore(filename: temporaryStoreFilename("case")),
         VitalsStore(filename: temporaryStoreFilename("vitals")),
         LabStore(filename: temporaryStoreFilename("labs")))
    }

    func testDeletingOneKindOfRecordLeavesTheOthersAlone() {
        let (checks, vitals, labs) = stores()
        checks.add(CaseLogEntry(symptomIDs: ["fever"], outcomeRawValue: 1))
        vitals.add(VitalsEntry(temperature: 38.4))
        labs.add(LabReport(platelets: 96))

        let vitalID = try! XCTUnwrap(vitals.entries.first).id
        vitals.delete(id: vitalID)

        XCTAssertTrue(vitals.entries.isEmpty)
        XCTAssertEqual(checks.entries.count, 1, "a check is not a reading")
        XCTAssertEqual(labs.reports.count, 1, "a lab report is not a reading")
    }

    func testAnIdFromAnotherStoreDeletesNothing() {
        let (checks, vitals, _) = stores()
        checks.add(CaseLogEntry(symptomIDs: ["fever"], outcomeRawValue: 1))
        vitals.add(VitalsEntry(temperature: 38.4))

        let checkID = try! XCTUnwrap(checks.entries.first).id
        vitals.delete(id: checkID)

        XCTAssertEqual(vitals.entries.count, 1, "an unknown id must be a no-op")
        XCTAssertEqual(checks.entries.count, 1)
    }

    func testDeletingOneOfSeveralKeepsTheRest() {
        let (_, vitals, _) = stores()
        for temperature in [38.0, 38.5, 39.0] {
            vitals.add(VitalsEntry(date: Date().addingTimeInterval(-temperature),
                                   temperature: temperature))
        }
        let middle = vitals.entries[1].id
        vitals.delete(id: middle)

        XCTAssertEqual(vitals.entries.count, 2)
        XCTAssertFalse(vitals.entries.contains { $0.id == middle })
    }

    /// Clearing is what "Delete all" does, and it has to reach every store —
    /// leaving lab reports behind would be a quiet lie about what was removed.
    func testClearingEmptiesEveryStore() {
        let (checks, vitals, labs) = stores()
        checks.add(CaseLogEntry(symptomIDs: ["fever"], outcomeRawValue: 1))
        vitals.add(VitalsEntry(temperature: 38.4))
        labs.add(LabReport(platelets: 96))

        checks.clear(); vitals.clear(); labs.clear()

        XCTAssertTrue(checks.entries.isEmpty)
        XCTAssertTrue(vitals.entries.isEmpty)
        XCTAssertTrue(labs.reports.isEmpty)
    }

    func testTheDeleteControlsAreLocalised() {
        // A day is deleted by swiping it and confirming; the whole log by
        // "Delete all". There is no multi-select edit mode any more.
        for key in ["common.delete", "log.delete.day", "common.deleteAll", "log.confirmDelete"] {
            XCTAssertNotNil(Strings.english[key], key)
            XCTAssertNotNil(Strings.bangla[key], key)
        }
    }

    // MARK: - Single symptom checks

    /// The latest check drives the care plan. Deleting it must hand that job
    /// to the check before it, not leave the deleted one's advice behind.
    func testDeletingTheLatestCheckMakesThePreviousOneLatest() {
        let (checks, _, _) = stores()
        let older = CaseLogEntry(date: Date().addingTimeInterval(-86_400),
                                 symptomIDs: ["fever"],
                                 outcomeRawValue: TriageOutcome.testAdvised.rawValue)
        let newer = CaseLogEntry(symptomIDs: ["faint"],
                                 outcomeRawValue: TriageOutcome.emergency.rawValue)
        checks.add(older)
        checks.add(newer)
        XCTAssertEqual(checks.entries.first?.id, newer.id)

        checks.delete(id: newer.id)

        XCTAssertEqual(checks.entries.map(\.id), [older.id])
        XCTAssertEqual(checks.entries.first?.outcome, .testAdvised)
    }

    func testDeletingOneCheckLeavesTheMeasurementsAlone() {
        let (checks, vitals, labs) = stores()
        checks.add(CaseLogEntry(symptomIDs: ["fever"], outcomeRawValue: 1))
        vitals.add(VitalsEntry(temperature: 38.4))
        labs.add(LabReport(platelets: 96))

        checks.delete(id: try! XCTUnwrap(checks.entries.first).id)

        XCTAssertTrue(checks.entries.isEmpty)
        XCTAssertEqual(vitals.entries.count, 1)
        XCTAssertEqual(labs.reports.count, 1)
    }

    func testTheCheckDeletionTextExistsInBothLanguages() {
        for key in ["check.actions", "check.history.title", "check.history.latest",
                    "check.history.footer", "check.delete", "check.delete.confirm",
                    "check.delete.detail", "log.checksOnly"] {
            XCTAssertNotNil(Strings.english[key], key)
            XCTAssertNotNil(Strings.bangla[key], key)
        }
    }
}
