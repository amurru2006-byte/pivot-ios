import Foundation

/// Bounded on-device search for an ordered group of at most three activities.
/// The model supplies constraints only; it never supplies these times. Old
/// slots of not-yet-placed activities remain busy conservatively. No claim of
/// exhaustive infeasibility, guessed routes, compressed durations or rest days.
enum CoachPlanningAlternatives {
    enum Failure: LocalizedError, Equatable {
        case preparation, logistics, changed, invalid
        var errorDescription: String? {
            switch self {
            case .preparation: return "Conferma prima che le durate comprendano cambio e preparazione."
            case .logistics: return "Controlla flessibilità e tragitti delle attività. I viaggi collegati richiedono una revisione dedicata: non sposto soltanto metà della coppia."
            case .changed: return "Il piano o l’agenda è cambiato. Cerca nuovamente le alternative."
            case .invalid: return "Questa alternativa non rispetta il piano. Nessuna modifica applicata."
            }
        }
    }

    static func options(for session: CoachPlanningSession, calendarAccess: Bool, events: [CalendarItem],
                        data: AppData, now: Date, preparationIncluded: Bool) throws -> [CoachOption] {
        guard preparationIncluded else { throw Failure.preparation }
        let selected = try CoachPlanningSelection.restore(session, calendarAccess: calendarAccess, events: events, data: data, now: now)
        guard selected.unconfirmedTravelIDs.isEmpty, selected.pairedReviewIDs.isEmpty else { throw Failure.logistics }
        let budgets = try selected.sources.map { try budget(for: $0, data: data) }
        guard !selected.allowedIntervals.isEmpty else { return [] }
        var result: [CoachOption] = []
        // At most 1 + 3 + 9 search nodes and three complete alternatives.
        // Each later activity starts after the previous full occupied envelope.
        func visit(_ index: Int, _ simulated: AppData, _ earliest: Date, _ moves: [PlanMove]) {
            guard result.count < 3 else { return }
            if index == selected.sources.count {
                let option = CoachOption(title: "Alternativa \(result.count + 1)",
                    explanation: moves.map { "\($0.source.title) · \(PivotDate.shortDate($0.proposedStart)) \(PivotDate.time($0.proposedStart))–\(PivotDate.time($0.proposedEnd))" }.joined(separator: "\n"),
                    consequences: "Durate integrali, nell’ordine mostrato. Cambio e preparazione già inclusi; andata e ritorno da ricontrollare per ogni orario. Nessun altro impegno spostato e nessuna pausa obbligatoria aggiunta.",
                    moves: moves, createdAt: now)
                if CoachPlanner.validate(option, events: events, data: data, now: now) == nil { result.append(option) }
                return
            }
            let source = selected.sources[index]
            let windows = CalendarRecoveryWindows.find(target: source, budget: budgets[index], events: events,
                data: simulated, now: earliest, days: 7, within: selected.allowedIntervals)
            for window in windows {
                let move = PlanMove(source: source, proposedStart: window.activityStart,
                    proposedEnd: window.activityStart.addingTimeInterval(source.end.timeIntervalSince(source.start)))
                var next = simulated; next.moves.append(move)
                visit(index + 1, next, window.occupiedEnd, moves + [move])
                if result.count == 3 { break }
            }
        }
        visit(0, data, now.addingTimeInterval(300), [])
        return result
    }

    /// Stages locally and atomically. Native Calendar writes remain behind the
    /// existing final review; this method cannot invoke EventKit or a provider.
    static func stage(_ option: CoachOption, session: CoachPlanningSession, calendarAccess: Bool,
                      events: [CalendarItem], data: inout AppData, now: Date,
                      preparationIncluded: Bool, routesReviewed: Bool) throws {
        guard preparationIncluded else { throw Failure.preparation }
        guard routesReviewed, option.createdAt <= now, now.timeIntervalSince(option.createdAt) <= 120 else { throw Failure.changed }
        let selected = try CoachPlanningSelection.restore(session, calendarAccess: calendarAccess, events: events, data: data, now: now)
        guard selected.unconfirmedTravelIDs.isEmpty, selected.pairedReviewIDs.isEmpty else { throw Failure.logistics }
        guard option.moves.count == selected.sources.count else { throw Failure.invalid }
        var occupiedEnd: Date?
        for (source, move) in zip(selected.sources, option.moves) {
            guard move.source == source, abs(move.proposedEnd.timeIntervalSince(move.proposedStart) - source.end.timeIntervalSince(source.start)) < 0.001 else { throw Failure.invalid }
            let value = try budget(for: source, data: data)
            let start = move.proposedStart.addingTimeInterval(-Double(value.beforeMinutes) * 60)
            let end = move.proposedStart.addingTimeInterval(Double(value.activityMinutes + value.afterMinutes) * 60)
            guard occupiedEnd.map({ start >= $0 }) ?? true,
                  selected.allowedIntervals.contains(where: { start >= $0.start && end <= $0.end }) else { throw Failure.invalid }
            occupiedEnd = end
        }
        var next = data
        guard CoachPlanner.accept(option, events: events, data: &next, now: now) == nil,
              let index = next.coachState.planningSessions?.firstIndex(where: { $0.id == session.id }) else { throw Failure.changed }
        next.coachState.planningSessions?[index].status = .staged
        if next.coachState.focusedPlanningSessionID == session.id { next.coachState.focusedPlanningSessionID = nil }
        guard CoachPlanningStore.valid(next.coachState) else { throw Failure.invalid }
        data = next
    }

    private static func budget(for source: CalendarItem, data: AppData) throws -> CalendarTimeBudget {
        let seconds = source.end.timeIntervalSince(source.start)
        guard seconds.isFinite, seconds > 0, seconds <= 86400,
              let value = CalendarTimeBudget.confirmed(activityMinutes: Int(ceil(seconds / 60)),
                rule: EventRule.effective(for: source, data: data), preparationMinutes: 0) else { throw Failure.logistics }
        return value
    }
}
