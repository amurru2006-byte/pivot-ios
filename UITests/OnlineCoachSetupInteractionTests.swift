import XCTest
import CryptoKit
import CommonCrypto

final class OnlineCoachSetupInteractionTests: XCTestCase {
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
        let consent = app.switches["online-coach-consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 10))
        for _ in 0..<8 { if consent.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(consent.isHittable); consent.tap()
        let save = app.buttons["online-coach-save"]
        for _ in 0..<5 { if save.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 8))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["open-pivot-coach"].waitForExistence(timeout: 15)); app.buttons["open-pivot-coach"].tap()
        XCTAssertTrue(app.staticTexts["coach-online-mode"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["coach-online-mode"].label, "AI online")
        // No message is sent: this synthetic endpoint must never be contacted.
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
