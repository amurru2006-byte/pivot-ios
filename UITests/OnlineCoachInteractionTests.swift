import XCTest

final class OnlineCoachInteractionTests: XCTestCase {
    func testQuotaCountdownKeepsComposerAndLocalConversationInsidePivot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-quota-test"]
        app.launch()
        let open = app.buttons["open-pivot-coach"]
        XCTAssertTrue(open.waitForExistence(timeout: 15)); open.tap()
        let countdown = app.staticTexts["coach-online-countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 8))
        XCTAssertTrue(countdown.label.contains("Riprova tra"))
        let input = app.textViews["coach-message-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        for _ in 0..<8 { if input.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(input.isHittable); input.tap(); input.typeText("Preferisco dopo cena")
        XCTAssertTrue(app.buttons["Fine"].waitForExistence(timeout: 8)); app.buttons["Fine"].tap()
        app.buttons["coach-send"].tap()
        XCTAssertTrue(app.staticTexts["coach-online-error"].waitForExistence(timeout: 8))
        XCTAssertEqual(input.value as? String, "Preferisco dopo cena")
        app.swipeDown()
        let local = app.buttons["coach-online-local-toggle"]
        for _ in 0..<5 { if local.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(local.isHittable); local.tap()
        XCTAssertEqual(app.staticTexts["coach-online-mode"].label, "Base locale")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "v8-quota-and-local-mode"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertTrue(app.navigationBars["Coach"].exists)
    }
    func testOnlineSettingsRequireConsentAndProtectTokenEntry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-quota-test"]
        app.launch()
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15)); app.buttons["open-pivot-coach"].tap()
        let settings = app.buttons["coach-online-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        for _ in 0..<5 { if settings.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.tap()
        XCTAssertTrue(app.secureTextFields["online-coach-token"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["online-coach-save"].isEnabled)
        XCTAssertTrue(app.switches["online-coach-consent"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "v8-online-privacy-settings"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
