import XCTest

final class TrainingConcernInteractionTests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<24 {
            if element.isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -150 : 150)))
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func prepare(injury: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--training-concern-test"] + (injury ? ["--reported-injury-test"] : [])
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let fixture = app.buttons["concern-fixture"]
        reveal(fixture, in: app); fixture.tap()
        XCTAssertTrue(app.staticTexts["Segnalazioni pronte"].waitForExistence(timeout: 8))
        let day = app.buttons["workout-day-concern-day"]
        reveal(day, in: app, up: false); day.tap()
        XCTAssertTrue(app.navigationBars["Allenamento"].waitForExistence(timeout: 5))
        return app
    }
    private func openReport(_ app: XCUIApplication, injury: Bool = false) {
        let options = app.buttons["exercise-options-concern-first"]
        reveal(options, in: app); options.tap()
        app.buttons[injury ? "Segnala infortunio" : "Segnala dolore"].tap()
        XCTAssertTrue(app.textFields["concern-area"].waitForExistence(timeout: 5))
    }
    private func fillAndSave(_ app: XCUIApplication) {
        let area = app.textFields["concern-area"]
        area.tap(); area.typeText("Zona TEST")
        let done = app.buttons["concern-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        let links = app.buttons["Esercizi collegati"]
        reveal(links, in: app); links.tap()
        let first = app.buttons["concern-link-concern-first"]
        XCTAssertEqual(first.value as? String, "Collegato", app.debugDescription)
        let second = app.buttons["concern-link-concern-second"]
        XCTAssertEqual(second.value as? String, "Non collegato", app.debugDescription)
        reveal(second, in: app); second.tap()
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        XCTAssertEqual(second.value as? String, "Collegato", app.debugDescription)
        XCTAssertEqual(first.value as? String, "Collegato", app.debugDescription)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-concern-links"; image.lifetime = .keepAlways; add(image)
        app.buttons["concern-save"].tap()
        XCTAssertTrue(app.textFields["concern-area"].waitForNonExistence(timeout: 8), app.debugDescription)
    }
    private func setResolved(_ toggle: XCUIElement, to value: Bool, in app: XCUIApplication) {
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, value ? "0" : "1", app.debugDescription)
        // SwiftUI exposes the labelled row as a switch; its midpoint is the
        // label, not the native switch at the trailing edge. Tap the control.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let selected = NSPredicate(format: "value == %@", value ? "1" : "0")
        expectation(for: selected, evaluatedWith: toggle)
        waitForExpectations(timeout: 3)
    }
    private func verifyFromRoot(_ app: XCUIApplication, resolved: Bool = false) {
        let verify = app.buttons["concern-verify"]
        reveal(verify, in: app); verify.tap()
        XCTAssertTrue(app.staticTexts[resolved ? "Segnalazione verificata · storico conservato" : "Segnalazione verificata · due movimenti"].waitForExistence(timeout: 8), app.debugDescription)
    }
    private func openSaved(_ app: XCUIApplication) {
        let list = app.buttons["training-concerns"]
        reveal(list, in: app, up: false); list.tap()
        let open = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "concern-open-")).firstMatch
        reveal(open, in: app); open.tap()
        XCTAssertTrue(app.textFields["concern-area"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["concern-area"].value as? String, "Zona TEST")
    }
    func testPainLinksTwoMovementsWithoutStartingWorkoutResolvesAndPersists() {
        let app = prepare()
        openReport(app); fillAndSave(app)
        let first = app.buttons["concern-warning-concern-first"]
        reveal(first, in: app, up: false)
        let second = app.buttons["concern-warning-concern-second"]
        reveal(second, in: app)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-concern-warning"; image.lifetime = .keepAlways; add(image)
        second.tap()
        let resolved = app.switches["concern-resolved"]
        setResolved(resolved, to: true, in: app); app.buttons["concern-save"].tap()
        XCTAssertTrue(app.textFields["concern-area"].waitForNonExistence(timeout: 8))
        XCTAssertFalse(app.buttons["concern-warning-concern-first"].exists)
        XCTAssertFalse(app.buttons["concern-warning-concern-second"].exists)
        app.navigationBars["Allenamento"].buttons.element(boundBy: 0).tap()
        verifyFromRoot(app, resolved: true)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        openSaved(app)
        reveal(resolved, in: app); XCTAssertEqual(resolved.value as? String, "1")
        setResolved(resolved, to: false, in: app); app.buttons["concern-save"].tap()
        XCTAssertTrue(app.textFields["concern-area"].waitForNonExistence(timeout: 8))
        app.navigationBars["Dolori e infortuni"].buttons.element(boundBy: 0).tap()
        verifyFromRoot(app)
    }
    func testReportedInjuryCanBeCancelledAndSavedWithoutChangingTraining() {
        let app = prepare(injury: true)
        openReport(app, injury: true)
        app.buttons["Annulla"].tap()
        XCTAssertTrue(app.textFields["concern-area"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["concern-warning-concern-first"].exists)
        openReport(app, injury: true); fillAndSave(app)
        app.navigationBars["Allenamento"].buttons.element(boundBy: 0).tap()
        verifyFromRoot(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        openSaved(app)
        app.buttons["Annulla"].tap()
        app.navigationBars["Dolori e infortuni"].buttons.element(boundBy: 0).tap()
        verifyFromRoot(app)
    }
}
