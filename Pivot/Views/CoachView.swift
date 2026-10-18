import SwiftUI
import UIKit

private struct OnlineCoachReview: Identifiable {
    let snapshot: CoachV8Snapshot
    let originalMessage: String
    var rewrite: CoachRewriteDraft? = nil
    var id: String { snapshot.request.requestID }
}

struct CoachView: View {
    var contextEventID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var coachModel: LocalCoachService
    @EnvironmentObject private var agenda: AgendaService
    @State private var input = ""
    @State private var memoryInput = ""
    @State private var memoryTemporary = false
    @State private var memoryUntil = Date().addingTimeInterval(7 * 86400)
    @State private var historyDay = Date()
    @State private var deleteHistory = false
    @State private var message: String?
    @State private var applyingID: UUID?
    @State private var isPlanning = false
    @State private var turnTask: Task<Void, Never>?
    @State private var turnGeneration = 0
    @State private var responseRecord: EventRecord?
    @State private var returnHomeAfterResponse = false
    @StateObject private var dictation = DictationService()
    @StateObject private var onlineCoach = OnlineCoachService()
    @State private var useLocal = false
    @State private var onlineReview: OnlineCoachReview?
    @State private var lastAuthorizedRequest: CoachV8Request?
    @State private var showOnlineData = false
    @State private var calendarDraft: CoachSavedCalendarDraft?
    @State private var reuseText: String?
    @State private var confirmReuse = false
    @FocusState private var composerFocused: Bool
    @State private var originalDictation: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var dictationComposer = DictationTextComposer()
    private var reviews: [WorkoutReview] { (store.data.workoutReviews ?? []).filter { !$0.dismissed && !$0.resolved } }
    private var contextEvent: CalendarItem? { agenda.planned.first { $0.id == contextEventID } }
    private var state: CoachState { store.data.coachState }
    private var todayMessages: [CoachMessage] { state.messages.filter { $0.dayKey == PivotDate.key(historyDay) } }
    private var missed: [CalendarItem] {
        Array(agenda.planned.filter {
            !$0.isAllDay && $0.occurs(on: Date()) && $0.end <= Date() && (store.data.records[$0.id]?.status ?? .pending) != .completed
                && (store.data.records[$0.id]?.status ?? .pending) != .partial
        }.suffix(4))
    }

