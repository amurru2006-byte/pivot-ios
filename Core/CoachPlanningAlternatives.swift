import Foundation

/// Bounded on-device search for an ordered group of at most three activities.
/// The model supplies constraints only; it never supplies these times. Old
/// slots of not-yet-placed activities remain busy conservatively. No claim of
/// exhaustive infeasibility, guessed routes, compressed durations or rest days.
enum CoachPlanningAlternatives {
    enum SearchState: Equatable { case optionsFound, notFoundWithinSearch, limitReached, cancelled }
    struct SearchResult {
        var options: [CoachOption]
        var state: SearchState
        var exploredNodes: Int
    }
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
        try search(for: session, calendarAccess: calendarAccess, events: events, data: data,
                   now: now, preparationIncluded: preparationIncluded).options
    }

    static func search(for session: CoachPlanningSession, calendarAccess: Bool, events: [CalendarItem],
                       data: AppData, now: Date, preparationIncluded: Bool, maxNodes: Int = 64,
                       fixedMoves: [PlanMove] = [], restrictedDays: [String: Date] = [:],
                       isCancelled: () -> Bool = { false }) throws -> SearchResult {
        guard (1...512).contains(maxNodes) else { throw Failure.invalid }
        guard preparationIncluded else { throw Failure.preparation }
        let selected = try CoachPlanningSelection.restore(session, calendarAccess: calendarAccess, events: events, data: data, now: now)
        guard selected.unconfirmedTravelIDs.isEmpty, selected.pairedReviewIDs.isEmpty else { throw Failure.logistics }
        let budgets = try selected.sources.map { try budget(for: $0, data: data) }
        var effectiveFixed = fixedMoves
        var effectiveDays = restrictedDays
        for pin in session.localPins ?? [] {
            guard let source = selected.sources.first(where: { $0.id == pin.sourceID }), pin.isValid(for: source),
                  session.allowedDays.contains(pin.day), !session.excludedDays.contains(pin.day),
                  !session.protectedExcludedDays.contains(pin.day),
                  effectiveDays[pin.sourceID].map({ $0 == pin.day }) ?? true else { throw CoachPlanningRefinement.Failure.savedChoice }
            effectiveDays[pin.sourceID] = pin.day
            if let start = pin.start {
                guard start > now else { throw CoachPlanningRefinement.Failure.savedChoice }
                let move = PlanMove(source: source, proposedStart: start,
                    proposedEnd: start.addingTimeInterval(source.end.timeIntervalSince(source.start)))
                if let existing = effectiveFixed.first(where: { $0.source.id == pin.sourceID }) {
                    guard existing.proposedStart == move.proposedStart, existing.proposedEnd == move.proposedEnd else { throw CoachPlanningRefinement.Failure.savedChoice }
                } else { effectiveFixed.append(move) }
            }
        }
        let sourceIDs = Set(selected.sources.map(\.id))
        guard effectiveFixed.count <= selected.sources.count,
              Set(effectiveFixed.map { $0.source.id }).count == effectiveFixed.count,
              Set(effectiveFixed.map { $0.source.id }).isSubset(of: sourceIDs),
              Set(effectiveDays.keys).isSubset(of: sourceIDs),
              effectiveDays.values.allSatisfy({ CoachPlanningSession.validDate($0) && PivotDate.calendar.startOfDay(for: $0) == $0 }) else { throw Failure.invalid }
        for move in effectiveFixed {
            guard selected.sources.contains(move.source), move.proposedStart > now,
                  abs(move.proposedEnd.timeIntervalSince(move.proposedStart) - move.source.end.timeIntervalSince(move.source.start)) < 0.001 else { throw Failure.changed }
        }
        guard !selected.allowedIntervals.isEmpty else {
            return .init(options: [], state: isCancelled() ? .cancelled : .notFoundWithinSearch, exploredNodes: 0)
        }
        var result: [CoachOption] = []
        var explored = 0, exhausted = false, cancelled = false
        // Bound the entire tree, not only each activity's first three slots.
        // Keep existing original slots busy conservatively; this is not a proof
        // that no other possible schedule exists when no candidate is found.
        // Each later activity starts after the previous full occupied envelope.
        func visit(_ index: Int, _ simulated: AppData, _ earliest: Date, _ moves: [PlanMove]) {
            if isCancelled() { cancelled = true; return }
            guard result.count < 3 else { return }
            guard explored < maxNodes else { exhausted = true; return }
            explored += 1
            if index == selected.sources.count {
                let option = CoachOption(title: "Alternativa \(result.count + 1)",
                    explanation: moves.map { "\($0.source.title) · \(PivotDate.shortDate($0.proposedStart)) \(PivotDate.time($0.proposedStart))–\(PivotDate.time($0.proposedEnd))" }.joined(separator: "\n"),
                    consequences: "Durate integrali, nell’ordine mostrato. Cambio e preparazione già inclusi; andata e ritorno da ricontrollare per ogni orario. Nessun altro impegno spostato e nessuna pausa obbligatoria aggiunta.",
                    moves: moves, createdAt: now)
                if CoachPlanner.validate(option, events: events, data: data, now: now) == nil { result.append(option) }
                return
            }
            let source = selected.sources[index]
            let intervals = selected.allowedIntervals.filter { interval in
                effectiveDays[source.id].map { PivotDate.calendar.isDate(interval.start, inSameDayAs: $0) } ?? true
            }
            let windows: [CalendarRecoveryWindow]
            if let fixed = effectiveFixed.first(where: { $0.source.id == source.id }) {
                let occupiedStart = fixed.proposedStart.addingTimeInterval(-Double(budgets[index].beforeMinutes) * 60)
                let occupiedEnd = fixed.proposedStart.addingTimeInterval(Double(budgets[index].activityMinutes + budgets[index].afterMinutes) * 60)
                guard occupiedStart >= earliest,
                      intervals.contains(where: { occupiedStart >= $0.start && occupiedEnd <= $0.end }) else { return }
                windows = [.init(occupiedStart: occupiedStart, activityStart: fixed.proposedStart,
                                 activityEnd: fixed.proposedEnd, occupiedEnd: occupiedEnd)]
            } else {
                windows = CalendarRecoveryWindows.find(target: source, budget: budgets[index], events: events,
                    data: simulated, now: earliest, days: 7, within: intervals, limit: 32)
            }
            for window in windows {
                if isCancelled() { cancelled = true; return }
                let move = PlanMove(source: source, proposedStart: window.activityStart,
                    proposedEnd: window.activityStart.addingTimeInterval(source.end.timeIntervalSince(source.start)))
                var next = simulated; next.moves.append(move)
                visit(index + 1, next, window.occupiedEnd, moves + [move])
                if result.count == 3 || exhausted || cancelled { break }
            }
        }
        visit(0, data, now.addingTimeInterval(300), [])
        if cancelled { return .init(options: [], state: .cancelled, exploredNodes: explored) }
        return .init(options: result, state: exhausted ? .limitReached : (result.isEmpty ? .notFoundWithinSearch : .optionsFound), exploredNodes: explored)
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
        guard option.moves.count == selected.sources.count, matchesPins(option, session: session) else { throw Failure.invalid }
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

    static func matchesPins(_ option: CoachOption, session: CoachPlanningSession) -> Bool {
        (session.localPins ?? []).allSatisfy { pin in
            guard let move = option.moves.first(where: { $0.source.id == pin.sourceID }) else { return false }
            return PivotDate.calendar.isDate(move.proposedStart, inSameDayAs: pin.day)
                && (pin.start.map { $0 == move.proposedStart } ?? true)
        }
    }
    private static func budget(for source: CalendarItem, data: AppData) throws -> CalendarTimeBudget {
        let seconds = source.end.timeIntervalSince(source.start)
        guard seconds.isFinite, seconds > 0, seconds <= 86400,
              let value = CalendarTimeBudget.confirmed(activityMinutes: Int(ceil(seconds / 60)),
                rule: EventRule.effective(for: source, data: data), preparationMinutes: 0) else { throw Failure.logistics }
        return value
    }
}
