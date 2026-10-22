import XCTest

final class CalendarCreationInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    private func launch(savedDraft: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-action-test", "--coach-calendar-create-test", "--calendar-travel-test", "--travel-estimate-test"]
        app.launchEnvironment["PIVOT_QA_COACH_ACTION_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_TRAVEL_ID"] = UUID().uuidString
        if savedDraft { app.launchArguments.append("--saved-travel-editor-test") }
        app.launch(); openCoach(app)
        if savedDraft { reopened(app); return app }
        let input = app.descendants(matching: .any)["coach-message-input"]
        tap(input, app); input.typeText("Crea un impegno di prova nel calendario Personale test")
        done("pivot-keyboard-done", app)
        tap(app.buttons["coach-send"], app); tap(app.buttons["coach-online-approve"], app)
        XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForExistence(timeout: 12))
        return app
    }
    private func openCoach(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15)); tap(app.buttons["open-pivot-coach"], app)
    }
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        scrollControlIntoView(element, in: app, maxSwipes: 20)
        XCTAssertTrue(element.isEnabled); element.tap()
    }
    private func done(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]; XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
    private func shot(_ name: String, _ app: XCUIApplication) {
        let file = XCTAttachment(screenshot: app.screenshot()); file.name = name; file.lifetime = .keepAlways; add(file)
    }
    private func reopened(_ app: XCUIApplication) {
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-saved-draft-")).firstMatch
        tap(card, app); XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForExistence(timeout: 8))
    }
    func testNativeEditorManualJourneySurvivesRelaunchAndCreatesExactlyTwoAfterConfirmation() {
        let app = launch()
        let location = app.textFields["creation-location"]
        tap(location, app); location.typeText("Destinazione QA"); done("coach-draft-keyboard-done", app)
        shot("calendar-native-editor-before-travel", app)
        tap(app.buttons["creation-travel-open"], app)
        let origin = app.textFields["creation-travel-origin"]
        tap(origin, app); origin.typeText("Partenza QA"); done("creation-travel-keyboard-done", app)
        tap(app.buttons["creation-travel-minutes-30"], app)
        tapVisibleSwitchOnce(app.switches["creation-travel-separate"], to: true, in: app)
        shot("calendar-native-travel-manual-selection", app)
        app.buttons["creation-travel-done"].tap()
        XCTAssertTrue(app.staticTexts["creation-travel-preview"].waitForExistence(timeout: 8))
        shot("calendar-native-editor-with-separate-travel", app)
        app.buttons["coach-create-close"].tap()
        app.terminate(); app.launch(); openCoach(app); reopened(app)
        XCTAssertEqual(app.textFields["creation-location"].value as? String, "Destinazione QA")
        XCTAssertTrue(app.staticTexts["creation-travel-preview"].exists)
        app.buttons["creation-top-save"].tap()
        let alert = app.alerts["Creare questo impegno nel Calendario?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10)); XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "due eventi")).firstMatch.exists)
        alert.buttons["Annulla"].tap()
        app.buttons["coach-create-close"].tap()
        let audit = app.staticTexts["creation-events-audit"]; tap(audit, app)
        XCTAssertEqual(audit.label, "0 eventi · 0 spostamenti · 0 incassi")
        reopened(app); app.buttons["creation-top-save"].tap()
        let confirm = alert.buttons.matching(identifier: "coach-create-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        // Full-run failure artifacts show the completed creation immediately
        // after the old deadline. Keep the two-event/one-trip/no-money checks.
        XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForNonExistence(timeout: 45))
        tap(audit, app); XCTAssertEqual(audit.label, "2 eventi · 1 spostamenti · 0 incassi")
    }
    func testAppleManualJourneyCreatesOnlyActivityAndClearlyRequiresCalendarCompletion() {
        let app = launch(savedDraft: true)
        tap(app.textFields["creation-location"], app)
        app.textFields["creation-location"].typeText("Destinazione QA")
        done("coach-draft-keyboard-done", app)
        tap(app.buttons["creation-travel-open"], app)
        tap(app.textFields["creation-travel-origin"], app)
        app.textFields["creation-travel-origin"].typeText("Partenza QA")
        done("creation-travel-keyboard-done", app)
        XCTAssertEqual(app.switches["creation-travel-separate"].value as? String, "0")
        tap(app.buttons["creation-travel-minutes-30"], app)
        app.buttons["creation-travel-done"].tap()
        XCTAssertTrue(app.staticTexts["creation-apple-travel-manual"].waitForExistence(timeout: 8))
        app.buttons["creation-top-save"].tap()
        let alert = app.alerts["Creare questo impegno nel Calendario?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Aggiungerò un evento")).firstMatch.exists)
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "va completata in Calendario Apple")).firstMatch.exists)
        alert.buttons.matching(identifier: "coach-create-confirm").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForNonExistence(timeout: 45))
        let audit = app.staticTexts["creation-events-audit"]; tap(audit, app)
        XCTAssertEqual(audit.label, "1 eventi · 0 spostamenti · 0 incassi")
        tap(app.staticTexts["coach-apple-travel-handoff"], app)
        XCTAssertTrue(app.staticTexts["coach-apple-travel-handoff"].exists)
        shot("apple-manual-travel-one-event-not-a-native-write", app)
    }
    func testMapsEstimateRequiresConsentCanBeUsedThenRemovedWithoutWriting() {
        // Calendar creation through chat is covered by the separate native
        // creation/online cases. Start this routing regression with a persisted
        // synthetic draft; still exercise every real editor and consent step.
        let app = launch(savedDraft: true)
        tap(app.buttons["creation-travel-open"], app); tap(app.buttons["creation-travel-maps"], app)
        XCTAssertTrue(app.buttons["travel-consent"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["travel-test-count"].label, "Richieste sintetiche: 0")
        tap(app.buttons["travel-consent"], app)
        tap(app.textFields["travel-origin"], app); app.textFields["travel-origin"].typeText("Partenza QA")
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        tap(app.buttons["travel-search-origin"], app); tap(app.buttons["travel-place-origin-Luogo QA A"], app)
        tap(app.textFields["travel-destination"], app); app.textFields["travel-destination"].typeText("Arrivo QA")
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        tap(app.buttons["travel-search-destination"], app); tap(app.buttons["travel-place-destination-Luogo QA B"], app)
        tap(app.buttons["travel-calculate"], app)
        XCTAssertTrue(app.staticTexts["travel-result"].waitForExistence(timeout: 8))
        tap(app.buttons["travel-use"], app)
        XCTAssertTrue(app.staticTexts["creation-travel-estimate"].waitForExistence(timeout: 8))
        shot("calendar-native-travel-apple-maps-estimate", app)
        app.buttons["creation-travel-done"].tap()
        XCTAssertTrue(app.staticTexts["creation-travel-preview"].waitForExistence(timeout: 5))
        tap(app.buttons["creation-travel-open"], app); tap(app.buttons["creation-travel-minutes-0"], app)
        app.buttons["creation-travel-done"].tap()
        // Observe the completed sheet transition, not a snapshot of the old
        // parent underneath its closing animation. Both the visible removal
        // and its persisted draft must be verified; no Calendar write occurs.
        XCTAssertTrue(app.navigationBars["Tempo di percorrenza"].waitForNonExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["creation-travel-preview"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["creation-travel-open"].label.contains("Nessuno"))
        shot("calendar-native-travel-removed", app)
        app.buttons["coach-create-close"].tap()
        app.terminate(); app.launch(); openCoach(app); reopened(app)
        XCTAssertFalse(app.staticTexts["creation-travel-preview"].exists)
        XCTAssertTrue(app.buttons["creation-travel-open"].label.contains("Nessuno"))
        app.buttons["coach-create-close"].tap()
        let audit = app.staticTexts["creation-events-audit"]; tap(audit, app)
        XCTAssertEqual(audit.label, "0 eventi · 0 spostamenti · 0 incassi")
    }
}
