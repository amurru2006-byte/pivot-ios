import Foundation

/// Remembered LOCAL choices, never Calendar moves or provider DTOs.
/// nil start fixes only a civil day. A start fixes the full original duration.
struct CoachPlanningPin: Codable, Equatable {
    var sourceID: String
    var day: Date
    var start: Date?
    func isValid(for source: CalendarItem) -> Bool {
        guard sourceID == source.id, CoachPlanningSession.validDate(day),
              day == PivotDate.calendar.startOfDay(for: day) else { return false }
        guard let start else { return true }
        let end = start.addingTimeInterval(source.end.timeIntervalSince(source.start))
        return CoachPlanningSession.validDate(start) && CoachPlanningSession.validDate(end)
            && start >= day && end > start && PivotDate.calendar.isDate(start, inSameDayAs: day)
            && PivotDate.calendar.isDate(end, inSameDayAs: day)
    }
}

/// Explicit local corrections. Unrecognized prose is a clarification, never a
/// guessed edit. Titles are resolved locally by exact normalized equality.
enum CoachPlanningRefinement {
    enum Failure: LocalizedError {
        case clarify, excludedDay, stale, noAlternative, savedChoice
        var errorDescription: String? {
            switch self {
            case .clarify: return "Indica una sola attività e il giorno, per esempio ‘sposta il secondo a venerdì alle 16:30’. Puoi usare anche il nome esatto. Le altre restano agli orari mostrati."
            case .excludedDay: return "Quel giorno non è tra quelli consentiti nel piano. Modifica prima i giorni nella chat: non tolgo un’esclusione in silenzio."
            case .stale: return "Questa alternativa è scaduta o l’agenda è cambiata. Cerca nuovamente prima di correggerla."
            case .noAlternative: return "Non ho trovato una correzione verificata mantenendo ferme le altre attività. Nessun vincolo è stato cambiato."
            case .savedChoice: return "Una scelta salvata non è compatibile con i giorni, gli orari o l’agenda attuali. Controlla le scelte nel piano: non le cambio automaticamente."
            }
        }
    }
    struct Request: Equatable {
        var index: Int
        var weekday: Int
        var minute: Int? = nil
    }
    struct Revision { var option: CoachOption; var session: CoachPlanningSession }
    static func parse(_ text: String, count: Int) throws -> Request {
        try parse(text, titles: Array(repeating: "", count: max(0, min(count, 4))))
    }
    static func parse(_ text: String, sources: [CalendarItem]) throws -> Request {
        try parse(text, titles: sources.map(\.title))
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static let ordinals = ["primo": 0, "prima": 0, "secondo": 1, "seconda": 1, "terzo": 2, "terza": 2]
    private static func parse(_ text: String, titles: [String]) throws -> Request {
        guard (1...3).contains(titles.count), text.utf8.count <= 500 else { throw Failure.clarify }
        let clean = normalized(text).trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        let pattern = #"^(?:sposta |metti |)(.+?) (?:a |al |meglio )(lunedi|martedi|mercoledi|giovedi|venerdi|sabato|domenica)(?: alle ([0-9]{1,2})(?::([0-9]{2}))?)?(?:, lascia ferm[oa] (?:il|la) (primo|prima|secondo|seconda|terzo|terza))?$"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..<clean.endIndex, in: clean)) else { throw Failure.clarify }
        func part(_ index: Int) -> String? { Range(match.range(at: index), in: clean).map { String(clean[$0]) } }
        guard let rawTarget = part(1), let day = part(2) else { throw Failure.clarify }
        let ordinalTarget = rawTarget.replacingOccurrences(of: #"^(?:il|la) "#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" (?:allenamento|attivita)$"#, with: "", options: .regularExpression)
        let ordinal = ordinals[ordinalTarget]
        let titleMatches = titles.indices.filter { !titles[$0].isEmpty && normalized(titles[$0]) == rawTarget }
        let index: Int
        if let ordinal {
            guard ordinal < titles.count, titleMatches.isEmpty || titleMatches == [ordinal] else { throw Failure.clarify }
            index = ordinal
        } else {
            guard titleMatches.count == 1, let matched = titleMatches.first else { throw Failure.clarify }
            index = matched
        }
        if let held = part(5) {
            guard let other = ordinals[held], other < titles.count, other != index else { throw Failure.clarify }
        }
        var minute: Int?
        if let hourText = part(3) {
            guard let hour = Int(hourText), (0...23).contains(hour), let minutes = Int(part(4) ?? "0"), (0...59).contains(minutes) else { throw Failure.clarify }
            minute = hour * 60 + minutes
        }
        guard let weekday = ["domenica":1,"lunedi":2,"martedi":3,"mercoledi":4,"giovedi":5,"venerdi":6,"sabato":7][day] else { throw Failure.clarify }
        return .init(index: index, weekday: weekday, minute: minute)
    }

    static func apply(_ request: Request, to option: CoachOption, session: CoachPlanningSession,
                      events: [CalendarItem], data: AppData, calendarAccess: Bool, now: Date,
                      isCancelled: () -> Bool = { false }) throws -> CoachOption {
        try revise(request, option: option, session: session, events: events, data: data,
                   calendarAccess: calendarAccess, now: now, isCancelled: isCancelled).option
    }

    /// Compute a copy. Caller rechecks data/calendar snapshots before saving.
    static func revise(_ request: Request, option: CoachOption, session: CoachPlanningSession,
                       events: [CalendarItem], data: AppData, calendarAccess: Bool, now: Date,
                       isCancelled: () -> Bool = { false }) throws -> Revision {
        guard option.moves.count == session.intent.eventIDs.count, option.moves.indices.contains(request.index),
              option.createdAt <= now, now.timeIntervalSince(option.createdAt) <= 120,
              (1...7).contains(request.weekday), request.minute.map({ (0...1439).contains($0) }) ?? true else { throw Failure.stale }
        let selection = try CoachPlanningSelection.restore(session, calendarAccess: calendarAccess, events: events, data: data, now: now)
        guard zip(selection.sources, option.moves).allSatisfy({ $0.0 == $0.1.source }),
              CoachPlanningAlternatives.matchesPins(option, session: session),
              CoachPlanner.validate(option, events: events, data: data, now: now) == nil else { throw Failure.stale }
        let candidates = session.allowedDays.filter { PivotDate.calendar.component(.weekday, from: $0) == request.weekday }
        guard candidates.count == 1, let day = candidates.first,
              !session.excludedDays.contains(day), !session.protectedExcludedDays.contains(day) else { throw Failure.excludedDay }
        var next = session
        next.updatedAt = now
        next.localPins = try option.moves.enumerated().map { index, move in
            if index != request.index {
                return .init(sourceID: move.source.id, day: PivotDate.calendar.startOfDay(for: move.proposedStart), start: move.proposedStart)
            }
            var start: Date?
            if let minute = request.minute {
                let calendar = PivotDate.calendar
                let first = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day,
                    matchingPolicy: .strict, repeatedTimePolicy: .first)
                let last = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day,
                    matchingPolicy: .strict, repeatedTimePolicy: .last)
                guard let first, first == last, calendar.isDate(first, inSameDayAs: day),
                      calendar.component(.hour, from: first) == minute / 60,
                      calendar.component(.minute, from: first) == minute % 60 else { throw Failure.clarify }
                start = first
            }
            return .init(sourceID: move.source.id, day: day, start: start)
        }
        var simulated = data
        try CoachPlanningStore.save(next, in: &simulated.coachState)
        let result = try CoachPlanningAlternatives.search(for: next, calendarAccess: calendarAccess,
            events: events, data: simulated, now: now, preparationIncluded: true, isCancelled: isCancelled)
        if result.state == .cancelled { throw CancellationError() }
        guard let revised = result.options.first else { throw Failure.noAlternative }
        return .init(option: revised, session: next)
    }
}
