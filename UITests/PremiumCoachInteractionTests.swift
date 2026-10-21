import XCTest

/// Real controls and persistence, with synthetic calendar/provider fixtures only.
final class PremiumCoachInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    private func launch(_ flags: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test"] + flags
        app.launchEnvironment["PIVOT_QA_KEYCHAIN_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_COACH_ACTION_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_RECOVERY_ID"] = UUID().uuidString
        app.launch(); openCoach(app); return app
    }
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 3)
        scrollControlIntoView(element, in: app, maxSwipes: 18)
        XCTAssertTrue(element.exists); XCTAssertTrue(element.isEnabled); element.tap()
    }
    private func navTap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8)); XCTAssertTrue(element.isHittable); element.tap()
    }
    private func openCoach(_ app: XCUIApplication) { tap(app.buttons["open-pivot-coach"], app) }
    private func enter(_ text: String, _ app: XCUIApplication) {
        let input = app.descendants(matching: .any)["coach-message-input"]
        tap(input, app); input.typeText(text)
        navTap(app.buttons["pivot-keyboard-done"])
        tap(app.buttons["coach-send"], app)
    }
    private func backFromMemories(_ app: XCUIApplication) {
        navTap(app.navigationBars["Preferenze di Pivot"].buttons.element(boundBy: 0))
    }
    private func cancelReview(_ app: XCUIApplication) {
        navTap(app.navigationBars["Prima dell’invio"].buttons["Annulla"])
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testMemoryOptInPersistsAppearsInExactDisclosureAndCanBeRevoked() {
        let app = launch(["--online-coach-review-test"])
        tap(app.buttons["coach-memories"], app); tap(app.buttons["coach-memory-add"], app)
        let text = app.descendants(matching: .any)["coach-memory-text"]
        tap(text, app); text.typeText("Preferisco allenarmi la sera")
        XCTAssertEqual(app.switches["coach-memory-online"].value as? String, "0")
        navTap(app.buttons["coach-memory-save"])
        XCTAssertTrue(app.staticTexts["Solo sul dispositivo"].waitForExistence(timeout: 8))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-memory-")).matching(NSPredicate(format: "label CONTAINS %@", "Preferisco allenarmi")).firstMatch
        tap(row, app); tap(app.switches["coach-memory-online"], app)
        XCTAssertEqual(app.switches["coach-memory-online"].value as? String, "1", "Consent must really change before Save, not just receive a tap on its label")
        capture("premium-memory-switch-enabled", app)
        navTap(app.buttons["coach-memory-save"])
        XCTAssertTrue(app.staticTexts["Locale e AI online"].waitForExistence(timeout: 8))
        app.terminate(); app.launch(); openCoach(app)
        tap(app.buttons["coach-memories"], app)
        XCTAssertTrue(app.staticTexts["Locale e AI online"].waitForExistence(timeout: 8)); backFromMemories(app)
        enter("Ciao Pivot", app)
        let disclosure = app.buttons["coach-online-memories"]
        tap(disclosure, app)
        XCTAssertTrue(app.staticTexts["Preferisco allenarmi la sera"].waitForExistence(timeout: 8))
        capture("premium-memory-explicit-online-disclosure", app); cancelReview(app)
        tap(app.buttons["coach-memories"], app); tap(row, app)
        tap(app.switches["coach-memory-online"], app)
        XCTAssertEqual(app.switches["coach-memory-online"].value as? String, "0", "Revocation must really switch off before Save")
        navTap(app.buttons["coach-memory-save"])
        XCTAssertTrue(app.staticTexts["Solo sul dispositivo"].waitForExistence(timeout: 8)); backFromMemories(app)
        // The canceled message is still in the composer; do not type a duplicate.
        tap(app.buttons["coach-send"], app)
        XCTAssertTrue(app.navigationBars["Prima dell’invio"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["coach-online-memories"].exists)
        cancelReview(app)
    }
    func testExpandingCalendarScopeRevokesPreviousConversationPermissionBeforeAnyNewSend() {
        let app = launch(["--online-coach-review-test", "--coach-scope-test"])
        enter("Vorrei organizzare lo studio", app)
        tap(app.buttons["coach-online-approve"], app)
        let counter = app.staticTexts["coach-online-fixture-requests"]
        let first = expectation(for: NSPredicate(format: "label == %@", "Richieste sintetiche: 1"), evaluatedWith: counter)
        wait(for: [first], timeout: 12)
        XCTAssertTrue(app.staticTexts["coach-online-conversation-authorized"].waitForExistence(timeout: 8))
        tap(app.buttons["coach-calendar-scope"], app)
        tap(app.buttons["Prossimi 7 giorni"], app)
        XCTAssertTrue(app.staticTexts["coach-online-conversation-authorized"].waitForNonExistence(timeout: 5))
        tap(app.buttons["coach-send"], app)
        XCTAssertTrue(app.navigationBars["Prima dell’invio"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Impegni inclusi: 2"].waitForExistence(timeout: 5))
        capture("premium-week-scope-requires-new-authorization", app)
        cancelReview(app)
        XCTAssertEqual(counter.label, "Richieste sintetiche: 1", "A wider scope needs a new review, not an automatic provider call")
    }
    func testBusyWeekRefusesWithoutSendingAndCanBeNarrowedWithoutLosingMessage() {
        let app = launch(["--online-coach-review-test", "--coach-scope-test", "--coach-scope-busy-test"])
        tap(app.buttons["coach-calendar-scope"], app)
        tap(app.buttons["Prossimi 7 giorni"], app)
        let text = "Vorrei organizzare lo studio"
        enter(text, app)
        let warning = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Troppi impegni nell’intervallo scelto")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["coach-online-fixture-requests"].label, "Richieste sintetiche: 0")
        XCTAssertFalse(app.buttons["coach-online-approve"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["coach-message-input"].value as? String, text)
        capture("premium-busy-week-refuses-with-actionable-guidance", app)
        tap(app.buttons["coach-calendar-scope"], app); tap(app.buttons["Oggi"], app)
        tap(app.buttons["coach-send"], app)
        XCTAssertTrue(app.navigationBars["Prima dell’invio"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Impegni inclusi: 1"].waitForExistence(timeout: 5))
        cancelReview(app)
        XCTAssertEqual(app.staticTexts["coach-online-fixture-requests"].label, "Richieste sintetiche: 0")
        XCTAssertEqual(app.descendants(matching: .any)["coach-message-input"].value as? String, text)
    }
    func testNamedWeekdayRecoveryOpensExactDayLocallyWithoutOnlineRequest() {
        let app = launch(["--recovery-forecast-test"])
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        let target = calendar.date(byAdding: .day, value: 3, to: Date())!
        let names = ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"]
        let name = names[calendar.component(.weekday, from: target) - 1]
        enter("Vorrei recuperare la palestra \(name) sera", app)
        XCTAssertFalse(app.buttons["coach-online-approve"].exists)
        let link = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-recovery-request-")).firstMatch
        tap(link, app)
        let day = app.staticTexts["prediction-recovery-requested-day"]
        XCTAssertTrue(day.waitForExistence(timeout: 8))
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "it_IT"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "d MMM yyyy"
        XCTAssertEqual(day.label, "Giorno richiesto: " + formatter.string(from: target))
        capture("premium-named-weekday-keeps-exact-day", app)
    }
    func testFocusedDraftSurvivesRelaunchEnrichesOneCardAndNewTopicClearsFocus() {
        let app = launch(["--online-coach-action-test", "--coach-calendar-create-test", "--conversation-continuity-test"])
        enter("Registra una attività passata, manca soltanto la fine", app)
        tap(app.buttons["coach-online-approve"], app)
        XCTAssertTrue(app.staticTexts["A che ora è finita?"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["coach-focused-draft"].waitForExistence(timeout: 8))
        app.terminate(); app.launch(); openCoach(app)
        tap(app.buttons["coach-clear-draft-focus"], app)
        XCTAssertFalse(app.staticTexts["coach-focused-draft"].exists)
        let resume = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-continue-draft-")).firstMatch
        tap(resume, app)
        navTap(app.buttons["pivot-keyboard-done"])
        XCTAssertTrue(app.staticTexts["coach-focused-draft"].exists)
        enter("È finita un’ora dopo l’inizio", app); tap(app.buttons["coach-online-approve"], app)
        XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.textFields["coach-create-title"].value as? String, "Attività passata QA")
        capture("premium-focused-draft-enriched", app)
        navTap(app.buttons["coach-create-close"])
        XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-saved-draft-")).count, 1)
        tap(app.buttons["coach-clear-draft-focus"], app)
        XCTAssertFalse(app.staticTexts["coach-focused-draft"].exists)
    }
    func testChatHandsRecoveryToRequestedDayWithoutCalendarWriteOrCloudConsent() {
        let app = launch(["--recovery-forecast-test"])
        enter("Vorrei recuperare la palestra domani sera", app)
        XCTAssertFalse(app.buttons["coach-online-approve"].exists)
        let link = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-recovery-request-")).firstMatch
        tap(link, app)
        let day = app.staticTexts["prediction-recovery-requested-day"]
        XCTAssertTrue(day.waitForExistence(timeout: 8))
        let picker = app.buttons["prediction-recovery-target"]
        XCTAssertTrue((picker.label + " " + (picker.value as? String ?? "")).contains("Allenamento QA da recuperare"))
        tap(app.switches["prediction-recovery-preparation"], app); tap(app.buttons["prediction-recovery-search"], app)
        let stage = app.buttons.matching(identifier: "prediction-recovery-stage").firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 10)); XCTAssertFalse(stage.isEnabled)
        XCTAssertFalse(app.staticTexts["Da applicare al Calendario"].exists)
        capture("premium-chat-recovery-day-and-alternatives", app)
    }
}
