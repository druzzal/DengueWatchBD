import XCTest

/// The flows a reader taps through in My health, driven on the real app.
///
/// The unit tests cover what each store and rule does; these cover that the
/// buttons reach them — a sheet that opens, a confirmation that deletes, a
/// total that updates on screen. Each test launches the app empty, in
/// English, through `UITestSupport`, and seeds only what it needs.
@MainActor
final class MyHealthUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Fluids

    func testAddingADrinkUpdatesTodaysTotal() {
        let app = launch()
        button("Add a drink", in: app).tap()
        button("250 ml", in: app).tap()
        button("Save", in: app).tap()

        let tile = app.descendants(matching: .any)["fluidIntakeTile"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertTrue(tile.label.contains("250"), tile.label)
        XCTAssertTrue(tile.label.contains("Drinks: 1"), tile.label)
    }

    func testPassedUrineIsOneTapAndCanBeUndone() {
        let app = launch()
        let tile = app.descendants(matching: .any)["fluidUrineTile"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertTrue(tile.label.contains("0"), tile.label)

        // The button, not the tile that shares its words.
        button("Passed urine", in: app).tap()
        XCTAssertTrue(waitFor(tile, labelContaining: "1"), tile.label)

        button("Today's entries", in: app).tap()
        button("Delete", in: app).tap()
        XCTAssertTrue(waitFor(tile, labelContaining: "0"), tile.label)
    }

    // MARK: - Symptom check

    func testASymptomCheckGivesItsAdviceAndIsKept() {
        let app = launch()
        button("Check symptoms", in: app).tap()
        button("Yes, I have a fever", in: app).tap()
        button("Continue", in: app).tap()          // other symptoms: none ticked
        button("None of these", in: app).tap()     // warning signs
        button("Continue", in: app).tap()          // fever timeline
        button("See what to do", in: app).tap()    // risk factors: none

        XCTAssertTrue(text("Get a dengue test", in: app).waitForExistence(timeout: 5))

        // Back to My health, where the kept check now drives the card.
        app.navigationBars.firstMatch.swipeDown(velocity: .fast)
        XCTAssertTrue(text("Get a dengue test", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(button("Check again", in: app).exists)
    }

    // MARK: - Deleting checks

    func testDeletingTheLatestCheckFallsBackToTheOneBefore() {
        let app = launch(seed: "checks")
        XCTAssertTrue(text("Go to a hospital now", in: app).waitForExistence(timeout: 5))

        button("Symptom check options", in: app).tap()
        button("Delete this check", in: app).tap()
        confirm("Delete", in: app)

        // The plain fever from two days ago is the latest check now.
        XCTAssertTrue(text("Get a dengue test", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(text("Go to a hospital now", in: app).exists)

        button("Symptom check options", in: app).tap()
        button("Delete this check", in: app).tap()
        confirm("Delete", in: app)

        XCTAssertTrue(button("Check symptoms", in: app).waitForExistence(timeout: 5),
                      "with no checks left, the card offers a first one")
    }

    func testAPastCheckIsDeletedFromTheList() {
        let app = launch(seed: "checks")
        button("Symptom check options", in: app).tap()
        button("Past checks", in: app).tap()

        // Rows that show a check's advice: the list's footer is a cell too.
        let rows = app.cells.containing(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@",
            "Go to a hospital now", "Get a dengue test"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2)

        rows.element(boundBy: 1).swipeLeft()
        button("Delete", in: app).tap()
        confirm("Delete", in: app)

        XCTAssertTrue(waitFor(count: 1, of: rows))
        button("Done", in: app).tap()
        // The latest check was the one kept.
        XCTAssertTrue(text("Go to a hospital now", in: app).waitForExistence(timeout: 5))
    }

    // MARK: - The log

    func testExportingTheLogOpensTheShareSheet() {
        let app = launch(seed: "vitals")
        button("My log", in: app).tap()
        button("Export as PDF", in: app).tap()

        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 15),
                      "the finished PDF is handed to the share sheet")
    }

    // MARK: - Lab report

    func testEachSerologyTestSaysWhenItIsInformative() {
        let app = launch()
        button("Add a report", in: app).tap()
        // The footer refers to these lines; they used to be translated and
        // never shown.
        // The form loads its rows as they scroll in, so each is looked for
        // on its way down rather than all at once.
        for line in ["Usually informative in the first five days of fever.",
                     "Usually detectable from about day five of fever.",
                     "Rises later, and may reflect a past infection."] {
            let element = text(line, in: app)
            var swipes = 0
            while !element.waitForExistence(timeout: 2) && swipes < 4 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(element.exists, "not shown: \(line)")
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Lab report form with test timing"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Ended in the background

    func testAHalfTypedReadingSurvivesTheAppBeingEnded() {
        var app = launch()
        button("Record readings", in: app).tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("38.6")

        // Into the background, where iOS saves the scene, then ended the way
        // the system ends an app — not swiped away, which discards it.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()

        app = launch()
        let restored = app.textFields.firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 8), "the form did not come back open")
        XCTAssertEqual(restored.value as? String, "38.6")

        // Saved or cancelled, the draft is gone: the next form starts empty.
        button("Cancel", in: app).tap()
        button("Record readings", in: app).tap()
        let fresh = app.textFields.firstMatch
        XCTAssertTrue(fresh.waitForExistence(timeout: 5))
        XCTAssertNotEqual(fresh.value as? String, "38.6")
    }

    // MARK: - Helpers

    private func launch(seed: String = "") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["DW_UITEST": "1",
                                 "DW_UITEST_SEED": seed,
                                 "DW_START_TAB": "health"]
        app.launch()
        return app
    }

    /// A button whose label contains the text. Labels can carry an icon's
    /// name as well as the words, so an exact match is too brittle.
    private func button(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let match = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5), "no button “\(title)”")
        return match
    }

    /// Any element showing the text, including combined accessibility rows.
    private func text(_ string: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", string)).firstMatch
    }

    /// Taps the confirming button of a dialog, wherever the system draws it.
    private func confirm(_ title: String, in app: XCUIApplication) {
        for container in [app.sheets, app.alerts] {
            let candidate = container.buttons[title]
            if candidate.waitForExistence(timeout: 2) {
                candidate.tap()
                return
            }
        }
        // Newer systems draw a confirmation dialog as a popover of plain
        // buttons; the confirming one is the last added.
        let buttons = app.buttons.matching(identifier: title)
        XCTAssertGreaterThan(buttons.count, 0, "no “\(title)” to confirm")
        buttons.element(boundBy: buttons.count - 1).tap()
    }

    private func waitFor(_ element: XCUIElement, labelContaining text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }

    private func waitFor(count: Int, of query: XCUIElementQuery) -> Bool {
        let predicate = NSPredicate(format: "count == %d", count)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }
}
