import XCTest

final class WorkoutRestAudioInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    func testOptInSingleAlarmManualStopRearmDisableAndPersistenceWithoutRealAudio() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--rest-alarm-test"]
        app.launchEnvironment["PIVOT_QA_REST_ID"] = UUID().uuidString
        app.launch()
        openAudio(app)
        let enable = app.buttons["rest-audio-enable"], count = app.staticTexts["rest-audio-test-count"]
        XCTAssertTrue(enable.waitForExistence(timeout: 8)); XCTAssertEqual(count.label, "Allarmi sintetici: 0")
        scrollControlIntoView(enable, in: app); enable.tap()
        XCTAssertTrue(app.staticTexts["rest-audio-enabled"].waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "Allarmi sintetici: 1")
        let stop = app.buttons.matching(identifier: "rest-audio-stop").firstMatch
        scrollControlIntoView(stop, in: app); stop.tap()
        XCTAssertEqual(count.label, "Allarmi sintetici: 0")
        let rearm = app.buttons.matching(identifier: "rest-audio-rearm").firstMatch
        scrollControlIntoView(rearm, in: app); rearm.tap()
        XCTAssertEqual(count.label, "Allarmi sintetici: 1")
        let disable = app.buttons["rest-audio-disable"]
        scrollControlIntoView(disable, in: app); disable.tap()
        XCTAssertTrue(enable.waitForExistence(timeout: 8)); XCTAssertEqual(count.label, "Allarmi sintetici: 0")
        app.terminate(); app.launch(); openAudio(app)
        XCTAssertTrue(enable.waitForExistence(timeout: 8)); XCTAssertFalse(app.staticTexts["rest-audio-enabled"].exists)
        XCTAssertEqual(count.label, "Allarmi sintetici: 0")
        XCTAssertFalse(app.alerts.firstMatch.exists, "La navigazione non richiede permessi né produce allarmi reali")
    }
    private func openAudio(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Impostazioni"].waitForExistence(timeout: 15)); app.tabBars.buttons["Impostazioni"].tap()
        let notifications = app.buttons["settings-notifications"]
        scrollControlIntoView(notifications, in: app); notifications.tap()
        let audio = app.buttons["open-rest-audio"]
        scrollControlIntoView(audio, in: app); audio.tap()
        XCTAssertTrue(app.navigationBars["Audio recupero"].waitForExistence(timeout: 8))
    }
}
