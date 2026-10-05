import Foundation

struct CoachTurnResult {
    var reply: String
    var options: [CoachOption]
    var needsActivityClarification = false
}

enum CoachPlanner {
    static func respond(message: String, events: [CalendarItem], data: AppData, now: Date, targetID: String? = nil) -> CoachTurnResult {
        let effective = Planner.plannedEvents(events, data: data)
        let selection = recoveryTarget(message: message, events: effective, data: data, now: now, targetID: targetID)
        let target: CalendarItem
        switch selection {
        case .ambiguous(let candidates):
            let choices = candidates.prefix(4).map { "‘\($0.title)’ (\(PivotDate.time($0.start)))" }.joined(separator: ", ")
            return CoachTurnResult(reply: "A quale attività ti riferisci? Potrebbe essere \(choices). Indica il titolo e l’orario, oppure scegli il pulsante dell’attività: non ne seleziono una a caso.", options: [], needsActivityClarification: true)
        case .none:
            let next = Planner.preferredEvent(effective, data: data, now: now)
            let suffix = next.map { " Il prossimo impegno utile è ‘\($0.title)’ alle \(PivotDate.time($0.start))." } ?? " Non vedo attività urgenti da recuperare in questo momento."
            return CoachTurnResult(
                reply: "Ho letto la giornata, ma non modifico nulla senza sapere quale attività vuoi recuperare o spostare." + suffix,
                options: [], needsActivityClarification: true
            )
        case .target(let item): target = item
        }

        // Leave time to read and accept, and use the real Calendar snapshot for writes.
        let canonical = EventCoalescer.unique(events, data: data)
        guard let source = canonical.first(where: { $0.id == target.id }) else {
            return CoachTurnResult(reply: "Aggiorna il Calendario: non trovo più questa attività.", options: [])
        }
        // A quick-action button supplies an occurrence ID, not a new day constraint.
        let query = targetID == nil ? EventCoalescer.normalized(message) : ""
        let words = query.split(separator: " ").map(String.init)
        let offset = words.contains("dopodomani") || query.contains("dopo domani") ? 2 : (words.contains("domani") ? 1 : 0)
        let onlyToday = words.contains("oggi")
        guard !(onlyToday && offset > 0) else {
            return CoachTurnResult(reply: "Vuoi recuperare l’attività oggi oppure \(offset == 1 ? "domani" : "dopodomani")? Chiariscilo prima di preparare gli orari.", options: [])
        }
        let roundedNow = Date(timeIntervalSince1970: ceil(now.addingTimeInterval(5 * 60).timeIntervalSince1970 / 300) * 300)
        guard !onlyToday || PivotDate.calendar.isDate(roundedNow, inSameDayAs: now) else {
            return CoachTurnResult(reply: "Non rimane uno spazio utile oggi. Non sposto l’attività a domani senza una nuova richiesta.", options: [])
        }
        let earliest: Date
        if offset > 0, let requestedDay = PivotDate.calendar.date(byAdding: .day, value: offset, to: PivotDate.calendar.startOfDay(for: now)) {
            earliest = requestedDay
        } else { earliest = roundedNow }
        let days = onlyToday || offset > 0 ? 1 : 3
        let suggestions = Planner.recover(target, events: events, data: data, now: earliest, days: days)
        guard !suggestions.isEmpty else {
            let alternatives = compressionOptions(target: target, events: events, data: data, now: earliest, days: days)
            if !alternatives.isEmpty {
                return CoachTurnResult(reply: "Uno spazio completo manca. Posso accorciare solo le attività per cui hai già indicato una durata minima. Controlla tutte le conseguenze prima di accettare.", options: alternatives)
            }
            let rule = data.rules[target.id] ?? .defaultRule(for: target)
            let reason: String
            if rule.flexibility == .fixed { reason = "è segnato come fisso" }
            else if !rule.travelConfirmed { reason = "mancano i tempi di tragitto confermati" }
            else { reason = days == 1 ? "non esiste uno spazio completo e senza conflitti nel giorno richiesto" : "non esiste uno spazio completo e senza conflitti nei prossimi tre giorni" }
            return CoachTurnResult(reply: "Non ti propongo uno spostamento rischioso: ‘\(target.title)’ \(reason). Apri l’attività per correggere flessibilità o tragitto, oppure dimmi esplicitamente cosa sei disposto ad accorciare.", options: [])
        }

        let options = suggestions.prefix(2).enumerated().map { index, suggestion in
            let move = PlanMove(source: source, proposedStart: suggestion.start, proposedEnd: suggestion.end)
            return CoachOption(
                title: index == 0 ? "Prima soluzione sicura" : "Alternativa sicura",
                explanation: "Sposta ‘\(target.title)’ a \(PivotDate.shortDate(suggestion.start)) dalle \(PivotDate.time(suggestion.start)) alle \(PivotDate.time(suggestion.end)).",
                consequences: suggestion.explanation,
                moves: [move]
            )
        }
        return CoachTurnResult(
            reply: "Ho trovato \(options.count == 1 ? "una soluzione" : "due soluzioni") senza toccare gli impegni fissi e senza inventare tempi di viaggio. Scegli tu: l’accettazione modifica prima soltanto Pivot; il Calendario resta invariato finché non dai una seconda conferma.",
            options: options
        )
    }

