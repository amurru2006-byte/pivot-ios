import SwiftUI

struct CoachView: View {
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var coachModel: LocalCoachService
    @State private var input = ""
    @State private var memoryInput = ""
    @State private var historyDay = Date()
    @State private var deleteHistory = false
    @State private var message: String?
    @State private var applyingID: UUID?
    private var state: CoachState { store.data.coachState }
    private var todayMessages: [CoachMessage] { state.messages.filter { $0.dayKey == PivotDate.key(historyDay) } }
    private var missed: [CalendarItem] {
        Array(Planner.plannedEvents(calendar.events, data: store.data).filter {
            !$0.isAllDay && $0.occurs(on: Date()) && $0.end <= Date() && (store.data.records[$0.id]?.status ?? .pending) != .completed
                && (store.data.records[$0.id]?.status ?? .pending) != .partial
        }.suffix(4))
    }

    var body: some View {
        PivotScreen {
            PivotHeader(title: "Pivot Coach", subtitle: "Riorganizza senza perdere il controllo")
            PivotCard(tint: PivotTheme.accent) {
                Label("Prima Pivot, poi Calendario", systemImage: "checkmark.shield.fill").font(.headline).foregroundStyle(PivotTheme.accent)
                Text("Il Coach può preparare una modifica locale. Il Calendario cambia soltanto quando la controlli qui e confermi una seconda volta.")
                    .font(.subheadline).foregroundStyle(PivotTheme.muted)
            }
            modelCard

            if !state.pendingCalendarChanges.isEmpty { pendingSection }

            if !missed.isEmpty {
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

            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Conversazione")
                DaySelector(day: $historyDay)
                if todayMessages.isEmpty {
                    EmptyCard(title: "Raccontami cosa è cambiato", message: "Per esempio: “Ho saltato la palestra, riesco a recuperarla oggi?”", icon: "brain.head.profile")
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
                TextField("Scrivi cosa è saltato o cosa vuoi spostare…", text: $input, axis: .vertical)
                    .accessibilityIdentifier("coach-message-input")
                    .lineLimit(2...6).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                Button { send(input) } label: { Label("Invia al Coach", systemImage: "paperplane.fill") }
                    .accessibilityIdentifier("coach-send")
                    .buttonStyle(PivotPrimaryButton()).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.locked || coachModel.isGenerating)
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
        }
        .navigationTitle("Coach")
        .toolbar { Button { Task { await calendar.refresh(settings: store.data.settings) } } label: { Image(systemName: "arrow.clockwise") } }
        .confirmationDialog("Eliminare questa conversazione? Anche il resoconto non la includerà più.", isPresented: $deleteHistory, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                let key = PivotDate.key(historyDay)
                store.change { data in var coach = data.coachState; coach.messages.removeAll { $0.dayKey == key }; data.coachState = coach }
            }
        }
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
                Text("Scarica una volta Qwen3 0,6B (397 MB). Il file viene verificato e resta sul telefono. Senza modello, il Coach funziona con le regole verificate. Le prestazioni reali vanno provate sul tuo iPhone.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                Button("Scarica e attiva") { Task { await coachModel.load() } }.buttonStyle(PivotSecondaryButton())
            case .unavailable:
                Label("Modalità sicura attiva", systemImage: "checkmark.shield.fill").font(.headline)
                Text("Questa build usa il motore deterministico; nessuna funzione di pianificazione è bloccata.").font(.caption).foregroundStyle(PivotTheme.muted)
            }
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
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3000))
        guard !clean.isEmpty, !store.locked, !coachModel.isGenerating else { return }
        let now = Date()
        historyDay = now
        let result = CoachPlanner.respond(message: clean, events: calendar.events, data: store.data, now: now, targetID: targetID)
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
        let agenda = Planner.plannedEvents(calendar.events, data: store.data).filter { $0.occurs(on: now) }.prefix(8).map {
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
