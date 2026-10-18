import XCTest
@testable import PivotCore

final class TravelEstimateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var request: TravelRouteRequest {
        .init(origin: .init(name: "Partenza QA", address: "Indirizzo sintetico A", latitude: 45, longitude: 9),
              destination: .init(name: "Arrivo QA", address: "Indirizzo sintetico B", latitude: 45.1, longitude: 9.1),
              mode: .transit, timing: .departAt, date: now.addingTimeInterval(3600))
    }
    private var estimate: TravelEstimate {
        .init(request: request, fetchedAt: now, departure: request.date, arrival: request.date.addingTimeInterval(1201),
              travelSeconds: 1201, distanceMeters: 1500)
    }
    func testEventContextRejectsDeletedMovedOrChangedLocationsBeforeNewMapRequests() {
        let event = CalendarItem(id: "event-qa", eventIdentifier: "event-qa", calendarIdentifier: "qa", calendarTitle: "QA", title: "Attività QA",
                                 start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), location: "Luogo QA", notes: "", colorHex: "7EE6CD",
                                 isAllDay: false, writable: true, kind: .other)
        let context = TravelEventContext(events: [event])
        XCTAssertTrue(context.isCurrent(events: [event], data: .init()))
        XCTAssertFalse(context.isCurrent(events: [], data: .init()))
        var changed = event; changed.location = "Altro luogo QA"
        XCTAssertFalse(context.isCurrent(events: [changed], data: .init()))
        changed = event; changed.start.addTimeInterval(60)
        XCTAssertFalse(context.isCurrent(events: [changed], data: .init()))
        XCTAssertFalse(TravelEventContext(events: [event, event]).isCurrent(events: [event], data: .init()))
    }
    func testExplicitConsentIsRequiredForEveryRequest() {
        XCTAssertFalse(request.canRequest(consent: false, now: now))
        XCTAssertTrue(request.canRequest(consent: true, now: now))
        XCTAssertFalse(estimate.isUsable(for: request, consent: false, now: now))
    }
    func testCoordinateAndTransportValidationDoesNotInventATransport() {
        var value = request
        value.mode = .unspecified; XCTAssertFalse(value.isValid)
        value.mode = .other; XCTAssertFalse(value.isValid)
        value.mode = .bicycle; XCTAssertTrue(value.isValid)
        value.origin.latitude = .nan; XCTAssertFalse(value.isValid)
        value.origin.latitude = 91; XCTAssertFalse(value.isValid)
        value.origin.latitude = 45; value.destination.longitude = 181; XCTAssertFalse(value.isValid)
    }
    func testRequestsAreBoundedToTheUpcomingWeek() {
        var value = request
        value.date = now.addingTimeInterval(-61); XCTAssertFalse(value.canRequest(consent: true, now: now))
        value.date = now.addingTimeInterval(7 * 86400 + 1); XCTAssertFalse(value.canRequest(consent: true, now: now))
        value.date = Date(timeIntervalSince1970: .infinity); XCTAssertFalse(value.isValid)
    }
    func testFreshEstimateRoundsUpWithoutTurningUnknownIntoZero() {
        XCTAssertTrue(estimate.isValid); XCTAssertEqual(estimate.minutes, 21)
        var value = estimate
        value.travelSeconds = 0; XCTAssertFalse(value.isValid); XCTAssertNil(value.minutes)
        value.travelSeconds = .infinity; XCTAssertFalse(value.isValid)
        value = estimate; value.distanceMeters = -1; XCTAssertFalse(value.isValid)
        value = estimate; value.arrival = value.departure; XCTAssertFalse(value.isValid)
    }
    func testTransitOccupancyIncludesWaitingWithoutInventingAServiceStatus() {
        var value = estimate
        value.arrival.addTimeInterval(600)
        XCTAssertTrue(value.isValid); XCTAssertEqual(value.minutes, 31)
        XCTAssertEqual(value.conflicts(nextStart: estimate.arrival), true)
    }
    func testChangingTimeModeOrPlacesInvalidatesEvenAFreshResult() {
        XCTAssertTrue(estimate.isUsable(for: request, consent: true, now: now))
        var value = request
        value.date.addTimeInterval(60); XCTAssertFalse(estimate.isUsable(for: value, consent: true, now: now))
        value = request; value.mode = .walking; XCTAssertFalse(estimate.isUsable(for: value, consent: true, now: now))
        value = request; value.destination.longitude += 0.01
        XCTAssertFalse(estimate.isUsable(for: value, consent: true, now: now))
    }
    func testFreshnessIsNotAnAccuracyGuaranteeAndRejectsFutureFetchDate() {
        XCTAssertTrue(estimate.isUsable(for: request, consent: true, now: now.addingTimeInterval(900)))
        XCTAssertFalse(estimate.isUsable(for: request, consent: true, now: now.addingTimeInterval(901)))
        XCTAssertFalse(estimate.isUsable(for: request, consent: true, now: now.addingTimeInterval(-1)))
    }
    func testArriveByAndDepartAtRespectRequestedBoundary() {
        var value = estimate
        value.departure = request.date.addingTimeInterval(-1201); value.arrival = request.date
        XCTAssertFalse(value.isValid)
        value.request.timing = .arriveBy; XCTAssertTrue(value.isValid)
        value.arrival.addTimeInterval(61); value.departure.addTimeInterval(61); XCTAssertFalse(value.isValid)
    }
    func testConflictAccountsForPreparationAndExactBoundary() {
        XCTAssertEqual(estimate.conflicts(nextStart: estimate.arrival), false)
        XCTAssertEqual(estimate.conflicts(nextStart: estimate.arrival, preparationMinutes: 1), true)
        XCTAssertNil(estimate.conflicts(nextStart: estimate.arrival, preparationMinutes: -1))
    }
}
