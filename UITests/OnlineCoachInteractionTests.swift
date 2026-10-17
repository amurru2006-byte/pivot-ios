import XCTest

final class OnlineCoachInteractionTests: XCTestCase {
    private func actionApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-action-test", "--coach-calendar-create-test"]
        app.launch()
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15)); app.buttons["open-pivot-coach"].tap()
        return app
    }
    private func enter(_ text: String, in app: XCUIApplication) -> XCUIElement {
        let input = app.descendants(matching: .any)["coach-message-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8)); scrollControlIntoView(input, in: app, maxSwipes: 12)
        input.tap(); input.typeText(text)
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        return input
    }
    private func authorizeFirstRequest(in app: XCUIApplication) {
        let approve = app.buttons["coach-online-approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 12)); scrollControlIntoView(approve, in: app); approve.tap()
    }
    func testRewriteIsSeparateFromSendingAndOriginalCanBeRestored() {
        let app = actionApp(), original = "Devo comprare latte uova farina."
        let input = enter(original, in: app)
        let rewrite = app.buttons["coach-rewrite"]
        scrollControlIntoView(rewrite, in: app); rewrite.tap(); authorizeFirstRequest(in: app)
        let undo = app.buttons["coach-rewrite-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 12))
        XCTAssertTrue((input.value as? String ?? "").contains("- latte"))
        XCTAssertFalse(app.navigationBars["Nuovo impegno"].exists)
        scrollControlIntoView(undo, in: app); undo.tap()
        XCTAssertEqual(input.value as? String, original)
    }
    func testCalendarDraftNeedsSeparateConfirmationAndCanCancelBeforeSaving() {
        let app = actionApp()
        _ = enter("Crea un impegno di prova dalle22 a mezzanotte oggi nel calendario Personale test", in: app)
        let send = app.buttons["coach-send"]
        scrollControlIntoView(send, in: app); send.tap(); authorizeFirstRequest(in: app)
        XCTAssertTrue(app.navigationBars["Nuovo impegno"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.textFields["coach-create-title"].value as? String, "Impegno di prova")
        let review = app.buttons["coach-create-review"]
        scrollControlIntoView(review, in: app); review.tap()
        let confirmation = app.alerts["Creare questo impegno nel Calendario?"]
        // iOS exposes both the native action and its nested SwiftUI button.
        // They have the same frame; scope to this alert and one native match.
        let create = confirmation.buttons.matching(identifier: "coach-create-confirm").firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 12))
        let cancel = confirmation.buttons["Annulla"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "La conferma deve permettere di annullare prima di scrivere")
        cancel.tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["Nuovo impegno"].exists)
        scrollControlIntoView(review, in: app); review.tap()
        XCTAssertTrue(create.waitForExistence(timeout: 12)); create.tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Impegno creato nel Calendario: Impegno di prova")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 12))
        XCTAssertFalse(app.navigationBars["Nuovo impegno"].exists)
    }

    func testConversationPermissionAvoidsRepeatedReviewAndCanBeRevoked() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-review-test"]
        app.launch()
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15)); app.buttons["open-pivot-coach"].tap()
        let input = app.descendants(matching: .any)["coach-message-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8)); scrollControlIntoView(input, in: app, maxSwipes: 12)
        input.tap(); input.typeText("Vorrei organizzare lo studio")
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        let send = app.buttons["coach-send"]
        scrollControlIntoView(send, in: app); send.tap()
        let approve = app.buttons["coach-online-approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 12)); scrollControlIntoView(approve, in: app); approve.tap()
        let counter = app.staticTexts["coach-online-fixture-requests"]
        let first = expectation(for: NSPredicate(format: "label == %@", "Richieste sintetiche: 1"), evaluatedWith: counter)
        wait(for: [first], timeout: 12)
        scrollControlIntoView(input, in: app, maxSwipes: 12)
        input.tap(); input.typeText(" e cucinare")
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        scrollControlIntoView(send, in: app); send.tap()
        let second = expectation(for: NSPredicate(format: "label == %@", "Richieste sintetiche: 2"), evaluatedWith: counter)
        wait(for: [second], timeout: 12)
        XCTAssertFalse(approve.exists)
        let data = app.buttons["coach-online-data"]
        scrollControlIntoView(data, in: app, maxSwipes: 12); data.tap()
        XCTAssertTrue(app.staticTexts["coach-online-reviewed-message"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["coach-online-reviewed-message"].label.contains("cucinare"))
        app.buttons["Chiudi"].tap()
        let revoke = app.buttons["coach-online-revoke"]
        scrollControlIntoView(revoke, in: app); revoke.tap()
        scrollControlIntoView(send, in: app, maxSwipes: 12); send.tap()
        XCTAssertTrue(approve.waitForExistence(timeout: 12))
        let cancel = app.buttons["coach-online-review-cancel"]
        scrollControlIntoView(cancel, in: app); cancel.tap()
        XCTAssertEqual(counter.label, "Richieste sintetiche: 2")
    }

    func testDictationPauseKeepsEarlierPhraseAndTypedPrefix() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--dictation-pause-test"]
        app.launch()
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15)); app.buttons["open-pivot-coach"].tap()
        let input = app.descendants(matching: .any)["coach-message-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8)); scrollControlIntoView(input, in: app, maxSwipes: 12)
        input.tap(); input.typeText("Appunti:")
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        let dictate = app.buttons["coach-dictation"]
        scrollControlIntoView(dictate, in: app); dictate.tap()
        let accumulated = expectation(for: NSPredicate(format: "value CONTAINS %@", "Appunti: Prima devo studiare. Poi fare la spesa."), evaluatedWith: input)
        wait(for: [accumulated], timeout: 12)
        dictate.tap()
        XCTAssertEqual(input.value as? String, "Appunti: Prima devo studiare. Poi fare la spesa.")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "dictation-preserved-after-pause"; shot.lifetime = .keepAlways; add(shot)
    }

    override func tearDownWithError() throws { attachFailureDiagnostics("online-coach"); try super.tearDownWithError() }
    func testOnlineReviewRequiresConfirmationAndCancelPreservesComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-review-test"]
        app.launch()
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15)); app.buttons["open-pivot-coach"].tap()
        let input = app.descendants(matching: .any)["coach-message-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8)); scrollControlIntoView(input, in: app, maxSwipes: 12)
        XCTAssertTrue(input.isHittable); input.tap(); input.typeText("Dopo cena, contattami a prova@example.test")
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        app.buttons["coach-send"].tap()
        let reviewed = app.staticTexts["coach-online-reviewed-message"]
        XCTAssertTrue(reviewed.waitForExistence(timeout: 12))
        XCTAssertTrue(reviewed.label.contains("[email]")); XCTAssertFalse(reviewed.label.contains("example.test"))
        XCTAssertFalse(app.staticTexts["coach-online-error"].exists)
        let cancel = app.buttons["coach-online-review-cancel"]
        scrollControlIntoView(cancel, in: app); cancel.tap()
        XCTAssertEqual(input.value as? String, "Dopo cena, contattami a prova@example.test")
        XCTAssertFalse(app.staticTexts["coach-online-error"].exists)
        let send = app.buttons["coach-send"]
        scrollControlIntoView(send, in: app); send.tap()
        let approve = app.buttons["coach-online-approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 12)); scrollControlIntoView(approve, in: app); approve.tap()
        // Only explicit approval reaches the synthetic provider. Never a network call.
        XCTAssertTrue(app.staticTexts["coach-online-error"].waitForExistence(timeout: 8))
        XCTAssertEqual(input.value as? String, "Dopo cena, contattami a prova@example.test")
    }

    func testSwitchingToLocalCancelsPreflightWithoutSendingOrLosingComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-preflight-test"]
        app.launch()
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15)); app.buttons["open-pivot-coach"].tap()
        let input = app.descendants(matching: .any)["coach-message-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8)); scrollControlIntoView(input, in: app, maxSwipes: 12)
        XCTAssertTrue(input.isHittable); input.tap(); input.typeText("Preferisco studiare con esercizi brevi")
        let done = app.buttons["Fine"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        let send = app.buttons["coach-send"]
        scrollControlIntoView(send, in: app)
        XCTAssertTrue(send.isHittable); send.tap()
        XCTAssertTrue(app.descendants(matching: .any)["coach-planning-progress"].waitForExistence(timeout: 8))
        let local = app.buttons["coach-online-local-toggle"]
        scrollControlIntoView(local, in: app); local.tap()
        let mode = app.staticTexts["coach-online-mode"]
        let localMode = expectation(for: NSPredicate(format: "label == %@", "Base locale"), evaluatedWith: mode)
        wait(for: [localMode], timeout: 5)
        XCTAssertEqual(mode.label, "Base locale")
        XCTAssertFalse(app.staticTexts["coach-online-error"].exists)
        scrollControlIntoView(input, in: app, maxSwipes: 12)
        XCTAssertEqual(input.value as? String, "Preferisco studiare con esercizi brevi")
        XCTAssertFalse(app.descendants(matching: .any)["coach-planning-progress"].exists)
        scrollControlIntoView(send, in: app)
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
        scrollControlIntoView(input, in: app)
        XCTAssertTrue(input.isHittable); input.tap(); input.typeText("Preferisco dopo cena")
        if app.keyboards.firstMatch.exists {
            XCTAssertTrue(app.buttons["Fine"].waitForExistence(timeout: 8)); app.buttons["Fine"].tap()
        }
        let send = app.buttons["coach-send"]
        scrollControlIntoView(send, in: app); send.tap()
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
        scrollControlIntoView(settings, in: app)
        XCTAssertTrue(settings.isHittable); settings.tap()
        let edit = app.buttons["online-coach-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8)); scrollControlIntoView(edit, in: app); edit.tap()
        XCTAssertTrue(app.secureTextFields["online-coach-token"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["online-coach-save"].isEnabled)
        XCTAssertTrue(app.switches["online-coach-consent"].exists)
        XCTAssertTrue(app.staticTexts["online-coach-edit-explanation"].label.contains("già salvato"))
        XCTAssertTrue(app.buttons["online-coach-disconnect"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "v8-online-privacy-settings"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
