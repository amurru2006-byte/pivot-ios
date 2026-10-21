import XCTest

final class PredictionInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    func testRecoveryAlternativesRequireReviewAndStayPendingBeforeCalendarConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--recovery-forecast-test"]
        app.launchEnvironment["PIVOT_QA_RECOVERY_ID"] = UUID().uuidString
        app.launch()
        let coach = app.buttons["open-pivot-coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: 15)); tap(coach, app)
        tap(app.buttons["coach-predictions"], app); tap(app.buttons["prediction-recovery"], app)
        let activity = app.buttons["prediction-recovery-target"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5)); tap(activity, app)
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Allenamento QA da recuperare")).firstMatch, app)
        tap(app.switches["prediction-recovery-preparation"], app)
        tap(app.buttons["prediction-recovery-search"], app)
        let stage = app.buttons.matching(identifier: "prediction-recovery-stage").firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 8)); XCTAssertFalse(stage.isEnabled)
        screenshot("recovery-alternatives-before-review", app)
        let review = app.switches.matching(identifier: "prediction-recovery-review").firstMatch
        tap(review, app); XCTAssertTrue(stage.isEnabled); tap(stage, app)
        XCTAssertTrue(app.staticTexts["prediction-recovery-message"].label.contains("Il Calendario non è ancora cambiato"))
        tap(app.buttons["prediction-recovery-open-coach"], app)
        XCTAssertTrue(app.staticTexts["Da applicare al Calendario"].waitForExistence(timeout: 5))
        // Do not tap the final Calendar write: only the pending draft is tested.
        app.terminate(); app.launch()
        XCTAssertTrue(coach.waitForExistence(timeout: 15)); tap(coach, app)
        XCTAssertTrue(app.staticTexts["Da applicare al Calendario"].waitForExistence(timeout: 5))
    }
    func testSavingsScenarioChangesOnlyThePreviewAndRejectsUnavailableFunds() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--savings-test"]
        app.launchEnvironment["PIVOT_QA_SAVINGS_ID"] = UUID().uuidString
        app.launch()
        let income = app.tabBars.buttons["Entrate"]
        XCTAssertTrue(income.waitForExistence(timeout: 15)); income.tap()
        tap(app.buttons["income-page-2"], app)
        tap(app.buttons["savings-create-goal"], app)
        let name = app.textFields["savings-goal-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Obiettivo QA")
        let target = app.textFields["savings-goal-target"]; target.tap(); target.typeText("900")
        dismissKeyboard(app); tap(app.buttons["savings-goal-save"], app)
        XCTAssertTrue(app.staticTexts["savings-reserved-total"].label.contains("0,00"))
        tap(app.buttons["savings-forecast"], app)
        let upfront = app.textFields["forecast-upfront"]
        XCTAssertTrue(upfront.waitForExistence(timeout: 5)); upfront.tap(); upfront.typeText("100")
        // The decimal keyboard toolbar can overlap this next row on a compact
        // screen. Use the visible Done action before scrolling to its field;
        // never type into a control that did not receive keyboard focus.
        dismissKeyboard(app)
        let weekly = app.textFields["forecast-weekly"]; tap(weekly, app); weekly.typeText("50")
        dismissKeyboard(app)
        XCTAssertTrue(app.staticTexts["forecast-remaining"].label.contains("800,00"))
        XCTAssertTrue(app.staticTexts["forecast-completion"].label.contains("16 settimane"))
        screenshot("savings-forecast-no-money-moved", app)
        tap(upfront, app); upfront.typeText("0"); dismissKeyboard(app)
        XCTAssertTrue(app.staticTexts["forecast-error"].waitForExistence(timeout: 5))
        app.navigationBars["Scenario Salvadanaio"].buttons["Chiudi"].tap()
        XCTAssertTrue(app.staticTexts["savings-reserved-total"].label.contains("0,00"))
        XCTAssertTrue(app.staticTexts["savings-free-total"].label.contains("350,00"))
    }
    func testWorkoutForecastIsCapturedAtStartAndPersistsWithoutInventedLegacyFeedback() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--training-forecast-test"]
        app.launchEnvironment["PIVOT_QA_FORECAST_ID"] = UUID().uuidString
        app.launch()
        let gym = app.tabBars.buttons["Palestra"]
        XCTAssertTrue(gym.waitForExistence(timeout: 15)); gym.tap()
        tap(app.buttons["forecast-fixture"], app)
        XCTAssertTrue(app.staticTexts["Previsioni pronte"].waitForExistence(timeout: 8))
        tap(app.buttons["workout-day-forecast-day"], app)
        let forecast = app.staticTexts["training-duration-prediction"]
        XCTAssertTrue(forecast.waitForExistence(timeout: 8)); XCTAssertTrue(forecast.label.contains("75 min"))
        XCTAssertTrue(app.staticTexts["training-duration-band"].label.contains("3 sedute"))
        screenshot("workout-personal-duration-band", app)
        tap(app.buttons["Inizia allenamento"], app)
        XCTAssertTrue(app.staticTexts["Allenamento in corso"].waitForExistence(timeout: 8))
        app.navigationBars["Allenamento"].buttons.element(boundBy: 0).tap()
        tap(app.buttons["forecast-verify"], app)
        XCTAssertTrue(app.staticTexts["Previsione verificata · nessuno storico inventato"].waitForExistence(timeout: 8))
        app.terminate(); app.launch()
        XCTAssertTrue(gym.waitForExistence(timeout: 15)); gym.tap()
        tap(app.buttons["forecast-verify"], app)
        XCTAssertTrue(app.staticTexts["Previsione verificata · nessuno storico inventato"].waitForExistence(timeout: 8))
        tap(app.buttons["workout-day-forecast-day"], app)
        XCTAssertTrue(app.staticTexts["Allenamento in corso"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["training-duration-prediction"].exists)
    }
    func testMapsRequiresExplicitConsentSelectsPlacesAndRevokesWithoutNetwork() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--travel-estimate-test"]
        app.launchEnvironment["PIVOT_QA_TRAVEL_ID"] = UUID().uuidString
        app.launch()
        openTravel(app)
        XCTAssertTrue(app.buttons["travel-consent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["travel-origin"].exists)
        XCTAssertTrue(app.staticTexts["travel-test-count"].label.contains("0"))
        tap(app.buttons["travel-consent"], app)
        let origin = app.textFields["travel-origin"]
        XCTAssertTrue(origin.waitForExistence(timeout: 5)); tap(origin, app); origin.typeText("Partenza QA")
        dismissKeyboard(app)
        tap(app.buttons["travel-search-origin"], app)
        let choice = app.buttons["travel-place-origin-Luogo QA A"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); tap(choice, app)
        let destination = app.textFields["travel-destination"]
        tap(destination, app); destination.typeText("Arrivo QA"); dismissKeyboard(app)
        tap(app.buttons["travel-search-destination"], app)
        let other = app.buttons["travel-place-destination-Luogo QA B"]
        XCTAssertTrue(other.waitForExistence(timeout: 5)); tap(other, app)
        tap(app.buttons["travel-calculate"], app)
        let result = app.staticTexts["travel-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); XCTAssertTrue(result.label.contains("20 min"))
        XCTAssertTrue(app.staticTexts["travel-test-count"].label.contains("3"))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "maps-synthetic-estimate"; screenshot.lifetime = .keepAlways; add(screenshot)
        tap(app.buttons["travel-revoke"], app)
        XCTAssertFalse(result.exists); XCTAssertFalse(app.textFields["travel-origin"].exists)
        XCTAssertTrue(app.buttons["travel-consent"].exists)
        app.terminate(); app.launch(); openTravel(app)
        XCTAssertTrue(app.buttons["travel-consent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["travel-test-count"].label.contains("0"))
    }
    private func openTravel(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["Impostazioni"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
        tap(app.buttons["settings-travel"], app)
    }
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        scrollControlIntoView(element, in: app); element.tap()
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        let done = app.buttons["Fine"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Fine")).count, 1, "Only the visible screen owns a keyboard toolbar")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
}
