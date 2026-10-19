import Foundation

/// On-device editor state. Never added to the online Coach request or its DTO.
struct CalendarCreationOptions: Codable, Equatable {
    var location = ""
    var availability = 0 // EventKit busy; free is 1. No private EventKit keys.
    var alertMinutes: Int? = nil
    var travel: CalendarCreationTravel? = nil

    var isValid: Bool {
        location.count <= 1000 && [0, 1].contains(availability)
            && (alertMinutes.map { [0, 5, 10, 15, 30, 60, 120, 1440].contains($0) } ?? true)
            && (travel?.isValid ?? true)
    }
    func problem(draft: CoachCalendarDraft, now: Date, mapsConsent: Bool) -> String? {
        guard isValid else { return "Controlla luogo, avviso e tempo di percorrenza." }
        guard let travel else { return nil }
        guard let start = draft.start else { return "Imposta prima l’inizio dell’evento." }
        guard !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !travel.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Indica partenza e destinazione del viaggio."
        }
        if let estimate = travel.estimate {
            guard mapsConsent, estimate.isUsable(for: estimate.request, consent: mapsConsent, now: now),
                  estimate.request.timing == .arriveBy, estimate.request.date == start,
                  estimate.request.destination.address == location,
                  estimate.request.origin.address == travel.origin,
                  estimate.minutes == travel.minutes else {
                return "La stima Maps è scaduta o il luogo, l’orario o il consenso sono cambiati. Ricalcola oppure scegli un tempo manuale."
            }
        }
        return nil
    }
    func parts(draft: CoachCalendarDraft, creationID: UUID) -> [CalendarCreationPart] {
        guard isValid, let start = draft.start, let end = draft.end, end > start else { return [] }
        let main = CalendarCreationPart(marker: "pivot://created/" + creationID.uuidString,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines), start: start, end: end,
            location: location, notes: draft.notes, availability: availability, alertMinutes: alertMinutes, isTravel: false)
        guard let travel else { return [main] }
        // ETA departure includes transit waiting; do not subtract only in-vehicle time.
        let departure = travel.estimate?.departure ?? start.addingTimeInterval(-Double(travel.minutes) * 60)
        guard departure < start else { return [] }
        let note = "Da: \(travel.origin)\nA: \(location)\n" +
            (travel.estimate == nil ? "Tempo indicato manualmente." : "Stima Apple Maps, non una garanzia.") +
            "\nCollegato a: \(main.title). Se cambi l’attività, verifica anche questo spostamento."
        let trip = CalendarCreationPart(marker: "pivot://travel/" + creationID.uuidString,
            title: "Spostamento", start: departure, end: start, location: location, notes: note,
            availability: 0, alertMinutes: nil, isTravel: true)
        return [trip, main]
    }
}

struct CalendarCreationTravel: Codable, Equatable {
    var minutes: Int
    var origin: String
    var estimate: TravelEstimate? = nil
    var isValid: Bool {
        (1...1440).contains(minutes) && origin.count <= 1000 && (estimate?.isValid ?? true)
    }
}

struct CalendarCreationPart: Equatable {
    let marker: String
    let title: String
    let start: Date
    let end: Date
    let location: String
    let notes: String
    let availability: Int
    let alertMinutes: Int?
    let isTravel: Bool
}

enum CalendarCreationBundle {
    /// A previous partial/changed write must not be completed or duplicated blindly.
    static func existing(parts: [CalendarCreationPart], items: [CalendarItem]) -> Bool {
        !parts.isEmpty && parts.count == items.count && zip(parts, items).allSatisfy { part, item in
            part.title == item.title && abs(part.start.timeIntervalSince(item.start)) < 1
                && abs(part.end.timeIntervalSince(item.end)) < 1
                && part.location == item.location && part.notes == item.notes
        }
    }
    static func conflicts(parts: [CalendarCreationPart], events: [CalendarItem]) -> [CalendarItem] {
        events.filter { item in parts.contains { $0.start < item.end && $0.end > item.start } }
            .sorted { $0.id < $1.id }
    }
}
