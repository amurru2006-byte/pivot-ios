import XCTest

final class PivotInteractionTests: XCTestCase {
    private let historyID = "33333333-3333-4333-8333-333333333333"
    private let emptyHistoryID = "44444444-4444-4444-8444-444444444444"
    private func prepareHistory(deletion: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--training-history-test"] + (deletion ? ["--history-deletion-test"] : [])
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let fixture = app.buttons["history-fixture"]
        for _ in 0..<15 { if fixture.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(fixture.isHittable); fixture.tap()
        XCTAssertTrue(app.staticTexts["Cronologia pronta"].waitForExistence(timeout: 5))
        openHistory(app)
        return app
    }
    private func openHistory(_ app: XCUIApplication) {
        let day = app.buttons["workout-day-history-squat-day"]
        for _ in 0..<15 { if day.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(day.waitForExistence(timeout: 8)); XCTAssertTrue(day.isHittable); day.tap()
        XCTAssertTrue(app.navigationBars["Allenamento"].waitForExistence(timeout: 5), app.debugDescription)
        let history = app.buttons["workout-day-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); XCTAssertTrue(history.isHittable, app.debugDescription); history.tap()
        XCTAssertTrue(app.navigationBars["Cronologia"].waitForExistence(timeout: 5), app.debugDescription)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-history-list"; image.lifetime = .keepAlways; add(image)
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "serie7-history-accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
    private func verifyHistory(_ app: XCUIApplication, label: String) {
        app.navigationBars["Cronologia"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Allenamento"].buttons.element(boundBy: 0).tap()
        let verify = app.buttons["history-verify"]
        for _ in 0..<15 { if verify.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(verify.isHittable); verify.tap()
        XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 8), app.debugDescription)
    }
    func testDayHistoryCorrectsCompletedWorkoutWithoutStartingRecoveryAndPersists() {
        let app = prepareHistory()
        let edit = app.buttons["history-open-" + historyID]
        for _ in 0..<6 { if edit.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(edit.isHittable, app.debugDescription); edit.tap()
        let field = app.textFields["weight-history-squat-0"]
        for _ in 0..<8 { if field.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(field.isHittable); field.tap()
        let value = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        XCTAssertFalse(app.alerts.firstMatch.exists, "Replacing a completed load must not interrupt typing with a modal error")
        field.typeText("50")
        XCTAssertTrue(app.buttons["Fine"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Fine"].tap()
        XCTAssertFalse(app.staticTexts["workout-rest-countdown"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-history-correction"; image.lifetime = .keepAlways; add(image)
        app.navigationBars["Allenamento"].buttons.element(boundBy: 0).tap()
        verifyHistory(app, label: "Cronologia verificata · correzione salvata")
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        openHistory(app)
        for _ in 0..<6 { if edit.isHittable { break }; app.swipeUp() }
        edit.tap()
        for _ in 0..<8 { if field.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(field.value as? String, "50,0")
        XCTAssertTrue(app.staticTexts["Allenamento terminato"].exists)
    }
    func testDayHistoryConfirmsDeletionOfRealAndEmptyWorkoutsAndPersists() {
        let app = prepareHistory(deletion: true)
        let empty = app.buttons["history-delete-" + emptyHistoryID]
        for _ in 0..<5 { if empty.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(empty.isHittable, app.debugDescription); empty.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons["Annulla"].tap(); XCTAssertTrue(empty.exists)
        empty.tap(); app.alerts.buttons["Elimina definitivamente"].tap()
        XCTAssertTrue(app.staticTexts["history-message"].waitForExistence(timeout: 8)); XCTAssertFalse(empty.exists)
        let real = app.buttons["history-delete-" + historyID]
        for _ in 0..<5 { if real.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(real.isHittable, app.debugDescription); real.tap()
        let warning = app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 serie svolte")).firstMatch
        XCTAssertTrue(warning.exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-history-delete-confirmation"; image.lifetime = .keepAlways; add(image)
        app.alerts.buttons["Elimina definitivamente"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-history-empty"].waitForExistence(timeout: 8))
        verifyHistory(app, label: "Cronologia verificata · eliminazioni salvate")
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        openHistory(app)
        XCTAssertTrue(app.descendants(matching: .any)["workout-history-empty"].exists)
    }
    func testFinishFromBottomAutomaticallyOpensPDFAndKeepsEndOnReopen() {
        verifyFinalization(reportFailure: false)
    }
    func testPDFWriteFailureKeepsWorkoutAndAllowsRetry() {
        verifyFinalization(reportFailure: true)
    }
    private func verifyFinalization(reportFailure: Bool) {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Notifiche") { alert in
            for title in ["Allow", "Consenti"] where alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--recovery-test", "--finalization-test"] + (reportFailure ? ["--report-failure-test"] : [])
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let fixture = app.buttons["recovery-fixture"]
        scrollControlIntoView(fixture, in: app); fixture.tap()
        XCTAssertTrue(app.staticTexts["Recupero pronto"].waitForExistence(timeout: 5))
        let url = URL(string: "pivot://workout/11111111-1111-4111-8111-111111111111?set=22222222-2222-4222-8222-222222222222")!
        app.open(url)
        let done = app.buttons["set-done-recovery-8-0"]
        XCTAssertTrue(done.waitForExistence(timeout: 8)); done.tap()
        let permission = app.alerts.firstMatch
        if permission.waitForExistence(timeout: 2) {
            for title in ["Allow", "Consenti"] where permission.buttons[title].exists { permission.buttons[title].tap(); break }
        }
        XCTAssertTrue(app.staticTexts["workout-rest-countdown"].exists)
        let finish = app.buttons["finish-workout"]
        for _ in 0..<8 { if finish.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(finish.isHittable); finish.tap()
        if reportFailure {
            let warning = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Allenamento salvato, ma il PDF non è stato creato:")).firstMatch
            XCTAssertTrue(warning.waitForExistence(timeout: 25), app.debugDescription)
            XCTAssertFalse(app.navigationBars["Report per il PT"].exists)
            XCTAssertFalse(app.staticTexts["workout-rest-countdown"].exists)
            XCTAssertTrue(finish.label.contains("Salva modifiche")); finish.tap()
        }
        XCTAssertTrue(app.navigationBars["Report per il PT"].waitForExistence(timeout: 8))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-auto-final-pdf"; image.lifetime = .keepAlways; add(image)
        app.buttons["Chiudi"].tap()
        XCTAssertFalse(app.staticTexts["workout-rest-countdown"].exists)
        let verify = app.buttons["verify-final-report"]
        for _ in 0..<8 { if verify.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(verify.isHittable); verify.tap()
        let report = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "PDF finale verificato · fine ")).firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 8)); let originalEnd = report.label
        app.launchArguments.removeAll { $0 == "--report-failure-test" }
        app.terminate(); app.open(url)
        XCTAssertTrue(app.navigationBars["Allenamento"].waitForExistence(timeout: 15))
        for _ in 0..<15 { if verify.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(verify.isHittable); verify.tap()
        XCTAssertTrue(report.waitForExistence(timeout: 8)); XCTAssertEqual(report.label, originalEnd)
        for _ in 0..<5 { if finish.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(finish.isHittable); finish.tap()
        XCTAssertTrue(app.navigationBars["Report per il PT"].waitForExistence(timeout: 8))
        app.buttons["Chiudi"].tap()
        for _ in 0..<5 { if verify.isHittable { break }; app.swipeUp() }
        verify.tap(); XCTAssertTrue(report.waitForExistence(timeout: 8)); XCTAssertEqual(report.label, originalEnd)
    }
    func testLiveActivityLayoutKeepsLargeButtonsWithinSystemHeight() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--preview", "--screen=workout-widget"]; app.launch()
        for id in ["working", "hold", "rest", "paused"] {
            let card = app.descendants(matching: .any)["live-preview-" + id].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 15))
            for _ in 0..<6 { if card.isHittable { break }; app.swipeUp() }
            XCTAssertLessThanOrEqual(card.frame.height, 160, id)
            if id == "rest" || id == "paused" {
                XCTAssertTrue(card.staticTexts["live-rest-next-values"].exists)
                XCTAssertTrue(card.staticTexts["live-rest-next-values"].label.contains("70"))
                XCTAssertTrue(card.staticTexts["live-rest-next-values"].label.contains("6 reps"))
                XCTAssertTrue(card.staticTexts["live-rest-next-prescription"].exists)
            }
            for button in card.buttons.allElementsBoundByIndex {
                // XCTest's converted screen coordinates can report 44 as 43.99999.
                // Allow only subpixel rounding; the actual layout still requires 44 pt.
                XCTAssertGreaterThanOrEqual(button.frame.width, 44 - 0.01, button.label)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.01, button.label)
            }
        }
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-live-activity-large-controls"; image.lifetime = .keepAlways; add(image)
    }
    func testRecoveryStaysReachableAtEighthExerciseAndLastSet() {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Notifiche") { alert in
            for title in ["Allow", "Consenti"] where alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            return false
        }
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--recovery-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let fixture = app.buttons["recovery-fixture"]
        scrollControlIntoView(fixture, in: app); fixture.tap()
        XCTAssertTrue(app.staticTexts["Recupero pronto"].waitForExistence(timeout: 5))
        let url = URL(string: "pivot://workout/11111111-1111-4111-8111-111111111111?set=22222222-2222-4222-8222-222222222222")!
        app.open(url)
        let done = app.buttons["set-done-recovery-8-0"]
        XCTAssertTrue(done.waitForExistence(timeout: 8)); done.tap()
        let permission = app.alerts.firstMatch
        if permission.waitForExistence(timeout: 2) {
            for title in ["Allow", "Consenti"] where permission.buttons[title].exists { permission.buttons[title].tap(); break }
        }
        let timer = app.staticTexts["workout-rest-countdown"], pause = app.buttons["workout-rest-pause"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5)); XCTAssertTrue(pause.isHittable)
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertTrue(timer.isHittable); XCTAssertTrue(pause.isHittable)
        XCTAssertEqual(app.staticTexts["workout-rest-exercise"].label, "Cable Crunch")
        XCTAssertGreaterThanOrEqual(pause.frame.height, 44); XCTAssertGreaterThanOrEqual(pause.frame.width, 44)
        XCTAssertLessThanOrEqual(pause.frame.maxY, app.tabBars.firstMatch.frame.minY)
        let collapse = app.buttons["workout-rest-collapse"]
        XCTAssertTrue(collapse.isHittable); collapse.tap()
        let expand = app.buttons["workout-rest-expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); XCTAssertTrue(timer.isHittable)
        XCTAssertFalse(pause.exists)
        expand.tap(); XCTAssertTrue(pause.waitForExistence(timeout: 5)); XCTAssertTrue(timer.isHittable)
        pause.tap(); XCTAssertTrue(app.staticTexts["Recupero in pausa"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-recovery-at-eighth-exercise"; image.lifetime = .keepAlways; add(image)
        app.terminate(); app.open(url)
        XCTAssertTrue(app.buttons["workout-rest-pause"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Recupero in pausa"].exists)
        app.buttons["workout-rest-reset"].tap()
        XCTAssertTrue(app.staticTexts["Recupero"].exists)
        app.buttons["workout-next-set"].tap()
        let restClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [restClosed], timeout: 8), .completed)
        let last = app.buttons["set-done-recovery-8-1"]
        XCTAssertTrue(last.isHittable); last.tap()
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workout-next-set"].label.contains("Chiudi recupero"))
        app.buttons["workout-next-set"].tap()
        let finalRestClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [finalRestClosed], timeout: 8), .completed)
        XCTAssertTrue(app.staticTexts["Serie registrate"].exists)
    }
    func testSerie7RankPopupUsesTheReceivedSecondCrestAndDoesNotRepeat() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--serie7-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let fixture = app.buttons["serie7-rank-fixture"]
        for _ in 0..<15 { if fixture.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(fixture.isHittable); fixture.tap()
        XCTAssertTrue(app.staticTexts["Rank Serie 7 pronto"].waitForExistence(timeout: 5))
        let url = URL(string: "pivot://workout/11111111-1111-4111-8111-111111111111?set=22222222-2222-4222-8222-222222222222")!
        app.open(url)
        let done = app.buttons["set-done-s7-bench-0"]
        XCTAssertTrue(done.waitForExistence(timeout: 8)); done.tap()
        let close = app.buttons["close-workout-achievement"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), app.debugDescription); close.tap() // PR first, then rank.
        // Inspect both exact texts in one snapshot. On the slower Intel
        // simulator, two separate queries consumed the real 4.5-second card
        // lifetime even though the recording showed the correct rank.
        let rankTexts = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Nuovo rank!", "Patto col ferro"]))
        let rankVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: rankTexts)
        XCTAssertEqual(XCTWaiter.wait(for: [rankVisible], timeout: 8), .completed)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-rank-patto-col-ferro"; image.lifetime = .keepAlways; add(image)
        XCTAssertTrue(close.waitForNonExistence(timeout: 12)) // Real automatic dismissal.
        app.terminate(); app.open(url)
        XCTAssertTrue(app.navigationBars["Allenamento"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["close-workout-achievement"].exists)
    }
    func testSerie7SevenRankSlotsAndManualProfilePersistWithoutInventedBirthDate() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--serie7-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let fixture = app.buttons["serie7-fixture"]
        scrollControlIntoView(fixture, in: app); fixture.tap()
        XCTAssertTrue(app.staticTexts["Serie 7 pronta"].waitForExistence(timeout: 5))
        let ranks = app.buttons["strength-ranks"]
        scrollControlIntoView(ranks, in: app); ranks.tap()
        XCTAssertTrue(app.navigationBars["Rank"].waitForExistence(timeout: 8), app.debugDescription)
        let names = ["Schiavo della gravità", "Patto col ferro", "Sfidante della fisica", "Distruttore di ego",
                     "Mutante", "Forza primordiale", "Onnipotente del carico"]
        for (index, name) in names.enumerated() {
            let row = app.buttons["strength-rank-level-\(index + 1)"]
            scrollControlIntoView(row, in: app)
            XCTAssertTrue(row.label.contains(name), row.label); row.tap()
            XCTAssertTrue(app.navigationBars["Immagini del rank"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.staticTexts[name].exists)
            XCTAssertTrue(app.images["rank-original-emblem"].exists, app.debugDescription)
            XCTAssertTrue(app.images["rank-original-title"].exists, app.debugDescription)
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-rank-original-\(index + 1)"; image.lifetime = .keepAlways; add(image)
            app.navigationBars["Immagini del rank"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Rank"].waitForExistence(timeout: 5))
        }
        let profile = app.buttons["strength-profile"]
        scrollControlIntoView(profile, in: app); profile.tap()
        XCTAssertTrue(app.navigationBars["Profilo forza"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.datePickers["strength-birth-date"].exists)
        let weight = app.textFields["strength-weight"], height = app.textFields["strength-height"]
        weight.tap(); weight.typeText("75"); height.tap(); height.typeText("180")
        app.navigationBars["Profilo forza"].buttons["Salva"].tap()
        XCTAssertTrue(app.navigationBars["Rank"].waitForExistence(timeout: 5)); profile.tap()
        XCTAssertTrue(app.navigationBars["Profilo forza"].waitForExistence(timeout: 5))
        XCTAssertEqual(weight.value as? String, "75,0"); XCTAssertEqual(height.value as? String, "180,0")
        XCTAssertFalse(app.datePickers["strength-birth-date"].exists)
        app.navigationBars["Profilo forza"].buttons["Annulla"].tap()
    }
    func testSerie7PRCelebrationCanBeClosedAndDoesNotRepeatOnReopen() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--serie7-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let fixture = app.buttons["serie7-fixture"]
        scrollControlIntoView(fixture, in: app); fixture.tap()
        XCTAssertTrue(app.staticTexts["Serie 7 pronta"].waitForExistence(timeout: 5))
        let url = URL(string: "pivot://workout/11111111-1111-4111-8111-111111111111?set=22222222-2222-4222-8222-222222222222")!
        app.open(url)
        let done = app.buttons["set-done-s7-bench-0"]
        XCTAssertTrue(done.waitForExistence(timeout: 8)); done.tap()
        let close = app.buttons["close-workout-achievement"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Nuovo massimale stimato!"].exists)
        close.tap(); XCTAssertTrue(close.waitForNonExistence(timeout: 3))
        XCTAssertEqual(done.value as? String, "Fatta")
        let recordRow = app.descendants(matching: .any)["set-row-s7-bench-0"].firstMatch
        XCTAssertEqual(recordRow.value as? String, "Record personale")
        XCTAssertTrue(app.buttons["set-type-0-0"].label.contains("Serie 1"))
        app.terminate(); app.open(url)
        XCTAssertTrue(app.navigationBars["Allenamento"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["close-workout-achievement"].exists)
    }
    func testSerie7DeepLinkReplacesWorkoutPageAndZeroHoldIsSkipped() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--serie7-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let fixture = app.buttons["serie7-fixture"]
        scrollControlIntoView(fixture, in: app); fixture.tap()
        XCTAssertTrue(app.staticTexts["Serie 7 pronta"].waitForExistence(timeout: 5))
        let day = app.buttons["workout-day-s7-day"]
        for _ in 0..<15 { if day.isHittable { break }; app.swipeDown() }
        day.tap(); XCTAssertTrue(app.navigationBars["Allenamento"].waitForExistence(timeout: 5))
        let url = URL(string: "pivot://workout/11111111-1111-4111-8111-111111111111?set=22222222-2222-4222-8222-222222222222")!
        app.open(url); app.open(url)
        XCTAssertTrue(app.buttons["set-done-s7-bench-0"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Chiudi"].exists)
        app.navigationBars.buttons["Palestra"].tap()
        XCTAssertTrue(app.navigationBars["Palestra"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Allenamento"].exists)
        app.terminate(); app.open(url)
        XCTAssertTrue(app.navigationBars["Allenamento"].waitForExistence(timeout: 15))
        let seconds = app.textFields["seconds-s7-plank-0"]
        for _ in 0..<15 { if seconds.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(seconds.isHittable); seconds.tap(); seconds.typeText("0"); app.buttons["Fine"].tap()
        let done = app.buttons["set-done-s7-plank-0"]; done.tap()
        XCTAssertEqual(done.value as? String, "Non svolta")
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-zero-hold-skipped"; image.lifetime = .keepAlways; add(image)
        app.terminate(); app.open(url)
        XCTAssertTrue(app.navigationBars["Allenamento"].waitForExistence(timeout: 15))
        for _ in 0..<15 { if done.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(done.value as? String, "Non svolta")
    }
    func testCompactTrainingRowsProtectPlanAndDeleteExtraSets() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-test", "--training-test", "--training-layout-test"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Palestra"].tap()
        let importer = app.buttons["import-training-fixture"]
        for _ in 0..<12 { if importer.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(importer.isHittable); importer.tap()
        XCTAssertTrue(app.buttons["Usa questa scheda"].waitForExistence(timeout: 8)); app.buttons["Usa questa scheda"].tap()
        let gallery = app.buttons["exercise-statistics-test-squat"]
        // The import control is below the gallery, so return toward the top
        // after dismissing the confirmation sheet.
        for _ in 0..<10 { if gallery.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        let photos = XCTAttachment(screenshot: app.screenshot())
        photos.name = "training-restored-073-photos"; photos.lifetime = .keepAlways; add(photos)
        let day = app.buttons["workout-day-test-a"]
        scrollControlIntoView(day, in: app); day.tap()
        XCTAssertTrue(app.buttons["Inizia allenamento"].waitForExistence(timeout: 5)); app.buttons["Inizia allenamento"].tap()
        let addSet = app.buttons["add-set-test-exercise"]
        for _ in 0..<10 { if addSet.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(addSet.isHittable)
        fullyRevealRow(app.descendants(matching: .any)["set-row-test-exercise-0"].firstMatch, in: app)
        let firstType = app.buttons["set-type-0-0"]
        firstType.tap()
        let types = XCTAttachment(screenshot: app.screenshot())
        types.name = "training-single-type-menu"; types.lifetime = .keepAlways; add(types)
        app.buttons["W · Warm-up"].tap()
        // Changing the appearance of a prescribed set must never make it removable.
        app.descendants(matching: .any)["set-row-test-exercise-0"].firstMatch.swipeLeft()
        XCTAssertFalse(app.buttons["delete-set-test-exercise-0"].exists)
        firstType.tap(); app.buttons["1 · Working"].tap()
        addSet.tap(); app.buttons["W · Warm-up"].tap()
        XCTAssertTrue(app.textFields["weight-test-exercise-4"].waitForExistence(timeout: 5))
        let compact = XCTAttachment(screenshot: app.screenshot())
        compact.name = "training-compact-set-table"; compact.lifetime = .keepAlways; add(compact)
        let extra = app.descendants(matching: .any)["set-row-test-exercise-0"].firstMatch
        fullyRevealRow(extra, in: app)
        extra.swipeLeft()
        let delete = app.buttons["delete-set-test-exercise-0"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); XCTAssertTrue(delete.isHittable)
        let swipe = XCTAttachment(screenshot: app.screenshot())
        swipe.name = "training-extra-set-swipe-delete"; swipe.lifetime = .keepAlways; add(swipe)
        delete.tap()
        XCTAssertTrue(app.textFields["weight-test-exercise-4"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["weight-test-exercise-3"].exists)
        let prescribed = app.descendants(matching: .any)["set-row-test-exercise-0"].firstMatch
        prescribed.swipeLeft()
        XCTAssertFalse(app.buttons["delete-set-test-exercise-0"].exists)
        app.buttons["set-options-test-exercise-0"].tap()
        XCTAssertTrue(app.navigationBars["Serie 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["rest-test-exercise-0"].exists)
        let options = XCTAttachment(screenshot: app.screenshot())
        options.name = "training-set-options"; options.lifetime = .keepAlways; add(options)
        app.navigationBars.buttons["Fine"].tap()
    }
    private func fullyRevealRow(_ row: XCUIElement, in app: XCUIApplication) {
        // isHittable can be true for a row partly hidden behind the navigation bar.
        // Full-screen swipes can oscillate between the two edges on long workout
        // pages, so move the scroll view in small, deterministic increments.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0..<12 {
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            let controls = app.descendants(matching: .any)["workout-recovery-bar"].firstMatch
            let bottom = (controls.exists ? controls.frame.minY : app.tabBars.firstMatch.frame.minY) - 8
            if row.frame.minY <= top {
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 110)))
            } else if row.frame.maxY >= bottom {
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -110)))
            } else { break }
        }
        XCTAssertGreaterThan(row.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThan(row.frame.maxY, app.tabBars.firstMatch.frame.minY)
    }
    func testWorkoutIntentActionsPersistBothSidesAndRestState() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--workout-controls-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let button = app.buttons["workout-controls-fixture"]
        for _ in 0..<15 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.isHittable); button.tap()
        let message = app.staticTexts["training-message"]
        if !message.waitForExistence(timeout: 10) {
            // The fixture inserts a plan, gallery and session above this
            // footer. The recorded failure had the new data but the message
            // below the viewport: seek the exact result, not a generic row.
            for _ in 0..<24 {
                if message.exists { break }
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)))
            }
        }
        XCTAssertTrue(message.exists, app.debugDescription)
        XCTAssertEqual(message.label, "Controlli allenamento verificati", app.debugDescription)
    }
    func testTrainingPDFUsesActualRendererAndSyntheticWeeklyData() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--report-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 15)); app.tabBars.buttons["Palestra"].tap()
        let button = app.buttons["report-fixture"]
        for _ in 0..<40 {
            if button.isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            let above = button.exists && button.frame.maxY > 0 && button.frame.minY < app.navigationBars.firstMatch.frame.maxY
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: above ? 150 : -150)))
        }
        XCTAssertTrue(button.isHittable, app.debugDescription); button.tap()
        let message = app.staticTexts["training-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("PDF verificato:"), message.label)
    }
    func testIncomeSummarySwipesToChart() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--preview", "--screen=income"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Entrate"].waitForExistence(timeout: 10)); app.tabBars.buttons["Entrate"].tap()
        let carousel = app.scrollViews["income-carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 8))
        let summary = app.descendants(matching: .any)["income-summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5)); XCTAssertTrue(summary.isHittable)
        XCTAssertLessThanOrEqual(summary.frame.height, 330, "Il riepilogo deve restare compatto, senza lo spazio vuoto richiesto dal grafico")
        XCTAssertLessThanOrEqual(carousel.frame.height, 330, "Anche il carosello deve restringersi, non solo la scheda al suo interno")
        let summaryScreenshot = XCTAttachment(screenshot: app.screenshot())
        summaryScreenshot.name = "income-compact-centered-summary"; summaryScreenshot.lifetime = .keepAlways
        add(summaryScreenshot)
        carousel.swipeLeft()
        XCTAssertTrue(app.buttons["income-page-2"].isSelected, "Il primo swipe deve aprire il Salvadanaio")
        XCTAssertTrue(app.buttons["savings-create-goal"].waitForExistence(timeout: 5))
        carousel.swipeLeft()
        let afterSwipe = XCTAttachment(screenshot: app.screenshot())
        afterSwipe.name = "income-immediately-after-swipe"; afterSwipe.lifetime = .keepAlways
        add(afterSwipe)
        // Only synthetic preview data is used in this test. Keep the hierarchy
        // when a failure prevents the final screenshot from being reached.
        print("INCOME_AFTER_SWIPE\n\(app.debugDescription)")
        let chart = app.descendants(matching: .any)["income-chart-title"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5)); XCTAssertTrue(chart.isHittable)
        let explanation = app.descendants(matching: .any)["income-chart-explanation"].firstMatch
        let pageButton = app.buttons["income-page-1"]
        XCTAssertTrue(pageButton.isSelected, "Lo swipe deve selezionare la pagina Grafico, non soltanto mostrare un elemento fuori schermo")
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertTrue(pageButton.isHittable)
        XCTAssertLessThanOrEqual(explanation.frame.maxY, pageButton.frame.minY, "La navigazione non deve coprire la spiegazione del grafico")
        XCTAssertLessThanOrEqual(explanation.frame.maxY, carousel.frame.maxY, "La spiegazione deve rientrare nella pagina, senza tagli")
        XCTAssertGreaterThan(explanation.frame.height, 25, "La spiegazione deve andare a capo, non essere troncata in una riga")
        app.buttons["income-page-0"].tap()
        let returnedSummary = app.descendants(matching: .any)["income-summary-title"].firstMatch
        XCTAssertTrue(waitUntilHittable(returnedSummary))
        XCTAssertTrue(app.buttons["income-page-0"].isSelected)
        XCTAssertLessThanOrEqual(carousel.frame.height, 330)
        pageButton.tap()
        let returnedToChart = waitUntilHittable(chart)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "income-chart-no-overlap"; screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(returnedToChart)
        XCTAssertTrue(pageButton.isSelected)
    }
    private func waitUntilHittable(_ element: XCUIElement) -> Bool {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        return XCTWaiter.wait(for: [ready], timeout: 15) == .completed
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
        scrollControlIntoView(day, in: app); day.tap()
        XCTAssertTrue(app.buttons["Inizia allenamento"].waitForExistence(timeout: 5)); app.buttons["Inizia allenamento"].tap()
        let extra = app.buttons["add-workout-exercise"]
        let recoveryBar = app.descendants(matching: .any)["workout-recovery-bar"].firstMatch
        // XCTest can call a partly visible button hittable while its centre
        // is behind the persistent recovery bar. Scroll its entire target
        // into the visible viewport, then perform the ordinary button tap.
        for _ in 0..<12 {
            if extra.isHittable && (!recoveryBar.exists || extra.frame.maxY < recoveryBar.frame.minY - 8) { break }
            app.swipeUp()
        }
        XCTAssertTrue(extra.isHittable)
        if recoveryBar.exists { XCTAssertLessThan(extra.frame.maxY, recoveryBar.frame.minY - 8) }
        extra.tap()
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
    func testAlarmProbeIsExplicitAndDoesNotStartOnOpening() {
        guard #available(iOS 26.0, *) else { XCTFail("The candidate CI must select iOS 26 or later to exercise AlarmKit"); return }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Impostazioni"].waitForExistence(timeout: 10)); app.tabBars.buttons["Impostazioni"].tap()
        let notifications = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Quando e come avvisarti")).firstMatch
        for _ in 0..<5 { if notifications.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(notifications.isHittable); notifications.tap()
        let probe = app.buttons["open-alarm-probe"]
        for _ in 0..<5 { if probe.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(probe.isHittable); probe.tap()
        XCTAssertTrue(app.staticTexts["Prova tecnica, non recupero"].waitForExistence(timeout: 5))
        let start = app.buttons["alarm-probe-start"]
        for _ in 0..<8 { if start.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(start.exists); XCTAssertFalse(start.isEnabled)
        XCTAssertEqual(app.staticTexts["alarm-probe-status"].label, "Nessun test avviato.")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Opening the screen must not ask permission or schedule an alarm")
        let consent = app.switches["alarm-probe-confirm"]
        for _ in 0..<5 { if consent.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(consent.isHittable); consent.tap()
        XCTAssertTrue(start.isEnabled)
        // Deliberately do not tap Start: a simulator cannot verify Bluetooth
        // routing, and ordinary CI must never ring a real user's alarm.
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
        XCTAssertEqual(input.value as? String, text)
        let done = app.buttons["Fine"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        let send = app.buttons["coach-send"]
        for _ in 0..<5 { if send.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(send.isHittable); send.tap()
        let savedMessage = app.staticTexts.matching(identifier: "coach-user-message").matching(NSPredicate(format: "label == %@", text)).firstMatch
        XCTAssertTrue(savedMessage.waitForExistence(timeout: 8))
        // The composer clears only after the durable write. An exact message
        // inside a TextField is not proof that the conversation was saved.
        let persisted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = input.value as? String ?? ""
            return !value.contains(text) && !app.descendants(matching: .any)["coach-planning-progress"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [persisted], timeout: 12), .completed)
        app.terminate(); app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["calendar-updated"].waitForExistence(timeout: 15))
        let reopened = app.buttons["open-pivot-coach"]
        for _ in 0..<6 { if reopened.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(reopened.isHittable); reopened.tap()
        let restoredMessage = app.staticTexts[text]
        if !restoredMessage.waitForExistence(timeout: 8) {
            let before = XCTAttachment(screenshot: app.screenshot()); before.name = "serie7-coach-reopen-before-scroll"; before.lifetime = .keepAlways; add(before)
            // Lazy content can be above or below the restored scroll position.
            // Seek in short steps in both directions; still require the exact
            // saved message, not a generic chat row or a weaker success signal.
            for direction in [-1.0, 1.0] {
                for _ in 0..<24 {
                    if restoredMessage.exists { break }
                    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * 150)))
                }
                if restoredMessage.exists { break }
            }
        }
        if !restoredMessage.exists {
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "serie7-coach-reopen-missing-message"; image.lifetime = .keepAlways; add(image)
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "serie7-coach-reopen-accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(restoredMessage.exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Modello locale attivo"].exists)
    }

    func testTrainingPDFImportSetLoggingAndPersistence() {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Permesso notifiche per il timer") { alert in
            for title in ["Allow", "Consenti"] where alert.buttons[title].exists {
                alert.buttons[title].tap(); return true
            }
            return false
        }
        let app = XCUIApplication(); app.launchArguments = ["--interaction-test", "--training-test"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Palestra"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Palestra"].tap()
        let importer = app.buttons["import-training-fixture"]
        for _ in 0..<8 { if importer.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(importer.isHittable); importer.tap()
        let confirm = app.buttons["Usa questa scheda"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8)); confirm.tap()
        let day = app.buttons["workout-day-test-a"]
        scrollControlIntoView(day, in: app); day.tap()
        let start = app.buttons["Inizia allenamento"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        let kg = app.textFields["weight-test-exercise-0"]
        for _ in 0..<8 { if kg.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(kg.isHittable); kg.tap(); kg.typeText("25")
        app.buttons["Fine"].tap()
        let reps = app.textFields["reps-test-exercise-0"]
        reps.tap(); reps.typeText("8"); app.buttons["Fine"].tap()
        let done = app.buttons["set-done-test-exercise-0"]
        XCTAssertTrue(done.exists); done.tap()
        let permission = app.alerts.firstMatch
        if permission.waitForExistence(timeout: 3) {
            for title in ["Allow", "Consenti"] where permission.buttons[title].exists { permission.buttons[title].tap(); break }
        }
        let finish = app.buttons["finish-workout-top"]
        for _ in 0..<8 { if finish.isHittable { break }; app.swipeDown() }
        finish.tap()
        XCTAssertTrue(app.navigationBars["Report per il PT"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Condividi PDF"].exists)
        app.buttons["Chiudi"].tap()
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
