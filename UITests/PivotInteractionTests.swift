import XCTest

final class PivotInteractionTests: XCTestCase {
    func testIncomeSummarySwipesToChart() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--payment-schedule-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Entrate"].waitForExistence(timeout: 10)); app.tabBars.buttons["Entrate"].tap()
        let carousel = app.collectionViews["income-carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 8)); carousel.swipeLeft()
        let chart = app.staticTexts["Andamento incassi"]
        XCTAssertTrue(chart.waitForExistence(timeout: 5)); XCTAssertTrue(chart.isHittable)
    }
    func testAutofilledActivityRetainsManualCorrectionAfterRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--student-recognition-test", "--autofill-test"]; app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 15))
        let details = app.buttons["Dettagli e registrazione"]
        for _ in 0..<8 { if details.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(details.isHittable); details.tap()
        let autofill = app.buttons["activity-autofill"]
        XCTAssertTrue(autofill.waitForExistence(timeout: 5)); autofill.tap()
        app.buttons["activity-save"].tap()
        XCTAssertTrue(app.navigationBars["Pivot"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Diario"].tap()
        let firstRow = app.buttons["diary-event-student-test"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10))
        for _ in 0..<12 { if firstRow.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(firstRow.isHittable); firstRow.tap()
        var notes = app.textFields["activity-notes"]
        if !notes.exists { notes = app.textViews["activity-notes"] }
        for _ in 0..<8 { if notes.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(notes.isHittable); notes.tap(); notes.typeText("Correzione manuale conservata")
        if app.buttons["Fine"].exists { app.buttons["Fine"].tap() }
        app.buttons["activity-save"].tap()
        XCUIDevice.shared.press(.home); app.activate(); app.terminate(); app.launch()
        app.tabBars.buttons["Diario"].tap()
        let row = app.buttons["diary-event-student-test"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<12 { if row.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(row.isHittable); row.tap()
        let saved = app.descendants(matching: .any)["activity-notes"]
        for _ in 0..<8 { if saved.exists { break }; app.swipeUp() }
        XCTAssertTrue(String(describing: saved.value).contains("Correzione manuale conservata"))
    }
    func testTrainingRevisionStatisticsAndOfflineExtraPickerAreReachable() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--training-test", "--training-edit-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 10)); app.tabBars.buttons["Palestra"].tap()
        let importer = app.buttons["import-training-fixture"]
        for _ in 0..<10 { if importer.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(importer.isHittable); importer.tap()
        XCTAssertTrue(app.buttons["Usa questa scheda"].waitForExistence(timeout: 8)); app.buttons["Usa questa scheda"].tap()
        let editor = app.buttons["edit-training-plan"]
        for _ in 0..<10 { if editor.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(editor.isHittable); editor.tap()
        let name = app.textFields["training-plan-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(" aggiornata")
        if app.buttons["Fine"].exists { app.buttons["Fine"].tap() }
        let save = app.buttons["training-plan-save"]
        for _ in 0..<8 { if save.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(save.isHittable); save.tap()
        XCTAssertTrue(app.staticTexts["Scheda TEST aggiornata"].waitForExistence(timeout: 5))
        let imageChoice = app.buttons["choose-exercise-image-test-exercise"]
        for _ in 0..<8 { if imageChoice.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(imageChoice.waitForExistence(timeout: 8)); imageChoice.tap()
        XCTAssertTrue(app.navigationBars["Scegli immagine"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Non c'è? Cerca in tutto il catalogo"].waitForExistence(timeout: 5))
        app.buttons["Non c'è? Cerca in tutto il catalogo"].tap()
        let imageChest = app.buttons["image-picker-group-bar-chest"]
        XCTAssertTrue(imageChest.waitForExistence(timeout: 5)); XCTAssertTrue(imageChest.isHittable); imageChest.tap()
        let benchImage = app.buttons["catalog-image-Barbell_Bench_Press_-_Medium_Grip"]
        for _ in 0..<8 { if benchImage.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(benchImage.isHittable); benchImage.tap()
        XCTAssertTrue(app.navigationBars["Palestra"].waitForExistence(timeout: 5))
        // Backgrounding flushes the coalesced save, as when closing the app on iPhone.
        XCUIDevice.shared.press(.home); app.activate()
        app.terminate(); app.launch(); app.tabBars.buttons["Palestra"].tap()
        let statistics = app.buttons["exercise-statistics-test-exercise"]
        for _ in 0..<8 { if statistics.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(statistics.isHittable)
        XCTAssertFalse(app.buttons["choose-exercise-image-test-exercise"].exists)
        let groups = app.scrollViews["exercise-group-bar"]
        let galleryArms = app.buttons["exercise-group-bar-arms"], galleryChest = app.buttons["exercise-group-bar-chest"]
        if !galleryArms.isHittable { groups.swipeLeft() }
        XCTAssertTrue(galleryArms.isHittable); galleryArms.tap(); XCTAssertFalse(statistics.exists)
        if !galleryChest.isHittable { groups.swipeRight() }
        XCTAssertTrue(galleryChest.isHittable); galleryChest.tap()
        XCTAssertTrue(statistics.waitForExistence(timeout: 5)); XCTAssertTrue(statistics.isHittable); statistics.tap()
        XCTAssertTrue(app.navigationBars["Progressi"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Principali: Pettorali"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let day = app.buttons["workout-day-test-a"]
        for _ in 0..<10 { if day.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(day.isHittable); day.tap()
        XCTAssertTrue(app.buttons["Inizia allenamento"].waitForExistence(timeout: 5)); app.buttons["Inizia allenamento"].tap()
        let extra = app.buttons["add-workout-exercise"]
        for _ in 0..<12 { if extra.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(extra.isHittable); extra.tap()
        XCTAssertTrue(app.navigationBars["Scegli esercizio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "876")).firstMatch.waitForExistence(timeout: 8))
    }
    func testWeeklyHabitAndOneReceiptForPreviousLessonPersist() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--payment-schedule-test"]; app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 15))
        let details = app.buttons["Dettagli e registrazione"]
        for _ in 0..<6 { if details.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(details.isHittable); details.tap()
        let amount = app.textFields["lesson-amount"]
        for _ in 0..<8 { if amount.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(amount.isHittable); amount.tap(); amount.typeText("18"); app.buttons["Fine"].tap()
        let received = app.switches["Ho già ricevuto un pagamento"]
        for _ in 0..<5 { if received.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(received.isHittable); received.tap()
        let receipt = app.textFields["lesson-received-amount"]
        for _ in 0..<5 { if receipt.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(receipt.isHittable); receipt.tap(); receipt.typeText("36"); app.buttons["Fine"].tap()
        let timing = app.descendants(matching: .any)["payment-timing"]
        for _ in 0..<5 { if timing.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(timing.exists)
        XCTAssertTrue((timing.label + String(describing: timing.value)).contains("settimana"))
        let done = app.buttons["Fatto"]
        for _ in 0..<10 { if done.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(done.isHittable); done.tap(); app.buttons["activity-save"].tap()
        XCTAssertTrue(app.navigationBars["Pivot"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate(); app.tabBars.buttons["Entrate"].tap()
        let student = app.buttons["client-detail-44444444-4444-4444-8444-444444444444"]
        for _ in 0..<10 { if student.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(student.isHittable); student.tap()
        XCTAssertTrue(app.staticTexts["student-balance-clear"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.tabBars.buttons["Entrate"].tap()
        for _ in 0..<10 { if student.isHittable { break }; app.swipeUp() }
        student.tap()
        XCTAssertTrue(app.staticTexts["student-balance-clear"].waitForExistence(timeout: 5))
        let habit = app.descendants(matching: .any)["student-payment-cadence"]
        XCTAssertTrue((habit.label + String(describing: habit.value)).contains("settimana"))
    }
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
        XCTAssertTrue(app.buttons["Collega app Salute"].waitForExistence(timeout: 5))
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
