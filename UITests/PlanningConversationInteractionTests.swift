import XCTest

/// Synthetic provider and calendar only. Exercises the real persistence,
/// constraint review and local staging UI, not live model understanding.
final class PlanningConversationInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-action-test", "--coach-calendar-create-test",
            "--calendar-mutations-test", "--conversation-continuity-test", "--planning-conversation-test"]
        app.launchEnvironment["PIVOT_QA_COACH_ACTION_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_KEYCHAIN_ID"] = UUID().uuidString
        app.launch(); tap(app.buttons["open-pivot-coach"], app); return app
    }
    private func tap(_ value: XCUIElement, _ app: XCUIApplication) {
        _ = value.waitForExistence(timeout: 2)
        scrollControlIntoView(value, in: app, maxSwipes: 20)
        XCTAssertTrue(value.exists); XCTAssertTrue(value.isEnabled); value.tap()
    }
    private func send(_ text: String, _ app: XCUIApplication, authorize: Bool) {
        let input = app.descendants(matching: .any)["coach-message-input"]
        tap(input, app); input.typeText(text)
        let done = app.buttons["pivot-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8)); done.tap()
        tap(app.buttons["coach-send"], app)
        if authorize { tap(app.buttons["coach-online-approve"], app) }
        let saved = app.staticTexts["coach-persistence-status"]
        let expectation = expectation(for: NSPredicate(format: "label == %@", "Conversazione salvata"), evaluatedWith: saved)
        wait(for: [expectation], timeout: 20)
    }
    private func openPlan(_ app: XCUIApplication) {
        tap(app.buttons["coach-planning-card"], app)
        XCTAssertTrue(app.navigationBars["Piano di recupero"].waitForExistence(timeout: 10))
    }
    private func leavePlan(_ app: XCUIApplication) {
        let back = app.navigationBars["Piano di recupero"].buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 8)); XCTAssertTrue(back.isHittable); back.tap()
    }
    func testPlanningRefinementRetainsTargetExcludedDaysAndInteractiveCardAfterRelaunch() {
        let app = launch()
        send("Recupera Impegno QA 1 domani pomeriggio", app, authorize: true)
        XCTAssertTrue(app.staticTexts["coach-focused-planning"].waitForExistence(timeout: 10))
        send("Domani no, meglio fra tre giorni; tieni escluso anche dopodomani", app, authorize: false)
        XCTAssertEqual(app.buttons.matching(identifier: "coach-planning-card").count, 1)
        openPlan(app)
        XCTAssertTrue(app.staticTexts["1. Impegno QA 1"].exists)
        XCTAssertTrue(app.staticTexts["coach-planning-days"].exists)
        XCTAssertFalse(app.buttons["coach-planning-search"].isEnabled)
        leavePlan(app); app.terminate(); app.launch(); tap(app.buttons["open-pivot-coach"], app)
        openPlan(app)
        XCTAssertTrue(app.staticTexts["1. Impegno QA 1"].exists)
        let excluded = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Esclusi:")).firstMatch
        XCTAssertTrue(excluded.exists)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let day = Calendar.current.component(.day, from: tomorrow)
        XCTAssertTrue(excluded.label.contains(String(day)), excluded.label)
        leavePlan(app); tap(app.buttons["coach-clear-planning-focus"], app)
        XCTAssertTrue(app.staticTexts["coach-focused-planning"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["coach-planning-card"].exists)
    }
    func testAlternativeRequiresDurationAndRouteReviewAndStagesWithoutCalendarWrites() {
        let app = launch()
        send("Recupera Impegno QA 1 domani pomeriggio", app, authorize: true)
        openPlan(app)
        let search = app.buttons["coach-planning-search"]
        XCTAssertFalse(search.isEnabled)
        tap(app.switches["coach-planning-preparation"], app)
        XCTAssertTrue(search.isEnabled); tap(search, app)
        let stage = app.buttons.matching(identifier: "coach-planning-stage").firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 15)); XCTAssertFalse(stage.isEnabled)
        tap(app.switches.matching(identifier: "coach-planning-route-review").firstMatch, app)
        XCTAssertTrue(stage.isEnabled); tap(stage, app)
        let confirmation = app.buttons["Apri le conferme per il Calendario"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 12))
        leavePlan(app)
        tap(app.buttons["calendar-mutation-audit"], app)
        let audit = app.staticTexts["calendar-mutation-audit-result"]
        XCTAssertTrue(audit.waitForExistence(timeout: 8))
        XCTAssertTrue(audit.label.contains("2 eventi"), audit.label)
        XCTAssertTrue(audit.label.contains("1 attività · 1 incassi · 500 ricevuti · 500 da incassare"), audit.label)
        XCTAssertTrue(app.buttons["coach-planning-card"].exists)
    }
}
