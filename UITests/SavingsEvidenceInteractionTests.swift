import XCTest

final class SavingsEvidenceInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        scrollControlIntoView(element, in: app); XCTAssertTrue(element.isEnabled); element.tap()
    }
    private func enable(_ id: String, _ app: XCUIApplication) {
        let control = app.switches[id]
        scrollControlIntoView(control, in: app)
        XCTAssertEqual(control.value as? String, "0")
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let enabled = expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: control)
        wait(for: [enabled], timeout: 5)
    }
    private func open(seeded: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--savings-test"] + (seeded ? ["--savings-evidence-test"] : [])
        app.launchEnvironment["PIVOT_QA_SAVINGS_ID"] = UUID().uuidString
        app.launch()
        let income = app.tabBars.buttons["Entrate"]
        XCTAssertTrue(income.waitForExistence(timeout: 15)); income.tap()
        tap(app.buttons["income-page-2"], app); tap(app.buttons["savings-create-goal"], app)
        let name = app.textFields["savings-goal-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Obiettivo prova locale")
        let target = app.textFields["savings-goal-target"]; target.tap(); target.typeText("900")
        app.buttons["Fine"].tap(); tap(app.buttons["savings-goal-save"], app)
        tap(app.buttons["savings-forecast"], app); tap(app.buttons["forecast-evidence-open"], app)
        XCTAssertTrue(app.navigationBars["Stima dai guadagni"].waitForExistence(timeout: 8))
        return app
    }
    func testMissingCoverageAndEmptyHistoryCannotInventAWeeklySavingOrDate() {
        let app = open(seeded: false)
        let error = app.staticTexts["evidence-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8)); XCTAssertTrue(error.label.contains("Conferma prima"))
        XCTAssertFalse(app.buttons["evidence-confirm"].isEnabled)
        enable("evidence-activities", app); enable("evidence-receipts", app); enable("evidence-expenses", app)
        tap(app.buttons["evidence-confirm"], app)
        XCTAssertFalse(app.staticTexts["evidence-completion"].exists)
        XCTAssertTrue(app.staticTexts["evidence-earned-weekly"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["evidence-saving-weekly"].label.contains("0,00"))
        XCTAssertTrue(app.staticTexts["evidence-no-date"].exists)
        app.navigationBars["Stima dai guadagni"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Scenario Salvadanaio"].buttons["Chiudi"].tap()
        XCTAssertTrue(app.staticTexts["savings-free-total"].label.contains("350,00"))
        XCTAssertTrue(app.staticTexts["savings-reserved-total"].label.contains("0,00"))
    }
    func testObservedCashLessAggregateExpensesCreatesOnlyAPreviewAndNoNewMoney() {
        let app = open(seeded: true)
        enable("evidence-activities", app); enable("evidence-receipts", app); enable("evidence-expenses", app)
        tap(app.buttons["evidence-confirm"], app)
        let saving = app.staticTexts["evidence-saving-weekly"]
        XCTAssertTrue(saving.waitForExistence(timeout: 15)); XCTAssertTrue(saving.label.contains("80,00"))
        XCTAssertTrue(app.staticTexts["evidence-earned-weekly"].label.contains("100,00"))
        XCTAssertTrue(app.staticTexts["evidence-completion"].waitForExistence(timeout: 8))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "savings-evidence-local-no-money-moved"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.navigationBars["Stima dai guadagni"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Scenario Salvadanaio"].buttons["Chiudi"].tap()
        XCTAssertTrue(app.staticTexts["savings-free-total"].label.contains("1.630,00"))
        XCTAssertTrue(app.staticTexts["savings-reserved-total"].label.contains("0,00"))
    }
}