    private static func compressionOptions(target: CalendarItem, events: [CalendarItem], data: AppData, now: Date, days: Int) -> [CoachOption] {
        let canonical = EventCoalescer.unique(events, data: data)
        guard let source = canonical.first(where: { $0.id == target.id }) else { return [] }
        var options: [CoachOption] = []
        for item in canonical where item.id != target.id && item.start > now && !item.isAllDay {
            // Only explicit minimums, never assume default rules authorize shrinking someone else's event.
            guard let rule = data.rules[item.id], rule.flexibility == .compressible, rule.compressionApproved == true, rule.travelConfirmed,
                  rule.minimumMinutes > 0, rule.minimumMinutes < item.durationMinutes,
                  EventContext.priority(item, data: data, now: now) != .essential,
                  EventContext.priority(item, data: data, now: now).rawValue <= EventContext.priority(target, data: data, now: now).rawValue,
                  !data.moves.contains(where: { !$0.syncedToCalendar && $0.source.id == item.id }) else { continue }
            let shortened = PlanMove(source: item, proposedStart: item.start, proposedEnd: item.start.addingTimeInterval(Double(rule.minimumMinutes) * 60))
            var simulated = data; simulated.moves.append(shortened)
            guard let recovery = Planner.recover(target, events: events, data: simulated, now: now, days: days).first else { continue }
            let move = PlanMove(source: source, proposedStart: recovery.start, proposedEnd: recovery.end)
            let option = CoachOption(title: "Recupero con una riduzione", explanation: "\(item.title): da \(item.durationMinutes) a \(rule.minimumMinutes) min. \(target.title): \(PivotDate.shortDate(move.proposedStart)) \(PivotDate.time(move.proposedStart))–\(PivotDate.time(move.proposedEnd)).",
                                     consequences: "Entrambe le modifiche sono visibili e richiedono conferma. " + recovery.explanation, moves: [shortened, move])
            if validate(option, events: events, data: data, now: now) == nil { options.append(option) }
            if options.count == 2 { break }
        }
        return options
    }

