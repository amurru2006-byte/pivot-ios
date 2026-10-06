import XCTest

final class PivotInteractionTests: XCTestCase {
    func testCalendarStudentIsRecognizedAndPaymentUsesSavedPerson() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--student-recognition-test"]; app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 15))
        let details = app.buttons["Dettagli e registrazione"]
        for _ in 0..<6 { if details.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(details.isHittable); details.tap()
        let recognized = app.descendants(matching: .any)["recognized-student"]
        for _ in 0..<8 { if recognized.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(recognized.exists)
        XCTAssertTrue(recognized.label.contains("Giulia Rossi"))
        XCTAssertFalse(app.textFields["student-name"].exists)
        let amount = app.textFields["lesson-amount"]
        XCTAssertTrue(amount.isHittable); amount.tap(); amount.typeText("18")
        if app.buttons["Fine"].waitForExistence(timeout: 3) { app.buttons["Fine"].tap() }
        let done = app.buttons["Fatto"]
        for _ in 0..<8 { if done.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(done.isHittable); done.tap()
        app.buttons["activity-save"].tap()
        XCTAssertTrue(app.navigationBars["Pivot"].waitForExistence(timeout: 5))
        // Backgrounding flushes pending writes; reopening must retain the linked lesson.
        XCUIDevice.shared.press(.home); app.activate()
        app.tabBars.buttons["Entrate"].tap()
        let student = app.staticTexts["Giulia Rossi"].firstMatch
        for _ in 0..<8 { if student.exists { break }; app.swipeUp() }
        XCTAssertTrue(student.exists)
        app.terminate(); app.launch(); app.tabBars.buttons["Entrate"].tap()
        for _ in 0..<8 { if app.staticTexts["Giulia Rossi"].firstMatch.exists { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Giulia Rossi"].firstMatch.exists)
    }
    func testSettingsSectionsAndDictationButtonAreReachable() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Impostazioni"].waitForExistence(timeout: 10)); app.tabBars.buttons["Impostazioni"].tap()
        let health = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Salute e Apple Watch")).firstMatch
        for _ in 0..<5 { if health.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(health.isHittable); health.tap()
        XCTAssertTrue(app.buttons["Collega / verifica Salute"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Oggi"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 15))
        let coach = app.buttons["open-pivot-coach"]
        for _ in 0..<8 { if coach.isHittable { break }; app.swipeDown() }; XCTAssertTrue(coach.isHittable); coach.tap()
        let dictation = app.buttons["coach-dictation"]
        for _ in 0..<12 { if dictation.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(dictation.isHittable)
    }
    func testQuickOutcomeSaveReturnsHomeAndKeepsCompletedActivityInHistory() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test"]; app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 15))
        let details = app.buttons["Dettagli e registrazione"]
        for _ in 0..<6 { if details.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(details.isHittable); details.tap()
        let done = app.buttons["Fatto"]
        for _ in 0..<6 { if done.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(done.isHittable); done.tap()
        app.buttons["activity-save"].tap()
        XCTAssertTrue(app.navigationBars["Pivot"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Attività"].exists)
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Già segnate")).firstMatch
        for _ in 0..<10 { if history.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(history.isHittable)
    }
    func testCoachConversationPersistsWithoutDownloadingAI() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 15))
        let coach = app.buttons["open-pivot-coach"]
        for _ in 0..<6 { if coach.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(coach.isHittable); coach.tap()
        let input = app.descendants(matching: .any)["coach-message-input"]
        for _ in 0..<12 { if input.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(input.isHittable)
        let text = "Preferisco studiare con esercizi brevi: prova persistenza Coach."
        input.tap(); input.typeText(text)
        let done = app.buttons["Fine"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        let send = app.buttons["coach-send"]
        for _ in 0..<5 { if send.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(send.isHittable); send.tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 15))
        let reopened = app.buttons["open-pivot-coach"]
        for _ in 0..<6 { if reopened.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(reopened.isHittable); reopened.tap()
        for _ in 0..<12 { if app.staticTexts[text].exists { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts[text].exists)
        XCTAssertFalse(app.staticTexts["Modello locale attivo"].exists)
    }

    func testTrainingPDFImportSetLoggingAndPersistence() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--training-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Palestra"].tap()
        let importer = app.buttons["import-training-fixture"]
        for _ in 0..<8 { if importer.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(importer.isHittable); importer.tap()
        let confirm = app.buttons["Usa questa scheda"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8)); confirm.tap()
        let day = app.buttons["workout-day-test-a"]
        for _ in 0..<8 { if day.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        let start = app.buttons["Inizia allenamento"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        let kg = app.textFields["weight-test-exercise-0"]
        for _ in 0..<8 { if kg.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(kg.isHittable); kg.tap(); kg.typeText("25")
        app.buttons["Fine"].tap()
        let reps = app.textFields["reps-test-exercise-0"]
        reps.tap(); reps.typeText("8"); app.buttons["Fine"].tap()
        let done = app.switches["set-done-test-exercise-0"]
        XCTAssertTrue(done.exists); done.tap()
        let finish = app.buttons["Termina allenamento"]
        for _ in 0..<8 { if finish.isHittable { break }; app.swipeDown() }
        finish.tap()
        XCTAssertTrue(app.staticTexts["Allenamento terminato"].waitForExistence(timeout: 4))
        app.terminate(); app.launch(); app.tabBars.buttons["Palestra"].tap()
        let reopened = app.buttons["workout-day-test-a"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5)); reopened.tap()
        // A fresh unlinked workout proposes the completed session's load, not a completed set.
        let proposed = app.textFields["weight-test-exercise-0"]
        for _ in 0..<8 { if proposed.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(proposed.exists)
        XCTAssertEqual(proposed.value as? String, "25,0")
        XCTAssertEqual(app.textFields["reps-test-exercise-0"].value as? String, "8")
    }

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
        app.buttons["Timer facoltativo"].tap()
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
        let save = app.buttons["Salva attività"]
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
