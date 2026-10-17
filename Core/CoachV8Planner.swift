import Foundation

enum CoachV8Planner {
    // No mutation: the result must still pass the existing accept/calendar confirmations.
    static func preview(_ response: CoachV8Response, snapshot: CoachV8Snapshot,
                        events: [CalendarItem], data: AppData, now: Date) throws -> CoachTurnResult {
        guard snapshot.isCurrent(events: events, data: data, now: now) else { throw CoachV8Error.staleContext }
        // Validate even typed responses, not only network JSON.
        guard response.version == snapshot.request.version, response.requestID == snapshot.request.requestID,
              response.reply.count <= 1000, !response.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(response.eventIDs).count == response.eventIDs.count,
              (response.mode == .plan ? (1...2).contains(response.eventIDs.count) : response.eventIDs.isEmpty) else {
            throw CoachV8Error.invalidResponse
        }
        guard response.mode == .plan else {
            return .init(reply: userFacingReply(response.reply, request: snapshot.request), options: [], needsActivityClarification: response.mode == .clarify)
        }
        var simulated = data
        var moves: [PlanMove] = []
        var explanations: [String] = []
        var consequences: [String] = []
        var earliest = Date(timeIntervalSince1970: ceil(now.addingTimeInterval(5 * 60).timeIntervalSince1970 / 300) * 300)
        for alias in response.eventIDs {
            guard let summary = snapshot.request.events.first(where: { $0.id == alias }),
                  summary.category != .other, let source = snapshot.sources[alias],
                  ![Completion.running, .completed, .partial].contains(data.records[source.id]?.status ?? .pending) else {
                throw CoachV8Error.invalidResponse
            }
            // A model cannot resolve indistinguishable occurrences by picking an ID.
            let eligible = snapshot.request.events.filter {
                $0.category == summary.category && ![Completion.running, .completed, .partial].contains($0.status)
            }
            guard eligible.count == 1 else {
                return .init(reply: "Ci sono più attività di questo tipo oggi. Indica quale vuoi organizzare; non scelgo una ricorrenza al posto tuo.", options: [], needsActivityClarification: true)
            }
            if data.moves.contains(where: { !$0.syncedToCalendar && $0.source.id == source.id }) {
                return .init(reply: "C'è già una proposta per ‘\(source.title)’. Confermala o scartala prima di prepararne un'altra.", options: [])
            }
            let rule = EventRule.effective(for: source, data: data)
            guard rule.flexibility != .fixed, rule.travelConfirmed else {
                return .init(reply: "Prima di organizzare ‘\(source.title)’, conferma che sia spostabile e indica i tempi di tragitto nei dettagli dell'attività.", options: [], needsActivityClarification: true)
            }
            guard PivotDate.key(earliest) == snapshot.request.dayKey else {
                return .init(reply: "Oggi non resta uno spazio completo per questa sequenza. Non preparo spostamenti a domani.", options: [])
            }
            // First block preserves full durations even when compression was approved elsewhere.
            var fullDurationRule = rule
            fullDurationRule.flexibility = .movable
            fullDurationRule.minimumMinutes = source.durationMinutes
            simulated.rules[source.id] = fullDurationRule
            let suggestion = Planner.recover(source, events: events, data: simulated, now: earliest, days: 1).first
            simulated.rules[source.id] = rule
            guard let suggestion, suggestion.end.timeIntervalSince(suggestion.start) == source.end.timeIntervalSince(source.start) else {
                return .init(reply: "Non trovo uno spazio completo per ‘\(source.title)’ nell'ordine richiesto. Controlla gli impegni e i tragitti: nessuna durata è stata ridotta.", options: [])
            }
            let move = PlanMove(source: source, proposedStart: suggestion.start, proposedEnd: suggestion.end)
            moves.append(move)
            simulated.moves.append(move)
            explanations.append("\(source.title): \(PivotDate.time(move.proposedStart))–\(PivotDate.time(move.proposedEnd)).")
            consequences.append(suggestion.explanation)
            earliest = suggestion.end.addingTimeInterval(Double(rule.travelAfterMinutes) * 60)
        }
        let option = CoachOption(title: "Sequenza proposta per oggi", explanation: explanations.joined(separator: " "),
                                 consequences: consequences.joined(separator: " "), moves: moves)
        if let problem = CoachPlanner.validate(option, events: events, data: data, now: now) {
            return .init(reply: problem, options: [])
        }
        // Hours and claims about actions in model prose cannot override the verified plan.
        return .init(reply: "Ho preparato questa sequenza con le durate e gli impegni della tua giornata. Controlla orari e conseguenze prima di applicarla.", options: [option])
    }

    // Replace internal aliases using only metadata already in the request. Free
    // calendar titles never enter the chat/history sent back to the provider.
    private static func userFacingReply(_ text: String, request: CoachV8Request) -> String {
        let fallback = "Quale attività intendi? Indica il suo nome nel Calendario: non scelgo un evento al posto tuo."
        guard let pattern = try? NSRegularExpression(pattern: #"\be[0-9]{1,2}\b"#) else { return fallback }
        var result = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result),
                  let event = request.events.first(where: { $0.id == String(result[range]) }) else { return fallback }
            let label: String
            switch event.category {
            case .gym: label = "la palestra prevista"
            case .lunch: label = "il pranzo previsto"
            case .other: label = "l'attività prevista"
            }
            result.replaceSubrange(range, with: label + " alle " + PivotDate.time(event.start))
        }
        return result.count <= 1000 ? result : fallback
    }
}
