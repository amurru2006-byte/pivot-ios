import XCTest
@testable import PivotCore

final class Pivot040Tests: XCTestCase {
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func item(_ id: String = "lesson", title: String = "lezione con Sara", kind: EventKind = .tutoring) -> CalendarItem {
        CalendarItem(id: id, eventIdentifier: id, calendarIdentifier: "work", calendarTitle: "Lavoro", title: title,
                     start: date("2026-10-10T11:00:00+02:00"), end: date("2026-10-10T12:00:00+02:00"), location: "", notes: "", colorHex: "#FFFF00", isAllDay: false, writable: true, kind: kind)
    }
    func payload() -> TrainingPlanPayload {
        TrainingPlanPayload(formatVersion: 1, name: "Scheda TEST, non personale", days: [
            TrainingDay(id: "test-a", name: "Giorno test", exercises: [
                TrainingExercise(id: "test-exercise", name: "Esercizio test", sets: 3, reps: "8–10", restSeconds: 90, coachNotes: "Nota test")
            ])
        ])
    }
    func testNativeTimingHandlesMidnightAndDSTWithoutManualArithmetic() {
        XCTAssertEqual(ActivityTiming.seconds(start: date("2026-10-03T23:30:00+02:00"), end: date("2026-10-04T01:00:00+02:00")), 5400)
        XCTAssertEqual(ActivityTiming.seconds(start: date("2026-10-25T01:30:00+02:00"), end: date("2026-10-25T03:30:00+01:00")), 10800)
        XCTAssertNil(ActivityTiming.seconds(start: date("2026-10-03T12:00:00+02:00"), end: date("2026-10-03T11:00:00+02:00")))
        XCTAssertEqual(ActivityTiming.duration(1037), "0 h 17 min 17 s")
    }
    func testLessonsAndGeneralWorkDoNotBecomeUniversity() {
        XCTAssertEqual(EventKind.classify(title: "lezione con Sara", calendar: "Lavoro"), .tutoring)
        XCTAssertEqual(EventKind.classify(title: "lezione di matematica", calendar: "Uni L27"), .university)
        XCTAssertEqual(EventKind.classify(title: "servizio occasionale", calendar: "Lavoro"), .work)
        XCTAssertEqual(EventKind.classify(title: "camminata", calendar: "Casa"), .workout)
        XCTAssertEqual(EventKind.classify(title: "escursione", calendar: "Casa"), .workout)
    }
    func testLessonDefaultsAreOnlySuggestionsAndConfirmationIsOccurrenceSpecific() {
        let first = item(), second = item("lesson-next")
        var data = AppData()
        let logistics = LessonLogistics(studentName: "Sara", place: .studentHome, confirmedAt: Date(), eventTitleAtConfirmation: first.title, calendarLocationAtConfirmation: first.location)
        var record = EventRecord(id: first.id, snapshot: first); record.logistics = logistics
        data.records[first.id] = record; data.lessonDefaults = [LessonLogistics.key("Sara"): logistics]
        data.lessonPrompts = LessonPromptState(startedAt: date("2026-10-03T09:00:00+02:00"), seenSeries: [], pendingSeries: [LessonPromptState.seriesKey(second)])
        let pending = LessonLogistics.pending(events: [first, second], data: data, now: date("2026-10-03T10:00:00+02:00"))
        XCTAssertEqual(pending.map(\.id), [second.id])
        var renamed = first; renamed.title = "lezione con Luca"
        XCTAssertFalse(logistics.isConfirmed(for: renamed))
        var moved = first; moved.start = moved.start.addingTimeInterval(3600)
        XCTAssertTrue(logistics.isConfirmed(for: moved))
    }
    func testWorkoutPDFParserAcceptsOnlyVersionedValidatedPayload() throws {
        let original = payload()
        let block = try TrainingPDFFormat.encodedBlock(original)
        XCTAssertEqual(try TrainingPDFFormat.parse("Testo della scheda\n" + block + "\nFine"), original)
        XCTAssertThrowsError(try TrainingPDFFormat.parse("Una scheda qualsiasi scansionata"))
        XCTAssertThrowsError(try TrainingPDFFormat.parse("PIVOT-WORKOUT-V1\ninvalid!\nEND-PIVOT-WORKOUT"))
        var invalid = original; invalid.days[0].exercises[0].sets = 0
        XCTAssertThrowsError(try TrainingPDFFormat.encodedBlock(invalid))
        invalid = original; invalid.formatVersion = 2
        XCTAssertThrowsError(try invalid.validate())
    }
    func testNewWorkoutUsesOnlyCompletedPreviousSetsAndKeepsPersonalTips() throws {
        let plan = TrainingPlan(payload: payload(), document: .init(name: "test.pdf", byteCount: 30))
        var library = TrainingLibrary(plans: [plan], activePlanID: plan.id)
        let day = plan.payload.days[0]
        var previous = library.makeSession(plan: plan, day: day, eventID: nil, now: date("2026-10-01T10:00:00+02:00"))
        previous.end = previous.start.addingTimeInterval(3600)
        previous.exercises[0].sets[0].kg = 25; previous.exercises[0].sets[0].reps = 8; previous.exercises[0].sets[0].done = true
        previous.exercises[0].sets[1].kg = 30; previous.exercises[0].sets[1].reps = 9
        library.sessions = [previous]; library.tips["test-exercise"] = "Nota personale test"
        let next = library.makeSession(plan: plan, day: day, eventID: "new", now: date("2026-10-03T10:00:00+02:00"))
        XCTAssertEqual(next.exercises[0].sets[0].kg, 25)
        XCTAssertEqual(next.exercises[0].sets[0].reps, 8)
        XCTAssertFalse(next.exercises[0].sets[0].done)
        XCTAssertNil(next.exercises[0].sets[1].kg)
        XCTAssertEqual(library.tips["test-exercise"], "Nota personale test")
        XCTAssertTrue(TrainingExport.text(next, library: library).contains("Precedente: 25.0 kg × 8"))
    }
    func testWorkoutPlanAndPDFSurviveBackupWithoutErasingHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pdf = Data("%PDF-1.4\nTEST fixture\n%%EOF\n".utf8)
        let document = StudyDocument(name: "test.pdf", byteCount: pdf.count)
        let plan = TrainingPlan(payload: payload(), document: document)
        try pdf.write(to: StudyFiles.url(for: document.id, directory: folder))
        var data = AppData(); data.training = TrainingLibrary(plans: [plan], activePlanID: plan.id, tips: ["test-exercise": "Panca test livello 5"])
        let backup = try BackupCodec.decode(BackupCodec.encode(StudyFiles.completeBackup(data, directory: folder)))
        let restored = try StudyFiles.installBackup(backup, directory: folder)
        let restoredPlan = try XCTUnwrap(restored.training?.activePlan)
        XCTAssertEqual(restoredPlan.id, plan.id)
        let restoredDocument = try XCTUnwrap(restoredPlan.document)
        XCTAssertNotEqual(restoredDocument.id, document.id)
        XCTAssertEqual(restored.training?.tips["test-exercise"], "Panca test livello 5")
        XCTAssertEqual(try Data(contentsOf: StudyFiles.url(for: restoredDocument.id, directory: folder)), pdf)
    }
    func testSleepCardioAndLogisticsSurviveRoundTripAndAppearInReport() throws {
        let event = item("walk", title: "camminata", kind: .workout)
        var data = AppData()
        var check = DayCheckIn(id: PivotDate.key(event.start)); check.sleep = SleepRecord(durationSeconds: 6 * 3600 + 42 * 60, score: 85, quality: "Buona", awakenings: 3, interruptionSeconds: 900)
        data.checkIns[check.id] = check
        var record = EventRecord(id: event.id, snapshot: event)
        record.cardio = CardioRecord(kind: .walk, durationSeconds: 1037, distanceKM: 1.27, activeCalories: 80, totalCalories: 112, elevationM: 9, paceSecondsPerKM: 811, averageBPM: 110, effort: 3)
        data.records[event.id] = record
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.records[event.id]?.cardio?.durationSeconds, 1037)
        XCTAssertEqual(restored.checkIns[check.id]?.sleep?.score, 85)
        let report = Report.day(event.start, events: [event], data: restored)
        XCTAssertTrue(report.contains("Tempo dormito (Apple Watch): 6 h 42 min"))
        XCTAssertTrue(report.contains("Dislivello: 9.0 m"))
    }
    func testOldBackupWithoutNewFieldsStillDecodes() throws {
        let bytes = try BackupCodec.encode(AppData())
        let decoded = try BackupCodec.decode(bytes)
        XCTAssertNil(decoded.training); XCTAssertNil(decoded.lessonDefaults)
        XCTAssertNoThrow(try BackupCodec.decode(bytes))
    }
    func testCardioInvalidNumbersCannotBeRestored() throws {
        var data = AppData(); let event = item()
        var record = EventRecord(id: event.id, snapshot: event)
        record.cardio = CardioRecord(kind: .treadmill, speedKMH: -10)
        data.records[event.id] = record
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        XCTAssertFalse(CardioRecord(kind: .walk, averageBPM: -1).isValid)
        XCTAssertFalse(CardioRecord(kind: .walk, effort: 11).isValid)
    }
    func testMissingLoadDoesNotCreateCompletedWorkoutSet() throws {
        var library = TrainingLibrary()
        let plan = TrainingPlan(payload: payload(), document: .init(name: "test.pdf", byteCount: 30))
        var session = library.makeSession(plan: plan, day: plan.payload.days[0], eventID: nil)
        session.exercises[0].sets[0].done = true
        library.sessions = [session]
        XCTAssertThrowsError(try library.validate())
    }
}
