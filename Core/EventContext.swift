import Foundation

enum EventPriority: Int, Codable, CaseIterable {
    case low = 0, normal = 1, high = 2, essential = 3
    var label: String {
        switch self {
        case .low: return "Bassa"
        case .normal: return "Normale"
        case .high: return "Alta"
        case .essential: return "Non rimandabile"
        }
    }
}

enum ContextRelation: String, Codable { case included, conflict, uncertain, travel }

struct EventDecision: Codable, Identifiable, Equatable {
    var id: String
    var firstID: String
    var secondID: String
    var firstTitle: String
    var secondTitle: String
    var date: Date
    var relation: ContextRelation
    var explanation: String
    var deferred: Bool = false
}

struct ContextAnswer: Codable, Equatable {
    var id: String
    var compatible: Bool
    var answeredAt: Date
    var travelMinutes: Int? = nil
}

enum EventContext {
    static func priority(_ event: CalendarItem, data: AppData, now: Date) -> EventPriority {
        if let value = data.rules[event.id]?.priority { return value }
        if event.kind == .exam { return .essential }
        if event.kind == .study && Planner.isStudyPriority(data, now: now) { return .essential }
        if [.university, .tutoring, .work].contains(event.kind) { return .high }
        return .normal
    }
    static func isTravel(_ item: CalendarItem) -> Bool {
        let words = EventCoalescer.normalized(item.title).split(separator: " ")
        return words.contains(where: { ["viaggio", "tragitto", "train", "treno", "bus", "metro"].contains(String($0)) })
    }
    static func key(_ a: CalendarItem, _ b: CalendarItem) -> String {
        // A calendar edit invalidates an old answer rather than silently hiding a new conflict.
        [a, b].sorted { $0.id < $1.id }.map {
            "\($0.id)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)|\($0.title)|\($0.location)|\($0.kind.rawValue)"
        }.joined(separator: "↔")
    }
    static func relation(_ a: CalendarItem, _ b: CalendarItem, data: AppData) -> (ContextRelation, String) {
        if let answer = data.contextAnswers?.last(where: { $0.id == key(a, b) }) {
            return answer.compatible ? (.included, "Compatibilità confermata da te per questi eventi.") : (.conflict, "Hai confermato che questi impegni non sono compatibili.")
        }
        let social: [EventKind] = [.friends, .partner, .social]
        let container = social.contains(a.kind) ? a : (social.contains(b.kind) ? b : nil)
        let child = container?.id == a.id ? b : a
        if let container, child.kind == .meal, container.start <= child.start, container.end >= child.end {
            // A default meal at home is a routine plan, not a separate appointment.
            let mealPlace = EventCoalescer.normalized(child.location)
            if mealPlace.isEmpty || ["casa", "a casa", "home"].contains(mealPlace) || mealPlace == EventCoalescer.normalized(container.location) {
                return (.included, "Il pasto rientra nell’uscita: non sono due appuntamenti separati.")
            }
            return (.uncertain, "Il pasto è dentro l’uscita, ma ha un luogo diverso. Lo fai insieme agli altri?")
        }
        if let container, isTravel(child), container.start <= child.start, container.end >= child.end {
            return (.uncertain, "Questo tragitto è parte dell’uscita o un impegno separato?")
        }
        let exclusive: [EventKind] = [.university, .tutoring, .work, .workout, .exam, .study]
        let dedicated = ["dentista", "visita", "spesa", "appuntamento"]
        if exclusive.contains(a.kind) || exclusive.contains(b.kind) || dedicated.contains(where: { EventCoalescer.normalized(a.title).contains($0) || EventCoalescer.normalized(b.title).contains($0) }) {
            return (.conflict, "Richiedono tempo dedicato nello stesso intervallo.")
        }
        let first = EventCoalescer.normalized(a.location), second = EventCoalescer.normalized(b.location)
        if !first.isEmpty && !second.isEmpty && first != second {
            return (.conflict, "Sono indicati due luoghi diversi nello stesso intervallo.")
        }
        return (.uncertain, "Gli orari coincidono: sono attività compatibili oppure separate?")
    }
    static func decisions(on day: Date, events: [CalendarItem], data: AppData) -> [EventDecision] {
        let items = events.filter { !$0.isAllDay && $0.occurs(on: day) && ![Completion.completed, .partial, .skipped].contains(data.records[$0.id]?.status ?? .pending) }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        var result: [EventDecision] = []
        func append(_ a: CalendarItem, _ b: CalendarItem, _ relation: ContextRelation, _ text: String) {
            guard relation != .included else { return }
            let id = key(a, b)
            result.append(.init(id: id, firstID: a.id, secondID: b.id, firstTitle: a.title, secondTitle: b.title,
                                date: max(a.start, b.start), relation: relation, explanation: text,
                                deferred: data.decisions?.first(where: { $0.id == id })?.deferred ?? false))
        }
        for i in items.indices {
            for j in items.indices where j > i {
                let a = items[i], b = items[j]
                if b.start < a.end && a.start < b.end {
                    let value = relation(a, b, data: data); append(a, b, value.0, value.1)
                }
            }
        }
        // Travel is checked between consecutive appointments, not all future pairs.
        let appointments = items.filter { !isTravel($0) && $0.kind != .meal }
        for (a, b) in zip(appointments, appointments.dropFirst()) where a.end <= b.start {
            let first = EventCoalescer.normalized(a.location), second = EventCoalescer.normalized(b.location)
            guard !first.isEmpty, !second.isEmpty, first != second else { continue }
            let ra = data.rules[a.id] ?? .defaultRule(for: a), rb = data.rules[b.id] ?? .defaultRule(for: b)
            let gap = b.start.timeIntervalSince(a.end) / 60
            if let minutes = data.contextAnswers?.last(where: { $0.id == key(a, b) })?.travelMinutes {
                if gap < Double(minutes) { append(a, b, .travel, "Hai \(Int(gap)) min, ma il tragitto confermato richiede \(minutes) min.") }
                continue
            }
            if ra.travelConfirmed && rb.travelConfirmed {
                let required = ra.travelAfterMinutes + rb.travelBeforeMinutes
                if gap < Double(required) { append(a, b, .travel, "Hai \(Int(gap)) min, ma hai confermato \(required) min di tragitto. Serve spostare un impegno.") }
            } else if gap < 90 {
                append(a, b, .uncertain, "Hai \(Int(gap)) min per cambiare luogo. Quanto dura il tragitto? Non considero zero un tempo sconosciuto.")
            }
        }
        return result
    }
    static func refreshed(events: [CalendarItem], data: AppData, now: Date) -> [EventDecision] {
        let planned = Planner.plannedEvents(events, data: data)
        return (0..<7).flatMap { offset -> [EventDecision] in
            guard let day = PivotDate.calendar.date(byAdding: .day, value: offset, to: now) else { return [] }
            return decisions(on: day, events: planned, data: data)
        }.reduce(into: [EventDecision]()) { result, value in
            if !result.contains(where: { $0.id == value.id }) { result.append(value) }
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
