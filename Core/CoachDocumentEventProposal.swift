import Foundation

/// A civil day is a date, not an invented midnight appointment. The exclusive
/// boundary follows the calendar, including 23/25-hour daylight-saving days.
enum CoachDocumentCivilDay {
    static func interval(_ key: String, timeZone: TimeZone = PivotDate.calendar.timeZone) -> DateInterval? {
        guard key.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1900...9999).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let result = calendar.dateInterval(of: .day, for: date) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: result.start)
        guard actual.year == parts[0], actual.month == parts[1], actual.day == parts[2] else { return nil }
        return result
    }
    static func instant(day: String, clock: String, timeZone: TimeZone = PivotDate.calendar.timeZone) -> Date? {
        guard let interval = interval(day, timeZone: timeZone),
              clock.range(of: #"^[0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        let pieces = clock.split(separator: ":").compactMap { Int($0) }
        guard pieces.count == 2, (0...23).contains(pieces[0]), (0...59).contains(pieces[1]) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let first = calendar.date(bySettingHour: pieces[0], minute: pieces[1], second: 0, of: interval.start,
            matchingPolicy: .strict, repeatedTimePolicy: .first)
        let last = calendar.date(bySettingHour: pieces[0], minute: pieces[1], second: 0, of: interval.start,
            matchingPolicy: .strict, repeatedTimePolicy: .last)
        guard let first, first == last, first >= interval.start, first < interval.end,
              calendar.component(.hour, from: first) == pieces[0], calendar.component(.minute, from: first) == pieces[1] else { return nil }
        return first
    }
}

/// A document interpretation remains untrusted even with a matching quotation.
/// No native Calendar identifiers, settings, URLs or write commands are accepted.
struct CoachDocumentEventProposal: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case allDay, timed }
    enum Timing: Equatable {
        case allDay(day: String)
        case timed(start: Date, end: Date)
        case needsClarification(String)
    }
    var id = UUID()
    var kind: Kind
    var title: String
    var day: String?
    var startClock: String?
    var endDay: String?
    var endClock: String?
    var notes: String
    var citations: [CoachDocumentCitation]
    var questions: [String]

    var timing: Timing {
        guard questions.isEmpty else { return .needsClarification(questions.joined(separator: "\n")) }
        guard let day, CoachDocumentCivilDay.interval(day) != nil else {
            return .needsClarification("Conferma la data completa, compreso l’anno: non l’ho dedotta.")
        }
        if kind == .allDay {
            guard startClock == nil, endClock == nil, endDay == nil else {
                return .needsClarification("La proposta mescola giornata intera e orari: scegli il tipo corretto.")
            }
            return .allDay(day: day)
        }
        guard let startClock, let start = CoachDocumentCivilDay.instant(day: day, clock: startClock) else {
            return .needsClarification("Conferma l’ora d’inizio; orari mancanti o ambigui non sono stati ricostruiti.")
        }
        guard let endClock, let end = CoachDocumentCivilDay.instant(day: endDay ?? day, clock: endClock),
              end > start, end.timeIntervalSince(start) <= 86400 else {
            return .needsClarification("Conferma giorno e ora di fine: non ho inventato durata o passaggio al giorno successivo.")
        }
        return .timed(start: start, end: end)
    }
    var references: [CoachDocumentReference] {
        let ids = citations.reduce(into: [UUID]()) { result, citation in if !result.contains(citation.sourceID) { result.append(citation.sourceID) } }
        return ids.map { id in .init(sourceID: id, pages: Array(Set(citations.filter { $0.sourceID == id }.map(\.page))).sorted()) }
    }
}

