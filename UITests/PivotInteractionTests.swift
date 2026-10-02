import XCTest

final class PivotInteractionTests: XCTestCase {
    func testTabsAndActivityButtonsRespondDuringCalendarImport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test"]
        app.launch()
        let income = app.tabBars.buttons["Entrate"]
        XCTAssertTrue(income.waitForExistence(timeout: 10))
        income.tap()
        XCTAssertTrue(app.staticTexts["Le tue entrate"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Impostazioni"].tap()
        XCTAssertTrue(app.staticTexts["Su misura per te"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Oggi"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 12))
        // Main UI remains interactive after the queued calendar-change burst.
        let details = app.buttons["Dettagli e registrazione"]
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        for _ in 0..<4 { if details.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(details.isHittable)
        details.tap()
        let start = app.buttons["Inizia attività"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()
        let finish = app.buttons["Termina attività"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.tap()
        XCTAssertTrue(app.buttons["Inizia attività"].waitForExistence(timeout: 3))
        // Also verify the foreground lifecycle path, which requests another refresh.
        XCUIDevice.shared.press(.home)
        app.activate()
        app.tabBars.buttons["Diario"].tap()
        XCTAssertTrue(app.staticTexts["Il tuo ritmo"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Entrate"].tap()
        XCTAssertTrue(app.staticTexts["Le tue entrate"].waitForExistence(timeout: 3))
    }
}
