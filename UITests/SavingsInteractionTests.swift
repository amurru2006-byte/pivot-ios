import XCTest

final class SavingsInteractionTests: XCTestCase {
    override func tearDownWithError() throws { attachFailureDiagnostics("savings"); try super.tearDownWithError() }
    func testWeeklyPlanIsOptInPersistsAndDeletionKeepsGoalAndMoneyWithEmptySimulationFields() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--savings-test"]
        app.launchEnvironment["PIVOT_QA_SAVINGS_ID"] = UUID().uuidString
        app.launch(); openSavings(in: app)
        func tap(_ id: String) { let button = app.buttons[id]; scrollControlIntoView(button, in: app); button.tap() }
        tap("savings-create-goal")
        let name = app.textFields["savings-goal-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8)); name.tap(); name.typeText("Piano settimanale QA")
        let target = app.textFields["savings-goal-target"]; target.tap(); target.typeText("900")
        finishKeyboard(in: app); tap("savings-goal-save")
        tap("savings-forecast")
        let upfront = app.textFields["forecast-upfront"], weekly = app.textFields["forecast-weekly"]
        XCTAssertEqual(upfront.value as? String, upfront.placeholderValue)
        XCTAssertEqual(weekly.value as? String, weekly.placeholderValue)
        app.navigationBars["Scenario Salvadanaio"].buttons["Chiudi"].tap()
        tap("savings-weekly-open")
        let automatic = app.switches["weekly-automatic"]
        XCTAssertEqual(automatic.value as? String, "0"); XCTAssertFalse(app.buttons["weekly-delete"].exists)
        tap("weekly-save")
        XCTAssertTrue(app.staticTexts["weekly-next"].waitForExistence(timeout: 8))
        scrollControlIntoView(automatic, in: app)
        let native = automatic.switches.firstMatch
        if native.exists { native.tap() } else { automatic.tap() }
        XCTAssertEqual(automatic.value as? String, "1"); tap("weekly-save")
        app.buttons["Chiudi"].tap()
        XCTAssertTrue(app.staticTexts["savings-reserved-total"].label.contains("0,00"))
        XCTAssertTrue(app.staticTexts["savings-free-total"].label.contains("350,00"))
        app.terminate(); app.launch(); openSavings(in: app); tap("savings-weekly-open")
        XCTAssertEqual(app.switches["weekly-automatic"].value as? String, "1")
        tap("weekly-delete")
        let alert = app.alerts["Eliminare il piano?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Annulla"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["weekly-delete"].exists)
        tap("weekly-delete")
        // The alert exposes a wrapper and native button with the same bounds,
        // identifier and action. This is one visible destructive control.
        alert.buttons.matching(identifier: "weekly-delete-confirm").firstMatch.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["savings-weekly-open"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["savings-reserved-total"].label.contains("0,00"))
        XCTAssertTrue(app.staticTexts["savings-free-total"].label.contains("350,00"))
        tap("savings-weekly-open")
        XCTAssertEqual(app.switches["weekly-automatic"].value as? String, "0")
        XCTAssertFalse(app.buttons["weekly-delete"].exists)
    }
    func testGoalReservationLimitRealExpenseReleaseAndRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--savings-test"]
        app.launchEnvironment["PIVOT_QA_SAVINGS_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_KEYCHAIN_ID"] = UUID().uuidString
        app.launch()
        openSavings(in: app)
        let create = app.buttons["savings-create-goal"]
        XCTAssertTrue(create.waitForExistence(timeout: 8)); scrollControlIntoView(create, in: app); create.tap()
        let name = app.textFields["savings-goal-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8)); name.tap(); name.typeText("Obiettivo di prova")
        let target = app.textFields["savings-goal-target"]; target.tap(); target.typeText("1000")
        finishKeyboard(in: app)
        let saveGoal = app.buttons["savings-goal-save"]
        scrollControlIntoView(saveGoal, in: app); saveGoal.tap()
        move("300", button: "savings-reserve", in: app)
        XCTAssertTrue(app.staticTexts["savings-reserved-total"].label.contains("300,00"))
        XCTAssertTrue(app.staticTexts["savings-free-total"].label.contains("50,00"))
        move("100", button: "savings-reserve", in: app)
        XCTAssertTrue(app.staticTexts["savings-movement-error"].waitForExistence(timeout: 8))
        app.buttons["Annulla"].tap()
        XCTAssertTrue(app.staticTexts["savings-reserved-total"].label.contains("300,00"))
        move("75", button: "savings-expense", in: app)
        XCTAssertTrue(app.staticTexts["savings-shortfall"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["savings-shortfall"].label.contains("25,00"))
        move("50", button: "savings-release", in: app)
        XCTAssertTrue(app.staticTexts["savings-reserved-total"].label.contains("250,00"))
        XCTAssertTrue(app.staticTexts["savings-free-total"].label.contains("25,00"))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "savings-orange-card-and-accounting"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch(); openSavings(in: app)
        XCTAssertTrue(app.staticTexts["savings-reserved-total"].label.contains("250,00"))
    }

    private func openSavings(in app: XCUIApplication) {
        let income = app.tabBars.buttons["Entrate"]
        XCTAssertTrue(income.waitForExistence(timeout: 15)); income.tap()
        let page = app.buttons["income-page-2"]
        XCTAssertTrue(page.waitForExistence(timeout: 8)); scrollControlIntoView(page, in: app); page.tap()
        XCTAssertTrue(page.isSelected)
    }
    private func finishKeyboard(in app: XCUIApplication) {
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
    }
    private func move(_ amount: String, button identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 8)); scrollControlIntoView(button, in: app); button.tap()
        let input = app.textFields["savings-movement-amount"]
        XCTAssertTrue(input.waitForExistence(timeout: 8)); input.tap(); input.typeText(amount)
        finishKeyboard(in: app)
        let save = app.buttons["savings-movement-save"]
        scrollControlIntoView(save, in: app); save.tap()
        // Wait for the usable destination, not a cached AX handle to a button
        // reused by successive sheets. A failed save leaves the sheet in front
        // and the root action/nav bar cannot be interacted with. Exact balances
        // and relaunch persistence are asserted by the caller after this wait.
        if !(identifier == "savings-reserve" && amount == "100") {
            let returned = expectation(for: NSPredicate { _, _ in
                guard button.exists, button.frame.height > 0 else { return false }
                return button.isHittable && app.navigationBars["Entrate"].isHittable
            }, evaluatedWith: app)
            wait(for: [returned], timeout: 8)
        }
    }
}