    static func validate(_ option: CoachOption, events: [CalendarItem], data: AppData, now: Date) -> String? {
        guard !option.moves.isEmpty, Set(option.moves.map { $0.source.id }).count == option.moves.count else { return "La proposta non contiene modifiche valide." }
        let canonical = EventCoalescer.unique(events, data: data)
        var simulated = data
        for move in option.moves {
            guard move.proposedStart > now, move.proposedEnd > move.proposedStart else { return "Uno degli orari proposti non è più valido." }
            guard let current = canonical.first(where: { $0.id == move.source.id }),
                  matchesSnapshot(move.source, current) else {
                return "Il Calendario è cambiato dopo la proposta. Aggiorna e chiedi una nuova soluzione."
            }
            let rule = simulated.rules[current.id] ?? .defaultRule(for: current)
            guard !current.isAllDay, rule.flexibility != .fixed, rule.travelConfirmed,
                  rule.travelBeforeMinutes >= 0, rule.travelAfterMinutes >= 0 else { return "‘\(current.title)’ non è spostabile oppure ha il tragitto da confermare." }
            let duration = move.proposedEnd.timeIntervalSince(move.proposedStart)
            let originalDuration = current.end.timeIntervalSince(current.start)
            guard duration >= originalDuration - 1 || (rule.flexibility == .compressible && rule.compressionApproved == true) else {
                return "La riduzione di questa attività non è stata autorizzata."
            }
            guard duration >= Double(max(1, rule.minimumMinutes)) * 60,
                  rule.flexibility == .compressible || abs(duration - originalDuration) < 1 else {
                return "La proposta riduce una durata non autorizzata."
            }
            guard PivotDate.calendar.isDate(move.proposedStart, inSameDayAs: move.proposedEnd),
                  let dayStart = PivotDate.calendar.date(bySettingHour: data.settings.quietEndHour, minute: 0, second: 0, of: move.proposedStart),
                  let dayEnd = PivotDate.calendar.date(bySettingHour: data.settings.quietStartHour, minute: 0, second: 0, of: move.proposedStart),
                  move.proposedStart.addingTimeInterval(-Double(rule.travelBeforeMinutes) * 60) >= max(now, dayStart),
                  move.proposedEnd.addingTimeInterval(Double(rule.travelAfterMinutes) * 60) <= dayEnd else {
                return "La proposta non rispetta sonno o tragitti."
            }
            let candidate = PlanMove(source: current, proposedStart: move.proposedStart, proposedEnd: move.proposedEnd)
            guard slotIsFree(candidate, events: events, data: simulated) else { return "Lo spazio proposto non è più libero." }
            simulated.moves.removeAll { !$0.syncedToCalendar && $0.source.id == current.id }
            simulated.moves.append(candidate)
        }
        let resulting = Planner.plannedEvents(events, data: simulated)
        var affectedDays: [String: Date] = [:]
        for move in option.moves {
            affectedDays[PivotDate.key(move.proposedStart)] = move.proposedStart
            affectedDays[PivotDate.key(move.proposedEnd)] = move.proposedEnd
        }
        for date in affectedDays.values {
            let affected = Set(option.moves.map { $0.source.id })
            guard !Planner.overlapsInPlannedEvents(on: date, events: resulting, data: simulated).contains(where: { affected.contains($0.0.id) || affected.contains($0.1.id) }) else {
                return "La proposta creerebbe una sovrapposizione e quindi è stata bloccata."
            }
        }
        return nil
    }

    static func matchesSnapshot(_ original: CalendarItem, _ current: CalendarItem) -> Bool {
        original.calendarIdentifier == current.calendarIdentifier && original.eventIdentifier == current.eventIdentifier
            && matchesPlanSnapshot(original, current)
            && modificationDateMatches(original.calendarModifiedAt, current.calendarModifiedAt)
    }

    // Imported copies may use different calendar IDs; writes still require strict IDs above.
    static func matchesPlanSnapshot(_ original: CalendarItem, _ current: CalendarItem) -> Bool {
        EventCoalescer.savedOccurrence(original, current)
            && abs(original.start.timeIntervalSince(current.start)) < 1 && abs(original.end.timeIntervalSince(current.end)) < 1 && original.title == current.title
            && original.location == current.location && original.notes == current.notes
            && original.isAllDay == current.isAllDay
    }

    static func modificationDateMatches(_ original: Date?, _ current: Date?) -> Bool {
        switch (original, current) {
        case (.none, .none): return true
        case (.some(let a), .some(let b)): return abs(a.timeIntervalSince(b)) < 1
        default: return false
        }
    }

    static func accept(_ option: CoachOption, events: [CalendarItem], data: inout AppData, now: Date) -> String? {
        if let error = validate(option, events: events, data: data, now: now) { return error }
        for move in option.moves {
            data.moves.removeAll { !$0.syncedToCalendar && $0.source.id == move.source.id }
            data.moves.append(move)
            var state = data.coachState
            state.pendingCalendarChanges.removeAll { $0.move.source.id == move.source.id }
            state.pendingCalendarChanges.append(PendingCalendarChange(move: move, optionTitle: option.title))
            data.coachState = state
            if var record = data.records[move.source.id], record.status == .skipped {
                record.status = .pending
                record.updatedAt = now
                data.records[move.source.id] = record
            }
        }
        var state = data.coachState
        // Alternatives for the same event become stale after accepting one option.
        let movedIDs = Set(option.moves.map { $0.source.id })
        state.options.removeAll { $0.moves.contains { movedIDs.contains($0.source.id) } }
        state.messages.append(.init(dayKey: PivotDate.key(now), role: .system, text: "Accettata in Pivot: \(option.title). In attesa della conferma finale per il Calendario."))
        data.coachState = state
        return nil
    }

