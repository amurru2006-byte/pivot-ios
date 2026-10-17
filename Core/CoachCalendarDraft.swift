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
        guard let start, let end, end > start, end.timeIntervalSince(start) <= 86400 else {
            return "Conferma inizio e fine, con la data corretta anche dopo mezzanotte."
        }
        guard start >= now.addingTimeInterval(-60), start <= now.addingTimeInterval(366 * 86400) else {
            return "Scegli un inizio futuro entro un anno: nessun evento è stato creato."
        }
        return nil
    }

    static func matchingCalendarIDs(hint: String?, choices: [(id: String, title: String)]) -> [String] {
        guard let hint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        // Never fuzzy-match a person's calendar or choose the first duplicate.
        return choices.filter { normalized($0.title) == normalized(hint) }.map(\.id)
    }
}
