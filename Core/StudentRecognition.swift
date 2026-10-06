import Foundation

// Calendar titles suggest a person; only an unambiguous match links a saved client.
// Names are compared as complete words, never substrings (Anna != Giovanna).
enum StudentRecognition {
    struct Result {
        var name: String
        var client: Client?
        var ambiguous: Bool
    }

    static func recognize(title: String, clients: [Client]) -> Result {
        let name = calendarName(title)
        let exact = clients.filter { !name.isEmpty && normalized($0.name) == normalized(name) }
        if exact.count == 1 { return Result(name: exact[0].name, client: exact[0], ambiguous: false) }
        if exact.count > 1 { return Result(name: name, client: nil, ambiguous: true) }
        let titleWords = normalized(title)
        let candidates = clients.filter { containsWords(titleWords, normalized($0.name)) }
        // "Anna Rossi" is more specific than an otherwise matching "Anna".
        let specific = candidates.filter { candidate in
            !candidates.contains { other in
                normalized(other.name) != normalized(candidate.name)
                    && containsWords(normalized(other.name), normalized(candidate.name))
            }
        }
        if specific.count == 1 { return Result(name: specific[0].name, client: specific[0], ambiguous: false) }
        if specific.count > 1 { return Result(name: name, client: nil, ambiguous: true) }
        return Result(name: name, client: nil, ambiguous: false)
    }

    static func existingClient(named name: String, clients: [Client]) -> Client? {
        let key = normalized(name)
        guard !key.isEmpty else { return nil }
        let matches = clients.filter { normalized($0.name) == key }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func normalized(_ name: String) -> String { EventCoalescer.normalized(name) }
    private static func containsWords(_ text: String, _ name: String) -> Bool {
        !name.isEmpty && (" " + text + " ").contains(" " + name + " ")
    }
    static func calendarName(_ title: String) -> String {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow "Ripetizioni di matematica con Giulia Rossi" as well as bare names.
        let pattern = "(?i)^(?:ripetizioni|ripetizione|lezione)(?:\\s+di\\s+.+?)?\\s+(?:(?:con|a)\\s+)?"
        if let range = name.range(of: pattern, options: .regularExpression) { name.removeSubrange(range) }
        for separator in [" (", " - ", " – ", " · ", " | "] {
            if let range = name.range(of: separator) { name = String(name[..<range.lowerBound]) }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = ["lezione", "ripetizioni", "ripetizione", "matematica", "chimica", "fisica", "studio", "lavoro"]
        guard !generic.contains(normalized(name)) else { return "" }
        return name
    }
}
