import SwiftUI

struct OnlineCoachSettingsView: View {
    @StateObject private var online = OnlineCoachService()
    @State private var endpoint = ""
    @State private var token = ""
    @State private var consent = false
    var body: some View {
        PivotScreen {
            PivotHeader(title: "AI online e privacy", subtitle: "Conversazione dentro Pivot, con base locale disponibile")
            PivotCard {
                Label(online.isConfigured ? "Collegamento configurato" : "Collegamento da configurare", systemImage: "lock.shield")
                    .font(.headline).accessibilityIdentifier("online-coach-configuration-status")
                Text("Quando usi l'AI online, invii il messaggio, fino a sei messaggi recenti di oggi e le ultime quattro preferenze esplicite. Il calendario viene riassunto con categorie e orari: titoli, indirizzi, note, nominativi e dati Salute non vengono aggiunti automaticamente.")
                    .font(.subheadline)
                Text("Il testo che scrivi può contenere informazioni personali. Il servizio AI deve leggerlo per rispondere: HTTPS protegge il trasporto, ma non lo rende invisibile al servizio. La configurazione richiede verifica della mancata conservazione dei contenuti nell'account del servizio.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                Text("Il token resta nel portachiavi di questo iPhone, senza sincronizzazione iCloud. Non viene incluso nel backup Pivot. Nessun servizio a pagamento si attiva quando finisce la quota.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            }.accessibilityIdentifier("online-coach-privacy")
            PivotCard {
                Text("Configurazione iniziale").font(.headline)
                Text("Questi dati arriveranno dal collegamento personale predisposto per Pivot. Usa il token di Pivot, mai la chiave del provider AI.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                TextField("Indirizzo HTTPS del collegamento", text: $endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityIdentifier("online-coach-endpoint")
                SecureField("Token personale di Pivot", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("online-coach-token")
                Toggle("Ho letto quali dati vengono inviati e abilito l'AI online", isOn: $consent)
                    .accessibilityIdentifier("online-coach-consent")
                Button("Salva collegamento protetto") {
                    if online.configure(endpoint: endpoint, token: token, consent: consent) { token = ""; endpoint = ""; consent = false }
                }.buttonStyle(PivotPrimaryButton()).disabled(!consent || endpoint.isEmpty || token.isEmpty)
                    .accessibilityIdentifier("online-coach-save")
                if online.isConfigured {
                    Button("Scollega AI online", role: .destructive) { if online.disconnect() { token = "" } }
                        .buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("online-coach-disconnect")
                }
            }
            if let message = online.configurationMessage {
                Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("online-coach-settings-message")
            }
            Text("Puoi usare la base locale e continuare a scrivere dentro Pivot anche senza questo collegamento.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
        }.navigationTitle("AI online e privacy")
            .onDisappear { token = "" }
    }
}
