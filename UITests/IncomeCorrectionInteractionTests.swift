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
    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--financial-corrections-test"] + extra
        app.launchEnvironment["PIVOT_QA_FINANCE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Entrate"].waitForExistence(timeout: 15)); app.tabBars.buttons["Entrate"].tap()
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        scrollControlIntoView(element, in: app)
    }
    func testRecentReceiptsExpandAndCollapseWithoutChangingTotals() {
        let app = launch(extra: ["--receipts-list-test"])
        let total = app.staticTexts["income-summary-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 8)); let before = total.label
        let expand = app.buttons["income-receipts-expand"]
        scrollControlIntoView(expand, in: app, maxSwipes: 15)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "receipt-detail-"))
        XCTAssertEqual(rows.count, 5)
        XCTAssertLessThanOrEqual(expand.frame.maxY, rows.element(boundBy: 0).frame.minY,
                                 "Espandi e riduci devono essere sopra la lista")
        XCTAssertEqual(expand.label, "Mostra tutto"); expand.tap()
        XCTAssertEqual(rows.count, 7)
        XCTAssertTrue(expand.isHittable, "Si deve poter richiudere senza attraversare tutte le righe")
        scrollControlIntoView(expand, in: app, maxSwipes: 15)
        XCTAssertEqual(expand.label, "Mostra meno"); expand.tap()
        XCTAssertEqual(rows.count, 5); XCTAssertEqual(total.label, before)
    }
    private func replace(_ field: XCUIElement, with value: String, app: XCUIApplication) {
        reveal(field, app: app); field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
        if app.buttons["Fine"].waitForExistence(timeout: 2) { app.buttons["Fine"].tap() }
    }
    func testContactTodayRestoresCurrentMonthWithoutChangingMoney() {
        let app = launch()
        let contact = app.buttons["client-detail-55555555-5555-4555-8555-555555555551"]
        reveal(contact, app: app); contact.tap()
        let period = app.segmentedControls["client-income-period"]
        reveal(period, app: app); period.buttons["Mese"].tap()
        let received = app.staticTexts["client-income-received"]
        XCTAssertTrue(received.waitForExistence(timeout: 8)); let before = received.label
        let months = ["Gen", "Feb", "Mar", "Apr", "Mag", "Giu", "Lug", "Ago", "Set", "Ott", "Nov", "Dic"]
        let currentMonth = Calendar.current.component(.month, from: Date())
        let other = currentMonth == 1 ? "Feb" : "Gen"
        let picker = app.buttons["client-income-month"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); reveal(picker, app: app)
        let viewport = app.descendants(matching: .any)["client-income-carousel"].firstMatch
        XCTAssertGreaterThanOrEqual(viewport.frame.minY, picker.frame.maxY,
                                    "Il carosello non deve coprire i controlli del mese")
        picker.tap()
        let option = app.buttons[other]; XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        let today = app.buttons["client-income-today"]
        reveal(today, app: app); today.tap()
        XCTAssertTrue(picker.label.contains(months[currentMonth - 1]))
        XCTAssertEqual(received.label, before)
        XCTAssertEqual(period.buttons["Mese"].isSelected, true)
    }
    func testContactBarsKeepOnlyOneExactValueAndCanClearIt() {
        let app = launch()
        let contact = app.buttons["client-detail-55555555-5555-4555-8555-555555555551"]
        reveal(contact, app: app); contact.tap()
        let graph = app.buttons["client-income-page-1"]
        reveal(graph, app: app); graph.tap()
        let chart = app.descendants(matching: .any)["client-income-chart"].firstMatch
        reveal(chart, app: app); XCTAssertTrue(chart.exists)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).tap()
        let value = app.staticTexts["client-income-bar-value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5)); let first = value.label
        XCTAssertTrue(first.contains("Gen")); XCTAssertTrue(first.contains("€"))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
        XCTAssertTrue(value.label.contains("Feb")); XCTAssertNotEqual(value.label, first)
        XCTAssertEqual(app.staticTexts.matching(identifier: "client-income-bar-value").count, 1)
        let close = app.buttons["Chiudi valore selezionato"]
        reveal(close, app: app); close.tap(); XCTAssertFalse(value.exists)
    }
    func testContactDefaultsAndMultipleOriginsPersistAfterRelaunch() {
        let app = launch()
        let contact = app.buttons["client-detail-55555555-5555-4555-8555-555555555551"]
        reveal(contact, app: app); contact.tap(); app.buttons["client-edit"].tap()
        let disclosure = app.buttons["Predefiniti e tragitti"]
        reveal(disclosure, app: app); disclosure.tap()
        let method = app.buttons["client-default-payment"]
        reveal(method, app: app); method.tap(); app.buttons["Bonifico"].tap()
        replace(app.textFields["client-default-destination"], with: "Luogo QA", app: app)
        XCTAssertEqual(app.textFields["client-default-destination"].value as? String, "Luogo QA")
        let add = app.buttons["client-origin-add"]
        let fields = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "client-origin-name-"))
        reveal(add, app: app); add.tap(); replace(fields.element(boundBy: 0), with: "Partenza A", app: app)
        reveal(add, app: app); add.tap(); replace(fields.element(boundBy: 1), with: "Partenza B", app: app)
        reveal(app.textFields["client-default-destination"], app: app)
        XCTAssertEqual(app.textFields["client-default-destination"].value as? String, "Luogo QA")
        let save = app.buttons["client-save"]; reveal(save, app: app); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.textFields["client-name"].waitForNonExistence(timeout: 10), "La finestra si chiude dopo il salvataggio durevole")
        XCTAssertTrue(app.buttons["client-edit"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.tabBars.buttons["Entrate"].tap()
        reveal(contact, app: app); contact.tap(); app.buttons["client-edit"].tap()
        reveal(disclosure, app: app); disclosure.tap()
        reveal(app.textFields["client-default-destination"], app: app)
        XCTAssertEqual(app.textFields["client-default-destination"].value as? String, "Luogo QA")
        XCTAssertEqual(fields.count, 2)
        reveal(fields.element(boundBy: 0), app: app)
        XCTAssertEqual(fields.element(boundBy: 0).value as? String, "Partenza A")
        reveal(fields.element(boundBy: 1), app: app)
        XCTAssertEqual(fields.element(boundBy: 1).value as? String, "Partenza B")
        reveal(method, app: app)
        XCTAssertTrue(method.label.contains("Bonifico"))
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
        let add = app.buttons["Aggiungi contatto"]; reveal(add, app: app); add.tap()
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

    func testContactPeriodsGraphAndAddPartialReceiptKeepFullHistory() {
        let app = launch(); merge(app)
        let received = app.staticTexts["client-income-received"]
        scrollControlIntoView(received, in: app); XCTAssertTrue(received.label.contains("15,00"))
        let due = app.staticTexts["client-income-outstanding"]
        XCTAssertTrue(due.label.contains("5,00"))
        let period = app.segmentedControls["client-income-period"]
        scrollControlIntoView(period, in: app); period.buttons["Mese"].tap()
        XCTAssertTrue(received.label.contains("15,00")); XCTAssertTrue(due.label.contains("5,00"))
        period.buttons["Tutto"].tap(); XCTAssertTrue(received.label.contains("15,00"))
        let graph = app.buttons["client-income-page-1"]
        scrollControlIntoView(graph, in: app); graph.tap()
        XCTAssertTrue(app.descendants(matching: .any)["client-income-chart"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(app.descendants(matching: .any)["client-income-carousel"].firstMatch.frame.height, 360,
                                 "Il grafico sintetico non deve mantenere un minimo vuoto di480punti")
        let add = app.buttons["client-add-activity"]
        scrollControlIntoView(add, in: app); add.tap()
        replace(app.textFields["income-manual-compensation"], with: "20", app: app)
        let hasReceipt = app.switches["income-manual-has-receipt"]
        scrollControlIntoView(hasReceipt, in: app)
        let actualSwitch = hasReceipt.switches.firstMatch
        if actualSwitch.exists { actualSwitch.tap() } else { hasReceipt.tap() }
        replace(app.textFields["income-manual-received"], with: "15", app: app)
        let save = app.buttons["income-manual-save"]
        scrollControlIntoView(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        let summary = app.buttons["client-income-page-0"]
        scrollControlIntoView(summary, in: app); summary.tap()
        scrollControlIntoView(received, in: app); XCTAssertTrue(received.label.contains("30,00"))
        let carousel = app.descendants(matching: .any)["client-income-carousel"].firstMatch
        XCTAssertTrue(carousel.exists)
        XCTAssertLessThanOrEqual(carousel.frame.height, 260, "Il riepilogo sintetico deve seguire i contenuti, non l'altezza del grafico")
        XCTAssertGreaterThanOrEqual(received.frame.minY, carousel.frame.minY - 1)
        XCTAssertLessThanOrEqual(received.frame.maxY, carousel.frame.maxY + 1)
        XCTAssertTrue(due.label.contains("10,00"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "contact-summary-partial-receipt"; screenshot.lifetime = .keepAlways; self.add(screenshot)
    }

    func testGiftContactRecordsAReceiptWithoutInventingWorkedHours() {
        let app = launch()
        let add = app.buttons["Aggiungi contatto"]
        scrollControlIntoView(add, in: app); add.tap()
        replace(app.textFields["client-name"], with: "Contributo Test", app: app)
        let activity = app.descendants(matching: .any)["client-activity"].firstMatch
        scrollControlIntoView(activity, in: app); activity.tap()
        let gift = app.buttons["Regali e contributi"]
        XCTAssertTrue(gift.waitForExistence(timeout: 8)); gift.tap()
        replace(app.textFields["client-rate"], with: "25", app: app)
        let saveContact = app.buttons["client-save"]
        scrollControlIntoView(saveContact, in: app); saveContact.tap()
        let contact = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "client-detail-", "Contributo Test")).firstMatch
        XCTAssertTrue(contact.waitForExistence(timeout: 8)); scrollControlIntoView(contact, in: app); contact.tap()
        let newIncome = app.buttons["client-add-activity"]
        scrollControlIntoView(newIncome, in: app); newIncome.tap()
        XCTAssertTrue(app.buttons["income-manual-save"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Durata della lezione"].exists)
        XCTAssertFalse(app.staticTexts["Durata del lavoro"].exists)
        XCTAssertEqual(app.switches["income-manual-has-receipt"].value as? String, "1")
        let save = app.buttons["income-manual-save"]
        scrollControlIntoView(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        let received = app.staticTexts["client-income-received"]
        XCTAssertTrue(received.waitForExistence(timeout: 8)); XCTAssertTrue(received.label.contains("25,00"))
        XCTAssertTrue(app.staticTexts["client-income-outstanding"].label.contains("0,00"))
    }
}
