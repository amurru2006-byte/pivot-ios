import SwiftUI

/// Human-readable counterpart of the exact bounded cloud request. No credentials.
struct CoachCloudDisclosure: View {
    let request: CoachV8Request
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Destinazione: Cloudflare → Groq").font(.headline)
            Text("Il tuo messaggio").font(.subheadline.weight(.semibold))
            Text(request.message).textSelection(.enabled)
                .accessibilityIdentifier("coach-online-reviewed-message")
            Text("Il testo viene filtrato, ma nomi o informazioni personali possono rimanere. I servizi online leggono ciò che invii. Per informazioni sanitarie usa la base locale.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
            DisclosureGroup("Messaggi recenti inclusi: \(request.history.count)") {
                ForEach(Array(request.history.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.role == "user" ? "Tu" : "Pivot").font(.caption.weight(.semibold))
                        Text(item.text).font(.subheadline).textSelection(.enabled)
                    }.padding(.vertical, 4)
                }
            }
            DisclosureGroup("Impegni inclusi: \(request.events.count)") {
                Text("Solo sigle interne, categorie, orari, durata, stato e vincoli. Non vengono aggiunti titoli, note o indirizzi del calendario.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                ForEach(request.events, id: \.id) { event in
                    Text("\(event.kind.label) · \(PivotDate.time(event.start))–\(PivotDate.time(event.end)) · \(event.status.label)")
                        .font(.subheadline)
                }
            }
            Text("Non vengono aggiunti automaticamente audio, dati Salute o memorie personali. Quello che scrivi tu può comunque contenere informazioni sensibili. Sono inclusi data, ora e un identificativo tecnico della richiesta.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
            DisclosureGroup("Dati tecnici completi") {
                if let bytes = try? request.encoded() {
                    Text(String(decoding: bytes, as: UTF8.self)).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
    }
}
