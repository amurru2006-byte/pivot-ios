import XCTest

final class BackupPrivacyInteractionTests: XCTestCase {
    override func tearDownWithError() throws { attachFailureDiagnostics("backup"); try super.tearDownWithError() }
    private func app() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--backup-privacy-test"]
        app.launchEnvironment["PIVOT_QA_BACKUP_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_KEYCHAIN_ID"] = UUID().uuidString
        app.launch()
        openBackup(in: app)
        return app
    }

    private func openBackup(in app: XCUIApplication) {
        let settings = app.tabBars.buttons["Impostazioni"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
        let backup = app.buttons["settings-backup"]
        XCTAssertTrue(backup.waitForExistence(timeout: 8)); scrollControlIntoView(backup, in: app); backup.tap()
        XCTAssertTrue(app.buttons["backup-password-setup"].waitForExistence(timeout: 8))
    }

    func testCancelDoesNotConfigureOrExportAPlaintextFallback() {
        let app = app()
        let setup = app.buttons["backup-password-setup"]
        XCTAssertTrue(setup.label.contains("Imposta")); setup.tap()
        let input = app.secureTextFields["backup-password"]
        enterSyntheticPassword(input, in: app)
        XCTAssertFalse(app.buttons["backup-password-save"].exists)
        app.buttons["Annulla"].tap()
        XCTAssertTrue(setup.waitForExistence(timeout: 8)); XCTAssertTrue(setup.label.contains("Imposta"))
        XCTAssertFalse(app.buttons["Scegli cartella backup"].isEnabled)
    }

    func testConfirmationAcknowledgementAndKeychainSurviveRelaunch() {
        let app = app()
        app.buttons["backup-password-setup"].tap()
        let input = app.secureTextFields["backup-password"]
        let repeated = app.secureTextFields["backup-password-confirmation"]
        enterSyntheticPassword(input, in: app)
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        let next = app.buttons["backup-password-next"]
        scrollControlIntoView(next, in: app); XCTAssertTrue(next.isEnabled); next.tap()
        XCTAssertFalse(input.exists)
        enterSyntheticPassword(repeated, in: app)
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        let save = app.buttons["backup-password-save"]
        XCTAssertFalse(save.isEnabled)
        let acknowledgement = app.switches["backup-password-saved"]
        scrollControlIntoView(acknowledgement, in: app)
        tapVisibleSwitchOnce(acknowledgement, to: true, in: app)
        XCTAssertEqual(acknowledgement.value as? String, "1")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "backup-confirmed-fields-and-acknowledgement"; screenshot.lifetime = .keepAlways; add(screenshot)
        scrollControlIntoView(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        let setup = app.buttons["backup-password-setup"]
        let configured = expectation(for: NSPredicate(format: "label CONTAINS %@", "Cambia"), evaluatedWith: setup)
        wait(for: [configured], timeout: 15)
        app.terminate(); app.launch(); openBackup(in: app)
        XCTAssertTrue(setup.label.contains("Cambia"))
        XCTAssertTrue(app.buttons["Scegli cartella backup"].isEnabled)
    }

    private func enterSyntheticPassword(_ field: XCUIElement, in app: XCUIApplication) {
        let navigation = app.navigationBars["Proteggi il backup"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 8))
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        // This is the first Form row. Dragging while the sheet is arriving can
        // dismiss the sheet; wait for its own navigation/field geometry instead.
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 8), .completed)
        XCTAssertGreaterThanOrEqual(field.frame.minY, navigation.frame.maxY + 8)
        XCTAssertLessThan(field.frame.maxY, app.frame.maxY - 34)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        field.typeText("Synthetic password only 42!")
        // Keep this behavioural assertion: a visible placeholder is not a successful edit.
        XCTAssertNotEqual(field.value as? String, field.placeholderValue)
    }
}
