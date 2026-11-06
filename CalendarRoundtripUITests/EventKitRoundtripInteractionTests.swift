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
    private func run(_ app: XCUIApplication, attempt: Int) {
        app.buttons["calendar-native-run"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = system.alerts.firstMatch
        if alert.waitForExistence(timeout: 8) {
            let owned = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Pivot Calendar QA")).firstMatch.exists
                || alert.label.contains("Pivot Calendar QA")
            XCTAssertTrue(owned, "Only the isolated host's Calendar prompt may be approved")
            guard owned else { return }
            let candidates = ["Allow Full Access", "Allow Access to All Events", "Consenti accesso completo"]
            guard let allow = candidates.map({ alert.buttons[$0] }).first(where: { $0.exists }) else {
                let shot = XCTAttachment(screenshot: system.screenshot()); shot.name = "synthetic-calendar-permission"; shot.lifetime = .keepAlways; add(shot)
                return XCTFail("No full-access action on the owned synthetic Calendar prompt")
            }
            allow.tap()
        }
        let report = app.staticTexts["calendar-native-result"]
        let completed = expectation(for: NSPredicate(format: "label == %@", "PASS \(attempt): spring23 autumn25 timed45 cleanupOK"), evaluatedWith: report)
        wait(for: [completed], timeout: 40)
        XCTAssertEqual(report.label, "PASS \(attempt): spring23 autumn25 timed45 cleanupOK",
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
