import XCTest

/// Uses only synthetic local PDF fixtures and a made-up response. It does not
/// open Share/File export, ChatGPT, credentials or the system Calendar.
final class DocumentExchangeInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        scrollControlIntoView(element, in: app, maxSwipes: 24)
        let ready = expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: element)
        wait(for: [ready], timeout: 20); element.tap()
    }
    private func openLibrary(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 20))
        tap(app.buttons["open-pivot-coach"], app); tap(app.buttons["coach-documents"], app)
    }
    private func openExchange(_ app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-review-")).firstMatch
        tap(row, app); tap(app.buttons["coach-document-exchange-open"], app)
        XCTAssertTrue(app.navigationBars["Scambio manuale"].waitForExistence(timeout: 15))
    }
    private func assertExportAvailability(_ enabled: Bool, in app: XCUIApplication) {
        let form = app.collectionViews.firstMatch
        for identifier in ["coach-exchange-save-file", "coach-exchange-share"] {
            let button = app.buttons[identifier]
            for _ in 0..<8 {
                if button.exists { break }
                form.swipeUp(velocity: .slow)
            }
            guard button.exists else { XCTFail("Export button missing: \(identifier)"); return }
            XCTAssertEqual(button.isEnabled, enabled, identifier)
        }
    }
    private func launchAndRead() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test"]
        app.launchEnvironment["PIVOT_QA_DOCUMENT_ID"] = UUID().uuidString
        app.launch(); openLibrary(app); tap(app.buttons["coach-document-import-qa"], app)
        let saved = expectation(for: NSPredicate(format: "label CONTAINS %@", "salvato senza duplicati"), evaluatedWith: app.staticTexts["coach-document-status"])
        wait(for: [saved], timeout: 30)
        let choice = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-select-")).firstMatch
        scrollControlIntoView(choice, in: app, maxSwipes: 24); tapVisibleSwitchOnce(choice, to: true, in: app)
        let field = app.descendants(matching: .any).matching(identifier: "coach-document-instruction").firstMatch
        tap(field, app); field.typeText("Elabora soltanto la pagina QA selezionata")
        tap(app.buttons["coach-document-keyboard-done"], app); tap(app.buttons["coach-document-read"], app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-review-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30)); openExchange(app)
        tap(app.buttons["coach-exchange-prepare"], app)
        XCTAssertTrue(app.textViews["coach-exchange-preview"].waitForExistence(timeout: 30))
        return app
    }
    func testExportRequiresExplicitApprovalAgainAfterRelaunchAndRequestIsDurable() {
        let app = launchAndRead()
        assertExportAvailability(false, in: app)
        let consent = app.switches["coach-exchange-approve-export"]
        let form = app.collectionViews.firstMatch
        for _ in 0..<8 {
            if consent.exists { break }
            form.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(consent.exists)
        tapVisibleSwitchOnce(consent, to: true, in: app)
        assertExportAvailability(true, in: app)
        let audit = app.staticTexts["coach-exchange-request-audit"]
        scrollControlIntoView(audit, in: app, maxSwipes: 24); let nonce = audit.label; XCTAssertFalse(nonce.isEmpty)
        app.terminate(); app.launch(); openLibrary(app); openExchange(app)
        XCTAssertTrue(app.textViews["coach-exchange-preview"].waitForExistence(timeout: 30))
        assertExportAvailability(false, in: app)
        scrollControlIntoView(app.staticTexts["coach-exchange-request-audit"], in: app, maxSwipes: 24)
        XCTAssertEqual(app.staticTexts["coach-exchange-request-audit"].label, nonce)
    }
    func testInvalidReplyKeepsOriginalAndSyntheticValidReplyOnlyAddsAReview() {
        let app = launchAndRead()
        let field = app.textViews["coach-exchange-reply"]
        tap(field, app); field.typeText("{\"version\":1}")
        tap(app.buttons["coach-exchange-keyboard-done"], app); tap(app.buttons["coach-exchange-import-text"], app)
        let error = expectation(for: NSPredicate(format: "label CONTAINS[c] %@", "risposta"), evaluatedWith: app.staticTexts["coach-exchange-status"])
        wait(for: [error], timeout: 20)
        XCTAssertEqual(app.staticTexts["coach-exchange-revisions-audit"].label, "1 revisioni QA")
        tap(app.buttons["coach-exchange-synthetic-reply"], app)
        let result = app.buttons["coach-exchange-open-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 30)); tap(result, app)
        XCTAssertEqual(app.staticTexts["coach-document-review-audit"].label, "1 proposte · 0 bozze preparate")
        XCTAssertFalse(app.alerts["Creare questo impegno nel Calendario?"].exists)
        app.terminate(); app.launch(); openLibrary(app)
        let reviews = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-review-"))
        scrollControlIntoView(reviews.element(boundBy: 1), in: app, maxSwipes: 24)
        XCTAssertEqual(reviews.count, 2)
    }
}
