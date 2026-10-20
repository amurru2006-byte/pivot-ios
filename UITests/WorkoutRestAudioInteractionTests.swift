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
        XCTAssertTrue(enable.waitForExistence(timeout: 8)); assertCount(0, count)
        scrollControlIntoView(enable, in: app); enable.tap()
        XCTAssertTrue(app.staticTexts["rest-audio-enabled"].waitForExistence(timeout: 10))
        assertCount(1, count)
        app.buttons["rest-audio-close"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openAudio(app)
        XCTAssertTrue(app.staticTexts["rest-audio-enabled"].waitForExistence(timeout: 8))
        assertCount(1, count)
        let stop = app.buttons.matching(identifier: "rest-audio-stop").firstMatch
        scrollControlIntoView(stop, in: app); stop.tap()
        assertCount(0, count)
        let rearm = app.buttons.matching(identifier: "rest-audio-rearm").firstMatch
        scrollControlIntoView(rearm, in: app); rearm.tap()
        assertCount(1, count)
        let disable = app.buttons["rest-audio-disable"]
        scrollControlIntoView(disable, in: app); disable.tap()
        XCTAssertTrue(enable.waitForExistence(timeout: 8)); assertCount(0, count)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: enable)], timeout: 10), .completed)
        app.terminate(); app.launch(); openAudio(app)
        XCTAssertTrue(enable.waitForExistence(timeout: 8)); XCTAssertFalse(app.staticTexts["rest-audio-enabled"].exists)
        assertCount(0, count)
        XCTAssertFalse(app.alerts.firstMatch.exists, "La navigazione non richiede permessi né produce allarmi reali")
    }
    private func assertCount(_ value: Int, _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Allarmi sintetici: \(value)"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, file: file, line: line)
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
