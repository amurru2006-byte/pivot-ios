import Foundation

/// Untrusted proposal, never an authorization to write to EventKit.
struct CoachCalendarDraft: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var start: Date?
    var end: Date?
    var calendarHint: String?
    var notes: String
    var endEstimated: Bool

    enum CodingKeys: String, CodingKey { case title, start, end, calendarHint, notes, endEstimated }

    func problem(now: Date, calendarID: String) -> String? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 160, notes.count <= 3000 else { return "Controlla titolo e note della proposta." }
        guard !calendarID.isEmpty else { return "Scegli il calendario dove salvare l'impegno." }
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let start, let end, start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              end > start, end.timeIntervalSince(start) <= 86400 else {
            return "Conferma inizio e fine, con la data corretta anche dopo mezzanotte."
        }
        guard start <= now.addingTimeInterval(366 * 86400) else {
            return "Scegli una data non oltre un anno nel futuro: nessun evento è stato creato."
        }
        return nil
    }

    func checkExistingNotes(_ existing: String) throws {
        guard notes.trimmingCharacters(in: .whitespacesAndNewlines) == existing.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw CoachCalendarDraftConflict.differentNotes
        }
    }

    static func matchingCalendarIDs(hint: String?, choices: [(id: String, title: String)]) -> [String] {
        guard let hint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        // Never fuzzy-match a person's calendar or choose the first duplicate.
        return choices.filter { normalizedCalendarHint($0.title) == normalizedCalendarHint(hint) }.map(\.id)
    }

    static func normalizedCalendarHint(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func selectedCalendar(hint: String?, choices: [(id: String, title: String)], aliases: [String: String], preferred: String?) -> String? {
        if let hint, !normalizedCalendarHint(hint).isEmpty {
            if let saved = aliases[normalizedCalendarHint(hint)], choices.contains(where: { $0.id == saved }) { return saved }
            let matches = matchingCalendarIDs(hint: hint, choices: choices)
            return matches.count == 1 ? matches[0] : nil
        }
        if let preferred, choices.contains(where: { $0.id == preferred }) { return preferred }
        return choices.count == 1 ? choices[0].id : nil
    }
}

enum CoachCalendarDraftConflict: LocalizedError {
    case differentNotes
    var errorDescription: String? {
        "Esiste già un impegno con questi orari e titolo, ma con note diverse. Non ho creato una copia né modificato le note esistenti."
    }
}
