import XCTest

/// A separate synthetic host, not the user's Pivot. CI creates a brand-new
/// simulator and deletes only that owned simulator afterwards.
final class EventKitRoundtripInteractionTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--pivot-isolated-eventkit-ci", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PIVOT_ROUNDTRIP_QA_ID"] = UUID().uuidString
        app.launch(); XCTAssertTrue(app.buttons["calendar-native-run"].waitForExistence(timeout: 20))
        return app
    }
    private func fullAccessButton(in alert: XCUIElement) -> XCUIElement? {
        let owned = alert.label.contains("Pivot Calendar QA")
            || alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Pivot Calendar QA")).firstMatch.exists
        guard owned else { return nil }
        let labels = ["Allow Full Access", "Allow Access to All Events", "Consenti accesso completo"]
        return labels.map { alert.buttons[$0] }.first(where: { $0.exists })
    }
    private func run(_ app: XCUIApplication, attempt: Int) {
        var approved = false
        // XCTest can intercept a late prompt during the next action and use
        // its default denial before the test can inspect SpringBoard.
        let monitor = addUIInterruptionMonitor(withDescription: "Owned Calendar host prompt") { alert in
            guard !approved, let allow = self.fullAccessButton(in: alert) else { return false }
            approved = true
            allow.tap()
            return true
        }
        defer { removeUIInterruptionMonitor(monitor) }
        app.buttons["calendar-native-run"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = system.alerts.firstMatch
        let report = app.staticTexts["calendar-native-result"]
        let expected = "PASS \(attempt): spring23 autumn25 timed45 cleanupOK"
        let deadline = Date().addingTimeInterval(75)
        var result = ""
        repeat {
            if !approved && alert.exists {
                guard let allow = fullAccessButton(in: alert) else {
                    let shot = XCTAttachment(screenshot: system.screenshot())
                    shot.name = "synthetic-calendar-permission"; shot.lifetime = .keepAlways; add(shot)
                    return XCTFail("Unexpected prompt or missing full-access button for the isolated host")
                }
                approved = true
                allow.tap()
            }
            if report.exists {
                result = report.label
                if result.hasPrefix("PASS \(attempt):") || result.hasPrefix("FAIL \(attempt):") { break }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        XCTAssertEqual(result, expected,
                       "The isolated host must report the committed reread and verified cleanup")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "owned-eventkit-roundtrip-\(attempt)"; shot.lifetime = .keepAlways; add(shot)
    }
    func testCommittedFloatingCivilDaysAndTimedEventCanBeReadByANewEventStore() {
        run(launch(), attempt: 1)
    }
    func testASecondOwnedCalendarRunAlsoCleansUpWithoutReusingAnEarlierResult() {
        let app = launch(); run(app, attempt: 1); run(app, attempt: 2)
    }
}
