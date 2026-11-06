import SwiftUI

struct CoachPlanningSessionView: View {
    let sessionID: UUID
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @State private var preparationIncluded = false
    @State private var options: [CoachOption] = []
    @State private var reviewed: Set<UUID> = []
    @State private var corrections: [UUID: String] = [:]
    @State private var message: String?
    @State private var planning = false
    @State private var task: Task<Void, Never>?
    @State private var preservedUpdate: Date?
    private var session: CoachPlanningSession? { store.data.coachState.planningSessions?.first { $0.id == sessionID } }

    var body: some View {
        PivotScreen {
            PivotHeader(title: "Il tuo piano", subtitle: "Controlliamo gli spazi reali. Il Calendario cambia soltanto dopo la tua conferma.")
            if let session {
                PivotCard {
                    ForEach(Array(session.intent.eventIDs.enumerated()), id: \.offset) { index, alias in
                        if let source = session.bindings[alias] {
                            Text("\(index + 1). \(source.title)").font(.headline)
                            Text("\(PivotDate.shortDate(source.start)) · \(source.durationMinutes) min").font(.subheadline)
                            if let group = session.groupSnapshots?.first(where: { $0.activity.id == source.id }) {
                                Text("Viaggio collegato: \(group.travel.title) · \(group.settings.minutes) min. Sarà incluso nella revisione finale; il tempo va verificato al nuovo orario.")
                                    .font(.caption).accessibilityIdentifier("coach-planning-linked-group")
                            }
                            if CoachPlanningDurationChoice.isEligible(source), session.status == .draft {
                                CoachPlanningDurationReview(sessionID: sessionID, source: source)
                            }
                            NavigationLink("Controlla attività e tragitti") {
                                EventDetailView(event: source, initial: store.record(for: source), rule: store.rule(for: source))
                            }.frame(minHeight: 44)
                        }
                    }
                    Text("Giorni: " + session.allowedDays.map(PivotDate.shortDate).joined(separator: ", "))
                        .accessibilityIdentifier("coach-planning-days")
                    if !session.excludedDays.isEmpty { Text("Esclusi: " + session.excludedDays.map(PivotDate.shortDate).joined(separator: ", ")) }
                    if let band = session.intent.band { Text("Fascia: " + band.label) }
                    if let minute = session.intent.earliestMinute { Text("Non prima delle \(minute / 60):\(String(format: "%02d", minute % 60))") }
                    if let minute = session.intent.latestMinute { Text("Entro le \(minute / 60):\(String(format: "%02d", minute % 60))") }
                    if let alias = session.intent.afterEventID, let reference = session.bindings[alias] { Text("Dopo: " + reference.title) }
                    if let pins = session.localPins, !pins.isEmpty {
                        Text("Scelte conservate nel piano").font(.headline).accessibilityIdentifier("coach-planning-saved-choices")
                        ForEach(pins, id: \.sourceID) { pin in
                            if let source = session.bindings.values.first(where: { $0.id == pin.sourceID }) {
                                Text(source.title + " · " + PivotDate.shortDate(pin.day) + (pin.start.map { " alle " + PivotDate.time($0) } ?? " · orario da cercare"))
                            }
                        }
                        Text("Restano valide anche riaprendo il piano o continuando la chat. Se l’agenda cambia, le ricontrollo senza spostarle automaticamente.").font(.caption)
                        if session.status == .draft {
                            Button("Rimuovi queste scelte di giorno e orario") { clearPins(session) }
                                .frame(minHeight: 44).disabled(planning || store.locked)
                                .accessibilityIdentifier("coach-planning-clear-choices")
                        }
                    }
                    if session.status == .staged {
                        Text("Alternativa preparata in Pivot. Restano le conferme finali per il Calendario.")
                        NavigationLink("Apri le conferme per il Calendario") { CoachView() }.frame(minHeight: 44)
                    } else if session.status == .dismissed {
                        Text("Piano archiviato. Nessun evento è stato cancellato.")
                    } else if !session.isActive(at: Date()) {
                        Text("La settimana di questo piano è terminata. Chiedi un nuovo piano: le date non vengono spostate automaticamente.")
                    } else if !session.pendingReadmittedDays.isEmpty {
                        Text("Questi giorni erano esclusi: " + session.pendingReadmittedDays.map(PivotDate.shortDate).joined(separator: ", "))
                            .foregroundStyle(PivotTheme.amber)
                        Button("Confermo di reincludere questi giorni") { readmit(session) }
                            .frame(minHeight: 44).disabled(store.locked).accessibilityIdentifier("coach-planning-readmit")
                    } else {
                        if session.groupSnapshots == nil,
                           session.bindings.values.contains(where: { CalendarActivityLinks.requiresPairedReview($0, data: store.data) }) {
                            Text("Verifica l’associazione salvata di attività e viaggio prima della ricerca. Le due parti saranno revisionate insieme.").font(.caption)
                            Button("Verifica e conserva il gruppo") { reviewGroups(session) }.frame(minHeight: 44)
                                .disabled(planning || store.locked).accessibilityIdentifier("coach-planning-verify-group")
                        }
                        Toggle("Le durate comprendono cambio e preparazione necessari", isOn: $preparationIncluded)
                            .accessibilityIdentifier("coach-planning-preparation")
                        Button("Cerca alternative") { search(session) }.buttonStyle(PivotPrimaryButton())
                            .disabled(!preparationIncluded || planning || store.locked).accessibilityIdentifier("coach-planning-search")
                        if planning { ProgressView("Confronto giorni e tragitti…") }
                    }
                }
                if session.status == .draft {
                    Text("Per cambiare giorni, fascia o ordine torna nella chat e continua questo piano. I vincoli restano salvati; questa ricerca è locale e non usa token AI.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                }
                ForEach(options) { option in
                    PivotCard(tint: PivotTheme.blue) {
                        Text(option.explanation).font(.headline)
                        Text(option.consequences).font(.subheadline).foregroundStyle(PivotTheme.muted)
                        TextField("Es. sposta il secondo a venerdì alle 16:30", text: Binding(
                            get: { corrections[option.id] ?? "" }, set: { corrections[option.id] = $0 }))
                            .textFieldStyle(.roundedBorder).accessibilityIdentifier("coach-planning-correction")
                        Text("Puoi usare il nome esatto dell’attività. Le altre restano agli orari mostrati; salvo queste scelte nel piano. Giorni esclusi e ordine restano validi.")
                            .font(.caption).foregroundStyle(PivotTheme.muted)
                        Button("Ricalcola questa alternativa") { refine(option, session: session) }
                            .frame(minHeight: 44).disabled(planning || store.locked || (corrections[option.id] ?? "").isEmpty)
                            .accessibilityIdentifier("coach-planning-refine")
                        ForEach(option.moves) { move in
                            if session.groupSnapshots?.contains(where: { $0.activity.id == move.source.id }) == true {
                                Text("Il viaggio di ‘\(move.source.title)’ si verifica insieme all’attività nell’anteprima finale, con un tempo manuale o Maps per il nuovo orario.")
                                    .font(.caption).foregroundStyle(PivotTheme.muted)
                            } else if !move.source.location.isEmpty {
                                NavigationLink { TravelCalculatorView(destination: move.source.location, date: move.proposedStart, timing: .arriveBy,
                                    nextStart: move.proposedStart, context: .init(events: [move.source])) } label: {
                                    Label("Controlla tragitto: " + move.source.title, systemImage: "map")
                                }.frame(minHeight: 44)
                            }
                        }
                        Toggle((session.groupSnapshots ?? []).isEmpty ? "Confermo ordine, durate e tragitti per questi orari" : "Confermo ordine, durate e stime di viaggio da verificare", isOn: Binding(get: { reviewed.contains(option.id) }, set: {
                            if $0 { reviewed.insert(option.id) } else { reviewed.remove(option.id) }
                        })).accessibilityIdentifier("coach-planning-route-review")
                        Button(CoachPlanningLogistics.hasSpecialReview(session) ? "Prepara l’anteprima finale" : "Scegli questa alternativa in Pivot") { stage(option, session: session) }.buttonStyle(PivotPrimaryButton())
                            .disabled(store.locked || !reviewed.contains(option.id)).accessibilityIdentifier("coach-planning-stage")
                    }
                }
                if session.status == .draft {
                    Button("Archivia questo piano", role: .destructive) {
                        store.change { data in
                            if let index = data.coachState.planningSessions?.firstIndex(where: { $0.id == sessionID }) { data.coachState.planningSessions?[index].status = .dismissed }
                            if data.coachState.focusedPlanningSessionID == sessionID { data.coachState.focusedPlanningSessionID = nil }
                        }
                    }.frame(minHeight: 44).disabled(store.locked || planning)
                }
            } else { Text("Questo piano non è più disponibile.") }
            if let message { Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("coach-planning-message") }
        }.navigationTitle("Piano di recupero")
            .onChange(of: preparationIncluded) { _, _ in invalidate() }
            .onChange(of: store.data.updatedAt) { _, value in
                if preservedUpdate == value { preservedUpdate = nil } else { invalidate() }
            }
            .onChange(of: calendar.events) { _, _ in invalidate() }
            .onChange(of: session?.durationChoices) { _, _ in preparationIncluded = false; invalidate() }
            .onChange(of: session?.groupSnapshots) { _, _ in preparationIncluded = false; invalidate() }
            .onDisappear { task?.cancel(); planning = false }
    }
    private func invalidate() { task?.cancel(); planning = false; options = []; reviewed = []; corrections = [:]; preservedUpdate = nil }
    private func refine(_ option: CoachOption, session: CoachPlanningSession) {
        guard !store.locked, !store.isRestoring, !planning else { return }
        do {
            let request = try CoachPlanningRefinement.parse(corrections[option.id] ?? "", sources: option.moves.map(\.source))
            let data = store.data, events = calendar.events, access = calendar.hasAccess, now = Date()
            planning = true; message = nil
            task = Task { @MainActor in
                do {
                    let worker = Task.detached(priority: .userInitiated) {
                        try CoachPlanningRefinement.revise(request, option: option, session: session,
                            events: events, data: data, calendarAccess: access, now: now,
                            isCancelled: { Task<Never, Never>.isCancelled })
                    }
                    let revised = try await withTaskCancellationHandler(operation: { try await worker.value },
                                                                      onCancel: { worker.cancel() })
                    guard !Task.isCancelled else { return }
                    planning = false
                    guard data.updatedAt == store.data.updatedAt, events == calendar.events, !store.locked,
                          !store.isRestoring, calendar.hasAccess, options.contains(where: { $0.id == option.id }),
                          Date().timeIntervalSince(revised.option.createdAt) <= 120,
                          CoachPlanningLogistics.validate(revised.option, session: revised.session, events: calendar.events, data: store.data, now: Date()) == nil else {
                        message = "L’agenda o i permessi sono cambiati: nessuna correzione salvata. Cerca nuovamente."; return
                    }
                    var failure: String?
                    let saved = store.change { value in
                        do { try CoachPlanningStore.save(revised.session, in: &value.coachState) }
                        catch { failure = error.localizedDescription }
                    }
                    guard saved, failure == nil else { message = failure ?? "Non riesco a salvare le scelte."; return }
                    preservedUpdate = store.data.updatedAt
                    options = [revised.option]; reviewed = []; corrections = [:]
                    message = "Scelte conservate nel piano. Le altre attività sono rimaste ferme; ricontrolla i tragitti prima di scegliere. Il Calendario non è cambiato."
                    if !(await store.flushPendingWrites()) {
                        message = "Scelte ancora in memoria: il salvataggio su disco non è riuscito. Tieni Pivot aperto e riprova il salvataggio nelle Impostazioni."
                    }
                } catch { guard !Task.isCancelled else { return }; planning = false; message = error.localizedDescription }
            }
        } catch { message = error.localizedDescription }
    }
    private func clearPins(_ value: CoachPlanningSession) {
        guard !store.locked, !store.isRestoring, !planning else { return }
        do {
            var next = value; next.localPins = nil; next.updatedAt = Date()
            guard next.isActive(at: next.updatedAt) else { throw CoachPlanningSession.Failure.expired }
            var state = store.data.coachState; try CoachPlanningStore.save(next, in: &state)
            guard store.change({ $0.coachState = state }) else { message = "Non riesco a salvare la modifica."; return }
            invalidate()
            message = "Rimosse soltanto le scelte locali di giorno e orario. Giorni esclusi, ordine, durate e Calendario restano invariati."
        } catch { message = error.localizedDescription }
    }
    private func reviewGroups(_ value: CoachPlanningSession) {
        guard !store.locked, !store.isRestoring, !planning, calendar.hasAccess else { return }
        do {
            let now = Date(); _ = try value.boundEvents(in: calendar.events, now: now)
            var next = value
            next.groupSnapshots = try CoachPlanningLogistics.capture(sources: value.intent.eventIDs.compactMap { value.bindings[$0] },
                events: calendar.events, data: store.data)
            next.updatedAt = now
            var state = store.data.coachState; try CoachPlanningStore.save(next, in: &state)
            guard store.change({ $0.coachState = state }) else { message = "Non riesco a salvare la verifica."; return }
            message = "Gruppo conservato nel piano. Verifica di nuovo preparazione e tragitti prima di scegliere gli orari."
        } catch { message = error.localizedDescription }
    }
    private func readmit(_ value: CoachPlanningSession) {
        do {
            var next = value; try next.confirmReadmittedDays(now: Date())
            var state = store.data.coachState; try CoachPlanningStore.save(next, in: &state)
            store.change { $0.coachState = state }
        } catch { message = error.localizedDescription }
    }
    private func search(_ value: CoachPlanningSession) {
        invalidate(); message = nil; planning = true
        task = Task { @MainActor in
            guard !Task.isCancelled, !store.locked, !store.isRestoring else { planning = false; return }
            let data = store.data, events = calendar.events, access = calendar.hasAccess, now = Date()
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try CoachPlanningAlternatives.search(for: value, calendarAccess: access, events: events,
                        data: data, now: now, preparationIncluded: true,
                        isCancelled: { Task<Never, Never>.isCancelled })
                }
                let result = try await withTaskCancellationHandler(operation: { try await worker.value },
                                                                  onCancel: { worker.cancel() })
                guard !Task.isCancelled else { return }
                planning = false
                guard data.updatedAt == store.data.updatedAt, events == calendar.events, !store.locked else { message = "L’agenda è cambiata: ripeti la ricerca."; return }
                options = result.options
                switch result.state {
                case .limitReached: message = "Ho raggiunto il limite di ricerca locale. Le eventuali alternative mostrate sono verificate, ma potrei non averle trovate tutte. Puoi restringere giorni o fascia."
                case .cancelled: options = []; message = "Ricerca interrotta. Nessuna modifica preparata."
                case .notFoundWithinSearch: message = "Non ho trovato un’alternativa verificata. Controlla giorni, flessibilità e tragitti; questo non significa che l’agenda sia necessariamente piena."
                case .optionsFound: break
                }
            } catch { guard !Task.isCancelled else { return }; planning = false; message = error.localizedDescription }
        }
    }
    private func stage(_ option: CoachOption, session: CoachPlanningSession) {
        guard !store.locked, !store.isRestoring else { return }
        var failure: String?
        let access = calendar.hasAccess, events = calendar.events, reviewed = reviewed.contains(option.id)
        let saved = store.change { data in
            do { try CoachPlanningAlternatives.stage(option, session: session, calendarAccess: access, events: events,
                data: &data, now: Date(), preparationIncluded: preparationIncluded, routesReviewed: reviewed) }
            catch { failure = error.localizedDescription }
        }
        message = saved ? failure ?? "Alternativa preparata. Apri le conferme per aggiornare il Calendario." : "Non riesco a salvare la proposta."
    }
}
