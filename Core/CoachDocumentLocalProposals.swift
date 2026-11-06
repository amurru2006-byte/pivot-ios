import Foundation

/// Deliberately narrow offline fallback, not a general PDF understanding model.
/// It handles one ISO date per line and explicit HH:mm ranges only. No request
/// is sent, no header year is propagated, and unhandled rows remain disclosed.
enum CoachDocumentLocalProposals {
    static func analyze(_ packet: CoachDocumentPacket) throws -> CoachDocumentEventResponse.Review {
        guard packet.isValid else { throw CoachDocumentReviewStore.Failure.invalid }
        let dates = try NSRegularExpression(pattern: #"(?<![0-9])[0-9]{4}-[0-9]{2}-[0-9]{2}(?![0-9])"#)
        let clocks = try NSRegularExpression(pattern: #"(?<![0-9])([0-9]{1,2}):([0-9]{2})(?![0-9])"#)
        var events = [CoachDocumentEventProposal](), skipped = 0, seen = Set<String>()
        for page in packet.pages {
            guard page.reading != .unreadable else { continue }
            for raw in page.text.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                let found = dates.matches(in: line, range: range)
                guard found.count == 1, line.count <= 160, line.utf16.count <= 800,
                      let dayRange = Range(found[0].range, in: line) else {
                    if line.rangeOfCharacter(from: .decimalDigits) != nil { skipped += 1 }
                    continue
                }
                let day = String(line[dayRange])
                let clockMatches = clocks.matches(in: line, range: range)
                var values = [String](), questions = [String]()
                for match in clockMatches {
                    guard let hours = Range(match.range(at: 1), in: line), let minutes = Range(match.range(at: 2), in: line),
                          let h = Int(line[hours]), let m = Int(line[minutes]) else { throw CoachDocumentReviewStore.Failure.invalid }
                    values.append(String(format: "%02d:%02d", h, m))
                }
                if CoachDocumentCivilDay.interval(day) == nil { questions.append("La data non esiste: correggila confrontandola con l’originale.") }
                let kind: CoachDocumentEventProposal.Kind = values.isEmpty ? .allDay : .timed
                if !values.isEmpty {
                    questions.append("Conferma che gli orari vadano interpretati nel fuso Europe/Rome.")
                    if values.count != 2 { questions.append("Indica inizio e fine: non ho aggiunto una durata o scelto fra più orari.") }
                } else if line.range(of: #"[0-9]{1,2}[.:][0-9]{2}"#, options: .regularExpression) != nil {
                    questions.append("La riga contiene un possibile orario in un formato non riconosciuto: conferma tipo e orari.")
                }
                if line.range(of: #"(?i)\b(?:UTC|GMT|CET|CEST)\b|[+-][0-9]{2}:?[0-9]{2}"#, options: .regularExpression) != nil {
                    questions.append("La fonte indica un fuso o un offset: il riconoscimento locale non lo converte automaticamente.")
                }
                if values.count == 2, let first = Range(clockMatches[0].range, in: line), let last = Range(clockMatches[1].range, in: line) {
                    let separator = String(line[first.upperBound..<last.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !["-", "–", "—", "alle", "to"].contains(separator.lowercased()) {
                        questions.append("Verifica quali orari siano inizio e fine: fra i due non c’è un intervallo esplicito.")
                    }
                }
                let fingerprint = ([line.lowercased(), day] + values).joined(separator: "\u{1f}")
                guard seen.insert(fingerprint).inserted else {
                    return .init(events: [], questions: ["Ci sono righe ripetute con gli stessi dati: seleziona le pagine pertinenti prima di preparare le bozze."])
                }
                let citation = CoachDocumentCitation(sourceID: page.sourceID, page: page.number, quote: line)
                guard citation.isGrounded(in: packet) else { throw CoachDocumentReviewStore.Failure.invalid }
                events.append(.init(kind: kind, title: line, day: day, startClock: values.first,
                    endDay: nil, endClock: values.count == 2 ? values.last : nil, notes: "", citations: [citation], questions: questions))
                guard events.count <= 20 else {
                    return .init(events: [], questions: ["La lettura contiene più di 20 possibili proposte. Seleziona meno pagine: non ne ho conservata una parte in silenzio."])
                }
            }
        }
        var questions = [String]()
        if skipped > 0 { questions.append("\(skipped) righe con numeri o date non sono state interpretate: possono contenere altri impegni. Controlla gli originali.") }
        if packet.unreadablePages > 0 { questions.append("\(packet.unreadablePages) pagine non sono leggibili: nessun contenuto è stato ricostruito.") }
        if events.isEmpty { questions.append("Non ho trovato righe con una singola data completa nel formato AAAA-MM-GG. Non ho dedotto anni o interpretato tabelle e paragrafi.") }
        return .init(events: events, questions: questions)
    }
}
