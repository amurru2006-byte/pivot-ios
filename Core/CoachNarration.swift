import Foundation

// A model can select a verified option and a tone, never invent calendar fields or text.
// This is post-generation validation, not a runtime grammar or a guarantee of good choices.
enum CoachNarration {
    private enum Tone: String, Decodable { case neutral, supportive }
    private struct Selection: Decodable {
        var version: Int
        var option_id: String?
        var tone: Tone
    }

    static func render(_ output: String, verified: CoachTurnResult) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 2048,
              let bytes = trimmed.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              Set(object.keys) == Set(["version", "option_id", "tone"]),
              let selection = try? JSONDecoder().decode(Selection.self, from: bytes), selection.version == 1 else { return nil }
        let introduction = selection.tone == .supportive ? "Un passo alla volta. " : ""
        if let id = selection.option_id {
            guard let option = verified.options.first(where: { $0.id.uuidString == id }) else { return nil }
            return introduction + "Valuterei questa soluzione: " + option.explanation + " " + option.consequences
                + " È solo un suggerimento: scegli tu se applicarlo in Pivot. Il Calendario non cambia senza la conferma separata."
        }
        if verified.needsActivityClarification {
            return introduction + "Indica il titolo e l’orario dell’attività, oppure scegli il suo pulsante in ‘Da recuperare?’. Non viene modificato nulla."
        }
        guard !verified.options.isEmpty else { return nil }
        return introduction + "Confronta le soluzioni verificate qui sotto. Nessuna viene applicata automaticamente."
    }
}
