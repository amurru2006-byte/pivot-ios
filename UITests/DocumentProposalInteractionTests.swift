import XCTest

/// Synthetic local sources and database only; these tests never confirm an
/// EventKit operation, authenticate to an AI service or use a real document.
final class DocumentProposalInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        scrollControlIntoView(element, in: app, maxSwipes: 24)
        let ready = expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: element)
        wait(for: [ready], timeout: 20); element.tap()
    }
    private func openLibrary(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 20))
        tap(app.buttons["open-pivot-coach"], app); tap(app.buttons["coach-documents"], app)
        XCTAssertTrue(app.navigationBars["Foto e documenti"].waitForExistence(timeout: 15))
    }
    private func openReview(_ app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-review-")).firstMatch
        tap(row, app)
        XCTAssertTrue(app.navigationBars["Proposte da documenti"].waitForExistence(timeout: 15))
    }
    private func launchAndRead(timed: Bool = false, pages: String = "1-2") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test"] + (timed ? ["--document-timed-test"] : [])
        app.launchEnvironment["PIVOT_QA_DOCUMENT_ID"] = UUID().uuidString
        app.launch(); openLibrary(app)
        tap(app.buttons["coach-document-import-qa"], app)
        let finished = expectation(for: NSPredicate(format: "label CONTAINS %@", "salvato senza duplicati"), evaluatedWith: app.staticTexts["coach-document-status"])
        wait(for: [finished], timeout: 30)
        let select = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-select-")).firstMatch
        scrollControlIntoView(select, in: app, maxSwipes: 24); tapVisibleSwitchOnce(select, to: true, in: app)
        let pageField = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-pages-")).firstMatch
        tap(pageField, app); pageField.typeText(XCUIKeyboardKey.delete.rawValue + pages)
        let instruction = app.descendants(matching: .any).matching(identifier: "coach-document-instruction").firstMatch
        tap(instruction, app); instruction.typeText("Prepara le esperienze QA dalle pagine selezionate")
        tap(app.buttons["coach-document-keyboard-done"], app); tap(app.buttons["coach-document-read"], app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-review-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30)); openReview(app)
        return app
    }
    func testSavedReadingAndSeparateAllDayProposalsSurviveRelaunchWithoutStaging() {
        let app = launchAndRead()
        XCTAssertEqual(app.staticTexts["coach-document-review-audit"].label, "2 proposte · 0 bozze preparate")
        XCTAssertTrue(app.staticTexts["Tutto il giorno · 2030-01-14"].exists)
        XCTAssertTrue(app.staticTexts["Tutto il giorno · 2030-01-15"].exists)
        XCTAssertFalse(app.buttons["coach-document-stage"].isEnabled)
        app.terminate(); app.launch(); openLibrary(app); openReview(app)
        XCTAssertEqual(app.staticTexts["coach-document-review-audit"].label, "2 proposte · 0 bozze preparate")
        XCTAssertEqual(app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-proposal-select-")).count, 2)
    }
    func testSelectedBatchCreatesOnlyDurableLocalDraftsAndOffersNoSecondStaging() {
        let app = launchAndRead()
        let selectors = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-proposal-select-"))
        XCTAssertEqual(selectors.count, 2)
        for index in 0..<2 {
            scrollControlIntoView(selectors.element(boundBy: index), in: app, maxSwipes: 24)
            tapVisibleSwitchOnce(selectors.element(boundBy: index), to: true, in: app)
        }
        tap(app.buttons["coach-document-stage"], app)
        let saved = expectation(for: NSPredicate(format: "label CONTAINS %@", "2 bozze salvate in Pivot"), evaluatedWith: app.staticTexts["coach-document-review-status"])
        wait(for: [saved], timeout: 30)
        XCTAssertFalse(app.alerts["Creare questo impegno nel Calendario?"].exists)
        app.terminate(); app.launch(); openLibrary(app); openReview(app)
        XCTAssertEqual(app.staticTexts["coach-document-review-audit"].label, "2 proposte · 2 bozze preparate")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-open-draft-")).count, 2)
        XCTAssertEqual(selectors.count, 0)
        XCTAssertFalse(app.buttons["coach-document-stage"].isEnabled)
    }
    func testTimedProposalKeepsTimeZoneQuestionAndCannotStageWithoutClarification() {
        let app = launchAndRead(timed: true, pages: "1")
        XCTAssertEqual(app.staticTexts["coach-document-review-audit"].label, "1 proposte · 0 bozze preparate")
        let choice = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coach-document-proposal-select-")).firstMatch
        XCTAssertTrue(choice.exists); XCTAssertFalse(choice.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Europe/Rome")).firstMatch.exists)
        app.terminate(); app.launch(); openLibrary(app); openReview(app)
        XCTAssertFalse(choice.isEnabled)
        XCTAssertEqual(app.staticTexts["coach-document-review-audit"].label, "1 proposte · 0 bozze preparate")
    }
}
