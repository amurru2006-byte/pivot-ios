import XCTest
@testable import PivotCore

final class Pivot071Tests: XCTestCase {
    private func event(_ id: String, title: String = "Studio") -> CalendarItem {
        let date = ISO8601DateFormatter().date(from: "2026-10-07T10:00:00+02:00")!
        return CalendarItem(id: id, eventIdentifier: id, calendarIdentifier: "test", calendarTitle: "Test", title: title,
                            start: date, end: date.addingTimeInterval(3600), location: "", notes: "", colorHex: "#ABCDEF", isAllDay: false, writable: true, kind: .tutoring)
    }

    func testCalendarStudentMatchesSavedPersonWithoutTyping() {
        let client = Client(name: "Giulia Rossi", rateCents: 1800)
        for title in ["Giulia Rossi", "Ripetizioni con Giulia Rossi", "Lezione GIULIA ROSSI", "Ripetizioni di matematica con Giulia Rossi (online)"] {
            let result = StudentRecognition.recognize(title: title, clients: [client])
            XCTAssertEqual(result.client?.id, client.id, title)
            XCTAssertEqual(result.name, client.name)
            XCTAssertFalse(result.ambiguous)
        }
    }
    func testRecognitionUsesWholeNamesNotSubstringsAndHandlesAccents() {
        let anna = Client(name: "Anna", rateCents: 1800)
        let result = StudentRecognition.recognize(title: "Ripetizioni Giovanna", clients: [anna])
        XCTAssertNil(result.client); XCTAssertEqual(result.name, "Giovanna")
        let niccolo = Client(name: "Niccolò D’Amico", rateCents: 1800)
        XCTAssertEqual(StudentRecognition.recognize(title: "Lezione con NICCOLO D'AMICO", clients: [niccolo]).client?.id, niccolo.id)
        XCTAssertNil(StudentRecognition.recognize(title: "Lezione Gianluca", clients: [.init(name: "Luca", rateCents: 0)]).client)
    }
    func testSpecificFullNameWinsButMultipleStudentsRequireChoice() {
        let anna = Client(name: "Anna", rateCents: 1800), full = Client(name: "Anna Rossi", rateCents: 1800)
        XCTAssertEqual(StudentRecognition.recognize(title: "Anna Rossi - matematica", clients: [anna, full]).client?.id, full.id)
        let luca = Client(name: "Luca", rateCents: 1800)
        let result = StudentRecognition.recognize(title: "Ripetizioni con Anna e Luca", clients: [anna, luca])
        XCTAssertTrue(result.ambiguous); XCTAssertNil(result.client)
        let duplicate = Client(name: "Anna", rateCents: 1200)
        XCTAssertTrue(StudentRecognition.recognize(title: "Anna", clients: [anna, duplicate]).ambiguous)
    }
    func testNewStudentGetsCalendarNameAndGenericTitleDoesNotCreatePerson() {
        XCTAssertEqual(StudentRecognition.recognize(title: "Ripetizioni con Francesca Bianchi (chimica)", clients: []).name, "Francesca Bianchi")
        for title in ["Lezione", "Ripetizioni", "Ripetizioni matematica"] {
            XCTAssertEqual(StudentRecognition.recognize(title: title, clients: []).name, "")
        }
    }
    func testRecognizedPersonPaymentAndRepeatSaveDoNotCreateDuplicates() throws {
        let client = Client(name: "Giulia Rossi", rateCents: 1800)
        var data = AppData(); data.clients = [client]
        let item = event("lesson", title: "Ripetizioni con Giulia Rossi")
        var record = EventRecord(id: item.id, snapshot: item); record.status = .completed
        let recognized = try XCTUnwrap(StudentRecognition.recognize(title: item.title, clients: data.clients).client)
        for _ in 0..<2 {
            TutoringLedger.register(event: item, record: &record, client: recognized, amountCents: 1800, collectedCents: 1000, paymentDate: item.end, data: &data)
        }
        data.records[item.id] = record
        XCTAssertEqual(data.clients.count, 1); XCTAssertEqual(data.income.count, 1); XCTAssertEqual(data.payments.count, 1)
        XCTAssertEqual(data.income.first?.clientID, client.id); XCTAssertEqual(data.income.first?.outstandingCents, 800)
        XCTAssertEqual(StudentRecognition.existingClient(named: " giulia ROSSI ", clients: data.clients)?.id, client.id)
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }

