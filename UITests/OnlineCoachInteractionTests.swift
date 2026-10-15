import XCTest

final class OnlineCoachInteractionTests: XCTestCase {
    func testSwitchingToLocalCancelsPreflightWithoutSendingOrLosingComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-preflight-test"]
        app.launch()
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15)); app.buttons["open-pivot-coach"].tap()
        let input = app.descendants(matching: .any)["coach-message-input"]
        for _ in 0..<12 { if input.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(input.isHittable); input.tap(); input.typeText("Preferisco studiare con esercizi brevi")
        let done = app.buttons["Fine"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        let send = app.buttons["coach-send"]
        for _ in 0..<5 { if send.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(send.isHittable); send.tap()
        XCTAssertTrue(app.descendants(matching: .any)["coach-planning-progress"].waitForExistence(timeout: 8))
        let local = app.buttons["coach-online-local-toggle"]
        scrollControlIntoView(local, in: app); local.tap()
        let mode = app.staticTexts["coach-online-mode"]
        let localMode = expectation(for: NSPredicate(format: "label == %@", "Base locale"), evaluatedWith: mode)
        wait(for: [localMode], timeout: 5)
        XCTAssertEqual(mode.label, "Base locale")
        XCTAssertFalse(app.staticTexts["coach-online-error"].exists)
        for _ in 0..<12 { if input.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(input.value as? String, "Preferisco studiare con esercizi brevi")
        XCTAssertFalse(app.descendants(matching: .any)["coach-planning-progress"].exists)
        for _ in 0..<5 { if send.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(send.isEnabled); send.tap()
        XCTAssertTrue(app.staticTexts["Preferisco studiare con esercizi brevi"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["coach-online-error"].exists)
    }
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
        // SwiftUI's vertical TextField is not always exposed as a textView.
        // Require the exact composer identifier, then test real typing and value.
        let input = app.descendants(matching: .any)["coach-message-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        for _ in 0..<8 { if input.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(input.isHittable); input.tap(); input.typeText("Preferisco dopo cena")
        XCTAssertTrue(app.buttons["Fine"].waitForExistence(timeout: 8)); app.buttons["Fine"].tap()
        app.buttons["coach-send"].tap()
        XCTAssertTrue(app.staticTexts["coach-online-error"].waitForExistence(timeout: 8))
        XCTAssertEqual(input.value as? String, "Preferisco dopo cena")
        app.swipeDown()
        let local = app.buttons["coach-online-local-toggle"]
        scrollControlIntoView(local, in: app); local.tap()
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
