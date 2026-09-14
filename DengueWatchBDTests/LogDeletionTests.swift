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
        let suffix = UUID().uuidString
        return (CaseLogStore(filename: "case-\(suffix).json"),
                VitalsStore(filename: "vitals-\(suffix).json"),
                LabStore(filename: "labs-\(suffix).json"))
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
        for key in ["common.edit", "common.delete", "log.delete.selected", "log.delete.day"] {
            XCTAssertNotNil(Strings.english[key], key)
            XCTAssertNotNil(Strings.bangla[key], key)
        }
    }
}
