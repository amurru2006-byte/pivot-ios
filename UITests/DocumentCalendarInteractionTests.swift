import XCTest

/// Synthetic saved draft and Calendar worker only, never the device Calendar.
final class DocumentCalendarInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-action-test", "--coach-calendar-create-test",
            "--calendar-travel-test", "--travel-estimate-test", "--saved-travel-editor-test"]
        app.launchEnvironment["PIVOT_QA_COACH_ACTION_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_TRAVEL_ID"] = UUID().uuidString
        app.launch(); openCoach(app); reopen(app); return app
    }
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        scrollControlIntoView(element, in: app, maxSwipes: 20)
        let ready = expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: element)
        wait(for: [ready], timeout: 15); element.tap()
    }
    private func openCoach(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15)); tap(app.buttons["open-pivot-coach"], app)
    }
    private func reopen(_ app: XCUIApplication) {
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-saved-draft-")).firstMatch
        tap(card, app); XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForExistence(timeout: 10))
    }
    private func close(_ app: XCUIApplication) {
        tap(app.buttons["coach-create-close"], app)
        XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForNonExistence(timeout: 30))
    }
    private func allDay(_ value: Bool, _ app: XCUIApplication) {
        let toggle = app.switches["creation-all-day"]
        scrollControlIntoView(toggle, in: app, maxSwipes: 20)
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: toggle)
        wait(for: [ready], timeout: 15)
        tapVisibleSwitchOnce(toggle, to: value, in: app)
    }
    private func audit(_ app: XCUIApplication, equals expected: String) {
        let field = app.staticTexts["creation-events-audit"]; tap(field, app); XCTAssertEqual(field.label, expected)
    }
    private func shot(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testAllDayDraftSurvivesRelaunchWithoutBecomingAMidnightAppointment() {
        let app = launch(); allDay(true, app)
        XCTAssertTrue(app.staticTexts["creation-all-day-summary"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["creation-time-summary"].exists)
        XCTAssertFalse(app.buttons["creation-travel-open"].exists)
        shot("document-all-day-date-review", app)
        close(app); app.terminate(); app.launch(); openCoach(app); reopen(app)
        XCTAssertEqual(app.switches["creation-all-day"].value as? String, "1")
        XCTAssertTrue(app.staticTexts["creation-all-day-summary"].exists)
        XCTAssertFalse(app.staticTexts["creation-time-summary"].exists)
        close(app); audit(app, equals: "0 eventi · 0 spostamenti · 0 incassi")
    }
    func testAllDayCreationNeedsConfirmationAndCannotBeReopenedAsANewDraft() {
        let app = launch(); allDay(true, app); tap(app.buttons["creation-top-save"], app)
        let alert = app.alerts["Creare questo impegno nel Calendario?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "evento giornaliero")).firstMatch.exists)
        alert.buttons["Annulla"].tap(); close(app)
        audit(app, equals: "0 eventi · 0 spostamenti · 0 incassi")
        reopen(app); tap(app.buttons["creation-top-save"], app)
        XCTAssertTrue(alert.waitForExistence(timeout: 15)); alert.buttons.matching(identifier: "coach-create-confirm").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForNonExistence(timeout: 45))
        audit(app, equals: "1 eventi · 0 spostamenti · 0 incassi")
        app.terminate(); app.launch(); openCoach(app)
        // The synthetic Calendar is volatile; the completed local draft is
        // durable and must not offer another creation after relaunch.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-draft-created-")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-saved-draft-")).count, 0)
    }
    func testTurningOffAllDayRequiresRealTimesInsteadOfInventingAMidnightDuration() {
        let app = launch(); allDay(true, app); allDay(false, app)
        XCTAssertFalse(app.staticTexts["creation-time-summary"].exists)
        XCTAssertTrue(app.buttons["Imposta inizio"].exists); XCTAssertTrue(app.buttons["Imposta fine"].exists)
        tap(app.buttons["creation-top-save"], app)
        XCTAssertFalse(app.alerts["Creare questo impegno nel Calendario?"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Conferma inizio e fine")).firstMatch.waitForExistence(timeout: 8))
        close(app); audit(app, equals: "0 eventi · 0 spostamenti · 0 incassi")
    }
}