    @MainActor func testWriterCombinesRapidChangesAndFlushPersistsLatest() async {
        var saved: [Int] = []
        let writer = CoalescingWriter<Int>(delayNanoseconds: 1_000_000, write: { saved.append($0) })
        for value in 0..<100 { writer.enqueue(value) }
        XCTAssertTrue(writer.isPending)
        let ok = await writer.flush()
        XCTAssertTrue(ok); XCTAssertEqual(saved, [99]); XCTAssertFalse(writer.isPending)
    }
    @MainActor func testWriterSerializesEditsDuringSlowSave() async {
        let entered = expectation(description: "Saving started")
        var saved: [Int] = [], active = 0, peak = 0
        let writer = CoalescingWriter<Int>(delayNanoseconds: 0, write: { value in
            active += 1; peak = max(peak, active)
            if value == 1 { entered.fulfill(); try await Task.sleep(nanoseconds: 30_000_000) }
            saved.append(value); active -= 1
        })
        writer.enqueue(1)
        await fulfillment(of: [entered], timeout: 2)
        // MainActor can accept the next edit while storage is in flight.
        writer.enqueue(2); writer.enqueue(3)
        let ok = await writer.flush()
        XCTAssertTrue(ok); XCTAssertEqual(saved, [1, 3]); XCTAssertEqual(peak, 1)
    }
    @MainActor func testWriterRetainsFailedDataForExplicitRetry() async {
        enum Failure: Error { case diskFull }
        let failed = expectation(description: "Save failed")
        var allowWrite = false, saved: [Int] = []
        let writer = CoalescingWriter<Int>(delayNanoseconds: 0, write: { value in
            guard allowWrite else { throw Failure.diskFull }; saved.append(value)
        }, onResult: { _, error in if error != nil { failed.fulfill() } })
        writer.enqueue(42)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertTrue(writer.isPending); XCTAssertTrue(saved.isEmpty)
        allowWrite = true
        let ok = await writer.flush()
        XCTAssertTrue(ok); XCTAssertEqual(saved, [42]); XCTAssertFalse(writer.isPending)
    }
    func testDiskPersistencePreservesPreviousAndPreRestoreData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = FilePersistence(directory: folder)
        var data = try await disk.load()
        let installation = data.installationID
        try await disk.save(data)
        data.clients = [.init(name: "Giulia Rossi", rateCents: 1800)]
        try await disk.save(data)
        let previous = try BackupCodec.decode(Data(contentsOf: folder.appendingPathComponent("previous.json")))
        XCTAssertEqual(previous.installationID, installation); XCTAssertTrue(previous.clients.isEmpty)
        let loaded = try await FilePersistence(directory: folder).load()
        XCTAssertEqual(loaded.clients.first?.name, "Giulia Rossi")
        try await disk.save(AppData(), restoring: true)
        let archives = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("before-restore-") }
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(try BackupCodec.decode(Data(contentsOf: XCTUnwrap(archives.first))).clients.first?.name, "Giulia Rossi")
    }
    func testUnreadableHistoricalFileIsNotReplacedByLoad() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("pivot-data.json"), bytes = Data("broken historical data".utf8)
        try bytes.write(to: file)
        do { _ = try await FilePersistence(directory: folder).load(); XCTFail("Invalid history should fail") } catch {}
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testIndexedArchiveKeepsSavedIDsAcrossLargeImport() {
        var data = AppData(), events: [CalendarItem] = []
        for index in 0..<2000 {
            var original = event("saved-\(index)", title: "Lezione \(index)")
            original.eventIdentifier = "external-\(index)"; original.recurring = false
            var record = EventRecord(id: original.id, snapshot: original); record.status = .completed
            data.records[original.id] = record
            var current = original; current.id = "new-\(index)"; current.title += " aggiornata"
            events.append(current)
        }
        let started = Date(), result = EventCoalescer.unique(events, data: data)
        XCTAssertEqual(result.count, 2000)
        XCTAssertTrue(result.allSatisfy { $0.id.hasPrefix("saved-") })
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }
    func testCachedPlanningAndNotificationPathsPreserveExistingBehavior() {
        let item = event("lesson"), now = item.start.addingTimeInterval(-3600)
        let data = AppData(), planned = Planner.plannedEvents([item], data: data)
        XCTAssertEqual(NotificationPlan.requests(events: [item], data: data, now: now).map(\.id), NotificationPlan.requestsFromPlanned(events: planned, data: data, now: now).map(\.id))
        XCTAssertEqual(WorkoutContext.missingCardio(events: [item], data: data, now: now).map(\.id), WorkoutContext.missingCardioInPlanned(events: planned, data: data, now: now).map(\.id))
    }
    func testDictationKeepsTypedPrefixAndRevisesOnlyRecognizedText() {
        var composer = DictationTextComposer()
        composer.begin(currentText: "Mi sono svegliato adesso.")
        var value = composer.apply(transcript: "Vorrei sistemare", to: "Mi sono svegliato adesso.")
        XCTAssertEqual(value, "Mi sono svegliato adesso. Vorrei sistemare")
        value = composer.apply(transcript: "Vorrei sistemare la giornata.", to: value)
        XCTAssertEqual(value, "Mi sono svegliato adesso. Vorrei sistemare la giornata.")
    }
    func testDictationDoesNotEraseTypingAddedWhileListening() {
        var composer = DictationTextComposer()
        composer.begin(currentText: "Iniziamo dal pranzo.")
        var value = composer.apply(transcript: "Bisogna trovare", to: "Iniziamo dal pranzo.")
        value += " senza saltare lo studio"
        value = composer.apply(transcript: "Bisogna trovare un buco per la palestra.", to: value)
        XCTAssertEqual(value, "Iniziamo dal pranzo. Bisogna trovare un buco per la palestra. senza saltare lo studio")
    }
}

