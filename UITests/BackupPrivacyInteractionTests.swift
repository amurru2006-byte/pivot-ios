import XCTest

final class BackupPrivacyInteractionTests: XCTestCase {
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
        XCTAssertTrue(input.waitForExistence(timeout: 8)); input.tap(); input.typeText("Synthetic password only 42!")
        XCTAssertFalse(app.buttons["backup-password-save"].isEnabled)
        app.buttons["Annulla"].tap()
        XCTAssertTrue(setup.waitForExistence(timeout: 8)); XCTAssertTrue(setup.label.contains("Imposta"))
        XCTAssertFalse(app.buttons["Scegli cartella backup"].isEnabled)
    }

    func testConfirmationAcknowledgementAndKeychainSurviveRelaunch() {
        let app = app()
        app.buttons["backup-password-setup"].tap()
        let input = app.secureTextFields["backup-password"]
        let repeated = app.secureTextFields["backup-password-confirmation"]
        XCTAssertTrue(input.waitForExistence(timeout: 8)); input.tap(); input.typeText("Synthetic password only 42!")
        repeated.tap(); repeated.typeText("Synthetic password only 42!")
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        let save = app.buttons["backup-password-save"]
        XCTAssertFalse(save.isEnabled)
        let acknowledgement = app.switches["backup-password-saved"]
        scrollControlIntoView(acknowledgement, in: app); acknowledgement.tap()
        scrollControlIntoView(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        let setup = app.buttons["backup-password-setup"]
        let configured = expectation(for: NSPredicate(format: "label CONTAINS %@", "Cambia"), evaluatedWith: setup)
        wait(for: [configured], timeout: 15)
        app.terminate(); app.launch(); openBackup(in: app)
        XCTAssertTrue(setup.label.contains("Cambia"))
        XCTAssertTrue(app.buttons["Scegli cartella backup"].isEnabled)
    }
}
