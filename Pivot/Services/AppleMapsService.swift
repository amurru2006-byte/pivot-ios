import Foundation
import MapKit

/// No GPS, background polling, online-Coach access or automatic retries.
/// Consent is installation-local and is deliberately not restored from backups.
@MainActor final class AppleMapsService: ObservableObject {
    static let shared = AppleMapsService()
    @Published private(set) var consentGranted: Bool
    @Published private(set) var busy = false
    @Published private(set) var requestCount = 0
    private let defaults: UserDefaults
    private static let consentKey = "pivot.appleMaps.explicitConsent.v1"
    private var search: MKLocalSearch?
    private var directions: MKDirections?
    private var generation = UUID()
    private let interactionTest: Bool
    let synthetic: Bool

    enum Failure: LocalizedError {
        case consent, invalid, unavailable, expired, busy
        var errorDescription: String? {
            switch self {
            case .consent: return "Prima autorizza le richieste ad Apple Maps."
            case .invalid: return "Controlla luoghi, mezzo e orario: scegli una data nei prossimi 7 giorni."
            case .unavailable: return "Stima non disponibile da Apple Maps. Non considero il tragitto pari a zero. Puoi riprovare più tardi o inserire un tempo verificato da te."
            case .expired: return "La richiesta è stata annullata o il consenso è cambiato."
            case .busy: return "Attendi la richiesta in corso."
            }
        }
    }
    private init() {
        let args = ProcessInfo.processInfo.arguments
        interactionTest = args.contains("--interaction-test")
        if interactionTest, args.contains("--travel-estimate-test"),
           let id = UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_TRAVEL_ID"] ?? ""),
           let isolated = UserDefaults(suiteName: "PivotTravelQA-\(id.uuidString)") {
            defaults = isolated; synthetic = true
        } else { defaults = .standard; synthetic = false }
        consentGranted = defaults.bool(forKey: Self.consentKey)
    }
    func setConsent(_ allowed: Bool) {
        consentGranted = allowed; defaults.set(allowed, forKey: Self.consentKey)
        if !allowed { cancelPending() }
    }
    func cancelPending() {
        generation = UUID(); search?.cancel(); directions?.cancel()
        search = nil; directions = nil; busy = false
    }
    private func begin() throws -> UUID {
        guard consentGranted else { throw Failure.consent }
        guard !interactionTest || synthetic else { throw Failure.unavailable }
        guard !busy else { throw Failure.busy }
        busy = true; return generation
    }
    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard consentGranted, token == generation else { throw Failure.expired }
    }
    func places(matching text: String) async throws -> [TravelPlace] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...500).contains(query.count) else { throw Failure.invalid }
        let token = try begin()
        defer { if token == generation { busy = false; search = nil } }
        try check(token); requestCount += 1
        if synthetic {
            return [.init(name: "Luogo QA A", address: "Indirizzo sintetico A", latitude: 45, longitude: 9),
                    .init(name: "Luogo QA B", address: "Indirizzo sintetico B", latitude: 45.1, longitude: 9.1)]
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let operation = MKLocalSearch(request: request); search = operation
        do {
            let response = try await operation.start()
            try check(token)
            let places = response.mapItems.prefix(10).map { item in
                TravelPlace(name: item.name ?? "Luogo", address: item.placemark.title ?? "",
                            latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            }.filter(\.isValid)
            guard !places.isEmpty else { throw Failure.unavailable }
            return places
        } catch {
            try check(token)
            throw Failure.unavailable
        }
    }
    func estimate(_ input: TravelRouteRequest) async throws -> TravelEstimate {
        guard input.canRequest(consent: consentGranted, now: Date()) else { throw consentGranted ? Failure.invalid : Failure.consent }
        let token = try begin()
        defer { if token == generation { busy = false; directions = nil } }
        try check(token); requestCount += 1
        if synthetic {
            let seconds = input.mode == .walking ? 1500.0 : 1200.0
            let departure = input.timing == .departAt ? input.date : input.date.addingTimeInterval(-seconds)
            return .init(request: input, fetchedAt: Date(), departure: departure,
                         arrival: departure.addingTimeInterval(seconds), travelSeconds: seconds, distanceMeters: 1500)
        }
        let request = MKDirections.Request()
        // Send selected coordinates, not personal contact names or calendar notes.
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: input.origin.latitude, longitude: input.origin.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: input.destination.latitude, longitude: input.destination.longitude)))
        switch input.mode {
        case .walking: request.transportType = .walking
        case .transit: request.transportType = .transit
        case .car: request.transportType = .automobile
        case .bicycle: request.transportType = .cycling
        default: throw Failure.invalid
        }
        if input.timing == .arriveBy { request.arrivalDate = input.date } else { request.departureDate = input.date }
        let operation = MKDirections(request: request); directions = operation
        do {
            let response = try await operation.calculateETA()
            try check(token)
            let result = TravelEstimate(request: input, fetchedAt: Date(), departure: response.expectedDepartureDate,
                                        arrival: response.expectedArrivalDate, travelSeconds: response.expectedTravelTime,
                                        distanceMeters: response.distance)
            guard result.isValid else { throw Failure.unavailable }
            return result
        } catch {
            try check(token)
            throw Failure.unavailable
        }
    }
}
