import SwiftUI

struct OnlineCoachSettingsView: View {
    var setup: CoachOnlineSetupLink? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var online = OnlineCoachService()
    @State private var endpoint = ""
    @State private var token = ""
    @State private var consent = false
    @State private var setupMessage: String?
    @State private var activationCode = ""
    @State private var isUnlocking = false
    @State private var unlockTask: Task<Void, Never>?
    @State private var unlockGeneration = 0
    @State private var editingConnection = false
    var body: some View {
        PivotScreen {
            PivotHeader(title: "AI online e privacy", subtitle: "Conversazione dentro Pivot, con base locale disponibile")
            #if DEBUG && targetEnvironment(simulator)
            if let namespace = OnlineCoachService.interactionTestNamespace {
                Text("Contenitore QA: " + namespace).font(.caption).accessibilityIdentifier("online-coach-qa-namespace")
            }
            #endif
            PivotCard {
                Label(online.isConfigured ? "Collegamento configurato" : "Collegamento da configurare", systemImage: "lock.shield")
                    .font(.headline).accessibilityIdentifier("online-coach-configuration-status")
                Text("All'inizio della conversazione autorizzi gli invii a Cloudflare e Groq; i messaggi successivi di oggi partono senza conferme ripetute finché Pivot resta in esecuzione. Puoi interrompere gli invii diretti e consultare Dati inviati nel Coach. Sono inclusi messaggio filtrato, fino a sei messaggi recenti ammissibili della chat online di oggi e calendario con alias, categorie e orari. Memorie, conversazioni locali, titoli e note degli eventi non vengono aggiunti. Stati e spostamenti riconoscibili come derivati da Salute restano locali.")
                    .font(.subheadline).accessibilityIdentifier("online-coach-privacy")
                Text("Il filtro non garantisce l’anonimato: controlla anche i messaggi recenti e non inviare informazioni sanitarie. Il servizio AI legge il contenuto: HTTPS protegge il trasporto, non lo nasconde al servizio. Va verificata la mancata conservazione dei contenuti nell’account del servizio.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                Text("Il token resta nel portachiavi di questo iPhone, senza sincronizzazione iCloud. Non viene incluso nel backup Pivot. Nessun servizio a pagamento si attiva quando finisce la quota.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            }
            PivotCard {
                DisclosureGroup(isExpanded: $editingConnection) {
                if setup != nil {
                    Text("Dati ricevuti dal QR. Controlla l'indirizzo del tuo collegamento e leggi quali dati vengono inviati. Scansionare il QR non abilita l'AI e non cambia il Calendario.")
                        .font(.caption).accessibilityIdentifier("online-coach-qr-review")
                    SecureField("Codice di attivazione dal computer", text: $activationCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(.asciiCapable)
                        .accessibilityIdentifier("online-coach-activation-code")
                    Button(isUnlocking ? "Sblocco in corso…" : "Sblocca il collegamento") { unlockSetup() }
                        .buttonStyle(PivotSecondaryButton()).disabled(isUnlocking || activationCode.isEmpty || !token.isEmpty)
                        .accessibilityIdentifier("online-coach-unlock")
                    Text(token.isEmpty ? "Il QR è cifrato: mostra il codice separato sul computer e inseriscilo qui. Il consenso resta una tua scelta." : "Token sbloccato, non mostrato. Ora puoi leggere e confermare il consenso.")
                        .font(.caption).accessibilityIdentifier("online-coach-unlock-status")
                }
                Text(online.isConfigured && setup == nil
                     ? "Il collegamento è già salvato. I campi restano vuoti per sicurezza: compilali solo per sostituirlo. Per usare l’AI torna a Parla con Pivot."
                     : "Questi dati arriveranno dal collegamento personale predisposto per Pivot. Usa il token di Pivot, mai la chiave del provider AI.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                    .accessibilityIdentifier("online-coach-edit-explanation")
                TextField("Indirizzo HTTPS del collegamento", text: $endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityIdentifier("online-coach-endpoint")
                    .disabled(setup != nil)
                SecureField("Token personale di Pivot", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("online-coach-token")
                    .disabled(setup != nil)
                Toggle("Ho letto quali dati vengono inviati e abilito l'AI online", isOn: $consent)
                    .accessibilityIdentifier("online-coach-consent")
                Button("Salva collegamento protetto") {
                    if let setup, !setup.isCurrent(at: Date()) {
                        token = ""; consent = false; setupMessage = "Il QR è scaduto. Richiedine uno nuovo sul computer."
                        return
                    }
                    if online.configure(endpoint: endpoint, token: token, consent: consent) {
                        token = ""; endpoint = ""; consent = false
                        editingConnection = false
                        if setup != nil { dismiss() }
                    }
                }.buttonStyle(PivotPrimaryButton()).disabled(!consent || endpoint.isEmpty || token.isEmpty || isUnlocking)
                    .accessibilityIdentifier("online-coach-save")
                } label: {
                    // Put the identifier on the label, not the container: SwiftUI
                    // otherwise replaces the identifiers of its secure fields.
                    Text(online.isConfigured && setup == nil ? "Modifica collegamento" : "Configurazione iniziale")
                        .accessibilityIdentifier("online-coach-edit")
                }
                if online.isConfigured {
                    Button("Scollega AI online", role: .destructive) { if online.disconnect() { token = "" } }
                        .buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("online-coach-disconnect")
                }
            }
            if let message = online.configurationMessage {
                Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("online-coach-settings-message")
            }
            #if DEBUG && targetEnvironment(simulator)
            if let diagnostic = online.keychainTestDiagnostic {
                Text("Portachiavi QA: " + diagnostic).font(.caption).accessibilityIdentifier("online-coach-keychain-diagnostic")
            }
            #endif
            if let setupMessage { Text(setupMessage).foregroundStyle(PivotTheme.amber) }
            Text("Puoi usare la base locale e continuare a scrivere dentro Pivot anche senza questo collegamento.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
        }.navigationTitle("AI online e privacy")
            .toolbar { if setup != nil { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { token = ""; dismiss() } } } }
            .onAppear {
                editingConnection = !online.isConfigured || setup != nil
                if let setup, setup.isCurrent(at: Date()) { endpoint = setup.endpoint; token = ""; consent = false }
            }
            .onChange(of: scenePhase) { _, value in
                if value != .active { cancelUnlock(); token = ""; consent = false; if setup != nil { dismiss() } }
            }
            .onDisappear { cancelUnlock(); token = "" }
    }
    private func cancelUnlock() {
        unlockGeneration += 1; unlockTask?.cancel(); unlockTask = nil
        activationCode = ""; isUnlocking = false
    }
    private func unlockSetup() {
        guard let setup else { return }
        unlockGeneration += 1
        let generation = unlockGeneration, code = activationCode
        isUnlocking = true; setupMessage = nil
        unlockTask = Task { @MainActor in
            let config = await Task.detached(priority: .userInitiated) { setup.configuration(code: code, now: Date()) }.value
            guard !Task.isCancelled, generation == unlockGeneration, scenePhase == .active else { return }
            isUnlocking = false; activationCode = ""; consent = false; unlockTask = nil
            guard setup.isCurrent(at: Date()) else {
                token = ""; setupMessage = "Il QR è scaduto. Richiedine uno nuovo sul computer."
                return
            }
            if let config { token = config.token }
            else { token = ""; setupMessage = "Codice errato o QR non valido. Controlla il codice sul computer o richiedi un nuovo QR." }
        }
    }
}
