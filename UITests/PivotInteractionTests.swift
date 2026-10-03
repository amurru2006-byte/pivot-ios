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
    func testStudyPDFImportOpenAndPersistenceAcrossRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--study-material-test"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 15))
        let details = app.buttons["Dettagli e registrazione"]
        for _ in 0..<5 { if details.isHittable { break }; app.swipeUp() }
        details.tap()
        let importer = app.buttons["import-study-fixture"]
        for _ in 0..<6 { if importer.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(importer.isHittable)
        importer.tap()
        let pdf = app.buttons["Scheda di prova.pdf"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 5))
        pdf.tap()
        XCTAssertTrue(app.buttons["Chiudi"].waitForExistence(timeout: 5))
        app.buttons["Chiudi"].tap()
        let objectives = app.descendants(matching: .any)["study-objectives"]
        XCTAssertTrue(objectives.exists)
        for _ in 0..<6 { if objectives.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(objectives.isHittable)
        objectives.tap()
        objectives.typeText("Obiettivo di prova")
        let done = app.buttons["Fine"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        app.swipeUp()
        let save = app.buttons["Salva registrazione"]
        for _ in 0..<10 { if save.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(save.isHittable)
        save.tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 15))
        let reopened = app.buttons["Dettagli e registrazione"]
        for _ in 0..<5 { if reopened.isHittable { break }; app.swipeUp() }
        reopened.tap()
        for _ in 0..<6 { if app.buttons["Scheda di prova.pdf"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["Scheda di prova.pdf"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["study-objectives"].value as? String, "Obiettivo di prova")
    }

}
