import XCTest

final class PredictionInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
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
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        scrollControlIntoView(element, in: app); element.tap()
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        let done = app.buttons["Fine"]
        if done.waitForExistence(timeout: 2) { done.tap() }
    }
}
