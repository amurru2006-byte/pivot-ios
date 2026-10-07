import SwiftUI

struct CoachView: View {
    var contextEventID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var coachModel: LocalCoachService
    @EnvironmentObject private var agenda: AgendaService
    @State private var input = ""
    @State private var memoryInput = ""
    @State private var historyDay = Date()
    @State private var deleteHistory = false
    @State private var message: String?
    @State private var applyingID: UUID?
    @State private var isPlanning = false
    @State private var responseRecord: EventRecord?
    @State private var returnHomeAfterResponse = false
    @StateObject private var dictation = DictationService()
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
                    .accessibilityIdentifier("coach-message-input")
                    .lineLimit(2...6).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                HStack {
                    Button {
                        if dictation.isListening { dictation.stop() }
                        else {
                            dictationComposer.begin(currentText: input)
                            Task { await dictation.start(contextualPhrases: dictationContext) }
                        }
                    } label: { Label(dictation.isListening ? "Termina" : "Detta", systemImage: dictation.isListening ? "stop.circle.fill" : "mic.fill") }.buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("coach-dictation")
                    Button { dictation.stop(); send(input) } label: { Label("Invia", systemImage: "arrow.up") }
                    .accessibilityIdentifier("coach-send")
                    .buttonStyle(PivotPrimaryButton()).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.locked || coachModel.isGenerating || isPlanning)
                }
                if isPlanning { ProgressView("Controllo il programma…") }
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
                            Text(memory.text).font(.subheadline)
                            Spacer()
                            Button(role: .destructive) {
                                store.change { data in var coach = data.coachState; coach.memories.removeAll { $0.id == memory.id }; data.coachState = coach }
                            } label: { Image(systemName: "minus.circle") }
                        }.padding(.vertical, 5)
                    }
                    TextField("Una preferenza o un’informazione utile", text: $memoryInput, axis: .vertical)
                    Button("Ricorda questa informazione") {
                        let text = String(memoryInput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1500))
                        guard !text.isEmpty else { return }
                        if store.change({ data in var coach = data.coachState; coach.memories.append(CoachMemory(text: text)); data.coachState = coach }) { memoryInput = "" }
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
        }
        .onDisappear { dictation.stop(); coachModel.pauseAndUnload() }
        .toolbar { Button { Task { await calendar.refresh(settings: store.data.settings) } } label: { Image(systemName: "arrow.clockwise") } }
        .sheet(item: $responseRecord, onDismiss: {
            if returnHomeAfterResponse { returnHomeAfterResponse = false; dismiss() }
        }) { record in
            NavigationStack { EventDetailView(event: record.snapshot, initial: record, rule: store.rule(for: record.snapshot), onSaved: { returnHomeAfterResponse = true }) }.presentationDragIndicator(.visible)
        }
        .confirmationDialog("Eliminare questa conversazione? Anche il resoconto non la includerà più.", isPresented: $deleteHistory, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                let key = PivotDate.key(historyDay)
                store.change { data in var coach = data.coachState; coach.messages.removeAll { $0.dayKey == key }; data.coachState = coach }
            }
        }
    }

    private var dictationContext: [String] {
        var values = ["Pivot", "palestra", "allenamento", "sonno", "sveglia", "calendario", "università", "ripetizioni"]
        values.append(contentsOf: store.data.clients.map(\.name))
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
        HStack {
            if item.role == .user { Spacer(minLength: 42) }
            Text(item.text).font(.subheadline).padding(13)
                .background(item.role == .user ? PivotTheme.accent.opacity(0.18) : PivotTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 560, alignment: item.role == .user ? .trailing : .leading)
            if item.role != .user { Spacer(minLength: 42) }
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
        isPlanning = true
        Task { await sendInBackground(text, targetID: targetID); isPlanning = false }
    }
    private func sendInBackground(_ text: String, targetID: String?) async {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3000))
        guard !clean.isEmpty, !store.locked, !coachModel.isGenerating else { return }
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
        let memory = state.memories.suffix(6).map { String($0.text.prefix(250)) }.joined(separator: "; ")
        let check = store.data.checkIns[PivotDate.key(now)]
        return "Ora: \(PivotDate.time(now)). Energia: \(check?.energyMorning.map(String.init) ?? "non indicata").\nAgenda:\n\(agenda)\nPreferenze dichiarate: \(memory)\nConversazione recente:\n\(recent)"
    }
}

