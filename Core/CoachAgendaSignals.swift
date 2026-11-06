import Foundation

/// Fresh local observations, with explicit coverage. Not missed-workout
/// inferences, provider requests, notifications or Calendar mutations.
enum CoachAgendaSignals {
    struct Signal: Identifiable {
        enum Kind: Equatable { case overlap, unconfirmedTravel, linkedReview }
        var id: String
        var kind: Kind
        var events: [CalendarItem]
        var explanation: String
        var prompt: String
    }
    enum Coverage: Equatable { case observedToday, limited, calendarUnavailable, oversized, invalid }
    struct Report {
        var signals: [Signal]
        var totalCount: Int
        var reviewedGroups: Int
        var coverage: Coverage
        var disclosure: String {
            switch coverage {
            case .calendarUnavailable: return "Accesso al Calendario non disponibile: non posso controllare l’agenda."
            case .oversized: return "Ci sono troppi impegni per questo controllo locale. Non ho verificato l’agenda completa."
            case .invalid: return "Alcuni dati dell’agenda non sono verificabili. Non posso confermare che gli spazi siano liberi."
            case .limited: return "Controllo parziale dell’agenda di oggi: alcuni tragitti, collegamenti o impegni giornalieri richiedono verifica."
            case .observedToday: return "Osservazioni sull’agenda di oggi disponibile in Pivot, con i tempi confermati. Non è una verifica esaustiva delle disponibilità."
            }
        }
        var countDisclosure: String? {
            totalCount > signals.count ? "Mostro \(signals.count) di \(totalCount) osservazioni." : nil
        }
    }
    private struct Group {
        var id: String
        var primary: CalendarItem
        var members: [CalendarItem]
        var start: Date
        var end: Date
    }
    static func make(events: [CalendarItem], data: AppData, now: Date) -> [Signal] {
        report(events: events, data: data, now: now).signals
    }
    static func report(events: [CalendarItem], data: AppData, now: Date, calendarAccess: Bool = true) -> Report {
        func empty(_ coverage: Coverage) -> Report { .init(signals: [], totalCount: 0, reviewedGroups: 0, coverage: coverage) }
        guard calendarAccess else { return empty(.calendarUnavailable) }
        guard CoachPlanningSession.validDate(now), let tomorrow = PivotDate.calendar.date(byAdding: .day, value: 1,
            to: PivotDate.calendar.startOfDay(for: now)) else { return empty(.invalid) }
        guard events.count <= 20_000 else { return empty(.oversized) }
        guard events.allSatisfy({ CoachPlanningSession.validDate($0.start) && CoachPlanningSession.validDate($0.end) && $0.end > $0.start }),
              Set(events.map(\.id)).count == events.count else { return empty(.invalid) }
        let planned = Planner.plannedEvents(events, data: data)
        let nearby = planned.filter {
            $0.end > now.addingTimeInterval(-86400) && $0.start < tomorrow.addingTimeInterval(86400)
                && ![Completion.completed, .skipped].contains(data.records[$0.id]?.status ?? .pending)
        }
        guard nearby.count <= 96 else { return empty(.oversized) }
        guard nearby.allSatisfy({ CoachPlanningSession.validDate($0.start) && CoachPlanningSession.validDate($0.end) && $0.end > $0.start }),
              Set(nearby.map(\.id)).count == nearby.count else { return empty(.invalid) }
        var limited = nearby.contains { $0.isAllDay && $0.start < tomorrow && $0.end > now }
        let availability = CoachPlanningLogistics.availabilityData(events: events, data: data)
        let rawIndex = CoachPlanningLogistics.EventIndex(events)
        let plannedIndex = CoachPlanningLogistics.EventIndex(planned)
        var groups: [Group] = [], signals: [Signal] = [], seen: Set<String> = []
        func needsReview(_ id: String, _ members: [CalendarItem], _ explanation: String) {
            limited = true
            signals.append(.init(id: "review:" + id, kind: .linkedReview, events: members,
                explanation: explanation, prompt: "Aiutami a verificare il collegamento attività/viaggio di ‘\(members.first?.title ?? "questa attività")’. Non modificare ancora il Calendario."))
        }
        func bounds(_ source: CalendarItem, key: String) -> (Date, Date)? {
            let rule = EventRule.effective(for: source, data: availability)
            guard (0...1440).contains(rule.travelBeforeMinutes), (0...1440).contains(rule.travelAfterMinutes) else {
                limited = true; return nil
            }
            guard rule.travelConfirmed else {
                limited = true
                if !source.location.isEmpty || rule.travelBeforeMinutes > 0 || rule.travelAfterMinutes > 0 {
                    signals.append(.init(id: "travel:" + key, kind: .unconfirmedTravel, events: [source],
                        explanation: "Per ‘\(source.title)’ manca un tragitto confermato. Non posso verificare se il tempo disponibile basta.",
                        prompt: "Aiutami a controllare il tragitto di ‘\(source.title)’ senza modificare ancora il Calendario."))
                }
                return nil
            }
            return (source.start.addingTimeInterval(-Double(rule.travelBeforeMinutes) * 60),
                    source.end.addingTimeInterval(Double(rule.travelAfterMinutes) * 60))
        }
        for source in nearby.sorted(by: { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }) where !source.isAllDay {
            if CalendarActivityLinks.requiresPairedReview(source, data: data) {
                guard let link = CalendarActivityLinks.link(for: source, data: data), link.isValid else {
                    if seen.insert("invalid:" + source.id).inserted { needsReview(source.id, [source], "Il collegamento di ‘\(source.title)’ non è verificabile. Controlla attività e viaggio insieme.") }
                    continue
                }
                let key = "linked:" + link.id.uuidString
                guard seen.insert(key).inserted else { continue }
                // Native revisions, not names/proximity. Check raw and planned
                // members so duplicate or half-moved observations cannot be hidden.
                let rawMain = rawIndex.matches(link.activity)
                let rawTrip = rawIndex.matches(link.travel)
                let mains = plannedIndex.matches(link.activity)
                let trips = plannedIndex.matches(link.travel)
                guard rawMain.count == 1, rawTrip.count == 1, mains.count == 1, trips.count == 1,
                      let main = mains.first, let trip = trips.first,
                      CalendarSnapshotMatch.revision(link.activity, main),
                      CalendarSnapshotMatch.revision(link.travel, trip) else {
                    needsReview(key, [link.activity, link.travel], "L’attività ‘\(link.activity.title)’ o il suo viaggio sono cambiati o incompleti. Il gruppo richiede verifica, non lo considero libero.")
                    continue
                }
                if [Completion.completed, .skipped].contains(data.records[main.id]?.status ?? .pending) {
                    if trip.end > now { needsReview(key, [main, trip], "L’attività ‘\(main.title)’ risulta conclusa o saltata, ma il viaggio è ancora presente in agenda. Verifica il gruppo.") }
                    continue
                }
                guard let a = bounds(main, key: key), let b = bounds(trip, key: key + ":trip") else { continue }
                let start = min(a.0, b.0), end = max(a.1, b.1)
                if start < tomorrow && end > now {
                    groups.append(.init(id: key, primary: main, members: [main, trip], start: start, end: end))
                }
            } else {
                guard seen.insert("event:" + source.id).inserted else { continue }
                guard let interval = bounds(source, key: source.id) else { continue }
                if interval.0 < tomorrow && interval.1 > now {
                    groups.append(.init(id: "event:" + source.id, primary: source, members: [source], start: interval.0, end: interval.1))
                }
            }
        }
        for (index, first) in groups.enumerated() {
            for second in groups.dropFirst(index + 1) {
                let start = max(first.start, second.start), end = min(first.end, second.end)
                guard start < end, end > now, start < tomorrow else { continue }
                let key = [first.id, second.id].sorted().joined(separator: "|")
                signals.append(.init(id: "overlap:" + key, kind: .overlap, events: first.members + second.members,
                    explanation: "‘\(first.primary.title)’ e ‘\(second.primary.title)’ si sovrappongono considerando le attività, i viaggi collegati e i tempi confermati. Ricontrolla le stime prima di scegliere nuovi orari.",
                    prompt: "Aiutami a riorganizzare ‘\(first.primary.title)’ e ‘\(second.primary.title)’, mantenendo durate e viaggi collegati. Mostrami prima le alternative."))
            }
        }
        // Stable priority: unverifiable groups/routes before conflicts, then ID.
        signals.sort {
            func priority(_ kind: Signal.Kind) -> Int { switch kind { case .linkedReview: return 0; case .unconfirmedTravel: return 1; case .overlap: return 2 } }
            let a = priority($0.kind), b = priority($1.kind)
            return a == b ? $0.id < $1.id : a < b
        }
        return .init(signals: Array(signals.prefix(3)), totalCount: signals.count,
            reviewedGroups: groups.count, coverage: limited ? .limited : .observedToday)
    }
    static func isCurrent(_ signal: Signal, events: [CalendarItem], data: AppData, now: Date, calendarAccess: Bool) -> Bool {
        report(events: events, data: data, now: now, calendarAccess: calendarAccess).signals.contains {
            $0.id == signal.id && $0.events == signal.events && $0.explanation == signal.explanation
        }
    }
}
