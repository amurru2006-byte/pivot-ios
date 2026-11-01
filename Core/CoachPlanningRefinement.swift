import Foundation

/// A deliberately narrow LOCAL correction grammar, scoped to the alternative
/// displayed by the user. Unsupported prose is a clarification, never a guessed edit.
enum CoachPlanningRefinement {
    enum Failure: LocalizedError {
        case clarify, excludedDay, stale, noAlternative
        var errorDescription: String? {
            switch self {
            case .clarify: return "Indica una sola attività e il giorno, per esempio ‘sposta il secondo a venerdì’. Le altre restano agli orari mostrati."
            case .excludedDay: return "Quel giorno non è tra quelli consentiti nel piano. Modifica prima i giorni nella chat: non tolgo un’esclusione in silenzio."
            case .stale: return "Questa alternativa è scaduta o l’agenda è cambiata. Cerca nuovamente prima di correggerla."
            case .noAlternative: return "Non ho trovato una correzione verificata mantenendo ferme le altre attività. Nessun vincolo è stato cambiato."
            }
        }
    }
    struct Request: Equatable { var index: Int; var weekday: Int }
    static func parse(_ text: String, count: Int) throws -> Request {
        guard (1...3).contains(count), text.utf8.count <= 500 else { throw Failure.clarify }
        let clean = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^sposta (?:il|la) (primo|prima|secondo|seconda|terzo|terza)(?: allenamento| attivita)? (?:a|al) (lunedi|martedi|mercoledi|giovedi|venerdi|sabato|domenica)$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
        guard let match = regex.firstMatch(in: clean, range: range),
              let ordinalRange = Range(match.range(at: 1), in: clean),
              let dayRange = Range(match.range(at: 2), in: clean) else { throw Failure.clarify }
        let ordinal = String(clean[ordinalRange]), day = String(clean[dayRange])
        let index = ["primo":0,"prima":0,"secondo":1,"seconda":1,"terzo":2,"terza":2][ordinal]!
        guard index < count, let weekday = ["domenica":1,"lunedi":2,"martedi":3,"mercoledi":4,"giovedi":5,"venerdi":6,"sabato":7][day] else { throw Failure.clarify }
        return .init(index: index, weekday: weekday)
    }
    static func apply(_ request: Request, to option: CoachOption, session: CoachPlanningSession,
                      events: [CalendarItem], data: AppData, calendarAccess: Bool, now: Date,
                      isCancelled: () -> Bool = { false }) throws -> CoachOption {
        guard option.moves.count == session.intent.eventIDs.count, option.moves.indices.contains(request.index),
              option.createdAt <= now, now.timeIntervalSince(option.createdAt) <= 120 else { throw Failure.stale }
        let selection = try CoachPlanningSelection.restore(session, calendarAccess: calendarAccess, events: events, data: data, now: now)
        guard zip(selection.sources, option.moves).allSatisfy({ $0.0 == $0.1.source }),
              CoachPlanner.validate(option, events: events, data: data, now: now) == nil else { throw Failure.stale }
        let candidates = session.allowedDays.filter { PivotDate.calendar.component(.weekday, from: $0) == request.weekday }
        guard candidates.count == 1, let day = candidates.first,
              !session.excludedDays.contains(day), !session.protectedExcludedDays.contains(day) else { throw Failure.excludedDay }
        let target = option.moves[request.index].source.id
        let preserved = option.moves.enumerated().filter { $0.offset != request.index }.map { $0.element }
        let result = try CoachPlanningAlternatives.search(for: session, calendarAccess: calendarAccess,
            events: events, data: data, now: now, preparationIncluded: true,
            fixedMoves: preserved, restrictedDays: [target: day], isCancelled: isCancelled)
        if result.state == .cancelled { throw CancellationError() }
        guard let revised = result.options.first else { throw Failure.noAlternative }
        return revised
    }
}
