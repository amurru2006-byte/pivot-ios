import XCTest
@testable import PivotCore

final class ClientDefaultsTests: XCTestCase {
    private func preferences() -> ClientDefaults {
        ClientDefaults(paymentMethod: .bankTransfer, place: .studentHome, address: "Destinazione sintetica 42",
            origins: [ClientTravelOrigin(name: "Partenza A", address: "Indirizzo sintetico 11", mode: .walking, beforeMinutes: 12, afterMinutes: 18),
                      ClientTravelOrigin(name: "Partenza B", address: "Indirizzo sintetico 22", mode: .transit, beforeMinutes: 50, afterMinutes: 35)])
    }
    func testLegacyClientAndLogisticsDecodeWithoutInventingDefaults() throws {
        let client = Client(name: "Contatto QA", rateCents: 1800)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Client.self, from: JSONEncoder().encode(client))
        XCTAssertNil(decoded.defaults)
        let legacy = Data(#"{"studentName":"Contatto QA","place":"studentHome","address":"","travelBeforeMinutes":0,"travelAfterMinutes":0,"travelConfirmed":false}"#.utf8)
        let logistics = try decoder.decode(LessonLogistics.self, from: legacy)
        XCTAssertNil(logistics.departure); XCTAssertNil(logistics.paymentMethod)
        XCTAssertNil(logistics.eventStartAtConfirmation)
    }
    func testDefaultsRoundTripAndDoNotChangePastMoney() throws {
        var data = AppData(); let client = Client(name: "Contatto QA", rateCents: 1800); data.clients = [client]
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        try ManualIncome.register(id: UUID(), client: client, date: date, minutes: 60, amountCents: 1800,
            receivedCents: 1300, paymentDate: date, notes: "QA", data: &data)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let payments = try encoder.encode(data.payments), income = try encoder.encode(data.income)
        try ClientRegistry.save(name: client.name, rateCents: 1800, cadence: .weekly, editingID: client.id, defaults: preferences(), data: &data)
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        XCTAssertEqual(restored.clients[0].defaults, data.clients[0].defaults)
        XCTAssertEqual(try encoder.encode(data.payments), payments)
        XCTAssertEqual(try encoder.encode(data.income), income)
        // Ordinary rate/cadence updates must not silently erase saved defaults.
        try ClientRegistry.save(name: client.name, rateCents: 2000, cadence: .weekly, editingID: client.id, data: &data)
        XCTAssertEqual(data.clients[0].defaults, restored.clients[0].defaults)
    }
    func testProposalDoesNotChooseOriginOrTreatDefaultAsVerified() {
        let value = preferences().proposal(studentName: "QA", calendarLocation: "Luogo diverso nel calendario")
        XCTAssertEqual(value.address, "Luogo diverso nel calendario"); XCTAssertEqual(value.paymentMethod, .bankTransfer)
        XCTAssertNil(value.departure); XCTAssertEqual(value.travelBeforeMinutes, 0)
        XCTAssertFalse(value.travelConfirmed); XCTAssertNil(value.confirmedAt)
    }
    func testSelectingAnotherOriginReplacesBothEstimatesAndInvalidatesConfirmation() {
        let defaults = preferences()
        var value = defaults.proposal(studentName: "QA", calendarLocation: "")
        value = ClientDefaults.applying(defaults.origins[0], to: value)
        value.confirmedAt = Date(); value.travelConfirmed = true
        value = ClientDefaults.applying(defaults.origins[1], to: value)
        XCTAssertEqual(value.departure?.id, defaults.origins[1].id)
        XCTAssertEqual(value.travelBeforeMinutes, 50); XCTAssertEqual(value.travelAfterMinutes, 35)
        XCTAssertNil(value.confirmedAt); XCTAssertFalse(value.travelConfirmed)
    }
    func testCalibrationOnlyChangesExplicitlySelectedSameRouteAfterConfirmation() throws {
        let defaults = preferences()
        var value = ClientDefaults.applying(defaults.origins[0], to: defaults.proposal(studentName: "QA", calendarLocation: ""))
        value.travelBeforeMinutes = 16; value.travelAfterMinutes = 22
        XCTAssertThrowsError(try defaults.calibrated(using: value))
        value.travelConfirmed = true; value.confirmedAt = Date()
        let updated = try defaults.calibrated(using: value)
        XCTAssertEqual(updated.origins[0].beforeMinutes, 16); XCTAssertEqual(updated.origins[0].afterMinutes, 22)
        XCTAssertEqual(updated.origins[1], defaults.origins[1]); XCTAssertEqual(defaults.origins[0].beforeMinutes, 12)
        value.departure?.mode = .car
        XCTAssertThrowsError(try defaults.calibrated(using: value))
        value.departure = defaults.origins[0]; value.address = "Altra destinazione"
        XCTAssertThrowsError(try defaults.calibrated(using: value))
    }
    func testInvalidOrAmbiguousDefaultsCannotEnterBackupOrRegistry() throws {
        var invalids: [ClientDefaults] = []
        var a = preferences(); a.origins[0].beforeMinutes = -1; invalids.append(a)
        a = preferences(); a.origins[0].afterMinutes = 241; invalids.append(a)
        a = preferences(); a.origins[0].name = " "; invalids.append(a)
        a = preferences(); a.origins[1].name = " PARTENZA A "; invalids.append(a)
        a = preferences(); a.origins[1].id = a.origins[0].id; invalids.append(a)
        a = preferences(); a.address = String(repeating: "a", count: 501); invalids.append(a)
        a = preferences(); a.origins = (0..<13).map { ClientTravelOrigin(name: "QA \($0)") }; invalids.append(a)
        for defaults in invalids {
            XCTAssertFalse(defaults.isValid)
            var data = AppData()
            XCTAssertThrowsError(try ClientRegistry.save(name: "Contatto QA", rateCents: 1800, cadence: .everyLesson, defaults: defaults, data: &data))
            XCTAssertTrue(data.clients.isEmpty)
            data.clients = [Client(name: "QA", rateCents: 1800, defaults: defaults)]
            XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
        }
    }
    func testMergeKeepsDefaultsAndRejectsConflictsBeforeChangingData() throws {
        var data = AppData()
        let a = Client(name: "Profilo QA A", rateCents: 1800, defaults: preferences())
        let b = Client(name: "Profilo QA B", rateCents: 1800)
        data.clients = [a, b]
        try ClientRegistry.merge(sourceID: a.id, into: b.id, data: &data)
        XCTAssertEqual(data.clients[0].defaults, a.defaults)
        var conflicting = a; conflicting.id = UUID(); conflicting.defaults?.paymentMethod = .cash
        data.clients.append(conflicting)
        let before = try BackupCodec.encode(data)
        XCTAssertThrowsError(try ClientRegistry.merge(sourceID: conflicting.id, into: b.id, data: &data))
        XCTAssertEqual(try BackupCodec.encode(data), before)
    }
    func testNewLogisticsConfirmationExpiresWhenEventTimesChange() {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        var event = CalendarItem(id: "qa", eventIdentifier: "qa", calendarIdentifier: "qa", calendarTitle: "QA",
            title: "Lezione QA", start: date, end: date.addingTimeInterval(3600), location: "", notes: "", colorHex: "#FFFFFF", isAllDay: false, writable: true, kind: .tutoring)
        var value = LessonLogistics(studentName: "QA", place: .studentHome, confirmedAt: date)
        value.eventStartAtConfirmation = event.start; value.eventEndAtConfirmation = event.end
        XCTAssertTrue(value.isConfirmed(for: event))
        event.start.addTimeInterval(600); event.end.addTimeInterval(600)
        XCTAssertFalse(value.isConfirmed(for: event))
    }
    func testPrivateDefaultsAreNotAddedToCloudAndKnownAddressesAreFiltered() throws {
        var data = AppData(); data.clients = [Client(name: "Contatto QA", rateCents: 1800, defaults: preferences())]
        let snapshot = try CoachV8Snapshot.make(message: "Organizza la giornata", events: [], data: data, now: Date(), purpose: "conversation")
        let sent = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        XCTAssertFalse(sent.contains("Destinazione sintetica")); XCTAssertFalse(sent.contains("Indirizzo sintetico"))
        XCTAssertFalse(sent.contains("bankTransfer"))
        let filtered = CoachPrivacy.text("Vado a Destinazione sintetica 42 da Indirizzo sintetico 11", events: [], data: data)
        XCTAssertFalse(filtered.contains("sintetica")); XCTAssertFalse(filtered.contains("sintetico"))
    }
}
