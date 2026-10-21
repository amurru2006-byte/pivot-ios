import XCTest

final class CalendarTimingInteractionTests: XCTestCase {
    override func tearDown() { attachFailureDiagnostics(name); super.tearDown() }
    func testEndOnlyCorrectionRequiresConfirmationAndUpdatesOnlyItsCalendarOccurrenceAcrossRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--online-coach-action-test", "--coach-calendar-create-test", "--calendar-mutations-test", "--actual-time-sync-test"]
        app.launchEnvironment["PIVOT_QA_COACH_ACTION_ID"] = UUID().uuidString
        app.launch()
        func tap(_ element: XCUIElement) { scrollControlIntoView(element, in: app); element.tap() }
        func openActivity() {
            let diary = app.tabBars.buttons["Diario"]
            XCTAssertTrue(diary.waitForExistence(timeout: 15)); diary.tap()
            tap(app.buttons["diary-event-mutation-qa-2"])
            XCTAssertTrue(app.navigationBars["Attività"].waitForExistence(timeout: 8))
        }
        openActivity()
        let audit = app.staticTexts["activity-calendar-timing-audit"]
        XCTAssertEqual(audit.label, "Calendario 11:00 · inizio reale assente · pending")
        // Identify the disclosure by its visible label, not an identifier on
        // its entire container that SwiftUI can propagate to child controls.
        tap(app.buttons["Orari reali e durata"]); tap(app.buttons["activity-real-end"])
        XCTAssertTrue(app.navigationBars["Fine reale"].waitForExistence(timeout: 8))
        let hour = app.pickerWheels.element(boundBy: 0)
        XCTAssertTrue(hour.waitForExistence(timeout: 5)); hour.adjust(toPickerWheelValue: "17")
        tap(app.buttons["Conferma orario"])
        app.buttons["activity-save"].tap()
        let confirm = app.alerts["Aggiornare gli orari nel Calendario?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8)); confirm.buttons["Non ora"].tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertEqual(audit.label, "Calendario 11:00 · inizio reale assente · pending")
        app.buttons["activity-save"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 8)); confirm.buttons.matching(identifier: "activity-calendar-confirm").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Attività"].waitForNonExistence(timeout: 15))
        app.terminate(); app.launch(); openActivity()
        XCTAssertEqual(audit.label, "Calendario 17:00 · inizio reale assente · pending")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "activity-calendar-end-only-confirmed"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars["Attività"].buttons.element(boundBy: 0).tap()
        tap(app.buttons["diary-event-mutation-qa-1"])
        XCTAssertEqual(audit.label, "Calendario 10:00 · inizio reale assente · pending")
    }
}
