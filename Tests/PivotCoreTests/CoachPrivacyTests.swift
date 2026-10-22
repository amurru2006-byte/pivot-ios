import XCTest
@testable import PivotCore

final class CoachPrivacyTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00+02:00")!
    private func event(_ id: String = "private-id", kind: EventKind = .workout) -> CalendarItem {
        .init(id: id, eventIdentifier: "private-event", calendarIdentifier: "private-calendar", calendarTitle: "Private",
              title: "Palestra", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600),
              location: "Via Esempio 42", notes: "private note", colorHex: "#123456", isAllDay: false, writable: true, kind: kind)
    }
    private func workout(_ event: CalendarItem) -> HealthWorkoutSummary {
        .init(id: "health-secret", start: event.start, end: event.end, type: "strength", durationSeconds: 3600,
              distanceKM: nil, activeCalories: 999, averageBPM: 123, elevationM: nil)
    }

    func testKnownNamesLocationsAndContactFormatsAreMinimized() {
        var data = AppData()
        data.clients = [.init(name: "Persona Fittizia", rateCents: 1500, calendarAliases: ["Alias Fittizio"])]
        let text = "Persona Fittizia, ALIAS FITTIZIO, Via Esempio 42, prova@example.test, +39 333 123 4567, https://example.test/path"
        let filtered = CoachPrivacy.text(text, events: [event()], data: data)
        for secret in ["Fittizia", "FITTIZIO", "Esempio", "example.test", "333"] { XCTAssertFalse(filtered.contains(secret), filtered) }
        for alias in ["[contatto 1]", "[luogo]", "[email]", "[telefono]", "[link]"] { XCTAssertTrue(filtered.contains(alias), filtered) }
    }

    func testDatesTimesAmountsAndNegationsRemainUsable() {
        let text = "Non domani: 2026-10-09 alle 18:30, non prima. Ho 15 euro e 90 minuti."
        XCTAssertEqual(CoachPrivacy.text(text, events: [], data: AppData()), text)
    }

    func testSavedAndRecentlyUsedPlaceNamesAddressesAndCoordinatePairsAreMinimized() throws {
        var library = PlaceLibrary()
        try library.save(name: "Etichetta privata QA", address: "Indirizzo privato QA 42")
        let resolved = TravelPlace(name: "Nome recente privato QA", address: "Indirizzo recente privato QA 8",
                                   latitude: 45.123456, longitude: 9.654321)
        try library.recordUse(resolved, now: now)
        var data = AppData(); data.placeLibrary = library
        let text = "Da Etichetta privata QA, Indirizzo privato QA 42 a Nome recente privato QA, Indirizzo recente privato QA 8, 45.123456, 9.654321. Ho 45 euro e 9 minuti."
        let filtered = CoachPrivacy.text(text, events: [], data: data)
        for secret in ["Etichetta privata QA", "Indirizzo privato QA", "Nome recente privato QA", "Indirizzo recente privato QA", "45.123456", "9.654321"] {
            XCTAssertFalse(filtered.contains(secret), filtered)
        }
        XCTAssertTrue(filtered.contains("Ho 45 euro e 9 minuti."), filtered)
        let snapshot = try CoachV8Snapshot.make(message: text, events: [], data: data, now: now, purpose: "conversation")
        let sent = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        for secret in ["Etichetta privata QA", "Indirizzo privato QA", "Nome recente privato QA", "45.123456", "9.654321", "placeLibrary", "latitude", "longitude"] {
            XCTAssertFalse(sent.contains(secret), sent)
        }
        XCTAssertEqual(data.placeLibrary, library, "Privacy filtering must not erase the local catalog")
    }

    func testExplicitShortPlaceLabelsArePrivateWithoutRedactingOtherWords() throws {
        var library = PlaceLibrary()
        try library.save(name: "HQ", address: "Via sintetica HQ 8")
        var data = AppData(); data.placeLibrary = library
        XCTAssertEqual(CoachPrivacy.text("HQ domani, non HQaltro", events: [], data: data), "[luogo] domani, non HQaltro")
    }

    func testNameMatchingDoesNotRedactSubstringsOfOtherWords() {
        var data = AppData(); data.clients = [.init(name: "Anna", rateCents: 1000)]
        XCTAssertEqual(CoachPrivacy.text("Anna torna domani, non a capodanno", events: [], data: data), "[contatto 1] torna domani, non a capodanno")
    }

    func testUnknownSensitiveProseIsNotClaimedAnonymous() {
        let text = "Mi chiamo NomeSconosciuto e ho un dolore."
        XCTAssertEqual(CoachPrivacy.text(text, events: [], data: AppData()), text)
        // This limitation is why every online turn requires an exact local review.
    }

    func testHealthOutcomeNeverEntersOnlineContextEvenWithReportConsent() throws {
        let item = event(); var data = AppData()
        HealthImport.apply(workout(item), to: item, data: &data)
        data.settings.includeHealthInExports = true
        let snapshot = try CoachV8Snapshot.make(message: "Organizza la palestra", events: [item], data: data, now: now)
        XCTAssertEqual(snapshot.request.events.first?.status, .pending)
        XCTAssertEqual(data.records[item.id]?.status, .completed)
        let json = String(decoding: try snapshot.request.encoded(), as: UTF8.self)
        for secret in ["health-secret", "activeCalories", "averageBPM", "private-id", "Via Esempio"] { XCTAssertFalse(json.contains(secret), secret) }
    }

    func testHealthDerivedMoveCannotChangeOutgoingCalendarTimes() throws {
        let item = event(); var data = AppData()
        data.moves = [.init(source: item, proposedStart: now.addingTimeInterval(3600), proposedEnd: now.addingTimeInterval(7200), healthDerived: true)]
        let snapshot = try CoachV8Snapshot.make(message: "Palestra", events: [item], data: data, now: now)
        XCTAssertEqual(snapshot.request.events.first?.start, item.start)
        XCTAssertEqual(data.moves.count, 1)
    }

    func testIndependentManualOutcomeRemainsAvailable() throws {
        let item = event(); var data = AppData()
        data.records[item.id] = .init(id: item.id, snapshot: item, status: .skipped)
        let snapshot = try CoachV8Snapshot.make(message: "Palestra", events: [item], data: data, now: now)
        XCTAssertEqual(snapshot.request.events.first?.status, .skipped)
    }

    func testHistoryIsFilteredAndMemoriesStayLocal() throws {
        let item = event(); var data = AppData()
        data.clients = [.init(name: "Persona Fittizia", rateCents: 1500)]
        data.coachState.messages = [.init(dayKey: PivotDate.key(now), role: .user, text: "Persona Fittizia scrive a prova@example.test", onlineHistoryEligible: true)]
        data.coachState.memories = [.init(text: "Memoria privata con dettagli sanitari")]
        let snapshot = try CoachV8Snapshot.make(message: "Persona Fittizia dopo cena", events: [item], data: data, now: now)
        XCTAssertEqual(snapshot.request.message, "[contatto 1] dopo cena")
        XCTAssertEqual(snapshot.request.history.first?.text, "[contatto 1] scrive a [email]")
        XCTAssertTrue(snapshot.request.memories.isEmpty)
        XCTAssertEqual(data.coachState.memories.count, 1)
    }

    func testLegacyProfileAndRankAreExcludedWithoutDeletingLocalData() throws {
        var data = AppData()
        data.strengthProfile = .init(birthDate: ISO8601DateFormatter().date(from: "2000-01-01T12:00:00Z"), bodyMassKG: 75, heightCM: 175, referenceSex: .male)
        let id = UUID(), setID = UUID()
        let pr = TrainingAchievement(id: "pr", kind: .personalRecord, sessionID: id, setID: setID, exercise: "Squat", value: 50, createdAt: now)
        let rank = TrainingAchievement(id: "rank", kind: .rank, sessionID: id, setID: setID, exercise: "Squat", value: 50, rankLevel: 1, createdAt: now)
        data.training = .init(achievements: [pr, rank])
        let filtered = HealthImport.exportData(data)
        XCTAssertNil(filtered.strengthProfile)
        XCTAssertEqual(filtered.training?.achievements?.map(\.id), ["pr"])
        XCTAssertEqual(data.strengthProfile?.bodyMassKG, 75)
        XCTAssertEqual(data.training?.achievements?.count, 2)
        data.settings.includeHealthInExports = true
        XCTAssertNotNil(HealthImport.exportData(data).strengthProfile)
        XCTAssertNil(HealthImport.exportData(data, allowHealth: false).strengthProfile)
    }

    func testHealthWakeWithoutSleepRecordDoesNotLeak() {
        var data = AppData(); let key = PivotDate.key(now)
        data.checkIns[key] = .init(id: key, wakeTime: now, healthWakeTime: now)
        let filtered = HealthImport.exportData(data)
        XCTAssertNil(filtered.checkIns[key]?.healthWakeTime)
        XCTAssertNil(filtered.checkIns[key]?.wakeTime)
        data.checkIns[key]?.wakeTime = now.addingTimeInterval(300)
        XCTAssertEqual(HealthImport.exportData(data).checkIns[key]?.wakeTime, now.addingTimeInterval(300))
    }

    func testForcedBackupFilterIgnoresLegacyConsentAndPreservesMoney() throws {
        let item = event(); var data = AppData()
        HealthImport.apply(workout(item), to: item, data: &data)
        data.settings.includeHealthInExports = true
        let client = Client(name: "Contatto sintetico", rateCents: 1500)
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: now, minutes: 60, amountCents: 1500, paidCents: 1000)
        data.clients = [client]; data.income = [entry]
        data.payments = [.init(incomeID: entry.id, clientName: client.name, date: now, amountCents: 1000)]
        let original = try BackupCodec.encodeCompact(data)
        let exported = try BackupCodec.decode(BackupCodec.encode(HealthImport.exportData(data, allowHealth: false)))
        XCTAssertNil(exported.records[item.id]?.health)
        XCTAssertEqual(exported.records[item.id]?.status, .pending)
        XCTAssertEqual(exported.income.first?.outstandingCents, 500)
        XCTAssertEqual(exported.payments.first?.amountCents, 1000)
        let before = try JSONSerialization.jsonObject(with: original) as! NSDictionary
        let after = try JSONSerialization.jsonObject(with: BackupCodec.encodeCompact(data)) as! NSDictionary
        XCTAssertEqual(before, after)
    }

    func testFrozenOutgoingBytesMatchTheReviewedRequest() throws {
        let snapshot = try CoachV8Snapshot.make(message: "Dopo cena", events: [event()], data: AppData(), now: now)
        let decoded = try JSONSerialization.jsonObject(with: snapshot.encodedRequest) as! NSDictionary
        let expected = try JSONSerialization.jsonObject(with: snapshot.request.encoded()) as! NSDictionary
        XCTAssertEqual(decoded, expected)
        var detachedCopy = snapshot.request
        detachedCopy.message = "Different message, never approved"
        XCTAssertEqual(decoded["message"] as? String, "Dopo cena")
        XCTAssertNotEqual(try detachedCopy.encoded(), snapshot.encodedRequest)
    }
}
