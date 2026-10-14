import XCTest
@testable import PivotCore

final class IncomeCorrectionTests: XCTestCase {
    private func fixture() -> AppData {
        var data = AppData()
        let client = Client(name: "Marta Test", rateCents: 0)
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: Date(timeIntervalSince1970: 1_780_000_000), minutes: 60, amountCents: 2000, paidCents: 1500, calendarEventID: "lesson-fixture")
        data.clients = [client]; data.income = [entry]
        data.payments = [Payment(incomeID: entry.id, clientName: client.name, date: entry.date, amountCents: 1000),
                         Payment(incomeID: entry.id, clientName: client.name, date: entry.date.addingTimeInterval(100), amountCents: 500)]
        data.ledger = AnnualLedger(openingCents: ["2026": 200])
        return data
    }
    func testAddingRateUpdatesSameProfileAndDoesNotRepricePastLessons() throws {
        var data = fixture(); let original = data.clients[0]
        let id = try ClientRegistry.save(name: "  MARTA  Test ", rateCents: 1800, cadence: .weekly, data: &data)
        XCTAssertEqual(id, original.id); XCTAssertEqual(data.clients.count, 1)
        XCTAssertEqual(data.clients[0].rateCents, 1800); XCTAssertEqual(data.clients[0].paymentCadence, .weekly)
        XCTAssertEqual(data.income[0].amountCents, 2000); XCTAssertEqual(data.income[0].paidCents, 1500)
        XCTAssertEqual(StudentRecognition.recognize(title: "Lezione con Marta Test", clients: data.clients).client?.id, id)
    }
    func testDuplicateNamesRequireExplicitMergeAndDoNotPartiallySave() throws {
        var data = fixture(); data.clients.append(Client(name: "Marta Test", rateCents: 1800))
        let before = try BackupCodec.encodeCompact(data)
        XCTAssertThrowsError(try ClientRegistry.save(name: "Marta Test", rateCents: 2000, cadence: .weekly, data: &data))
        XCTAssertEqual(data.clients.count, 2); XCTAssertEqual(data.clients[0].rateCents, 0)
        XCTAssertTrue(StudentRecognition.recognize(title: "Lezione Marta Test", clients: data.clients).ambiguous)
        XCTAssertEqual(try BackupCodec.decode(before).clients.count, 2)
    }
    func testExplicitMergePreservesAllMoneyIDsDatesAndCalendarLink() throws {
        var data = fixture(); let source = data.clients[0]
        let target = Client(name: "Marta Test", rateCents: 1800, paymentCadence: .weekly)
        data.clients.append(target)
        let income = data.income[0], paymentIDs = data.payments.map(\.id), dates = data.payments.map(\.date)
        try ClientRegistry.merge(sourceID: source.id, into: target.id, data: &data)
        XCTAssertEqual(data.clients.map(\.id), [target.id]); XCTAssertEqual(data.clients[0].rateCents, 1800)
        XCTAssertEqual(data.income[0].id, income.id); XCTAssertEqual(data.income[0].clientID, target.id)
        XCTAssertEqual(data.income[0].calendarEventID, income.calendarEventID)
        XCTAssertEqual(data.income[0].amountCents, 2000); XCTAssertEqual(data.income[0].paidCents, 1500)
        XCTAssertEqual(data.payments.map(\.id), paymentIDs); XCTAssertEqual(data.payments.map(\.date), dates)
        XCTAssertEqual(data.payments.map(\.amountCents), [1000, 500]); XCTAssertEqual(data.ledger?.openingCents["2026"], 200)
        XCTAssertEqual(StudentPayments.balance(clientID: target.id, data: data), 500)
        XCTAssertEqual(StudentRecognition.recognize(title: "Lezione Marta Test", clients: data.clients).client?.id, target.id)
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }
    func testMergeKeepsExplicitFormerNameAsCalendarAlias() throws {
        var data = fixture(); let old = data.clients[0].id
        let target = Client(name: "Marta Esempio", rateCents: 1800); data.clients.append(target)
        try ClientRegistry.merge(sourceID: old, into: target.id, data: &data)
        XCTAssertEqual(StudentRecognition.recognize(title: "Ripetizioni con Marta Test", clients: data.clients).client?.id, target.id)
        XCTAssertEqual(data.payments[0].clientName, target.name)
    }
    func testConflictingCalendarAliasNeverChoosesAPerson() {
        let first = Client(name: "Marta Uno", rateCents: 1800, calendarAliases: ["Marta"])
        let second = Client(name: "Marta Due", rateCents: 1500, calendarAliases: ["Marta"])
        let result = StudentRecognition.recognize(title: "Lezione con Marta", clients: [first, second])
        XCTAssertNil(result.client); XCTAssertTrue(result.ambiguous)
        XCTAssertNil(StudentRecognition.existingClient(named: "Marta", clients: [first, second]))
    }
    func testFailedMergeAndRenameLeaveRegistryAndLedgerUnchanged() throws {
        var data = fixture(); let id = data.clients[0].id
        data.clients.append(Client(name: "Altra Persona", rateCents: 1800))
        XCTAssertThrowsError(try ClientRegistry.merge(sourceID: id, into: id, data: &data))
        XCTAssertThrowsError(try ClientRegistry.merge(sourceID: UUID(), into: id, data: &data))
        XCTAssertThrowsError(try ClientRegistry.save(name: "Altra Persona", rateCents: 1200, cadence: .weekly, editingID: id, data: &data))
        XCTAssertEqual(data.clients[0].name, "Marta Test"); XCTAssertEqual(data.income[0].clientID, id)
    }
    func testCompensationCanBeCorrectedUpAndDownWithoutChangingCash() throws {
        var data = fixture(); let id = data.income[0].id
        try IncomeEdits.compensation(incomeID: id, cents: 2500, data: &data)
        XCTAssertEqual(data.income[0].outstandingCents, 1000)
        try IncomeEdits.compensation(incomeID: id, cents: 1500, data: &data)
        XCTAssertEqual(data.income[0].outstandingCents, 0)
        XCTAssertEqual(data.payments.map(\.amountCents), [1000, 500]); XCTAssertEqual(data.incomeEdits?.count, 2)
        XCTAssertEqual(data.incomeEdits?.first?.previousCents, 2000)
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }
    func testCompensationBelowRealReceiptsIsRejectedAtomically() {
        var data = fixture()
        XCTAssertThrowsError(try IncomeEdits.compensation(incomeID: data.income[0].id, cents: 1400, data: &data))
        XCTAssertEqual(data.income[0].amountCents, 2000); XCTAssertNil(data.incomeEdits)
    }
    func testReceiptCorrectionUpdatesSameReceiptAndYearWithoutFutureAdjustment() throws {
        var data = fixture(); let receipt = data.payments[0], entry = data.income[0]
        try IncomeEdits.receipt(paymentID: receipt.id, cents: 500, data: &data)
        XCTAssertEqual(data.payments.count, 2); XCTAssertEqual(data.payments[0].id, receipt.id)
        XCTAssertEqual(data.payments[0].date, receipt.date); XCTAssertEqual(data.payments[1].amountCents, 500)
        XCTAssertEqual(data.income[0].paidCents, 1000); XCTAssertEqual(data.income[0].outstandingCents, 1000)
        XCTAssertEqual(data.income[0].amountCents, entry.amountCents); XCTAssertEqual(data.income.count, 1)
        XCTAssertEqual(data.ledger?.total(year: 2026, payments: data.payments), 1200)
        XCTAssertEqual(data.incomeEdits?.first?.paymentID, receipt.id)
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }
    func testReceiptCorrectionRejectsOverpaymentZeroAndInconsistentHistory() {
        var data = fixture(); let id = data.payments[0].id
        for amount in [0, -100, 1600, 100_000_001] { XCTAssertThrowsError(try IncomeEdits.receipt(paymentID: id, cents: amount, data: &data)) }
        XCTAssertEqual(data.payments[0].amountCents, 1000); XCTAssertEqual(data.income[0].paidCents, 1500)
        data.income[0].paidCents = 1400
        XCTAssertThrowsError(try IncomeEdits.receipt(paymentID: id, cents: 900, data: &data))
        XCTAssertNil(data.incomeEdits)
    }
    func testUnchangedValuesDoNotAddDuplicateCorrections() throws {
        var data = fixture()
        try IncomeEdits.compensation(incomeID: data.income[0].id, cents: 2000, data: &data)
        try IncomeEdits.receipt(paymentID: data.payments[0].id, cents: 1000, data: &data)
        XCTAssertNil(data.incomeEdits)
    }
    func testOldBackupsWithoutOptionalRegistryAndAuditFieldsStillLoad() throws {
        var data = fixture(); data.clients[0].calendarAliases = ["Marta calendario"]
        let backup = try BackupCodec.encodeCompact(data)
        // Verify legacy client payload independently; no new mandatory field.
        let client = try JSONDecoder().decode(Client.self, from: Data("{\"id\":\"44444444-4444-4444-8444-444444444444\",\"name\":\"Test\",\"rateCents\":0}".utf8))
        XCTAssertNil(client.calendarAliases)
        XCTAssertNoThrow(try BackupCodec.decode(backup))
    }
    func testRenamingProfileKeepsFormerCalendarNameAndIdentity() throws {
        var data = fixture(); let id = data.clients[0].id
        try ClientRegistry.save(name: "Marta Esempio", rateCents: 1800, cadence: .weekly, editingID: id, data: &data)
        XCTAssertEqual(data.clients.count, 1)
        XCTAssertEqual(StudentRecognition.recognize(title: "Lezione con Marta Test", clients: data.clients).client?.id, id)
        XCTAssertEqual(try ClientRegistry.save(name: "Marta Test", rateCents: 1900, cadence: .weekly, data: &data), id)
        XCTAssertEqual(data.clients[0].name, "Marta Esempio")
    }
    func testLedgerReusesUniqueIdentityEvenWhenCallerConstructsANewClient() throws {
        var data = fixture(); let id = data.clients[0].id
        let event = CalendarItem(id: "new-lesson", eventIdentifier: "new-lesson", calendarIdentifier: "test", calendarTitle: "Lavoro", title: "Lezione con Marta Test", start: data.income[0].date, end: data.income[0].date.addingTimeInterval(3600), location: "", notes: "", colorHex: "#ABCDEF", isAllDay: false, writable: true, kind: .tutoring)
        var record = EventRecord(id: event.id, snapshot: event)
        XCTAssertNotNil(TutoringLedger.register(event: event, record: &record, client: Client(name: "marta test", rateCents: 0), amountCents: 1800, collectedCents: 0, paymentDate: event.end, data: &data))
        XCTAssertEqual(data.clients.count, 1); XCTAssertEqual(data.income.last?.clientID, id)
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }
    func testLedgerDoesNotCreateThirdProfileForAmbiguousCalendarName() {
        var data = fixture(); data.clients.append(Client(name: "Marta Test", rateCents: 1500))
        let event = CalendarItem(id: "ambiguous-lesson", eventIdentifier: "ambiguous-lesson", calendarIdentifier: "test", calendarTitle: "Lavoro", title: "Lezione con Marta Test", start: data.income[0].date, end: data.income[0].date.addingTimeInterval(3600), location: "", notes: "", colorHex: "#ABCDEF", isAllDay: false, writable: true, kind: .tutoring)
        var record = EventRecord(id: event.id, snapshot: event)
        XCTAssertNil(TutoringLedger.register(event: event, record: &record, client: Client(name: "Marta Test", rateCents: 0), amountCents: 1800, collectedCents: 0, paymentDate: event.end, data: &data))
        XCTAssertEqual(data.clients.count, 2); XCTAssertEqual(data.income.count, 1)
        XCTAssertFalse(record.tutoringAnswered ?? true)
    }
}
