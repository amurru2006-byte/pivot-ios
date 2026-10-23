import SwiftUI

/// Human-readable counterpart of the exact bounded cloud request. No credentials.
struct CoachCloudDisclosure: View {
    let request: CoachV8Request
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Destinazione: Cloudflare → Groq").font(.headline)
            Text(request.purpose == "rewrite" ? "Testo da riordinare" : "Il tuo messaggio").font(.subheadline.weight(.semibold))
            if request.purpose == "rewrite" {
                Text("Questa richiesta serve soltanto a riordinare il testo. Non crea un impegno e non invia calendario o conversazioni precedenti. I segnaposto privati saranno ripristinati sull'iPhone.").font(.caption)
            }
            Text(request.message).textSelection(.enabled)
                .accessibilityIdentifier("coach-online-reviewed-message")
            Text("Il testo viene filtrato, ma nomi o informazioni personali possono rimanere. I servizi online leggono ciò che invii. Per informazioni sanitarie usa la base locale.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
            if !request.memories.isEmpty {
                DisclosureGroup("Preferenze che hai autorizzato: \(request.memories.count)") {
                    ForEach(Array(request.memories.enumerated()), id: \.offset) { _, value in
                        Text(value).font(.subheadline).textSelection(.enabled)
                    }
                }.accessibilityIdentifier("coach-online-memories")
            }
            DisclosureGroup("Messaggi recenti inclusi: \(request.history.count)") {
                ForEach(Array(request.history.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.role == "user" ? "Tu" : "Pivot").font(.caption.weight(.semibold))
                        Text(item.text).font(.subheadline).textSelection(.enabled)
                    }.padding(.vertical, 4)
                }
            }
            if let omitted = request.historyOmittedCount, omitted > 0 {
                Text("\(omitted) messaggi precedenti esclusi per rispettare il limite. I messaggi inclusi non sono tagliati a metà.").font(.caption)
            }
            if let drafts = request.draftContext, !drafts.isEmpty {
                DisclosureGroup("Dati della bozza da continuare") {
                    ForEach(drafts) { draft in
                        Text(draft.title.isEmpty ? "Titolo ancora da definire" : draft.title)
                        if let start = draft.start { Text("Inizio: " + DisplayDate.label(start, format: "d MMM yyyy HH:mm")) }
                        if let end = draft.end { Text("Fine: " + DisplayDate.label(end, format: "d MMM yyyy HH:mm")) }
                        if let hint = draft.calendarHint { Text("Calendario richiesto: " + hint) }
                        if !draft.notes.isEmpty { Text(draft.notes).textSelection(.enabled) }
                    }
                }
            }
            if let contexts = request.planningContext, !contexts.isEmpty {
                DisclosureGroup("Vincoli del piano da continuare") {
                    ForEach(Array(contexts.enumerated()), id: \.offset) { _, context in
                        Text("Date riferite al " + PivotDate.shortDate(context.anchor))
                        Text("Attività: " + context.intent.eventIDs.joined(separator: ", "))
                        Text("Giorni consentiti: " + context.intent.allowedDayOffsets.sorted().compactMap {
                            PivotDate.calendar.date(byAdding: .day, value: $0, to: PivotDate.calendar.startOfDay(for: context.anchor)).map(PivotDate.shortDate)
                        }.joined(separator: ", "))
                        Text("Le sole attività originarie necessarie possono essere incluse anche se ora sono nel passato. Non viene aggiunto tutto lo storico.").font(.caption)
                    }
                }.accessibilityIdentifier("coach-online-planning-context")
            }
            DisclosureGroup("Impegni inclusi: \(request.events.count)") {
                Text("Solo sigle interne, categorie, orari, durata, stato e vincoli. Non vengono aggiunti titoli, note o indirizzi del calendario.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                ForEach(request.events, id: \.id) { event in
                    Text("\(PivotDate.shortDate(event.start)) · \(event.kind.label) · \(PivotDate.time(event.start))–\(PivotDate.time(event.end)) · \(event.status.label)")
                        .font(.subheadline)
                }
            }
            if request.version >= 3 { Text("Le corrispondenze fra il tuo messaggio e gli eventi sono indicate solo con sigle interne. La bozza da continuare viene filtrata come il messaggio e resta visibile qui sopra.").font(.caption).foregroundStyle(PivotTheme.muted) }
            Text("Non vengono aggiunti automaticamente audio, dati Salute o memorie private. Sono incluse solo le preferenze abilitate esplicitamente per l’AI online, se presenti qui sopra. Quello che scrivi tu può comunque contenere informazioni sensibili. Sono inclusi data, ora e un identificativo tecnico della richiesta.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
            DisclosureGroup("Dati tecnici completi") {
                if let bytes = try? request.encoded() {
                    Text(String(decoding: bytes, as: UTF8.self)).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
    }
}
