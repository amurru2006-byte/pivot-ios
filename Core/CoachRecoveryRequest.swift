import Foundation

/// A conservative, on-device hand-off, not an LLM interpretation or permission
/// to move anything. Ambiguous activities remain a choice in the recovery UI.
struct CoachRecoveryRequest: Codable, Equatable {
    var requestedAt: Date
    var dayOffset: Int?
    var band: TrainingDurationTimeBand?
    var workoutOnly: Bool
    var targetID: String? = nil
    var instruction: String? = nil

    var isValid: Bool {
        requestedAt.timeIntervalSinceReferenceDate.isFinite
            && (dayOffset.map { (0...6).contains($0) } ?? true)
            && (targetID.map { !$0.isEmpty && $0.count <= 2048 } ?? true)
            && (instruction.map { !$0.isEmpty && $0.count <= 1500 } ?? true)
    }
    var day: Date? {
        dayOffset.flatMap { PivotDate.calendar.date(byAdding: .day, value: $0, to: PivotDate.calendar.startOfDay(for: requestedAt)) }
    }

    static func parse(_ text: String, now: Date) -> Self? {
        let clean = EventCoalescer.normalized(text)
        let tokens = Set(clean.split(separator: " ").map(String.init))
        let recovery = ["recupera", "recuperare", "recuperarlo", "recuperarla"].contains { tokens.contains($0) }
        // Do not reduce conditions, medical statements or a mixed create/delete
        // request to a recovery command. Unrecognized prose stays in normal chat.
        let excluded: Set<String> = ["non", "senza", "se", "forse", "dolore", "infortunio", "febbre", "male", "medico", "cancella", "elimina", "crea", "registra"]
        guard recovery, excluded.isDisjoint(with: tokens), text.count <= 1500, now.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let afterTomorrow = tokens.contains("dopodomani") || clean.contains("dopo domani")
        let explicitDays = [tokens.contains("oggi") || tokens.contains("stasera") || tokens.contains("stamattina"), tokens.contains("domani") && !afterTomorrow, afterTomorrow]
        guard explicitDays.filter({ $0 }).count <= 1 else { return nil }
        // Never silently reinterpret an explicit date, weekday or clock time.
        let unsupported: Set<String> = ["lunedi", "martedi", "mercoledi", "giovedi", "venerdi", "sabato", "domenica", "settimana", "mese", "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
        guard unsupported.isDisjoint(with: tokens), !text.contains(":"),
              !clean.contains(where: { $0.isNumber }) else { return nil }
        let proposedBands: [TrainingDurationTimeBand?] = [
            tokens.contains("mattina") || tokens.contains("mattino") || tokens.contains("stamattina") ? .morning : nil,
            tokens.contains("pomeriggio") ? .afternoon : nil,
            tokens.contains("sera") || tokens.contains("serata") || tokens.contains("stasera") ? .evening : nil
        ]
        let bands = proposedBands.compactMap { $0 }
        guard bands.count <= 1 else { return nil }
        return .init(requestedAt: now, dayOffset: explicitDays[2] ? 2 : explicitDays[1] ? 1 : explicitDays[0] ? 0 : nil,
                     band: bands.first, workoutOnly: !tokens.isDisjoint(with: ["palestra", "allenamento", "squat", "bench", "deadlift"]), instruction: text)
    }

    static func candidates(events: [CalendarItem], data: AppData, now: Date, workoutOnly: Bool = false) -> [CalendarItem] {
        EventCoalescer.unique(events, data: data).filter { item in
            item.end <= now && item.end >= now.addingTimeInterval(-14 * 86400) && !item.isAllDay && item.writable
                && (!workoutOnly || item.kind == .workout)
                && [.pending, .skipped].contains(data.records[item.id]?.status ?? .pending)
                && !data.moves.contains(where: { $0.source.id == item.id })
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start > $1.start }
    }

    func resolving(text: String, events: [CalendarItem], data: AppData, now: Date) -> Self {
        var result = self
        let values = Self.candidates(events: events, data: data, now: now, workoutOnly: workoutOnly)
        let query = " " + EventCoalescer.normalized(text) + " "
        let named = values.filter {
            let title = EventCoalescer.normalized($0.title)
            return title.count >= 4 && query.contains(" " + title + " ")
        }
        let selected = named.isEmpty ? (workoutOnly ? values : []) : named
        result.targetID = selected.count == 1 ? selected.first?.id : nil
        return result
    }
}
