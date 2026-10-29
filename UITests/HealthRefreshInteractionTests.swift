import XCTest

final class HealthRefreshInteractionTests: XCTestCase {
    // Fixed synthetic dates keep the old successful read distinct from the
    // current attempt, including when hosted tests run across midnight.
    private let now = Date(timeIntervalSince1970: 1_793_275_200)
    private var yesterday: Date { now.addingTimeInterval(-86_400) }

    override func tearDownWithError() throws {
        attachFailureDiagnostics("health-refresh")
        try super.tearDownWithError()
    }

    private func launch(outcome: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--health-refresh-interaction-test"]
        app.launchEnvironment["PIVOT_QA_HEALTH_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_QA_KEYCHAIN_ID"] = UUID().uuidString
        app.launchEnvironment["PIVOT_UI_HEALTH_STATUS"] = outcome
        app.launchEnvironment["PIVOT_UI_HEALTH_NOW"] = String(now.timeIntervalSince1970)
        app.launch()
        return app
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        scrollControlIntoView(element, in: app)
        XCTAssertTrue(element.isEnabled)
        element.tap()
    }

    private func openTodayHealth(in app: XCUIApplication) {
        let today = app.tabBars.buttons["Oggi"]
        XCTAssertTrue(today.waitForExistence(timeout: 15))
        today.tap()
        tap(app.buttons["open-health"], in: app)
        XCTAssertTrue(app.staticTexts["health-last-successful-read"].waitForExistence(timeout: 8))
    }

    private func openHealthSettings(in app: XCUIApplication) {
        let settings = app.tabBars.buttons["Impostazioni"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        tap(app.buttons["settings-health"], in: app)
        XCTAssertTrue(app.staticTexts["health-last-successful-read"].waitForExistence(timeout: 8))
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")!
        formatter.dateFormat = "d MMMM yyyy · HH:mm"
        return formatter.string(from: date)
    }

    private func assertState(in app: XCUIApplication, message: String, reportDate: Date,
                             file: StaticString = #filePath, line: UInt = #line) {
        let status = app.staticTexts["health-last-attempt-status"]
        let changed = expectation(for: NSPredicate(format: "label == %@", message), evaluatedWith: status)
        wait(for: [changed], timeout: 8)
        XCTAssertEqual(status.label, message, file: file, line: line)
        XCTAssertTrue(app.staticTexts["health-last-attempt-time"].label.contains(dateText(now)), file: file, line: line)
        XCTAssertTrue(app.staticTexts["health-last-successful-read"].label.contains(dateText(reportDate)), file: file, line: line)
        XCTAssertFalse(app.staticTexts["Lettura completata."].exists, file: file, line: line)
    }

    private func attachScreen(_ name: String, in app: XCUIApplication) {
        scrollControlIntoView(app.staticTexts["health-last-attempt-time"], in: app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFailedRefreshKeepsYesterdayReportAndShowsCurrentAttemptInBothScreens() {
        let app = launch(outcome: "failed")
        openTodayHealth(in: app)
        let report = app.staticTexts["health-last-successful-read"]
        let originalRead = report.label
        XCTAssertTrue(originalRead.contains(dateText(yesterday)))
        XCTAssertTrue(app.staticTexts["health-last-attempt-time"].label.contains(dateText(yesterday)))
        XCTAssertEqual(app.staticTexts["health-last-attempt-status"].label, "Lettura completata.")

        tap(app.buttons["Aggiorna dati da Salute"], in: app)
        assertState(in: app, message: "Lettura da Salute non completata.", reportDate: yesterday)
        XCTAssertEqual(report.label, originalRead)
        XCTAssertFalse(report.label.contains(dateText(now)))
        attachScreen("health-failed-today", in: app)

        app.buttons["Chiudi"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Chiudi"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
        openHealthSettings(in: app)
        assertState(in: app, message: "Lettura da Salute non completata.", reportDate: yesterday)
        XCTAssertFalse(app.staticTexts["health-last-successful-read"].label.contains(dateText(now)))
        attachScreen("health-failed-settings", in: app)
    }

    func testPartialHeartRateRefreshSavesCurrentBaseReadWithoutClaimingFullSuccess() {
        let app = launch(outcome: "partial")
        openHealthSettings(in: app)
        XCTAssertTrue(app.staticTexts["health-last-successful-read"].label.contains(dateText(yesterday)))
        XCTAssertTrue(app.staticTexts["health-last-attempt-time"].label.contains(dateText(yesterday)))
        XCTAssertEqual(app.staticTexts["health-last-attempt-status"].label, "Lettura completata.")

        tap(app.buttons["Aggiorna dati da Salute"], in: app)
        assertState(in: app, message: "Lettura parziale: dettagli cardiaci non aggiornati.", reportDate: now)
        XCTAssertFalse(app.staticTexts["health-last-successful-read"].label.contains(dateText(yesterday)))
        attachScreen("health-partial-settings", in: app)

        openTodayHealth(in: app)
        assertState(in: app, message: "Lettura parziale: dettagli cardiaci non aggiornati.", reportDate: now)
        XCTAssertFalse(app.staticTexts["health-last-successful-read"].label.contains(dateText(yesterday)))
        attachScreen("health-partial-today", in: app)
    }
}
