import XCTest

final class SavedPlacesInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }

    func testManualSavedPlacePersistsAndSelectionDoesNotRequestMapsOrCreateEvents() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Isolate real persistence and Maps consent, while all external
        // Calendar/Maps operations remain on the existing synthetic boundary.
        app.launchArguments = ["--interaction-test", "--online-coach-action-test", "--coach-calendar-create-test",
                               "--calendar-travel-test", "--travel-estimate-test"]
        app.launchEnvironment["PIVOT_QA_COACH_ACTION_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_TRAVEL_ID"] = UUID().uuidString
        let placeName = "Casa QA salvata", address = "Via Sintetica QA 42"
        app.launch()
        openSettings(app)
        tap(app.buttons["settings-places"], in: app)
        XCTAssertTrue(app.navigationBars["Luoghi"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["places-empty"].waitForExistence(timeout: 5), "The initial list must be visible, not collapsed inside another scroll view")
        toolbarTap(app.buttons["places-add"])
        XCTAssertTrue(app.navigationBars["Salva luogo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["place-save"].isEnabled)
        type(placeName, into: app.textFields["place-name"], in: app)
        dismissPlaceKeyboard(app)
        type(address, into: app.textFields["place-address"], in: app)
        dismissPlaceKeyboard(app)
        toolbarTap(app.buttons["place-save"])
        XCTAssertTrue(app.navigationBars["Salva luogo"].waitForNonExistence(timeout: 8))
        let saved = app.buttons["place-select-" + placeName]
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        let created = XCTAttachment(screenshot: app.screenshot())
        created.name = "manual-place-saved-without-maps"; created.lifetime = .keepAlways; add(created)

        app.terminate(); app.launch()
        openSettings(app)
        tap(app.buttons["settings-places"], in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        tap(saved, in: app)
        XCTAssertTrue(app.navigationBars["Modifica luogo"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["place-name"].value as? String, placeName)
        XCTAssertEqual(app.textFields["place-address"].value as? String, address)
        toolbarTap(app.buttons["place-close"])
        XCTAssertTrue(app.navigationBars["Modifica luogo"].waitForNonExistence(timeout: 8))
        app.navigationBars["Luoghi"].buttons.element(boundBy: 0).tap()
        tap(app.buttons["settings-travel"], in: app)
        let count = app.staticTexts["travel-test-count"]
        XCTAssertTrue(app.buttons["travel-consent"].waitForExistence(timeout: 5))
        tap(count, in: app)
        XCTAssertEqual(count.label, "Richieste sintetiche: 0")
        tap(app.buttons["travel-consent"], in: app)
        tap(app.buttons["travel-saved-origin"], in: app)
        XCTAssertTrue(app.navigationBars["Luoghi"].waitForExistence(timeout: 5))
        tap(saved, in: app)
        XCTAssertTrue(app.navigationBars["Luoghi"].waitForNonExistence(timeout: 8))
        XCTAssertEqual(app.textFields["travel-origin"].value as? String, address)
        // A manually saved address is not a verified Maps coordinate. Merely
        // choosing it must neither resolve it remotely nor enable routing.
        XCTAssertFalse(app.buttons["travel-calculate"].isEnabled)
        XCTAssertFalse(app.staticTexts["travel-result"].exists)
        tap(count, in: app)
        XCTAssertEqual(count.label, "Richieste sintetiche: 0")
        let selected = XCTAttachment(screenshot: app.screenshot())
        selected.name = "manual-place-selected-zero-maps-requests"; selected.lifetime = .keepAlways; add(selected)

        let today = app.tabBars.buttons["Oggi"]
        XCTAssertTrue(today.waitForExistence(timeout: 5)); today.tap()
        tap(app.buttons["open-pivot-coach"], in: app)
        let audit = app.staticTexts["creation-events-audit"]
        tap(audit, in: app)
        XCTAssertEqual(audit.label, "0 eventi · 0 spostamenti · 0 incassi")
        // Settings routes to these complete screens without wrapping another
        // ScrollView around their own. Do not read or replace protected fields.
        openSettings(app)
        tap(app.buttons["settings-online"], in: app)
        let status = app.descendants(matching: .any).matching(identifier: "online-coach-configuration-status").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 8)); XCTAssertTrue(status.isHittable)
        let privacy = XCTAttachment(screenshot: app.screenshot())
        privacy.name = "settings-online-screen-owns-its-scroll-layout"; privacy.lifetime = .keepAlways; add(privacy)
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["Impostazioni"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        scrollControlIntoView(element, in: app)
        XCTAssertTrue(element.isEnabled); element.tap()
    }
    private func toolbarTap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable); XCTAssertTrue(element.isEnabled); element.tap()
    }
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        tap(field, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(text)
    }
    private func dismissPlaceKeyboard(_ app: XCUIApplication) {
        let done = app.buttons.matching(identifier: "place-keyboard-done").firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
}
