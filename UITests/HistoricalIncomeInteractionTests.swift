import XCTest

final class HistoricalIncomeInteractionTests: XCTestCase {
    override func tearDownWithError() throws { attachFailureDiagnostics("historical-income"); try super.tearDownWithError() }
    func testLocalReviewCancelImportAndRelaunchKeepFundsSeparate() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--history-test"]
        app.launchEnvironment["PIVOT_QA_HISTORY_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_KEYCHAIN_ID"] = UUID().uuidString
        app.launch()
        openHistory(in: app, expectedUnassigned: "25,00")
        let load = app.buttons["history-load"]
        XCTAssertTrue(load.waitForExistence(timeout: 8)); load.tap()
        let select = app.buttons["history-select-ready"]
        XCTAssertTrue(select.waitForExistence(timeout: 8)); scrollControlIntoView(select, in: app); select.tap()
        let review = app.buttons["history-review"]
        scrollControlIntoView(review, in: app); XCTAssertTrue(review.isEnabled); review.tap()
        let confirm = app.buttons["history-confirm-import"]
        XCTAssertTrue(app.navigationBars["Conferma lo storico"].waitForExistence(timeout: 8))
        // Form virtualizes its lower rows; the disabled confirmation action
        // does not enter the AX tree until its collection is scrolled.
        scrollControlIntoView(confirm, in: app); XCTAssertFalse(confirm.isEnabled)
        app.buttons["Annulla"].tap()
        scrollControlIntoView(review, in: app); review.tap()
        let paid = app.switches["history-paid-confirmation"]
        XCTAssertTrue(paid.waitForExistence(timeout: 8)); scrollControlIntoView(paid, in: app)
        let actualSwitch = paid.switches.firstMatch
        if actualSwitch.exists { actualSwitch.tap() } else { paid.tap() }
        scrollControlIntoView(confirm, in: app); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        let result = app.staticTexts["history-message"]
        XCTAssertTrue(result.waitForExistence(timeout: 15)); XCTAssertTrue(result.label.contains("2 lezioni"))
        app.buttons["Chiudi"].tap()
        let total = app.staticTexts["income-summary-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 8)); XCTAssertTrue(total.label.contains("30,00"))
        XCTAssertFalse(app.staticTexts["income-unassigned-opening"].exists)
        let savings = app.buttons["income-page-2"]
        scrollControlIntoView(savings, in: app); savings.tap()
        let free = app.staticTexts["savings-free-total"]
        XCTAssertTrue(free.waitForExistence(timeout: 8)); XCTAssertTrue(free.label.contains("25,00"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "historical-import-keeps-funds-separate"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch(); openHistory(in: app)
        XCTAssertTrue(load.waitForExistence(timeout: 8)); load.tap()
        XCTAssertTrue(select.waitForExistence(timeout: 8)); scrollControlIntoView(select, in: app); select.tap()
        scrollControlIntoView(review, in: app); XCTAssertFalse(review.isEnabled)
    }

    private func openHistory(in app: XCUIApplication, expectedUnassigned: String? = nil) {
        let income = app.tabBars.buttons["Entrate"]
        XCTAssertTrue(income.waitForExistence(timeout: 15)); income.tap()
        XCTAssertTrue(app.navigationBars["Entrate"].waitForExistence(timeout: 8))
        if let expectedUnassigned {
            let amount = app.staticTexts["income-unassigned-opening"]
            XCTAssertTrue(amount.waitForExistence(timeout: 8)); XCTAssertTrue(amount.label.contains(expectedUnassigned))
        }
        let open = app.buttons["income-history-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 8)); scrollControlIntoView(open, in: app)
        XCTAssertTrue(open.isEnabled); open.tap()
        XCTAssertTrue(app.navigationBars["Storico dal calendario"].waitForExistence(timeout: 8),
                      "Recupera dal calendario deve aprire la schermata anche dopo il riavvio")
    }
}
