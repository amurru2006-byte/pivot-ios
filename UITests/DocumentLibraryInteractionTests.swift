import XCTest

final class DocumentLibraryInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test"]
        app.launchEnvironment["PIVOT_QA_DOCUMENT_ID"] = UUID().uuidString
        app.launch(); open(app); return app
    }
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        scrollControlIntoView(element, in: app, maxSwipes: 20)
        let ready = expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: element)
        wait(for: [ready], timeout: 20); element.tap()
    }
    private func open(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 20))
        tap(app.buttons["open-pivot-coach"], app); tap(app.buttons["coach-documents"], app)
        XCTAssertTrue(app.navigationBars["Foto e documenti"].waitForExistence(timeout: 10))
    }
    private func status(_ app: XCUIApplication, contains text: String) {
        let element = app.staticTexts["coach-document-status"]
        scrollControlIntoView(element, in: app, maxSwipes: 20)
        let finished = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        wait(for: [finished], timeout: 30)
    }
    func testImportSurvivesRelaunchAndReimportKeepsOneVerifiedSource() {
        let app = launch(); tap(app.buttons["coach-document-import-qa"], app)
        status(app, contains: "salvato senza duplicati")
        app.terminate(); app.launch(); open(app)
        XCTAssertEqual(app.staticTexts["coach-document-library-audit"].label, "1 fonti salvate")
        tap(app.buttons["coach-document-import-qa"], app); status(app, contains: "salvato senza duplicati")
        scrollControlIntoView(app.staticTexts["coach-document-library-audit"], in: app, maxSwipes: 20)
        XCTAssertEqual(app.staticTexts["coach-document-library-audit"].label, "1 fonti salvate")
        tap(app.buttons["Apri originale"], app)
        XCTAssertTrue(app.navigationBars["Documento QA.pdf"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Fonte non disponibile"].exists)
    }
    func testForgedMetadataIsRejectedWithoutRegisteringAnySource() {
        let app = launch(); tap(app.buttons["coach-document-invalid-qa"], app)
        status(app, contains: "interrotta")
        scrollControlIntoView(app.staticTexts["coach-document-library-audit"], in: app, maxSwipes: 20)
        XCTAssertEqual(app.staticTexts["coach-document-library-audit"].label, "0 fonti salvate")
        app.terminate(); app.launch(); open(app)
        XCTAssertEqual(app.staticTexts["coach-document-library-audit"].label, "0 fonti salvate")
    }
    func testSelectedPageReadingRemainsLocalAndDoesNotIncludeAnotherPage() {
        let app = launch(); tap(app.buttons["coach-document-import-qa"], app)
        status(app, contains: "salvato senza duplicati")
        let choice = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-select-")).firstMatch
        scrollControlIntoView(choice, in: app, maxSwipes: 20); tapVisibleSwitchOnce(choice, to: true, in: app)
        let field = app.descendants(matching: .any).matching(identifier: "coach-document-instruction").firstMatch
        tap(field, app); field.typeText("Mostra gli impegni nella pagina selezionata")
        tap(app.buttons["coach-document-keyboard-done"], app)
        tap(app.buttons["coach-document-read"], app)
        let heading = app.staticTexts["Controlla la lettura"]
        scrollControlIntoView(heading, in: app, maxSwipes: 20)
        XCTAssertTrue(heading.waitForExistence(timeout: 30))
        let page = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pagina 1 · Testo PDF")).firstMatch
        tap(page, app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "LABORATORY QA")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "SECOND PAGE QA")).firstMatch.exists)
        XCTAssertFalse(app.alerts["Creare questo impegno nel Calendario?"].exists)
    }
}
