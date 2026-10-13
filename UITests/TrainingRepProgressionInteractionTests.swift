import XCTest

final class TrainingRepProgressionInteractionTests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<24 {
            if element.isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -150 : 150)))
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func verify(_ app: XCUIApplication) {
        let verify = app.buttons["progression-verify"]
        reveal(verify, in: app); verify.tap()
        XCTAssertTrue(app.staticTexts["Progressione verificata · carichi e avvisi conservati"].waitForExistence(timeout: 8), app.debugDescription)
    }
    func testRepGoalShowsRecordedWorkAndWarningsWithoutChangingLoadsAndPersists() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--training-progression-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let fixture = app.buttons["progression-fixture"]
        reveal(fixture, in: app); fixture.tap()
        XCTAssertTrue(app.staticTexts["Progressione pronta"].waitForExistence(timeout: 8))
        let open = app.buttons["progression-open"]
        reveal(open, in: app); open.tap()
        XCTAssertTrue(app.navigationBars["Progressi"].waitForExistence(timeout: 5))
        let status = app.staticTexts["progression-status"]
        reveal(status, in: app); XCTAssertEqual(status.label, "Limite superiore raggiunto in tutte le serie")
        let completed = app.staticTexts["progression-completed"]
        reveal(completed, in: app); XCTAssertEqual(completed.label, "3 di 3 serie prescritte confermate")
        let comparison = app.staticTexts["progression-comparison"]
        reveal(comparison, in: app); XCTAssertTrue(comparison.label.contains("+6 ripetizioni totali"))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-rep-goal"; image.lifetime = .keepAlways; add(image)
        let concern = app.buttons["progression-concerns"]
        reveal(concern, in: app, up: false); concern.tap()
        XCTAssertTrue(app.navigationBars["Dolori e infortuni"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Zona progressione TEST"], in: app)
        app.navigationBars["Dolori e infortuni"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Progressi"].buttons.element(boundBy: 0).tap()
        verify(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        verify(app)
    }
}
