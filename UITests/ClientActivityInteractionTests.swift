import XCTest

final class ClientActivityInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    func testFutureAppointmentBlocksManualOffAndInactiveHistoryCanBeReactivated() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--financial-corrections-test", "--contact-activity-test"]
        app.launchEnvironment["PIVOT_QA_FINANCE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Entrate"].waitForExistence(timeout: 15)); app.tabBars.buttons["Entrate"].tap()
        let active = app.buttons["client-detail-55555555-5555-4555-8555-555555555551"]
        scrollControlIntoView(active, in: app); active.tap()
        let toggle = app.switches["client-active-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8)); scrollControlIntoView(toggle, in: app); toggle.tap()
        let warning = app.alerts["Contatto ancora attivo"]
        XCTAssertTrue(warning.waitForExistence(timeout: 15))
        XCTAssertTrue(warning.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Lezione Contatto Attivo QA")).firstMatch.exists)
        warning.buttons["Va bene"].tap(); XCTAssertEqual(toggle.value as? String, "1")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let inactiveMenu = app.buttons["income-inactive-contacts"]
        scrollControlIntoView(inactiveMenu, in: app); XCTAssertEqual(inactiveMenu.value as? String, "Chiuso")
        inactiveMenu.tap()
        let inactive = app.buttons["client-detail-55555555-5555-4555-8555-555555555552"]
        scrollControlIntoView(inactive, in: app); inactive.tap()
        XCTAssertTrue(app.staticTexts["student-balance-total"].waitForExistence(timeout: 8))
        assertOutstandingBalance(app)
        scrollControlIntoView(toggle, in: app); XCTAssertEqual(toggle.value as? String, "0"); toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Entrate"].waitForExistence(timeout: 15)); app.tabBars.buttons["Entrate"].tap()
        scrollControlIntoView(inactive, in: app); inactive.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        assertOutstandingBalance(app)
    }
    private func assertOutstandingBalance(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // Currency formatting correctly uses a nonbreaking space on iOS.
        // Normalize that separator only, retaining the exact contact/amount.
        let label = app.staticTexts["student-balance-total"].label
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(label, "Saldo totale di Contatto Inattivo QA: 5,00 €", file: file, line: line)
    }
}
