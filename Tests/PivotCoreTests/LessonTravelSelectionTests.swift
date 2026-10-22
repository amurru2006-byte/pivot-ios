import XCTest
@testable import PivotCore

final class LessonTravelSelectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var event: CalendarItem {
        .init(id: "lesson-qa", eventIdentifier: "lesson-qa", calendarIdentifier: "qa", calendarTitle: "Lavoro QA", title: "Lezione QA",
              start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), location: "", notes: "", colorHex: "FFFFFF", isAllDay: false, writable: true, kind: .tutoring)
    }
    private var estimate: TravelEstimate {
        let request = TravelRouteRequest(origin: .init(name: "Nuova partenza QA", address: "Via Origine QA", latitude: 45, longitude: 9),
            destination: .init(name: "Nuova destinazione QA", address: "Via Destinazione QA", latitude: 45.1, longitude: 9.1),
            mode: .transit, timing: .arriveBy, date: event.start)
        return .init(request: request, fetchedAt: now, departure: event.start.addingTimeInterval(-1800), arrival: event.start,
                     travelSeconds: 1500, distanceMeters: 2000)
    }
    func testMapsChoiceCopiesEntireRouteAndNeverConfirmsOrInventsReturn() throws {
        let old = LessonLogistics(studentName: "QA", place: .studentHome, address: "Vecchio luogo QA", travelBeforeMinutes: 4,
            travelAfterMinutes: 40, travelConfirmed: true, confirmedAt: now, departure: .init(name: "Vecchia partenza QA", address: "Vecchia via QA"))
        let result = try old.applying(estimate, for: event)
        XCTAssertEqual(result.address, estimate.request.destination.address)
        XCTAssertEqual(result.departure?.address, estimate.request.origin.address)
        XCTAssertEqual(result.departure?.mode, .transit); XCTAssertEqual(result.travelBeforeMinutes, 30)
        XCTAssertEqual(result.travelAfterMinutes, 0); XCTAssertFalse(result.travelConfirmed); XCTAssertNil(result.confirmedAt)
        XCTAssertNotEqual(result.departure?.id, old.departure?.id)
    }
    func testSameKnownOriginPreservesIdentityAndOnlyExistingReturnEstimate() throws {
        let origin = ClientTravelOrigin(name: "Casa QA", address: estimate.request.origin.address, mode: .transit)
        let old = LessonLogistics(studentName: "QA", place: .studentHome, address: estimate.request.destination.address,
                                  travelAfterMinutes: 12, departure: origin)
        let result = try old.applying(estimate, for: event)
        XCTAssertEqual(result.departure?.id, origin.id); XCTAssertEqual(result.departure?.name, "Casa QA")
        XCTAssertEqual(result.travelAfterMinutes, 12); XCTAssertFalse(result.travelConfirmed)
    }
    func testWrongTimeModeOfTimingAndOversizedPlacesCannotAttachDuration() {
        let value = LessonLogistics(studentName: "QA", place: .studentHome)
        var invalid = estimate; invalid.request.timing = .departAt
        XCTAssertThrowsError(try value.applying(invalid, for: event))
        invalid = estimate; invalid.request.date.addTimeInterval(60)
        XCTAssertThrowsError(try value.applying(invalid, for: event))
        invalid = estimate; invalid.request.destination.address = String(repeating: "x", count: 501)
        XCTAssertThrowsError(try value.applying(invalid, for: event))
        invalid = estimate; invalid.request.origin.name = String(repeating: "x", count: 121)
        XCTAssertThrowsError(try value.applying(invalid, for: event))
        invalid = estimate; invalid.departure = event.start.addingTimeInterval(-241 * 60)
        XCTAssertThrowsError(try value.applying(invalid, for: event))
    }
    func testDraftHomeAddressRequiresUnambiguousLessonAndPreservesExplicitLocation() {
        let client = Client(name: "Cliente QA", rateCents: 1500, defaults: .init(place: .studentHome, address: "Via Cliente QA"))
        XCTAssertEqual(ClientDefaults.lessonDraftLocation(title: "Ripetizioni Cliente QA", currentLocation: "", clients: [client]), "Via Cliente QA")
        XCTAssertEqual(ClientDefaults.lessonDraftLocation(title: "Lezione Cliente QA", currentLocation: "Luogo dell’evento QA", clients: [client]), "Luogo dell’evento QA")
        XCTAssertEqual(ClientDefaults.lessonDraftLocation(title: "Telefonata Cliente QA", currentLocation: "", clients: [client]), "")
        XCTAssertEqual(ClientDefaults.lessonDraftLocation(title: "Lezione online Cliente QA", currentLocation: "", clients: [client]), "")
        var duplicate = client; duplicate.id = UUID()
        XCTAssertEqual(ClientDefaults.lessonDraftLocation(title: "Lezione Cliente QA", currentLocation: "", clients: [client, duplicate]), "")
    }
}
