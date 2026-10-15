import XCTest

final class IncomeCorrectionInteractionTests: XCTestCase {
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            let app = XCUIApplication()
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "financial-correction-failure"; screenshot.lifetime = .keepAlways; add(screenshot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "financial-correction-accessibility"; tree.lifetime = .keepAlways; add(tree)
        }
        try super.tearDownWithError()
    }
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--financial-corrections-test"]
        app.launchEnvironment["PIVOT_QA_FINANCE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Entrate"].waitForExistence(timeout: 15)); app.tabBars.buttons["Entrate"].tap()
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0..<10 { if element.isHittable { return }; if up { app.swipeUp() } else { app.swipeDown() } }
        XCTAssertTrue(element.isHittable)
    }
    private func replace(_ field: XCUIElement, with value: String, app: XCUIApplication) {
        reveal(field, app: app); field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
        if app.buttons["Fine"].waitForExistence(timeout: 2) { app.buttons["Fine"].tap() }
    }
    private func merge(_ app: XCUIApplication) {
        let target = app.buttons["client-detail-55555555-5555-4555-8555-555555555551"]
        reveal(target, app: app); target.tap()
        let merge = app.buttons["client-merge"]; reveal(merge, app: app); merge.tap()
        let source = app.descendants(matching: .any)["client-merge-source"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5)); source.tap()
        let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Marta Test")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        let confirmation = app.switches["client-merge-confirm"]
        reveal(confirmation, app: app); confirmation.tap()
        let save = app.buttons["client-merge-save"]; reveal(save, app: app); save.tap()
        XCTAssertTrue(app.buttons["client-edit"].waitForExistence(timeout: 5))
    }
    func testExplicitMergeAndRateUpdateKeepSingleStudentAfterRelaunch() {
        let app = launch(); merge(app)
        app.buttons["client-edit"].tap()
        replace(app.textFields["client-rate"], with: "18", app: app)
        let save = app.buttons["client-save"]; reveal(save, app: app); save.tap()
        XCTAssertTrue(app.buttons["client-edit"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "student-merged-with-history"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCUIDevice.shared.press(.home); app.activate(); app.terminate(); app.launch(); app.tabBars.buttons["Entrate"].tap()
        let kept = app.buttons["client-detail-55555555-5555-4555-8555-555555555551"]
        reveal(kept, app: app); XCTAssertFalse(app.buttons["client-detail-55555555-5555-4555-8555-555555555552"].exists)
        kept.tap(); XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 lezioni registrate")).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let add = app.buttons["Aggiungi studente"]; reveal(add, app: app); add.tap()
        replace(app.textFields["client-name"], with: "Marta Test", app: app)
        XCTAssertTrue(app.staticTexts["client-update-existing"].waitForExistence(timeout: 5))
        replace(app.textFields["client-rate"], with: "20", app: app)
        reveal(app.buttons["client-save"], app: app); app.buttons["client-save"].tap()
        reveal(kept, app: app); XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "client-detail-")).count, 1)
    }
    func testCorrectionsPersistAndDoNotInventAnAdditionalReceipt() {
        let app = launch()
        let receipt = app.buttons["receipt-detail-55555555-5555-4555-8555-555555555554"]
        reveal(receipt, app: app); receipt.tap()
        XCTAssertTrue(app.navigationBars["Pagamento"].waitForExistence(timeout: 10))
        let compensation = app.buttons["income-edit-compensation"]
        reveal(compensation, app: app); compensation.tap()
        replace(app.textFields["income-corrected-amount"], with: "25", app: app)
        reveal(app.buttons["income-correction-save"], app: app); app.buttons["income-correction-save"].tap()
        let editReceipt = app.buttons["income-edit-receipt-55555555-5555-4555-8555-555555555554"]
        reveal(editReceipt, app: app); editReceipt.tap()
        replace(app.textFields["income-corrected-amount"], with: "10", app: app)
        reveal(app.buttons["income-correction-save"], app: app); app.buttons["income-correction-save"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "income-edit-receipt-")).count, 1)
        XCUIDevice.shared.press(.home); app.activate(); app.terminate(); app.launch(); app.tabBars.buttons["Entrate"].tap()
        reveal(receipt, app: app); receipt.tap()
        XCTAssertTrue(app.navigationBars["Pagamento"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Totale 25")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ricevuto 10")).firstMatch.exists)
        let audit = app.buttons["Correzioni registrate (2)"]; reveal(audit, app: app); XCTAssertTrue(audit.exists)
    }
    func testCompensationBelowReceivedShowsErrorAndCanBeCancelled() {
        let app = launch(); let receipt = app.buttons["receipt-detail-55555555-5555-4555-8555-555555555554"]
        reveal(receipt, app: app); receipt.tap()
        XCTAssertTrue(app.navigationBars["Pagamento"].waitForExistence(timeout: 10))
        reveal(app.buttons["income-edit-compensation"], app: app); app.buttons["income-edit-compensation"].tap()
        replace(app.textFields["income-corrected-amount"], with: "10", app: app)
        reveal(app.buttons["income-correction-save"], app: app); app.buttons["income-correction-save"].tap()
        XCTAssertTrue(app.staticTexts["income-correction-error"].waitForExistence(timeout: 5)); app.buttons["Annulla"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Totale 20")).firstMatch.waitForExistence(timeout: 5))
    }
}
