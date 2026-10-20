import XCTest
import CryptoKit
import CommonCrypto

final class OnlineCoachSetupInteractionTests: XCTestCase {
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            let app = XCUIApplication()
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "synthetic-qr-setup-failure"; screenshot.lifetime = .keepAlways; add(screenshot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "synthetic-qr-setup-accessibility"; tree.lifetime = .keepAlways; add(tree)
        }
        try super.tearDownWithError()
    }
    private func app() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test"]
        app.launchEnvironment["PIVOT_QA_KEYCHAIN_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15))
        return app
    }
    private func link(age: TimeInterval = 0) -> URL {
        var parts = URLComponents()
        parts.scheme = "pivot"; parts.host = "coach-setup"
        let issued = Int(Date().addingTimeInterval(-age).timeIntervalSince1970)
        let endpoint = "https://synthetic.workers.dev/v1/coach", code = "ABCD234567"
        let salt = Data((0..<16).map { UInt8($0) })
        var derived = [UInt8](repeating: 0, count: 32)
        let status = derived.withUnsafeMutableBufferPointer { output in
            code.withCString { password in salt.withUnsafeBytes { source in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, code.utf8.count,
                    source.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 100_000, output.baseAddress!, output.count)
            } }
        }
        XCTAssertEqual(status, 0)
        let box = try! AES.GCM.seal(Data(String(repeating: "a", count: 43).utf8), using: SymmetricKey(data: Data(derived)),
            nonce: AES.GCM.Nonce(data: Data((16..<28).map { UInt8($0) })),
            authenticating: Data("PivotCoachSetupV2|\(endpoint)|\(issued)".utf8))
        let bytes = salt + box.combined!
        let payload = bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        parts.queryItems = [.init(name: "version", value: "2"), .init(name: "issued", value: String(issued)),
            .init(name: "endpoint", value: endpoint), .init(name: "payload", value: payload)]
        return parts.url!
    }
    func testQRCodeImportProtectsTokenAndRequiresExplicitConsent() {
        let app = app()
        app.open(link())
        XCTAssertTrue(app.secureTextFields["online-coach-token"].waitForExistence(timeout: 10))
        let input = app.textFields["online-coach-endpoint"]
        XCTAssertEqual(input.value as? String, "https://synthetic.workers.dev/v1/coach")
        XCTAssertFalse((app.secureTextFields["online-coach-token"].value as? String ?? "").contains(String(repeating: "a", count: 43)))
        XCTAssertFalse(app.buttons["online-coach-save"].isEnabled)
        let cancel = app.buttons["Annulla"]
        XCTAssertTrue(cancel.isHittable); cancel.tap()
        app.buttons["open-pivot-coach"].tap()
        XCTAssertTrue(app.staticTexts["coach-online-mode"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["coach-online-mode"].label, "Base locale")
    }
    func testQRCodeExplicitSavePersistsOnlyProtectedConfigurationAcrossLaunches() {
        let app = app()
        app.open(link())
        unlock(app)
        let namespace = app.staticTexts["online-coach-qa-namespace"]
        XCTAssertTrue(namespace.waitForExistence(timeout: 5))
        XCTAssertEqual(namespace.label, "Contenitore QA: " + app.launchEnvironment["PIVOT_QA_KEYCHAIN_ID"]!)
        let consent = app.switches["online-coach-consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 10))
        scrollControlIntoView(consent, in: app)
        XCTAssertTrue(consent.isHittable)
        XCTAssertEqual(consent.value as? String, "0")
        // SwiftUI exposes a long label and the trailing native switch as one
        // row. Tap the visible knob, not the centre of the multiline label.
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let consentChanged = expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: consent)
        wait(for: [consentChanged], timeout: 5)
        let save = app.buttons["online-coach-save"]
        scrollControlIntoView(save, in: app)
        XCTAssertTrue(save.isEnabled); save.tap()
        // An underlying button can still exist while the QR sheet covers it.
        // Require a successful save/dismissal before attempting navigation.
        let review = app.staticTexts["online-coach-qr-review"]
        XCTAssertTrue(review.waitForNonExistence(timeout: 10), "Il salvataggio deve chiudere la revisione QR; verificare la diagnostica QA del portachiavi negli allegati.")
        openCoach(app)
        XCTAssertTrue(app.staticTexts["coach-online-mode"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["coach-online-mode"].label, "AI online")
        app.navigationBars.buttons.firstMatch.tap()
        app.terminate(); app.launch()
        openCoach(app)
        XCTAssertTrue(app.staticTexts["coach-online-mode"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["coach-online-mode"].label, "AI online")
        // No message is sent: this synthetic endpoint must never be contacted.
    }
    private func openCoach(_ app: XCUIApplication) {
        let button = app.buttons["open-pivot-coach"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        let hittable = NSPredicate(format: "hittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: button)], timeout: 10), .completed)
        button.tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 10))
    }
    private func unlock(_ app: XCUIApplication, code: String = "ABCD234567") {
        let field = app.secureTextFields["online-coach-activation-code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for _ in 0..<8 { if field.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(field.isHittable); field.tap(); field.typeText(code)
        let done = app.buttons["Fine"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        let button = app.buttons["online-coach-unlock"]
        for _ in 0..<5 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.isEnabled); button.tap()
        if code == "ABCD234567" {
            XCTAssertTrue(app.staticTexts["Token sbloccato, non mostrato. Ora puoi leggere e confermare il consenso."].waitForExistence(timeout: 12))
        }
    }
    func testQRCodeWrongCodeKeepsConfigurationDisabled() {
        let app = app(); app.open(link())
        unlock(app, code: "ABCD234568")
        XCTAssertTrue(app.staticTexts["Codice errato o QR non valido. Controlla il codice sul computer o richiedi un nuovo QR."].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["online-coach-save"].isEnabled)
        app.buttons["Annulla"].tap()
        app.buttons["open-pivot-coach"].tap()
        XCTAssertTrue(app.staticTexts["coach-online-mode"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["coach-online-mode"].label, "Base locale")
    }
    func testExpiredQRCodeDoesNotOpenOrEnableConfiguration() {
        let app = app()
        app.open(link(age: 360))
        let alert = app.alerts["Pivot"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertFalse(app.secureTextFields["online-coach-token"].exists)
        XCTAssertTrue(alert.staticTexts["Il QR non è valido o è scaduto. Richiedine uno nuovo sul computer."].exists)
        alert.buttons["OK"].tap()
        app.buttons["open-pivot-coach"].tap()
        XCTAssertTrue(app.staticTexts["coach-online-mode"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["coach-online-mode"].label, "Base locale")
    }
}
