import XCTest

final class TrainingConcernInteractionTests: XCTestCase {
    override func tearDown() {
        attachFailureDiagnostics("training-concern")
        super.tearDown()
    }

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
        // Saving flushes to disk before dismissing. On the loaded iOS26 runner,
        // the old 8s timeout expired although the failure snapshot was already
        // back in Allenamento. Wait for the real destination, never tap twice.
        XCTAssertTrue(app.navigationBars["Allenamento"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.textFields["concern-area"].waitForNonExistence(timeout: 20), app.debugDescription)
    }
    private func setResolved(_ toggle: XCUIElement, to value: Bool, in app: XCUIApplication) {
        reveal(toggle, in: app)
        // A Form row can be hittable while its switch overlaps the home
        // indicator. The failure recording showed the row at y=800 on an
        // 852-point screen: bring the whole control inside the safe viewport.
        for _ in 0..<12 {
            if toggle.frame.maxY < app.frame.maxY - 65 { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -110)))
        }
        XCTAssertLessThan(toggle.frame.maxY, app.frame.maxY - 65, app.debugDescription)
        XCTAssertEqual(toggle.value as? String, value ? "0" : "1", app.debugDescription)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "concern-resolved-before-tap"; before.lifetime = .keepAlways; add(before)
        // The failure hierarchy exposes a labelled 361x52 wrapper Switch and
        // a separate 63x28 UIKit Switch inside it. Query and tap that native
        // control instead of guessing coordinates on the labelled wrapper.
        let control = toggle.switches.firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertLessThan(control.frame.width, toggle.frame.width, app.debugDescription)
        XCTAssertTrue(control.isHittable, app.debugDescription)
        control.tap()
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "concern-resolved-after-tap"; after.lifetime = .keepAlways; add(after)
        let selected = NSPredicate(format: "value == %@", value ? "1" : "0")
        expectation(for: selected, evaluatedWith: toggle)
        waitForExpectations(timeout: 8)
        XCTAssertEqual(control.value as? String, value ? "1" : "0", app.debugDescription)
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
