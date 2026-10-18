import Foundation

/// Local-only values. Neither selected places nor route requests belong in the
/// online Coach DTO. A coordinate is a user-selected result, not a GPS fix.
struct TravelPlace: Equatable, Identifiable {
    var id = UUID()
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    static func == (lhs: Self, rhs: Self) -> Bool {
        // Result-row identity is not route identity. Re-selecting the exact same
        // place must not change its coordinates or the request it represents.
        lhs.name == rhs.name && lhs.address == rhs.address && lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 500 && address.count <= 1000
            && latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

enum TravelTiming: String, CaseIterable {
    case departAt, arriveBy
    var label: String { self == .departAt ? "Parti alle" : "Arriva entro" }
}

struct TravelEventContext {
    var events: [CalendarItem]
    func isCurrent(events current: [CalendarItem], data: AppData) -> Bool {
        guard !events.isEmpty, events.count <= 2, Set(events.map(\.id)).count == events.count else { return false }
        let effective = Planner.effectiveEvents(current, data: data)
        return events.allSatisfy { source in
            effective.contains { $0.id == source.id && CoachPlanner.matchesSnapshot(source, $0) }
        }
    }
}

struct TravelRouteRequest: Equatable {
    var origin: TravelPlace
    var destination: TravelPlace
    var mode: ClientTravelMode
    var timing: TravelTiming
    var date: Date
    var isValid: Bool {
        origin.isValid && destination.isValid && Self.supportedModes.contains(mode)
            && date.timeIntervalSinceReferenceDate.isFinite
    }
    static let supportedModes: [ClientTravelMode] = [.walking, .transit, .car, .bicycle]
    func canRequest(consent: Bool, now: Date) -> Bool {
        consent && isValid && now.timeIntervalSinceReferenceDate.isFinite
            && date >= now.addingTimeInterval(-60) && date <= now.addingTimeInterval(7 * 86400)
    }
}

struct TravelEstimate: Equatable {
    var request: TravelRouteRequest
    var fetchedAt: Date
    var departure: Date
    var arrival: Date
    var travelSeconds: Double
    var distanceMeters: Double
    var minutes: Int? { isValid ? Int(ceil(arrival.timeIntervalSince(departure) / 60)) : nil }
    var isValid: Bool {
        request.isValid && fetchedAt.timeIntervalSinceReferenceDate.isFinite
            && departure.timeIntervalSinceReferenceDate.isFinite && arrival.timeIntervalSinceReferenceDate.isFinite
            && travelSeconds.isFinite && (0...86400).contains(travelSeconds) && travelSeconds > 0
            && distanceMeters.isFinite && (0...20_000_000).contains(distanceMeters)
            && arrival > departure && arrival.timeIntervalSince(departure) <= 86400
            && arrival.timeIntervalSince(departure) >= travelSeconds - 60
            && (request.timing == .departAt ? departure >= request.date.addingTimeInterval(-60) : arrival <= request.date.addingTimeInterval(60))
    }
    /// An explicit freshness policy, not an accuracy guarantee. A changed route,
    /// mode or requested time requires another request, even within 15 minutes.
    func isUsable(for current: TravelRouteRequest, consent: Bool, now: Date) -> Bool {
        isValid && request == current && current.canRequest(consent: consent, now: now)
            && now >= fetchedAt && now.timeIntervalSince(fetchedAt) <= 15 * 60
    }
    func conflicts(nextStart: Date, preparationMinutes: Int = 0) -> Bool? {
        guard isValid, nextStart.timeIntervalSinceReferenceDate.isFinite,
              (0...1440).contains(preparationMinutes) else { return nil }
        return arrival.addingTimeInterval(Double(preparationMinutes) * 60) > nextStart
    }
}
