import Foundation

/// Local, freshly recomputed observations. Not missed-activity inferences,
/// notifications, provider requests or Calendar mutations.
enum CoachAgendaSignals {
    struct Signal: Identifiable {
        enum Kind { case overlap, unconfirmedTravel }
        var id: String
        var kind: Kind
        var events: [CalendarItem]
        var explanation: String
        var prompt: String
    }
    static func make(events: [CalendarItem], data: AppData, now: Date) -> [Signal] {
        guard CoachPlanningSession.validDate(now),
              let tomorrow = PivotDate.calendar.date(byAdding: .day, value: 1, to: PivotDate.calendar.startOfDay(for: now)) else { return [] }
        let upcoming = Planner.plannedEvents(events, data: data).filter {
            !$0.isAllDay && $0.end > now && $0.start < tomorrow && $0.end > $0.start
                && ![Completion.completed, .skipped].contains(data.records[$0.id]?.status ?? .pending)
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        // Do not silently truncate a large calendar and imply a full review.
        guard upcoming.count <= 96 else { return [] }
        let paired = Set(upcoming.filter { CalendarActivityLinks.requiresPairedReview($0, data: data) }.map(\.id))
        var result: [Signal] = []
        for event in upcoming {
            let rule = EventRule.effective(for: event, data: data)
            if !event.location.isEmpty && !rule.travelConfirmed {
                result.append(.init(id: "travel:" + event.id, kind: .unconfirmedTravel, events: [event],
                    explanation: "Per ‘\(event.title)’ manca un tragitto confermato. Non posso verificare se il tempo disponibile basta.",
                    prompt: "Aiutami a controllare il tragitto di ‘\(event.title)’ senza modificare ancora il Calendario."))
            }
        }
        for (index, first) in upcoming.enumerated() {
            let a = EventRule.effective(for: first, data: data)
            guard a.travelConfirmed, (0...1440).contains(a.travelBeforeMinutes), (0...1440).contains(a.travelAfterMinutes) else { continue }
            for second in upcoming.dropFirst(index + 1) {
                let b = EventRule.effective(for: second, data: data)
                guard b.travelConfirmed, (0...1440).contains(b.travelBeforeMinutes), (0...1440).contains(b.travelAfterMinutes) else { continue }
                // Linked travel is one occupied group, not a conflict against its own activity.
                guard !paired.contains(first.id), !paired.contains(second.id) else { continue }
                let start = max(first.start.addingTimeInterval(-Double(a.travelBeforeMinutes) * 60), second.start.addingTimeInterval(-Double(b.travelBeforeMinutes) * 60))
                let end = min(first.end.addingTimeInterval(Double(a.travelAfterMinutes) * 60), second.end.addingTimeInterval(Double(b.travelAfterMinutes) * 60))
                if start < end && end > now {
                    let ids = [first.id, second.id].sorted().joined(separator: "|")
                    result.append(.init(id: "overlap:" + ids, kind: .overlap, events: [first, second],
                        explanation: "‘\(first.title)’ e ‘\(second.title)’ si sovrappongono considerando le durate e i tragitti confermati. Le stime di viaggio vanno ricontrollate prima di scegliere nuovi orari.",
                        prompt: "Aiutami a riorganizzare ‘\(first.title)’ e ‘\(second.title)’, mantenendo durate e tragitti. Mostrami prima le alternative."))
                }
            }
        }
        return Array(result.prefix(3))
    }
}
