import XCTest

/// Synthetic provider and calendar only. Exercises the real persistence,
/// constraint review and local staging UI, not live model understanding.
final class PlanningConversationInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    private func launch(logistics: Bool = false, duration: Bool = false, signals: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-action-test", "--coach-calendar-create-test",
            "--calendar-mutations-test", "--conversation-continuity-test", "--planning-conversation-test"]
        if logistics { app.launchArguments += ["--linked-travel-test", "--planning-logistics-test"] }
        if duration { app.launchArguments.append("--planning-duration-test") }
        if signals { app.launchArguments += ["--planning-signals-test", "--online-coach-review-test"] }
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
private func correctFirstAlternative(_ app: XCUIApplication, text: String) {
        tap(app.switches["coach-planning-preparation"], app)
        tap(app.buttons["coach-planning-search"], app)
        let field = app.textFields.matching(identifier: "coach-planning-correction").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        tap(field, app); field.typeText(text)
        let done = app.buttons["pivot-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8)); done.tap()
        tap(app.buttons.matching(identifier: "coach-planning-refine").firstMatch, app)
    }
    private func tomorrowWeekday() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        return ["", "domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"][calendar.component(.weekday, from: tomorrow)]
    }
    func testExactTitleAndClockCorrectionSurvivesRelaunchAndRequiresNewRouteReview() {
        let app = launch()
        send("Recupera Impegno QA 1 domani pomeriggio", app, authorize: true)
        openPlan(app)
        correctFirstAlternative(app, text: "sposta Impegno QA 1 a \(tomorrowWeekday()) alle 14:30")
        XCTAssertTrue(app.staticTexts["coach-planning-saved-choices"].waitForExistence(timeout: 15))
        let stage = app.buttons.matching(identifier: "coach-planning-stage").firstMatch
        XCTAssertTrue(stage.exists); XCTAssertFalse(stage.isEnabled)
        let message = app.staticTexts["coach-planning-message"]
        let saved = expectation(for: NSPredicate(format: "label CONTAINS %@", "Scelte conservate"), evaluatedWith: message)
        wait(for: [saved], timeout: 10)
        leavePlan(app); app.terminate(); app.launch(); tap(app.buttons["open-pivot-coach"], app)
        openPlan(app)
        XCTAssertTrue(app.staticTexts["coach-planning-saved-choices"].exists)
        let clock = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "alle 14:30")).firstMatch
        XCTAssertTrue(clock.exists)
        tap(app.switches["coach-planning-preparation"], app)
        tap(app.buttons["coach-planning-search"], app)
        let proposed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "14:30–")).firstMatch
        XCTAssertTrue(proposed.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons.matching(identifier: "coach-planning-stage").firstMatch.isEnabled)
    }
    func testUnrecognizedCorrectionDoesNotSaveChoicesAndExplicitRemovalKeepsPlan() {
        let app = launch()
        send("Recupera Impegno QA 1 domani pomeriggio", app, authorize: true)
        openPlan(app)
        correctFirstAlternative(app, text: "sposta quello a venerdì")
        let message = app.staticTexts["coach-planning-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 8))
        XCTAssertTrue(message.label.contains("Indica una sola attività"), message.label)
        XCTAssertFalse(app.staticTexts["coach-planning-saved-choices"].exists)
        let field = app.textFields.matching(identifier: "coach-planning-correction").firstMatch
        tap(field, app)
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText("metti il primo a \(tomorrowWeekday()) alle 14:30")
        tap(app.buttons["pivot-keyboard-done"], app)
        tap(app.buttons.matching(identifier: "coach-planning-refine").firstMatch, app)
        XCTAssertTrue(app.staticTexts["coach-planning-saved-choices"].waitForExistence(timeout: 15))
        tap(app.buttons["coach-planning-clear-choices"], app)
        XCTAssertTrue(app.staticTexts["coach-planning-saved-choices"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["1. Impegno QA 1"].exists)
        XCTAssertTrue(app.staticTexts["coach-planning-days"].exists)
        XCTAssertFalse(app.buttons.matching(identifier: "coach-planning-stage").firstMatch.exists)
    }
private func evidence(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testLinkedPlanningStagesAGroupForExplicitReviewWithoutNativeWrites() {
        let app = launch(logistics: true)
        tap(app.buttons["linked-travel-prepare-qa"], app)
        let link = app.staticTexts["linked-travel-audit"]
        XCTAssertTrue(link.waitForExistence(timeout: 8)); XCTAssertTrue(link.label.contains("sincronizzato"), link.label)
        send("Recupera Impegno QA 1 domani pomeriggio", app, authorize: true)
        openPlan(app)
        XCTAssertTrue(app.staticTexts["coach-planning-linked-group"].exists)
        tap(app.switches["coach-planning-preparation"], app); tap(app.buttons["coach-planning-search"], app)
        let stage = app.buttons.matching(identifier: "coach-planning-stage").firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 15)); XCTAssertFalse(stage.isEnabled)
        let trip = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Viaggio collegato (stima da verificare)")).firstMatch
        XCTAssertTrue(trip.exists)
        evidence(app, name: "ai-planning-linked-group-preview")
        tap(app.switches.matching(identifier: "coach-planning-route-review").firstMatch, app); tap(stage, app)
        tap(app.buttons["Apri le conferme per il Calendario"], app)
        let batch = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-calendar-batch-")).firstMatch
        tap(batch, app)
        tap(app.buttons["coach-mutations-review"], app)
        let included = app.staticTexts["coach-mutations-error"]
        XCTAssertTrue(included.waitForExistence(timeout: 12)); XCTAssertTrue(included.label.contains("incluso il viaggio collegato"), included.label)
        let reviewBoth = app.buttons["coach-mutations-review"]
        scrollControlIntoView(reviewBoth, in: app, maxSwipes: 20)
        XCTAssertEqual(reviewBoth.label, "Verifica 2 modifiche")
        XCTAssertFalse(app.buttons["coach-mutations-confirm"].exists)
        evidence(app, name: "ai-planning-linked-pair-final-review")
    }
    func testPersonalDurationNeedsExplicitPlanDayAdoptionAndPreparationReconfirmation() {
        let app = launch(duration: true)
        send("Recupera Impegno QA 1 domani pomeriggio", app, authorize: true)
        openPlan(app)
        tap(app.switches["coach-planning-preparation"], app)
        tap(app.buttons["Durata personale · Impegno QA 1"], app)
        XCTAssertFalse(app.buttons["coach-planning-duration-estimate"].isEnabled)
        tap(app.buttons["coach-planning-duration-plan"], app); tap(app.buttons["Scheda durata QA"], app)
        tap(app.buttons["coach-planning-duration-day"], app); tap(app.buttons["Giorno durata QA"], app)
        tap(app.buttons["coach-planning-duration-estimate"], app)
        let preview = app.staticTexts["coach-planning-duration-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15)); XCTAssertTrue(preview.label.contains("75 min"), preview.label)
        XCTAssertFalse(app.staticTexts["coach-planning-duration-saved"].exists)
        evidence(app, name: "ai-planning-personal-duration-review")
        tap(app.buttons["coach-planning-duration-adopt"], app)
        XCTAssertTrue(app.staticTexts["coach-planning-duration-saved"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["coach-planning-search"].isEnabled)
        tap(app.switches["coach-planning-preparation"], app); tap(app.buttons["coach-planning-search"], app)
        XCTAssertTrue(app.buttons.matching(identifier: "coach-planning-stage").firstMatch.waitForExistence(timeout: 15))
        tap(app.buttons["coach-planning-duration-clear"], app)
        XCTAssertTrue(app.staticTexts["coach-planning-duration-saved"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.buttons["coach-planning-search"].isEnabled)
    }
    func testContextSignalDiscussOnlyFillsComposerWithoutAProviderRequestOrCalendarWrite() {
        let app = launch(signals: true)
        let coverage = app.staticTexts["coach-agenda-coverage"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 10))
        let requests = app.staticTexts["coach-online-fixture-requests"]
        XCTAssertTrue(requests.exists); XCTAssertEqual(requests.label, "Richieste sintetiche: 0")
        let discuss = app.buttons.matching(NSPredicate(format: "label == %@", "Discuti questa situazione")).firstMatch
        tap(discuss, app)
        let input = app.descendants(matching: .any)["coach-message-input"]
        let value = input.value as? String ?? ""
        XCTAssertTrue(value.contains("Impegno QA 1") && value.contains("Impegno QA 2"), value)
        XCTAssertEqual(requests.label, "Richieste sintetiche: 0")
        tap(app.buttons["pivot-keyboard-done"], app)
        scrollControlIntoView(coverage, in: app, maxSwipes: 20)
        evidence(app, name: "ai-contextual-signal-local-only")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Nessun impegno è dedotto saltato")).firstMatch.exists)
    }
}