    private enum TargetSelection {
        case none, target(CalendarItem), ambiguous([CalendarItem])
    }

    private static func recoveryTarget(message: String, events: [CalendarItem], data: AppData, now: Date, targetID: String?) -> TargetSelection {
        let query = EventCoalescer.normalized(message)
        let candidates = events.filter { item in
            guard !item.isAllDay, item.occurs(on: now) else { return false }
            let status = data.records[item.id]?.status ?? .pending
            return status == .skipped || (status == .pending && item.end <= now)
        }
        if let targetID {
            if let target = candidates.first(where: { $0.id == targetID }) { return .target(target) }
            return .none
        }
        let queryWords = Set(query.split(separator: " ").map(String.init))
        // Match whole words, not e.g. "pers" in "personale" or "des" in "destinazione".
        let verbs = ["recuper", "spost", "salt", "rimand", "riprogramm"]
        let intent = queryWords.contains { word in verbs.contains { word.hasPrefix($0) } }
            || queryWords.contains("ritardo") || queryWords.contains("perso") || queryWords.contains("persa") || query.contains("non ho fatto")
        let deniesRecovery = ["non voglio", "non devo", "non posso", "non serve", "non spostare", "non recuperare", "senza spostare", "senza recuperare", "non ho saltato", "non ho perso"].contains { query.contains($0) }
        guard intent && !deniesRecovery else { return .none }
        let stopWords: Set<String> = ["con", "per", "del", "dei", "della", "delle", "alla", "alle", "dalle", "una", "uno", "gli", "che", "oggi", "domani", "prova"]
        let scored = candidates.map { item -> (CalendarItem, Int) in
            let title = EventCoalescer.normalized(item.title)
            let titleWords = Set(title.split(separator: " ").map(String.init).filter { $0.count > 2 && !stopWords.contains($0) })
            let hits = titleWords.intersection(queryWords).count
            let kindWords = Set(EventCoalescer.normalized(item.kind.label).split(separator: " ").map(String.init).filter { $0.count > 2 })
            let kindHit = kindWords.intersection(queryWords).isEmpty ? 0 : 2
            let timeHit = message.contains(PivotDate.time(item.start)) ? 10 : 0
            let exact = !title.isEmpty && (" " + query + " ").contains(" " + title + " ") ? 20 : 0
            return (item, hits + kindHit + timeHit + exact)
        }.sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0.end > rhs.0.end : lhs.1 > rhs.1 }
        if let best = scored.first, best.1 > 0 {
            let tied = scored.filter { $0.1 == best.1 }.map { $0.0 }
            return tied.count == 1 ? .target(best.0) : .ambiguous(tied)
        }
        return candidates.isEmpty ? .none : .ambiguous(candidates)
    }

    private static func slotIsFree(_ move: PlanMove, events: [CalendarItem], data: AppData) -> Bool {
        let rule = data.rules[move.source.id] ?? .defaultRule(for: move.source)
        let start = move.proposedStart.addingTimeInterval(-Double(rule.travelBeforeMinutes) * 60)
        let end = move.proposedEnd.addingTimeInterval(Double(rule.travelAfterMinutes) * 60)
        return !Planner.plannedEvents(events, data: data).contains { item in
            guard item.id != move.source.id, !item.isAllDay else { return false }
            let other = data.rules[item.id] ?? .defaultRule(for: item)
            if !item.location.isEmpty && !other.travelConfirmed && item.occurs(on: move.proposedStart) { return true }
            return item.start.addingTimeInterval(-Double(other.travelBeforeMinutes) * 60) < end
                && item.end.addingTimeInterval(Double(other.travelAfterMinutes) * 60) > start
        }
    }
}

extension AppData {
    var coachState: CoachState {
        get { coach ?? CoachState() }
        set { coach = newValue }
    }
}
