import XCTest

final class TrainingPhaseInteractionTests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<24 {
            if element.isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -150 : 150)))
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    func testPlanAndDayPhasesPreserveHistoryAndNewSessionPersistsContext() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--training-phase-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let fixture = app.buttons["phase-fixture"]
        reveal(fixture, in: app); fixture.tap()
        XCTAssertTrue(app.staticTexts["Fasi pronte"].waitForExistence(timeout: 8))
        let edit = app.buttons["edit-training-plan"]
        reveal(edit, in: app, up: false); edit.tap()
        let planPhase = app.buttons["training-plan-phase"]
        XCTAssertTrue(planPhase.waitForExistence(timeout: 5)); planPhase.tap()
        app.buttons["Scarico"].tap()
        let dayPhase = app.buttons["training-day-phase-phase-day"]
        reveal(dayPhase, in: app); dayPhase.tap(); app.buttons["Recupero / rientro"].tap()
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-plan-day-phase"; image.lifetime = .keepAlways; add(image)
        app.buttons["training-plan-save"].tap()
        XCTAssertTrue(app.navigationBars["Modifica scheda"].waitForNonExistence(timeout: 5))
        let day = app.buttons["workout-day-phase-day"]
        reveal(day, in: app); day.tap()
        let phase = app.buttons["workout-phase"]
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        XCTAssertTrue((phase.label + " " + (phase.value as? String ?? "")).contains("Recupero / rientro"), app.debugDescription)
        phase.tap(); app.buttons["Scarico"].tap()
        XCTAssertTrue(app.staticTexts["Pronto per iniziare"].exists)
        XCTAssertFalse(app.staticTexts["Allenamento in corso"].exists)
        phase.tap(); app.buttons["Recupero / rientro"].tap()
        let start = app.buttons["Inizia allenamento"]
        reveal(start, in: app); start.tap()
        XCTAssertTrue(app.staticTexts["Allenamento in corso"].waitForExistence(timeout: 5))
        reveal(phase, in: app, up: false); phase.tap(); app.buttons["Scarico"].tap()
        XCTAssertTrue((phase.label + " " + (phase.value as? String ?? "")).contains("Scarico"))
        phase.tap(); app.buttons["Recupero / rientro"].tap()
        let history = app.buttons["workout-day-history"]
        reveal(history, in: app, up: false); history.tap()
        XCTAssertTrue(app.staticTexts["Fase: Recupero / rientro"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Fase: Carico"], in: app)
        let historyImage = XCTAttachment(screenshot: app.screenshot()); historyImage.name = "serie7-phase-history"; historyImage.lifetime = .keepAlways; add(historyImage)
        app.navigationBars["Cronologia"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Allenamento"].buttons.element(boundBy: 0).tap()
        let verify = app.buttons["phase-verify"]
        reveal(verify, in: app); verify.tap()
        XCTAssertTrue(app.staticTexts["Fasi verificate · storico e carichi conservati"].waitForExistence(timeout: 8), app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        reveal(day, in: app); day.tap()
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        XCTAssertTrue((phase.label + " " + (phase.value as? String ?? "")).contains("Recupero / rientro"), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Allenamento in corso"].exists)
        app.navigationBars["Allenamento"].buttons.element(boundBy: 0).tap()
        reveal(verify, in: app); verify.tap()
        XCTAssertTrue(app.staticTexts["Fasi verificate · storico e carichi conservati"].waitForExistence(timeout: 8))
    }
}