    var body: some View {
        PivotScreen {
            PivotHeader(title: "Parla con Pivot", subtitle: "Racconta cosa è cambiato. Decidi tu cosa applicare.")
            onlineStatusCard
            NavigationLink { PersonalForecastView() } label: {
                Label("Previsioni personali", systemImage: "sparkles").frame(maxWidth: .infinity)
            }.buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("coach-predictions")
            if store.data.actualWorkoutDraft != nil { WorkoutChatCard() }
            ForEach(reviews) { review in
                PivotCard(tint: PivotTheme.blue) {
                    Label("È l’allenamento del giorno?", systemImage: "figure.strengthtraining.traditional").font(.headline)
                    Text("Da Salute: \(PivotDate.shortDate(review.workout.start)) · \(PivotDate.time(review.workout.start))–\(PivotDate.time(review.workout.end)) · \(ActivityTiming.duration(review.workout.durationSeconds))").font(.subheadline)
                    Text("Il tipo indica una sessione strutturata; non deduco automaticamente lo sforzo o la colazione.").font(.caption).foregroundStyle(PivotTheme.muted)
                    ForEach(agenda.planned.filter { review.eventIDs.contains($0.id) }) { event in
                        Button("Sì, è ‘\(event.title)’") { prepareActual(event, workout: review.workout, start: review.workout.start) }.buttonStyle(PivotPrimaryButton()).disabled(store.data.actualWorkoutDraft != nil)
                    }
                    Button("No, è un’altra attività") {
                        store.change { data in
                            if let index = data.workoutReviews?.firstIndex(where: { $0.id == review.id }) { data.workoutReviews?[index].dismissed = true }
                            var coach = data.coachState; coach.messages.append(.init(dayKey: PivotDate.key(Date()), role: .user, text: "L’attività Salute delle \(PivotDate.time(review.workout.start)) non è l’allenamento programmato.", healthDerived: true)); data.coachState = coach
                        }
                    }.buttonStyle(PivotSecondaryButton())
                }
            }
            let missingCardio = WorkoutContext.missingCardioInPlanned(events: agenda.planned, data: store.data, now: Date())
            if !missingCardio.isEmpty {
                PivotCard {
                    Label("Cardio da chiarire", systemImage: "figure.walk").font(.headline)
                    Text("Il cardio previsto non risulta completato. Lo hai fatto senza Apple Watch, vuoi recuperarlo o è saltato? Una camminata breve non lo sostituisce automaticamente.").font(.subheadline)
                    ForEach(missingCardio) { event in
                        Button(event.title + " · segna l’esito") { responseRecord = store.record(for: event) }.buttonStyle(PivotSecondaryButton())
                    }
                }
            }
            if let event = contextEvent {
                PivotCard(tint: Color(calendarItem: event)) {
                    Label(event.kind.label, systemImage: event.kind.icon).foregroundStyle(Color.readableCalendar(event)).font(.caption)
                    Text(event.end <= Date() ? "Com’è andata ‘\(event.title)’?" : event.title).font(.headline)
                    Text(event.timeSummary).font(.caption).foregroundStyle(PivotTheme.muted)
                    if event.end <= Date() {
                        HStack {
                            ForEach([Completion.completed, .partial, .skipped], id: \.self) { outcome in
                                Button(outcome.label) { var value = store.record(for: event); value.status = outcome; responseRecord = value }
                                    .buttonStyle(PivotSecondaryButton())
                            }
                        }
                    }
                    Button { responseRecord = store.record(for: event) } label: { Label("Apri i dettagli dell’attività", systemImage: "slider.horizontal.3") }.buttonStyle(PivotSecondaryButton())
                }
            }

            if !state.pendingCalendarChanges.isEmpty { pendingSection }

            if !missed.isEmpty && contextEventID == nil {
                DisclosureGroup("Attività da recuperare · \(missed.count)") {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "Da recuperare?")
                    ForEach(missed) { event in
                        Button { send("Voglio recuperare \(event.title)", targetID: event.id) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Label(event.title, systemImage: event.kind.icon).lineLimit(2)
                                    Text(event.timeSummary).font(.caption)
                                }
                                Spacer(); Image(systemName: "arrow.up.right.circle.fill")
                            }
                        }.buttonStyle(PivotSecondaryButton())
                    }
                }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Conversazione")
                DisclosureGroup(DisplayDate.label(historyDay, format: "d MMMM")) { DaySelector(day: $historyDay) }.font(.caption).foregroundStyle(PivotTheme.muted)
                if todayMessages.isEmpty {
                    Text("Puoi scrivere o dettare: “Sono andato in palestra alle 5:50 AM oggi”. Ti chiederò gli orari che mancano prima di cambiare qualcosa.").font(.subheadline).foregroundStyle(PivotTheme.muted)
                } else {
                    ForEach(todayMessages) { item in bubble(item) }
                }
                if !todayMessages.isEmpty {
                    Button("Elimina la conversazione di questo giorno", role: .destructive) { deleteHistory = true }.font(.caption)
                }
            }

            if !state.options.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Soluzioni verificate")
                    ForEach(state.options) { option in optionCard(option) }
                }
            }

            PivotCard {
                TextField(dictation.isListening ? "Ti ascolto…" : "Scrivi o detta cosa è cambiato…", text: $input, axis: .vertical)
                    .focused($composerFocused)
                    .accessibilityIdentifier("coach-message-input")
                    .lineLimit(2...6).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                HStack {
                    Button {
                        if dictation.isListening { finishDictation() }
                        else {
                            dictationComposer.begin(currentText: input)
                            Task { await dictation.start(contextualPhrases: dictationContext) }
                        }
                    } label: { Label(dictation.isListening ? "Termina" : "Detta", systemImage: dictation.isListening ? "stop.circle.fill" : "mic.fill") }.buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("coach-dictation")
                    Button { dictation.stop(); send(input) } label: { Label("Invia", systemImage: "arrow.up") }
                    .accessibilityIdentifier("coach-send")
                    .buttonStyle(PivotPrimaryButton()).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.locked || coachModel.isGenerating || isPlanning)
                }
                if isPlanning { ProgressView("Controllo il programma…").accessibilityIdentifier("coach-planning-progress") }
                if onlineCoach.isConfigured && !useLocal {
                    Button("Riordina testo") { startRewrite() }
                        .disabled(isPlanning || dictation.isListening || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("coach-rewrite")
                }
                if let originalDictation {
                    Button("Ripristina testo originale") { input = originalDictation; self.originalDictation = nil }
                        .disabled(isPlanning || dictation.isListening)
                        .accessibilityIdentifier("coach-rewrite-undo")
                }
                if dictation.isListening { Text("Dettatura attiva · continua anche dopo una pausa; controlla il testo prima di inviare").font(.caption).foregroundStyle(PivotTheme.accent) }
                if let status = dictation.message { Text(status).font(.caption).foregroundStyle(PivotTheme.amber) }
                if coachModel.isGenerating {
                    HStack {
                        ProgressView()
                        Text("L’AI locale valuta le soluzioni verificate…").font(.caption)
                        Spacer()
                        Button("Interrompi") { coachModel.stop() }.font(.caption)
                    }
                }
            }
            PivotCard {
                DisclosureGroup("Cose che vuoi far ricordare al Coach") {
                    Text("Solo informazioni aggiunte da te. Puoi rimuoverle quando vuoi; sono incluse nel backup.").font(.caption).foregroundStyle(PivotTheme.muted)
                    ForEach(state.memories) { memory in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(memory.text).font(.subheadline)
                                if let until = memory.expiresAt {
                                    Text(memory.isActive(at: Date()) ? "Fino al \(DisplayDate.label(until, format: "d MMM HH:mm"))" : "Scaduta · non usata dal modello locale")
                                        .font(.caption).foregroundStyle(PivotTheme.muted)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                store.change { data in var coach = data.coachState; coach.memories.removeAll { $0.id == memory.id }; data.coachState = coach }
                            } label: { Image(systemName: "minus.circle") }
                        }.padding(.vertical, 5)
                    }
                    TextField("Una preferenza o un’informazione utile", text: $memoryInput, axis: .vertical)
                    Toggle("Informazione temporanea", isOn: $memoryTemporary)
                    if memoryTemporary { DatePicker("Ricorda fino a", selection: $memoryUntil, in: Date()...) }
                    Button("Ricorda questa informazione") {
                        let text = String(memoryInput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1500))
                        guard !text.isEmpty else { return }
                        let memory = CoachMemory(text: text, expiresAt: memoryTemporary ? memoryUntil : nil)
                        guard memory.isValid else { message = "La scadenza deve essere successiva a questo momento."; return }
                        if store.change({ data in var coach = data.coachState; coach.memories.append(memory); data.coachState = coach }) { memoryInput = ""; memoryTemporary = false }
                    }.disabled(store.locked || memoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let message { Label(message, systemImage: "info.circle.fill").font(.subheadline).foregroundStyle(PivotTheme.amber) }
            DisclosureGroup("Modello locale e sicurezza") {
                modelCard
                Text("Le proposte restano locali. Il Calendario cambia solo dopo la tua conferma finale.").font(.caption).foregroundStyle(PivotTheme.muted)
            }.font(.subheadline)
        }
        .navigationTitle("Coach")
        .onChange(of: dictation.transcript) { _, value in if !value.isEmpty { input = dictationComposer.apply(transcript: value, to: input) } }
        .onChange(of: scenePhase) { _, phase in
            // Permission dialogs temporarily make the scene inactive. Let the
            // request finish; actual backgrounding or leaving still cancels it.
            if phase == .background || (phase == .inactive && dictation.isListening) { dictation.stop() }
            if phase == .background { cancelTurn() }
        }
        .onAppear { onlineCoach.reload() }
        .onReceive(NotificationCenter.default.publisher(for: OnlineCoachService.settingsChanged)) { _ in
            store.onlineConversationPermission.revoke(); cancelTurn(); onlineCoach.reload()
        }
        .onDisappear { dictation.stop(); coachModel.pauseAndUnload(); cancelTurn() }
        .toolbar { Button { Task { await calendar.refresh(settings: store.data.settings) } } label: { Image(systemName: "arrow.clockwise") } }
        .sheet(item: $responseRecord, onDismiss: {
            if returnHomeAfterResponse { returnHomeAfterResponse = false; dismiss() }
        }) { record in
            NavigationStack { EventDetailView(event: record.snapshot, initial: record, rule: store.rule(for: record.snapshot), onSaved: { returnHomeAfterResponse = true }) }.presentationDragIndicator(.visible)
        }
        .sheet(item: $onlineReview) { review in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Autorizza questa conversazione").font(.headline)
                        Text("Questo messaggio, il suo eventuale riordino e i successivi messaggi online di oggi useranno le categorie di dati indicate sotto, senza chiedere conferma ogni volta. Vale finché Pivot resta in esecuzione; puoi interrompere gli invii diretti dal Coach. Le modifiche al calendario richiedono sempre una conferma separata.")
                            .font(.subheadline)
                        CoachCloudDisclosure(request: review.snapshot.request)
                        Button("Autorizza conversazione e invia") { sendReviewed(review) }
                            .buttonStyle(PivotPrimaryButton()).accessibilityIdentifier("coach-online-approve")
                        Button("Annulla e modifica") { onlineReview = nil }
                            .buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("coach-online-review-cancel")
                    }.padding()
                }.navigationTitle("Prima dell’invio")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { onlineReview = nil } } }
            }.interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showOnlineData) {
            NavigationStack {
                ScrollView {
                    if let request = lastAuthorizedRequest {
                        CoachCloudDisclosure(request: request).padding()
                    } else {
                        Text("Nessuna richiesta autorizzata in questa schermata. Il primo invio ti mostrerà il messaggio e i dati inclusi.").padding()
                    }
                }.navigationTitle("Ultima richiesta autorizzata")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { showOnlineData = false } } }
            }
        }
        .sheet(item: $calendarDraft) { savedDraft in
            CoachCalendarDraftView(draft: savedDraft.draft, savedDraftID: savedDraft.id, initialCalendarID: savedDraft.calendarID,
                sourceMessage: state.messages.first(where: { $0.id == savedDraft.userMessageID })?.text ?? "") { event, existing in
                let text = existing ? "Questo impegno era già presente: non ne ho creata un'altra copia." : "Impegno creato nel Calendario: \(event.title)."
                let saved = store.change { data in
                    _ = CoachDraftStore.markCreated(id: savedDraft.id, eventID: event.id, calendarID: event.calendarIdentifier, data: &data)
                    data.coachState.messages.append(.init(dayKey: PivotDate.key(Date()), role: .coach, text: text, onlineHistoryEligible: false))
                }
                message = saved ? text : text + " Non riesco ancora a salvare il resoconto in Pivot."
            }
        }
        .confirmationDialog("Eliminare questa conversazione? Anche il resoconto non la includerà più.", isPresented: $deleteHistory, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                let key = PivotDate.key(historyDay)
                store.change { data in var coach = data.coachState; coach.messages.removeAll { $0.dayKey == key }; coach.calendarDrafts?.removeAll { $0.dayKey == key }; data.coachState = coach }
                if key == PivotDate.key(Date()) { store.onlineConversationPermission.revoke() }
            }
        }
        .confirmationDialog("Hai già del testo da inviare. Come vuoi riutilizzare il messaggio?", isPresented: $confirmReuse, titleVisibility: .visible) {
            Button("Sostituisci il testo") { if let reuseText { input = reuseText; originalDictation = nil; composerFocused = true }; reuseText = nil }
            Button("Aggiungi in fondo") { if let reuseText { input += "\n" + reuseText; originalDictation = nil; composerFocused = true }; reuseText = nil }
            Button("Annulla", role: .cancel) { reuseText = nil }
        }
    }

    private var onlineStatusCard: some View {
        PivotCard(tint: PivotTheme.blue) {
            Label(onlineCoach.isConfigured && !useLocal ? "AI online" : "Base locale", systemImage: onlineCoach.isConfigured && !useLocal ? "network" : "iphone")
                .font(.headline).accessibilityIdentifier("coach-online-mode")
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--online-coach-review-test") {
                Text("Richieste sintetiche: \(onlineCoach.interactionRequestCount)")
                    .accessibilityIdentifier("coach-online-fixture-requests")
            }
            #endif
            if onlineCoach.isConfigured && !useLocal {
                Text("Conversazione, riordino del testo e bozze per nuovi impegni. Spostamenti verificati per pranzo e palestra di oggi; recuperi multigiorno, cancellazioni e tragitti automatici non sono ancora disponibili.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                Button("Dati inviati") { showOnlineData = true }
                    .accessibilityIdentifier("coach-online-data")
                if store.onlineConversationPermission.allows(dayKey: PivotDate.key(Date())) {
                    Text("Invii diretti autorizzati per questa conversazione.").font(.caption).foregroundStyle(PivotTheme.accent)
                        .accessibilityIdentifier("coach-online-conversation-authorized")
                    Button("Interrompi invii diretti") { store.onlineConversationPermission.revoke(); cancelTurn() }
                        .accessibilityIdentifier("coach-online-revoke")
                }
            }
            if let failure = onlineCoach.failure {
                Text(failure.errorDescription ?? "AI online non disponibile").font(.subheadline)
                    .accessibilityIdentifier("coach-online-error")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let label = failure.timingLabel(at: context.date) {
                        Text(label).font(.subheadline.monospacedDigit()).accessibilityIdentifier("coach-online-countdown")
                    }
                }
                if let retryAt = failure.retryAt, retryAt > Date() {
                    Text("Orario per riprovare: " + DisplayDate.label(retryAt, format: "d MMM · HH:mm"))
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                    Button("Avvisami quando posso riprovare") { Task { await onlineCoach.notifyWhenRetryIsPossible() } }
                        .buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("coach-online-notify")
                }
            }
            if onlineCoach.isConfigured {
                Button(useLocal ? "Usa AI online" : "Continua con la base locale") {
                    store.onlineConversationPermission.revoke(); useLocal.toggle(); cancelTurn()
                }
                    .buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("coach-online-local-toggle")
                Text("La base locale usa le regole di pianificazione disponibili; non ha la stessa comprensione della conversazione online.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            } else {
                Text("L'AI online non è ancora collegata. Puoi usare le regole locali; configura il collegamento qui sotto per attivare la conversazione online.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            }
            NavigationLink { OnlineCoachSettingsView() } label: { Label("AI online e privacy", systemImage: "lock.shield") }
                .accessibilityIdentifier("coach-online-settings")
            if let status = onlineCoach.configurationMessage { Text(status).font(.caption).foregroundStyle(PivotTheme.muted) }
        }
    }

    private var dictationContext: [String] {
        var values = ["Pivot", "palestra", "allenamento", "sonno", "sveglia", "calendario", "università", "ripetizioni"]
        values.append(contentsOf: store.data.clients.map(\.name))
        values.append(contentsOf: calendar.choices.map(\.title))
        values.append(contentsOf: agenda.planned.filter { abs($0.start.timeIntervalSinceNow) < 14 * 86_400 }.map(\.title))
        var seen = Set<String>()
        return values.compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else { return nil }
            return clean
        }.prefix(100).map { $0 }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Da applicare al Calendario", detail: "\(state.pendingCalendarChanges.count)")
            ForEach(state.pendingCalendarChanges) { change in
                PivotCard(tint: PivotTheme.amber) {
                    Label(change.move.source.title, systemImage: "calendar.badge.clock").font(.headline).foregroundStyle(PivotTheme.amber)
                    Text("Prima: \(PivotDate.shortDate(change.move.source.start)) · \(PivotDate.time(change.move.source.start))–\(PivotDate.time(change.move.source.end))")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                    Text("Dopo: \(PivotDate.shortDate(change.move.proposedStart)) · \(PivotDate.time(change.move.proposedStart))–\(PivotDate.time(change.move.proposedEnd))")
                        .font(.subheadline.weight(.semibold))
                    if let conflict = change.conflictMessage { Text(conflict).font(.caption).foregroundStyle(Color.red) }
                    Button { Task { await apply(change) } } label: {
                        Label(applyingID == change.id ? "Applicazione…" : "Conferma nel Calendario", systemImage: "checkmark.circle.fill")
                    }.buttonStyle(PivotPrimaryButton(color: PivotTheme.amber)).disabled(applyingID != nil || !change.move.source.writable)
                    Button("Lascia solo in Pivot") { discard(change) }.buttonStyle(PivotSecondaryButton()).disabled(applyingID != nil)
                }
            }
        }
    }

    private var modelCard: some View {
        PivotCard(tint: PivotTheme.blue) {
            switch coachModel.status {
            case .ready:
                Label("Modello locale attivo", systemImage: "cpu.fill").font(.headline).foregroundStyle(PivotTheme.blue)
                Text("Qwen3 0,6B può consigliare una delle soluzioni verificate. Non può inventare orari né applicare modifiche. Se la risposta non supera i controlli, resta il pianificatore sicuro.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                Button(coachModel.isGenerating ? "Modello impegnato…" : "Test su questo iPhone") { Task { await coachModel.testOnDevice() } }
                    .buttonStyle(PivotSecondaryButton()).disabled(coachModel.isGenerating)
            case .downloading(let progress):
                Label("Download e caricamento del modello", systemImage: "arrow.down.circle.fill").font(.headline)
                ProgressView(value: progress)
                Text(progress == 0 ? "Download in corso: tieni Pivot aperto. La percentuale si aggiorna al termine del trasferimento." : "Verifica di integrità e caricamento…").font(.caption).foregroundStyle(PivotTheme.muted)
            case .failed(let error):
                Label("Modello locale non disponibile", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(PivotTheme.amber)
                Text(error).font(.caption).foregroundStyle(PivotTheme.muted)
                Button("Riprova") { Task { await coachModel.load() } }.buttonStyle(PivotSecondaryButton())
            case .notLoaded:
                Label("Suggerimenti AI opzionali", systemImage: "cpu").font(.headline).foregroundStyle(PivotTheme.blue)
                Text(coachModel.hasDownloadedModel ? "Il modello è già scaricato. Attivalo quando vuoi un suggerimento AI; la memoria viene liberata quando lasci questa schermata." : "Scarica una volta Qwen3 0,6B (397 MB). Il file viene verificato e resta sul telefono. Senza modello, il Coach funziona con le regole verificate.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                Button(coachModel.hasDownloadedModel ? "Attiva AI già scaricata" : "Scarica e attiva") { Task { await coachModel.load() } }.buttonStyle(PivotSecondaryButton())
            case .unavailable:
                Label("Modalità sicura attiva", systemImage: "checkmark.shield.fill").font(.headline)
                Text("Questa build usa il motore deterministico; nessuna funzione di pianificazione è bloccata.").font(.caption).foregroundStyle(PivotTheme.muted)
            }
            if let report = coachModel.performanceReport { Text(report).font(.caption).foregroundStyle(PivotTheme.muted) }
        }
    }

    private func bubble(_ item: CoachMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack {
            if item.role == .user { Spacer(minLength: 42) }
            Text(item.text).font(.subheadline).padding(13)
                .accessibilityIdentifier(item.role == .user ? "coach-user-message" : "coach-assistant-message")
                .background(item.role == .user ? PivotTheme.accent.opacity(0.18) : PivotTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 560, alignment: item.role == .user ? .trailing : .leading)
                .contextMenu {
                    Button { UIPasteboard.general.setItems([["public.utf8-plain-text": item.text]], options: [.localOnly: true]) } label: { Label("Copia", systemImage: "doc.on.doc") }
                    if item.role == .user {
                        Button {
                            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { input = item.text; originalDictation = nil; composerFocused = true }
                            else { reuseText = item.text; confirmReuse = true }
                        } label: { Label("Modifica e riutilizza", systemImage: "square.and.pencil") }
                        .disabled(isPlanning || dictation.isListening || store.locked)
                    }
                }
            if item.role != .user { Spacer(minLength: 42) }
        }
        if let saved = state.calendarDrafts?.first(where: { $0.messageID == item.id }) {
            CoachDraftCard(saved: saved) { calendarDraft = saved }
        }
        }
    }

    private func optionCard(_ option: CoachOption) -> some View {
        PivotCard(tint: PivotTheme.blue) {
            Label(option.title, systemImage: "sparkles").font(.headline).foregroundStyle(PivotTheme.blue)
            Text(option.explanation).font(.subheadline)
            Text(option.consequences).font(.caption).foregroundStyle(PivotTheme.muted)
            Button("Applica solo in Pivot") { accept(option) }.buttonStyle(PivotPrimaryButton())
            Button("Scarta proposta") { reject(option) }.buttonStyle(PivotSecondaryButton())
        }
    }

    private func send(_ text: String, targetID: String? = nil) {
        guard !isPlanning else { return }
        turnGeneration += 1
        let generation = turnGeneration
        isPlanning = true
        turnTask = Task {
            await sendInBackground(text, targetID: targetID)
            guard generation == turnGeneration else { return }
            isPlanning = false; turnTask = nil
        }
    }
    private func finishDictation() {
        dictation.stop()
        input = dictationComposer.apply(transcript: dictation.transcript, to: input)
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--dictation-pause-test") { return }
        #endif
        startRewrite()
    }

    private func startRewrite() {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isPlanning, !dictation.isListening, !store.locked else { return }
        guard onlineCoach.isConfigured, !useLocal else {
            message = "Il dettato è conservato. Per riordinarlo con l'AI serve il collegamento online."; return
        }
        turnGeneration += 1
        let generation = turnGeneration
        isPlanning = true; message = nil
        turnTask = Task {
            await sendOnline(clean, now: Date(), purpose: "rewrite")
            guard generation == turnGeneration else { return }
            isPlanning = false; turnTask = nil
        }
    }

    private func cancelTurn() {
        turnGeneration += 1
        turnTask?.cancel(); turnTask = nil; isPlanning = false
        onlineCoach.cancel()
        onlineReview = nil
    }

    private func sendReviewed(_ review: OnlineCoachReview) {
        onlineReview = nil
        guard !isPlanning, !store.locked, !useLocal, onlineCoach.isConfigured else { return }
        store.onlineConversationPermission.authorize(dayKey: review.snapshot.request.dayKey)
        turnGeneration += 1
        let generation = turnGeneration
        isPlanning = true
        turnTask = Task {
            await sendOnline(review.originalMessage, now: review.snapshot.request.now, approved: review.snapshot,
                             purpose: review.snapshot.request.purpose ?? "conversation", rewrite: review.rewrite)
            guard generation == turnGeneration else { return }
            isPlanning = false; turnTask = nil
        }
    }
    private func sendInBackground(_ text: String, targetID: String?) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !store.locked, !coachModel.isGenerating, !Task.isCancelled else { return }
        let now = Date()
        historyDay = now
        if let start = WorkoutContext.statedStart(clean, now: now) {
            let candidates = agenda.effective.filter { $0.kind == .workout && CardioKind.suggested($0.title) == nil && $0.occurs(on: start) }
            if candidates.count == 1, let event = candidates.first, store.data.actualWorkoutDraft == nil {
                prepareActual(event, workout: nil, start: start)
                store.change { data in var coach = data.coachState; coach.messages.append(.init(dayKey: PivotDate.key(now), role: .user, text: clean)); data.coachState = coach }
                input = ""; return
            }
            message = "Ci sono più allenamenti, nessun evento palestra oppure una conferma già aperta. Completa la proposta o apri l’attività precisa: non ne scelgo una a caso."
            return
        }
        if onlineCoach.isConfigured && !useLocal && targetID == nil && contextEventID == nil {
            await sendOnline(clean, now: now)
            return
        }
        var verified: CoachTurnResult?
        let target = targetID ?? contextEventID
        let started = ProcessInfo.processInfo.systemUptime
        for _ in 0..<3 {
            let snapshot = store.data, events = calendar.events, version = store.data.updatedAt
            let result = await Task.detached(priority: .userInitiated) {
                CoachPlanner.respond(message: clean, events: events, data: snapshot, now: now, targetID: target)
            }.value
            guard !store.locked, !store.isRestoring, !Task.isCancelled else { return }
            if version == store.data.updatedAt && events == calendar.events { verified = result; break }
        }
        store.diagnostics.record("Pianificatore Coach", seconds: ProcessInfo.processInfo.systemUptime - started)
        guard let result = verified else { message = "Il programma sta cambiando. Riprova fra un momento: nessuna proposta precedente è stata applicata."; return }
        let context = contextForModel(now: now)
        let coachReplyID = UUID()
        guard store.change({ data in
            var coach = data.coachState
            coach.messages.append(.init(dayKey: PivotDate.key(now), role: .user, text: clean, createdAt: now))
            coach.messages.append(.init(id: coachReplyID, dayKey: PivotDate.key(now), role: .coach, text: result.reply, createdAt: now))
            coach.options = result.options
            data.coachState = coach
        }) else { message = "Messaggio non salvato. Riprova."; return }
        guard await store.flushPendingWrites() else {
            message = "La conversazione è ancora in memoria, ma non è salvata su disco. Tieni Pivot aperto e riprova il salvataggio nelle Impostazioni."
            return
        }
        guard !Task.isCancelled else { return }
        if coachModel.isReady {
            Task {
                guard let comment = await coachModel.comment(userMessage: clean, verified: result, context: context) else { return }
                // Calendar edits or an accepted/discarded option invalidate a delayed suggestion.
                guard result.options.allSatisfy({ CoachPlanner.validate($0, events: calendar.events, data: store.data, now: Date()) == nil }) else { return }
                store.change { data in
                    var coach = data.coachState
                    guard coach.messages.contains(where: { $0.id == coachReplyID }),
                          result.options.allSatisfy({ option in coach.options.contains(where: { $0.id == option.id }) }) else { return }
                    coach.messages.append(.init(dayKey: PivotDate.key(now), role: .coach, text: "Suggerimento AI locale (scelta da valutare):\n" + comment))
                    data.coachState = coach
                }
            }
        }
        input = ""
        message = result.options.isEmpty ? "Nessuna modifica è stata preparata." : nil
    }

    private func sendOnline(_ clean: String, now: Date, approved: CoachV8Snapshot? = nil,
                            purpose: String = "conversation", rewrite: CoachRewriteDraft? = nil) async {
        do {
            try Task.checkCancellation()
            var authorizedSnapshot = approved
            var rewriteDraft = rewrite
            if let approved {
                await calendar.refresh(settings: store.data.settings)
                try Task.checkCancellation()
                guard approved.isCurrent(events: calendar.events, data: store.data, now: Date()) else { throw CoachV8Error.staleContext }
            } else {
                // No provider request is made while preparing the on-device review.
                // A known quota failure also avoids an unnecessary calendar refresh.
                if let failure = onlineCoach.failure, let seconds = failure.remaining(at: Date()), seconds > 0 { throw failure }
                await calendar.refresh(settings: store.data.settings)
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--online-coach-preflight-test") {
                    // A slow UI runner must not turn an unfinished preflight
                    // into a provider error. Only cancellation releases it.
                    while !Task.isCancelled { try await Task.sleep(nanoseconds: 1_000_000_000) }
                    try Task.checkCancellation()
                }
                #endif
                try Task.checkCancellation()
                let snapshotData = store.data, events = calendar.events
                let preparedRewrite = purpose == "rewrite" ? CoachRewriteDraft(original: clean, events: events, data: snapshotData) : nil
                let outbound = preparedRewrite?.message ?? clean
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try CoachV8Snapshot.make(message: outbound, events: events, data: snapshotData, now: now, purpose: purpose)
                }.value
                rewriteDraft = preparedRewrite
                try Task.checkCancellation()
                guard snapshot.isCurrent(events: calendar.events, data: store.data, now: Date()) else { throw CoachV8Error.staleContext }
                if store.onlineConversationPermission.allows(dayKey: snapshot.request.dayKey) {
                    authorizedSnapshot = snapshot
                } else {
                    onlineReview = .init(snapshot: snapshot, originalMessage: clean, rewrite: preparedRewrite)
                    return
                }
            }
            guard let snapshot = authorizedSnapshot,
                  store.onlineConversationPermission.allows(dayKey: snapshot.request.dayKey) else { throw CoachV8Error.staleContext }
            // First message: exact reviewed bytes. Following messages: the same
            // bounded data policy, authorized for this conversation, freshly checked.
            lastAuthorizedRequest = snapshot.request
            let response = try await onlineCoach.ask(snapshot)
            guard !store.locked, !store.isRestoring, !Task.isCancelled else { return }
            if purpose == "rewrite" {
                guard response.mode == .rewrite, let rewriteDraft, let rewritten = response.rewrittenMessage else { throw CoachV8Error.invalidResponse }
                let restored = try rewriteDraft.restore(rewritten)
                guard input.trimmingCharacters(in: .whitespacesAndNewlines) == clean else {
                    message = "Hai modificato il testo durante il riordino: non l'ho sovrascritto. Puoi riprovare."; return
                }
                originalDictation = clean; input = restored
                message = "Testo riordinato. Controllalo prima di premere Invia."
                return
            }
            let currentData = store.data, currentEvents = calendar.events, currentTime = Date()
            let result = try await Task.detached(priority: .userInitiated) {
                try CoachV8Planner.preview(response, snapshot: snapshot, events: currentEvents, data: currentData, now: currentTime)
            }.value
            try Task.checkCancellation()
            guard snapshot.isCurrent(events: calendar.events, data: store.data, now: Date()) else { throw CoachV8Error.staleContext }
            let replyMessage = CoachMessage(dayKey: PivotDate.key(now), role: .coach, text: result.reply, onlineHistoryEligible: response.mode != .plan)
            let userMessage = CoachMessage(dayKey: PivotDate.key(now), role: .user, text: clean, createdAt: now, onlineHistoryEligible: true)
            var savedDraft: CoachSavedCalendarDraft?
            if var draft = response.draft, response.mode == .create {
                for (index, client) in store.data.clients.enumerated() {
                    let alias = "[contatto \(index + 1)]"
                    draft.title = draft.title.replacingOccurrences(of: alias, with: client.name)
                    draft.notes = draft.notes.replacingOccurrences(of: alias, with: client.name)
                    draft.calendarHint = draft.calendarHint?.replacingOccurrences(of: alias, with: client.name)
                }
                savedDraft = CoachSavedCalendarDraft(messageID: replyMessage.id, userMessageID: userMessage.id, dayKey: replyMessage.dayKey, draft: draft)
            }
            guard store.change({ data in
                var coach = data.coachState
                coach.messages.append(userMessage)
                // Plan validation may mention a private local event title. Only
                // provider conversation/clarification prose is safe for history.
                coach.messages.append(replyMessage)
                if let savedDraft { var drafts = coach.calendarDrafts ?? []; drafts.append(savedDraft); coach.calendarDrafts = drafts }
                coach.options = result.options
                data.coachState = coach
            }) else { message = "Non riesco a salvare la conversazione. Il messaggio resta qui."; return }
            guard await store.flushPendingWrites() else {
                message = "La conversazione è ancora in memoria, ma non è salvata su disco. Tieni Pivot aperto e riprova il salvataggio nelle Impostazioni."
                return
            }
            try Task.checkCancellation()
            if input.trimmingCharacters(in: .whitespacesAndNewlines) == clean { input = ""; originalDictation = nil }
            if let savedDraft { calendarDraft = savedDraft }
            message = response.mode == .create ? "Bozza pronta: controllala prima di creare l'impegno." :
                (result.options.isEmpty ? "Nessuna modifica è stata preparata." : nil)
        } catch let failure as CoachOnlineFailure {
            guard !Task.isCancelled else { return }
            // Keep the composer intact; retries are manual and never queued invisibly.
            message = failure.errorDescription
        } catch let problem as CoachV8Error {
            guard !Task.isCancelled else { return }
            message = problem.errorDescription
        } catch {
            guard !Task.isCancelled else { return }
            message = "L'AI online non è disponibile. Il messaggio resta qui; puoi continuare con la base locale."
        }
    }

    private func prepareActual(_ event: CalendarItem, workout: HealthWorkoutSummary?, start: Date) {
        guard store.data.actualWorkoutDraft == nil else { return }
        let check = store.data.checkIns[PivotDate.key(start)]
        let context = agenda.effective
        let draft = ActualWorkoutDraft(source: event, health: workout, start: start, end: workout?.end,
            wake: check?.wakeTime.flatMap { $0 <= start ? $0 : nil }, bedtime: check?.sleep?.bedtime,
            breakfastDone: nil, breakfastStart: nil, breakfastEnd: nil, contextEvents: context.filter { $0.kind == .routine || $0.kind == .meal },
            healthDerived: workout != nil || check?.sleep?.importedFromHealth == true || check?.healthWakeTime != nil ? true : nil)
        store.change { data in
            data.actualWorkoutDraft = draft
            var coach = data.coachState; coach.messages.append(.init(dayKey: PivotDate.key(Date()), role: .coach,
                text: "Prima di aggiornare ‘\(event.title)’ alle \(PivotDate.time(start)), conferma fine dell’allenamento, sveglia reale, sonno e colazione nel riquadro. Nessun dato mancante sarà inventato.", healthDerived: draft.healthDerived)); data.coachState = coach
        }
    }
    private func accept(_ option: CoachOption) {
        guard !store.locked else { return }
        let now = Date()
        var failure: String?
        let saved = store.change { data in failure = CoachPlanner.accept(option, events: calendar.events, data: &data, now: now) }
        message = saved ? (failure ?? "Modifica applicata in Pivot. Il Calendario non è ancora cambiato.") : "Modifica non salvata. Riprova."
    }

    private func reject(_ option: CoachOption) {
        store.change { data in
            var coach = data.coachState
            coach.options.removeAll { $0.id == option.id }
            coach.messages.append(.init(dayKey: PivotDate.key(Date()), role: .system, text: "Proposta scartata: \(option.title)."))
            data.coachState = coach
        }
    }

    private func apply(_ change: PendingCalendarChange) async {
        guard !store.locked, !store.isRestoring, applyingID == nil else { return }
        applyingID = change.id
        defer { applyingID = nil }
        guard await store.flushPendingWrites() else { message = "Prima di aggiornare il Calendario completa il salvataggio nelle Impostazioni."; return }
        await calendar.refresh(settings: store.data.settings)
        do {
            let option = CoachOption(title: change.optionTitle, explanation: "", consequences: "", moves: [change.move])
            if let problem = CoachPlanner.validate(option, events: calendar.events, data: store.data, now: Date()) {
                throw NSError(domain: "PivotCoach", code: 1, userInfo: [NSLocalizedDescriptionKey: problem])
            }
            try await calendar.apply(change.move, data: store.data)
            guard store.change({ data in
                if let index = data.moves.firstIndex(where: { $0.id == change.move.id }) { data.moves[index].syncedToCalendar = true }
                var coach = data.coachState
                coach.pendingCalendarChanges.removeAll { $0.id == change.id }
                coach.messages.append(.init(dayKey: PivotDate.key(Date()), role: .system, text: "Calendario aggiornato: \(change.move.source.title)."))
                data.coachState = coach
            }) else {
                message = "Il Calendario è stato modificato, ma il salvataggio locale non è riuscito. Aggiorna prima di riprovare."; return
            }
            await calendar.refresh(settings: store.data.settings)
            message = "Calendario aggiornato. È stata modificata soltanto questa occorrenza."
        } catch {
            let text = error.localizedDescription
            store.change { data in
                var coach = data.coachState
                if let index = coach.pendingCalendarChanges.firstIndex(where: { $0.id == change.id }) { coach.pendingCalendarChanges[index].conflictMessage = text }
                data.coachState = coach
            }
            message = text
        }
    }

    private func discard(_ change: PendingCalendarChange) {
        store.change { data in
            var coach = data.coachState
            coach.pendingCalendarChanges.removeAll { $0.id == change.id }
            data.coachState = coach
        }
        message = "La modifica resta in Pivot e non verrà inviata al Calendario."
    }

    private func contextForModel(now: Date) -> String {
        let agenda = self.agenda.planned.filter { $0.occurs(on: now) }.prefix(8).map {
            "\(PivotDate.time($0.start))–\(PivotDate.time($0.end)) \(String($0.title.prefix(120))) [\(store.data.records[$0.id]?.status.label ?? "da compilare")]"
        }.joined(separator: "\n")
        let recent = state.messages.filter { $0.dayKey == PivotDate.key(now) }.suffix(4).map {
            "\($0.role.rawValue): \(String($0.text.prefix(350)))"
        }.joined(separator: "\n")
        let memory = state.memories.filter { $0.isActive(at: now) }.suffix(6).map { String($0.text.prefix(250)) }.joined(separator: "; ")
        let check = store.data.checkIns[PivotDate.key(now)]
        return "Ora: \(PivotDate.time(now)). Energia: \(check?.energyMorning.map(String.init) ?? "non indicata").\nAgenda:\n\(agenda)\nPreferenze dichiarate: \(memory)\nConversazione recente:\n\(recent)"
    }
}