enum CoachDocumentEventResponse {
    enum Failure: LocalizedError {
        case invalid, source, duplicate
        var errorDescription: String? {
            switch self {
            case .invalid: return "La risposta non contiene proposte verificabili. Gli originali restano conservati; nessun evento è stato creato."
            case .source: return "Una citazione non corrisponde alle pagine lette. Non ho collegato una fonte diversa né preparato scritture."
            case .duplicate: return "Ci sono proposte duplicate: vanno chiarite prima di preparare gli eventi."
            }
        }
    }
    private struct Wire: Decodable {
        var version: Int; var requestID: String; var events: [Event]; var questions: [String]
        struct Citation: Decodable { var document: String; var page: Int; var quote: String }
        struct Event: Decodable {
            var kind: CoachDocumentEventProposal.Kind; var title: String; var day: String?
            var startClock: String?; var endDay: String?; var endClock: String?
            var notes: String; var citations: [Citation]; var questions: [String]
        }
    }
    struct Review { var events: [CoachDocumentEventProposal]; var questions: [String] }
    private static func validQuestions(_ values: [String]) -> Bool {
        values.count <= 8 && values.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 240
        }
    }
    private static func visibleClock(_ clock: String, in text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: #"(?<![0-9])([01]?[0-9]|2[0-3]):([0-5][0-9])(?![0-9])"#) else { return false }
        return expression.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).contains { match in
            guard let hours = Range(match.range(at: 1), in: text), let minutes = Range(match.range(at: 2), in: text),
                  let hour = Int(text[hours]), let minute = Int(text[minutes]) else { return false }
            return String(format: "%02d:%02d", hour, minute) == clock
        }
    }
    static func decode(_ bytes: Data, packet: CoachDocumentPacket) throws -> Review {
        guard packet.isValid, bytes.count <= 64_000, CoachJSONIntegrity.hasUniqueObjectKeys(bytes),
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys) == Set(["version", "requestID", "events", "questions"]),
              let rawEvents = object["events"] as? [[String: Any]], rawEvents.count <= 20 else { throw Failure.invalid }
        let eventKeys: Set<String> = ["kind", "title", "day", "startClock", "endDay", "endClock", "notes", "citations", "questions"]
        for event in rawEvents {
            guard Set(event.keys) == eventKeys, let quotes = event["citations"] as? [[String: Any]],
                  (1...6).contains(quotes.count), quotes.allSatisfy({ Set($0.keys) == Set(["document", "page", "quote"]) }) else { throw Failure.invalid }
        }
        let response = try JSONDecoder().decode(Wire.self, from: bytes)
        guard response.version == 1, response.requestID == packet.id.uuidString, validQuestions(response.questions),
              !response.events.isEmpty || !response.questions.isEmpty else { throw Failure.invalid }
        let aliases = Dictionary(uniqueKeysWithValues: packet.sources.enumerated().map { ("d\($0.offset + 1)", $0.element.id) })
        var proposals: [CoachDocumentEventProposal] = [], fingerprints = Set<String>()
        for event in response.events {
            guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, event.title.count <= 160,
                  event.notes.count <= 1800, validQuestions(event.questions),
                  [event.day, event.startClock, event.endDay, event.endClock].allSatisfy({ ($0?.utf16.count ?? 0) <= 10 }) else { throw Failure.invalid }
            let citations = try event.citations.map { wire -> CoachDocumentCitation in
                guard wire.quote.utf16.count <= 800, let id = aliases[wire.document] else { throw Failure.source }
                let citation = CoachDocumentCitation(sourceID: id, page: wire.page, quote: wire.quote)
                guard citation.isGrounded(in: packet) else { throw Failure.source }
                return citation
            }
            let fingerprint = [event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                event.kind.rawValue, event.day ?? "", event.startClock ?? "", event.endDay ?? "", event.endClock ?? ""].joined(separator: "\u{1f}")
            guard fingerprints.insert(fingerprint).inserted else { throw Failure.duplicate }
            var questions = event.questions
            if let day = event.day, CoachDocumentCivilDay.interval(day) != nil {
                let yearPattern = "(?<![0-9])" + String(day.prefix(4)) + "(?![0-9])"
                let yearVisible = citations.contains { $0.quote.range(of: yearPattern, options: .regularExpression) != nil }
                    || packet.instruction.range(of: yearPattern, options: .regularExpression) != nil
                if !yearVisible { questions.append("L’anno non compare nelle citazioni o nella tua richiesta: confermalo prima di preparare l’evento.") }
            }
            if event.kind == .allDay, citations.contains(where: {
                $0.quote.range(of: #"(?:^|\D)(?:[01]?[0-9]|2[0-3]):[0-5][0-9](?:$|\D)"#, options: .regularExpression) != nil
            }) { questions.append("La citazione contiene un orario: controlla se deve essere un evento giornaliero o con un’ora precisa.") }
            if event.kind == .timed {
                let visible = citations.map(\.quote).joined(separator: "\n") + "\n" + packet.instruction
                if visible.range(of: "Europe/Rome", options: .caseInsensitive) == nil {
                    questions.append("Conferma che gli orari siano Europe/Rome o correggili: il fuso non è esplicito nelle citazioni o nella richiesta.")
                }
                if [event.startClock, event.endClock].compactMap({ $0 }).contains(where: { !visibleClock($0, in: visible) }) {
                    questions.append("Un orario proposto non compare in forma verificabile nelle citazioni o nella tua richiesta: controllalo.")
                }
            }
            proposals.append(.init(kind: event.kind, title: event.title, day: event.day, startClock: event.startClock,
                endDay: event.endDay, endClock: event.endClock, notes: event.notes, citations: citations, questions: questions))
        }
        return .init(events: proposals, questions: response.questions)
    }
}
