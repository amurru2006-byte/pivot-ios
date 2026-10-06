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
        StudentRecognition.recognize(title: event.title, clients: clients).name
    }
    static func pending(events: [CalendarItem], data: AppData, now: Date) -> [CalendarItem] {
        pendingEffective(events: Planner.effectiveEvents(events, data: data), data: data, now: now)
    }
    static func pendingEffective(events: [CalendarItem], data: AppData, now: Date) -> [CalendarItem] {
        guard let prompts = data.lessonPrompts else { return [] }
        let answeredSeries = Set(data.records.values.filter { $0.logistics?.confirmedAt != nil }.map { LessonPromptState.seriesKey($0.snapshot) })
        var included: Set<String> = []
        return events.sorted { $0.start < $1.start }.filter {
            let key = LessonPromptState.seriesKey($0)
            return $0.kind == .tutoring && $0.end > now && prompts.pendingSeries.contains(key)
                && !answeredSeries.contains(key)
                && !(data.records[$0.id]?.logistics?.isConfirmed(for: $0) ?? false)
                && included.insert(key).inserted
        }
    }
}

// The first successful calendar import is a baseline, never a queue of forms.
// Track recurring series rather than the occurrences in the rolling date window.
struct LessonPromptState: Codable, Equatable {
    var startedAt: Date
    var seenSeries: Set<String>
    var pendingSeries: Set<String> = []

    static func seriesKey(_ event: CalendarItem) -> String {
        if let external = event.externalIdentifier, !external.isEmpty {
            return event.calendarIdentifier + "|external|" + external
        }
        // CalendarService appends the occurrence anchor to a recurring item's ID.
        if event.recurring == true, let separator = event.id.lastIndex(of: "|"),
           Int(event.id[event.id.index(after: separator)...]) != nil {
            return String(event.id[..<separator])
        }
        return event.calendarIdentifier + "|event|" + event.eventIdentifier
    }

    static func observed(_ events: [CalendarItem], data: AppData, now: Date) -> LessonPromptState {
        let lessons = events.filter { $0.kind == .tutoring }
        let keys = Set(lessons.map(seriesKey))
        guard var state = data.lessonPrompts else {
            return LessonPromptState(startedAt: now, seenSeries: keys)
        }
        for event in lessons {
            let key = seriesKey(event)
            guard !state.seenSeries.contains(key) else { continue }
            // A late-synced old event or old series entering the window is not new.
            if event.end > now && (event.calendarCreatedAt.map { $0 > state.startedAt } ?? true) {
                state.pendingSeries.insert(key)
            }
        }
        state.seenSeries.formUnion(keys)
        // A confirmation is per occurrence; automatic prompting is once per new series.
        // Manual edits for any future occurrence remain available in its detail screen.
        for record in data.records.values where record.logistics?.confirmedAt != nil {
            state.pendingSeries.remove(seriesKey(record.snapshot))
        }
        state.pendingSeries.formIntersection(keys)
        return state
    }
}
