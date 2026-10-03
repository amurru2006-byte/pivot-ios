import Foundation

enum LessonPlace: String, Codable, CaseIterable {
    case myHome, studentHome, other, undecided
    var label: String {
        switch self {
        case .myHome: return "Viene da me"
        case .studentHome: return "Vado da lui/lei"
        case .other: return "Altro / online"
        case .undecided: return "Da decidere"
        }
    }
}

struct LessonLogistics: Codable {
    var studentName: String
    var place: LessonPlace
    var address: String = ""
    var travelBeforeMinutes: Int = 0
    var travelAfterMinutes: Int = 0
    var travelConfirmed: Bool = false
    var confirmedAt: Date? = nil
    var eventTitleAtConfirmation: String? = nil
    var calendarLocationAtConfirmation: String? = nil
    func isConfirmed(for event: CalendarItem) -> Bool {
        confirmedAt != nil
            && (eventTitleAtConfirmation.map { EventCoalescer.normalized($0) == EventCoalescer.normalized(event.title) } ?? true)
            && (calendarLocationAtConfirmation.map { EventCoalescer.normalized($0) == EventCoalescer.normalized(event.location) } ?? true)
    }
    static func key(_ name: String) -> String { EventCoalescer.normalized(name) }
    static func suggestedName(_ event: CalendarItem, clients: [Client]) -> String {
        let title = EventCoalescer.normalized(event.title)
        let matches = clients.filter { title.contains(EventCoalescer.normalized($0.name)) }
        if matches.count == 1 { return matches[0].name }
        // This is only an editable suggestion, never an automatic person association.
        var result = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["lezione con ", "ripetizioni con ", "ripetizione con ", "lezione ", "ripetizioni "] {
            if result.lowercased().hasPrefix(prefix) { result = String(result.dropFirst(prefix.count)); break }
        }
        return result
    }
    static func pending(events: [CalendarItem], data: AppData, now: Date) -> [CalendarItem] {
        Planner.effectiveEvents(events, data: data).filter {
            $0.kind == .tutoring && $0.end > now && !(data.records[$0.id]?.logistics?.isConfirmed(for: $0) ?? false)
        }.sorted { $0.start < $1.start }
    }
}
