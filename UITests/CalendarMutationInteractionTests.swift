import XCTest

/// Synthetic EventKit boundary and provider. Exercises the real confirmation,
/// disk persistence, archive and mapping paths, not live calendar/model quality.
final class CalendarMutationInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    private func launch(continuity: Bool = false, archiveFailure: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-action-test", "--coach-calendar-create-test",
                               continuity ? "--conversation-continuity-test" : "--calendar-mutations-test"]
        if archiveFailure { app.launchArguments.append("--calendar-archive-write-failure-test") }
        app.launchEnvironment["PIVOT_QA_COACH_ACTION_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_KEYCHAIN_ID"] = UUID().uuidString
        app.launch(); openCoach(app); return app
    }
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        // Form virtualizes rows below the viewport: waiting for their AX
        // existence before scrolling never materializes the review button.
        _ = element.waitForExistence(timeout: 2)
        scrollControlIntoView(element, in: app, maxSwipes: 20)
        XCTAssertTrue(element.exists); XCTAssertTrue(element.isEnabled); element.tap()
    }
    private func tapNavigation(_ element: XCUIElement, _ app: XCUIApplication) {
        // A fixed navigation control is outside the scroll-content viewport.
        // Check its real screen bounds and hittability, without swiping the Form.
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        XCTAssertTrue(app.frame.contains(element.frame)); XCTAssertTrue(element.isHittable)
        XCTAssertTrue(element.isEnabled); element.tap()
    }
    private func openCoach(_ app: XCUIApplication) { tap(app.buttons["open-pivot-coach"], app) }
    private func send(_ text: String, _ app: XCUIApplication, authorize: Bool = true) {
        let input = app.descendants(matching: .any)["coach-message-input"]
        tap(input, app); input.typeText(text)
        let done = app.buttons["pivot-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons.matching(identifier: "pivot-keyboard-done").count, 1); done.tap()
        tap(app.buttons["coach-send"], app)
        if authorize { tap(app.buttons["coach-online-approve"], app) }
    }
    private func batch(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-calendar-batch-")).firstMatch
    }
    private func audit(_ count: Int, _ app: XCUIApplication) -> String {
        tap(app.buttons["calendar-mutation-audit"], app)
        let result = app.staticTexts["calendar-mutation-audit-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("\(count) eventi"), result.label)
        XCTAssertTrue(result.label.contains("1 attività · 1 incassi · 500 ricevuti · 500 da incassare"), result.label)
        return result.label
    }
    private func confirmBatch(_ app: XCUIApplication, cancelFirst: Bool = false) {
        let review = app.buttons["coach-mutations-review"]
        tap(review, app)
        let alert = app.alerts["Confermare le modifiche selezionate?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        if cancelFirst {
            alert.buttons["Annulla"].tap()
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
            tapNavigation(app.navigationBars["Modifiche proposte"].buttons["Chiudi"], app)
            _ = audit(2, app)
            tap(batch(app), app); tap(review, app)
        }
        let confirm = alert.buttons.matching(identifier: "coach-mutations-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8)); confirm.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Revisione conclusa.")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["coach-mutations-error"].exists)
    }
    private func restoreFirst(_ app: XCUIApplication) {
        tap(app.buttons["Storico modifiche"], app)
        let restore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "calendar-history-restore-")).firstMatch
        tap(restore, app)
        let confirm = app.buttons.matching(identifier: "calendar-history-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8)); XCTAssertTrue(confirm.isHittable); confirm.tap()
        let result = app.staticTexts["calendar-history-message"]
        XCTAssertTrue(result.waitForExistence(timeout: 15)); XCTAssertTrue(result.label.contains("Modifica annullata"), result.label)
        tapNavigation(app.navigationBars["Storico modifiche"].buttons.element(boundBy: 0), app)
        tapNavigation(app.navigationBars["Modifiche proposte"].buttons["Chiudi"], app)
    }
    func testDeletePreviewCancelAndSingleRestoreKeepMoneyAfterRelaunch() {
        let app = launch(); _ = audit(2, app)
        send("Cancella i due impegni QA di oggi", app)
        tap(batch(app), app); confirmBatch(app, cancelFirst: true)
        tapNavigation(app.navigationBars["Modifiche proposte"].buttons["Chiudi"], app)
        _ = audit(0, app)
        tap(batch(app), app); restoreFirst(app)
        _ = audit(1, app)
        app.terminate(); app.launch(); openCoach(app); _ = audit(1, app)
        tap(app.buttons["coach-calendar-history"], app)
        XCTAssertTrue(app.staticTexts["Modifica annullata"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "calendar-history-restore-")).count, 1)
    }
    func testOriginalArchiveWriteFailurePreventsExternalDeletion() {
        let app = launch(archiveFailure: true)
        send("Cancella i due impegni QA di oggi", app)
        tap(batch(app), app); tap(app.buttons["coach-mutations-review"], app)
        let alert = app.alerts["Confermare le modifiche selezionate?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8)); alert.buttons.matching(identifier: "coach-mutations-confirm").firstMatch.tap()
        let storageAlert = app.alerts["Pivot"]
        if storageAlert.waitForExistence(timeout: 5) { storageAlert.buttons["OK"].tap() }
        let error = app.staticTexts["coach-mutations-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 15)); XCTAssertTrue(error.label.contains("non è salvata su disco"), error.label)
        tapNavigation(app.navigationBars["Modifiche proposte"].buttons["Chiudi"], app)
        _ = audit(2, app)
        app.terminate(); app.launch(); openCoach(app); _ = audit(2, app)
    }
    func testTitleUpdateAndUndoLeaveOtherEventAndReceiptsUntouched() {
        let app = launch()
        send("Modifica il titolo del primo impegno QA", app)
        tap(batch(app), app)
        XCTAssertTrue(app.staticTexts["Impegno QA modificato"].waitForExistence(timeout: 8))
        confirmBatch(app)
        tapNavigation(app.navigationBars["Modifiche proposte"].buttons["Chiudi"], app)
        XCTAssertTrue(audit(2, app).contains("Impegno QA modificato"))
        app.terminate(); app.launch(); openCoach(app)
        XCTAssertTrue(audit(2, app).contains("Impegno QA modificato"))
        tap(batch(app), app); restoreFirst(app)
        XCTAssertFalse(audit(2, app).contains("Impegno QA modificato"))
        app.terminate(); app.launch(); openCoach(app)
        XCTAssertFalse(audit(2, app).contains("Impegno QA modificato"))
    }
    func testPartialConversationSurvivesRelaunchAndCreatesPastEventOnlyAfterConfirmation() {
        let app = launch(continuity: true)
        send(String(repeating: "Premessa della richiesta. ", count: 20) + "Registra la mia attività già terminata, manca soltanto l’ora di fine.", app)
        XCTAssertTrue(app.staticTexts["A che ora è finita?"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.navigationBars["Nuovo impegno"].exists)
        app.terminate(); app.launch(); openCoach(app)
        send("È finita un’ora dopo l’inizio, usa titolo e nota che ti avevo già detto.", app)
        XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.textFields["coach-create-title"].value as? String, "Attività passata QA")
        tap(app.buttons["coach-create-review"], app)
        let alert = app.alerts["Creare questo impegno nel Calendario?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "evento nel passato")).firstMatch.exists)
        let create = alert.buttons.matching(identifier: "coach-create-confirm").firstMatch
        XCTAssertTrue(create.isEnabled); create.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Impegno creato nel Calendario: Attività passata QA")).firstMatch.waitForExistence(timeout: 12))
    }
}
