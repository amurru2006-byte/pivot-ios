import XCTest
@testable import PivotCore

final class ClientActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ offset: Int) -> Date { PivotDate.calendar.date(byAdding: .day, value: offset, to: now)! }
    private func data(daysAgo: Int = 91) -> AppData {
        var data = AppData()
        let client = Client(name: "Contatto Attivo QA", rateCents: 1500)
        data.clients = [client]
        data.income = [.init(clientID: client.id, clientName: client.name, date: day(-daysAgo), minutes: 60, amountCents: 1500)]
        return data
    }
    private func event(_ data: AppData, start: Date) -> CalendarItem {
        .init(id: "contact-event-qa", eventIdentifier: "contact-event-qa", calendarIdentifier: "qa-work", calendarTitle: "Lavoro",
              title: "Lezione " + data.clients[0].name, start: start, end: start.addingTimeInterval(3600), location: "", notes: "",
              colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .tutoring)
    }
    private func scan(_ items: [CalendarItem] = [], complete: Bool = true) -> ClientCalendarActivity {
        .init(observedAt: now, from: day(-91), through: PivotDate.calendar.date(byAdding: .year, value: 4, to: day(2))!, complete: complete, items: items)
    }
    func testNinetyDaysExpiresButRecentActivityDoesNot() {
        XCTAssertEqual(ClientActivity.refreshed(data: data(daysAgo: 90), scan: scan(), now: now)[0].activityState?.inactive, true)
        XCTAssertEqual(ClientActivity.refreshed(data: data(daysAgo: 89), scan: scan(), now: now)[0].activityState?.inactive, false)
    }
    func testDayNinetySevenLessonKeepsContactActive() {
        let data = data(daysAgo: 90)
        let result = ClientActivity.refreshed(data: data, scan: scan([event(data, start: day(7))]), now: now)
        XCTAssertEqual(result[0].activityState?.inactive, false)
    }
    func testDistantFutureLessonAlsoProtectsContact() {
        let data = data()
        XCTAssertEqual(ClientActivity.refreshed(data: data, scan: scan([event(data, start: day(900))]), now: now)[0].activityState?.inactive, false)
    }
    func testDeniedIncompleteStaleOrShortHomeWindowCannotDeactivate() {
        let data = data()
        var home = scan(); home.through = day(60)
        var stale = scan(); stale.observedAt = now.addingTimeInterval(-901)
        for evidence in [nil, scan(complete: false), home, stale] as [ClientCalendarActivity?] {
            XCTAssertEqual(ClientActivity.refreshed(data: data, scan: evidence, now: now)[0].activityState?.inactive, false)
        }
    }
    func testManualDeactivationRefusesFutureAppointmentAtomically() throws {
        var data = data()
        let before = data.clients
        XCTAssertThrowsError(try ClientActivity.setActive(false, clientID: data.clients[0].id, data: &data,
            scan: scan([event(data, start: day(2))]), now: now)) { XCTAssertEqual($0 as? ClientActivity.Failure, .futureAppointment) }
        XCTAssertEqual(data.clients, before)
        XCTAssertThrowsError(try ClientActivity.setActive(false, clientID: data.clients[0].id, data: &data, scan: nil, now: now))
        XCTAssertEqual(data.clients, before)
    }
    func testManualOffPersistsAndFutureCalendarReactivates() throws {
        var data = data()
        try ClientActivity.setActive(false, clientID: data.clients[0].id, data: &data, scan: scan(), now: now)
        data.clients = ClientActivity.refreshed(data: data, scan: scan(), now: now)
        XCTAssertEqual(data.clients[0].activityState?.manuallyInactive, true)
        data.clients = ClientActivity.refreshed(data: data, scan: scan([event(data, start: day(2))]), now: now)
        XCTAssertEqual(data.clients[0].activityState?.inactive, false)
        XCTAssertEqual(data.clients[0].activityState?.manuallyInactive, false)
    }
    func testToggleDoesNotInventSortingActivityAndActivationHasGracePeriod() throws {
        var data = data()
        let last = ClientActivity.lastActivity(clientID: data.clients[0].id, data: data, now: now)
        try ClientActivity.setActive(true, clientID: data.clients[0].id, data: &data, scan: nil, now: now)
        XCTAssertEqual(ClientActivity.lastActivity(clientID: data.clients[0].id, data: data, now: now), last)
        XCTAssertEqual(ClientActivity.refreshed(data: data, scan: scan(), now: now)[0].activityState?.inactive, false)
    }
    func testLegacyAndUnknownNewContactDoNotAcquireInventedOldActivity() throws {
        let bytes = Data(#"{"id":"77777777-7777-4777-8777-777777777777","name":"Contatto Legacy QA","rateCents":1500}"#.utf8)
        let legacy = try JSONDecoder().decode(Client.self, from: bytes)
        XCTAssertNil(legacy.activityState)
        var data = AppData(); data.clients = [legacy]
        let result = ClientActivity.refreshed(data: data, scan: scan(), now: now)
        XCTAssertEqual(result[0].activityState?.inactive, false)
        XCTAssertNil(result[0].activityState?.lastCalendarActivityAt)
        XCTAssertNil(ClientActivity.lastActivity(clientID: legacy.id, data: data, now: now))
    }
    func testAmbiguousNameAndSkippedEventDoNotReactivate() throws {
        var data = data()
        let item = event(data, start: day(2))
        try ClientActivity.setActive(false, clientID: data.clients[0].id, data: &data, scan: scan(), now: now)
        var other = data.clients[0]; other.id = UUID(); data.clients.append(other)
        XCTAssertEqual(ClientActivity.refreshed(data: data, scan: scan([item]), now: now)[0].activityState?.inactive, true)
        data.clients.removeLast(); data.records[item.id] = .init(id: item.id, snapshot: item, status: .skipped)
        XCTAssertEqual(ClientActivity.refreshed(data: data, scan: scan([item]), now: now)[0].activityState?.inactive, true)
    }
    func testHistoryTotalsAndReceivablesAreNotMutated() throws {
        var data = data(), second = Client(name: "Contatto Recente QA", rateCents: 1000)
        second.activityState = .init(inactive: true, manuallyInactive: true, firstObservedAt: now)
        data.clients.append(second)
        data.income.append(.init(clientID: second.id, clientName: second.name, date: day(-2), minutes: 60, amountCents: 1000))
        let incomeIDs = data.income.map(\.id), amount = data.income.reduce(0) { $0 + $1.outstandingCents }
        data.clients = ClientActivity.refreshed(data: data, scan: scan(), now: now)
        XCTAssertEqual(data.income.map(\.id), incomeIDs)
        XCTAssertEqual(data.income.reduce(0) { $0 + $1.outstandingCents }, amount)
        XCTAssertEqual(ClientActivity.sorted(data.clients, data: data, now: now).first?.id, second.id)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(data)).clients, data.clients)
    }
    func testMergeDoesNotDiscardConflictingManualChoices() throws {
        var data = data(), other = Client(name: "Contatto Duplicato QA", rateCents: 1500)
        data.clients[0].activityState = .init(inactive: true, manuallyInactive: true, firstObservedAt: now)
        other.activityState = .init(firstObservedAt: now); data.clients.append(other)
        let original = data.clients
        XCTAssertThrowsError(try ClientRegistry.merge(sourceID: other.id, into: data.clients[0].id, data: &data))
        XCTAssertEqual(data.clients, original)
    }
}
