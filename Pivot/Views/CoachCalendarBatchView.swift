import SwiftUI

struct CoachCalendarBatchView: View {
    let batchID: UUID
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = Set<UUID>()
    @State private var loaded = false
    @State private var busy = false
    @State private var problem: String?
    @State private var review: CalendarMutationReview?
    @State private var confirming = false
    @State private var task: Task<Void, Never>?
    @State private var travelTarget: CoachCalendarMutation?
    @State private var travelChoices: [String: CalendarCreationTravel] = [:]
    private var batch: CoachCalendarBatch? { store.data.coachState.calendarBatches?.first { $0.id == batchID } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            Form {
                if let batch {
                    if let problem {
                        Section {
                            Text(problem).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("coach-mutations-error")
                        }.id("coach-mutations-notice")
                    }
                    Section {
                        Text("Controlla ogni evento. Le cancellazioni riguardano solo questa occorrenza; incassi, diario e allenamenti in Pivot non vengono eliminati.").font(.subheadline)
                        Text("Se ripristini un evento eliminato, Pivot ne ricrea una copia singola: non riattiva una serie né reinvia inviti.").font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                    ForEach(batch.actions) { action in
                        Section(action.kind == .delete ? "Elimina evento" : "Modifica evento") {
                            if batch.status == .pending {
                                Toggle("Includi questa modifica", isOn: Binding(get: { selected.contains(action.id) }, set: { value in
                                    if value { selected.insert(action.id) } else { selected.remove(action.id) }
                                    review = nil
                                })).accessibilityIdentifier("coach-mutation-select-" + action.id.uuidString)
                            }
                            Text(action.source.title).font(.headline)
                            Text(action.source.calendarTitle + " · " + (action.source.sourceTitle ?? "")).font(.caption)
                            Text(DisplayDate.label(action.source.start, format: "d MMM yyyy HH:mm") + " – " + DisplayDate.label(action.source.end, format: "d MMM yyyy HH:mm")).font(.subheadline)
                            if let after = action.after {
                                Label("Diventa", systemImage: "arrow.down")
                                Text(after.title).font(.headline)
                                Text(DisplayDate.label(after.start, format: "d MMM yyyy HH:mm") + " – " + DisplayDate.label(after.end, format: "d MMM yyyy HH:mm")).font(.subheadline)
                                if after.notes != action.source.notes { Text(after.notes.isEmpty ? "Note da rimuovere" : after.notes).font(.caption) }
                                if let link = CalendarActivityLinks.link(for: action.source, data: store.data),
                                   CalendarSnapshotMatch.identity(link.activity, action.source),
                                   !CalendarSnapshotMatch.instant(after.start, action.source.start) {
                                    Button("Verifica viaggio collegato") { travelTarget = action }
                                        .accessibilityIdentifier("linked-travel-edit")
                                    Text("Il viaggio sarà incluso nella verifica. Puoi confermare un tempo manuale o ricalcolare con Maps.")
                                        .font(.caption).foregroundStyle(PivotTheme.muted)
                                }
                            }
                        }
                    }
                    if batch.status == .pending {
                        Button("Verifica \(selected.count) modifiche") { prepare(batch) }
                            .disabled(selected.isEmpty || busy || store.locked || calendar.mutationInProgress)
                            .accessibilityIdentifier("coach-mutations-review")
                        Button("Scarta tutte le proposte", role: .destructive) {
                            guard !busy else { return }
                            if store.change({ data in
                                if let index = data.coachState.calendarBatches?.firstIndex(where: { $0.id == batchID }) { data.coachState.calendarBatches?[index].status = .discarded }
                            }) { dismiss() }
                        }.accessibilityIdentifier("coach-mutations-discard")
                    } else {
                        Text(batch.status == .discarded ? "Proposte scartate: il Calendario non è stato modificato." : "Revisione conclusa. Trovi l’esito e le copie originali nello storico modifiche.")
                    }
                    NavigationLink { CalendarMutationHistoryView() } label: { Label("Storico modifiche", systemImage: "clock.arrow.circlepath") }
                } else { Text("Questa proposta non è più disponibile.") }
            }.disabled(busy)
                .onChange(of: problem) { _, value in
                    if value != nil { withAnimation { scroll.scrollTo("coach-mutations-notice", anchor: .top) } }
                }
                .navigationTitle("Modifiche proposte")
                .toolbar { Button("Chiudi") { task?.cancel(); dismiss() }.disabled(busy) }
                .task {
                    guard !loaded, let batch else { return }; loaded = true
                    selected = Set(batch.actions.map(\.id))
                    travelChoices = batch.linkedTravelChoices ?? [:]
                }
                .alert("Confermare le modifiche selezionate?", isPresented: $confirming) {
                    Button("Conferma modifiche", role: .destructive) { apply() }.accessibilityIdentifier("coach-mutations-confirm")
                    Button("Annulla", role: .cancel) { review = nil }
                } message: {
                    if let review {
                        let deletes = review.entries.filter { $0.kind == .delete }.count
                        Text("\(deletes) eliminazioni e \(review.entries.count - deletes) modifiche. Le proposte non selezionate non verranno applicate. " +
                             (review.conflicts.isEmpty ? "Nessuna sovrapposizione aggiuntiva rilevata." : "Sovrapposizioni: " + review.conflicts.map(\.title).joined(separator: ", ") + "."))
                    }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .background { task?.cancel(); confirming = false; review = nil } }
                .onDisappear { task?.cancel() }
                .sheet(item: $travelTarget) { action in
                    if let after = action.after, let link = CalendarActivityLinks.link(for: action.source, data: store.data) {
                        CalendarTravelEditor(options: travelOptions(link: link, destination: after.location), start: after.start,
                            suggestedOrigin: link.settings.origin) { options in
                            guard let travel = options.travel else { problem = "Conferma il viaggio, oppure scarta la proposta. Non lascio una metà del collegamento."; return }
                            saveTravelChoice(travel, link: link)
                        }
                    }
                }
            }
        }.interactiveDismissDisabled(busy)
    }
    private func prepare(_ batch: CoachCalendarBatch) {
        let actions = batch.actions.filter { selected.contains($0.id) }
        guard !busy, !actions.isEmpty else { return }
        busy = true; problem = nil
        task = Task {
            defer { busy = false }
            do {
                let expanded = try CalendarActivityLinks.expanded(actions, data: store.data, choices: travelChoices,
                    now: Date(), mapsConsent: AppleMapsService.shared.consentGranted)
                guard !store.locked, !store.isRestoring, self.batch?.status == .pending else { throw CalendarFailure.changed }
                let oldSelectedIDs = Set(actions.map(\.id))
                var updated = batch
                // Retain unselected independent proposals; replace the selected
                // group with the locally expanded, visibly reviewable pair.
                updated.actions = batch.actions.filter { old in !oldSelectedIDs.contains(old.id) && !expanded.contains(where: { $0.source.id == old.source.id }) } + expanded
                updated.linkedTravelChoices = travelChoices
                guard updated.isValid, store.change({ data in
                    if let index = data.coachState.calendarBatches?.firstIndex(where: { $0.id == batchID }) { data.coachState.calendarBatches?[index] = updated }
                }) else { throw CalendarFailure.archiveNotSaved }
                selected = Set(expanded.map(\.id))
                if expanded != actions {
                    problem = "Ho incluso il viaggio collegato. Controlla entrambi gli eventi qui sopra, poi premi di nuovo Verifica. Nessuna modifica applicata."
                    return
                }
                let value = try await calendar.reviewMutations(batchID: batch.id, actions: expanded, settings: store.data.settings)
                try Task.checkCancellation()
                guard self.batch?.status == .pending else { throw CalendarFailure.changed }
                review = value; confirming = true
            } catch is CancellationError { }
            catch { problem = error.localizedDescription }
        }
    }
    private func travelOptions(link: CalendarActivityLink, destination: String) -> CalendarCreationOptions {
        var options = CalendarCreationOptions(); options.location = destination
        options.travel = travelChoices[link.id.uuidString] ?? link.settings
        return options
    }
    private func saveTravelChoice(_ travel: CalendarCreationTravel, link: CalendarActivityLink) {
        guard var batch, batch.status == .pending else { return }
        var choices = travelChoices; choices[link.id.uuidString] = travel
        let removed = batch.actions.filter { CalendarSnapshotMatch.identity(link.travel, $0.source) }.map(\.id)
        batch.actions.removeAll { removed.contains($0.id) }; batch.linkedTravelChoices = choices
        guard batch.isValid, store.change({ data in
            if let index = data.coachState.calendarBatches?.firstIndex(where: { $0.id == batchID }) { data.coachState.calendarBatches?[index] = batch }
        }) else { problem = "Non riesco a salvare la scelta del viaggio."; return }
        selected.subtract(removed); travelChoices = choices; review = nil
    }
    private func apply() {
        guard !busy, let review else { return }
        busy = true; problem = nil
        task = Task {
            defer { busy = false; self.review = nil }
            do { try await calendar.commitMutations(review, store: store) }
            catch { problem = error.localizedDescription }
        }
    }
}

struct CalendarMutationHistoryView: View {
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @Environment(\.scenePhase) private var scenePhase
    @State private var target: UUID?
    @State private var restoring = false
    @State private var confirming = false
    @State private var busy = false
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    private var entries: [ArchivedCalendarMutation] { (store.data.calendarActionArchive ?? []).sorted { $0.preparedAt > $1.preparedAt } }
    var body: some View {
        List {
            Section {
                Text("Le copie originali restano sul dispositivo e nel backup personale. Non vengono inviate all’AI né aggiunte ai resoconti. Il ripristino richiede una nuova conferma.").font(.caption)
            }
            ForEach(entries) { entry in
                Section(entry.kind == .delete ? "Eliminazione" : "Modifica") {
                    Text(entry.original.snapshot.title).font(.headline)
                    Text(entry.original.snapshot.calendarTitle + " · " + DisplayDate.label(entry.original.snapshot.start, format: "d MMM yyyy HH:mm")).font(.caption)
                    Text(status(entry)).font(.subheadline)
                    if [.committed, .restorationPrepared].contains(entry.status) {
                        Button(entry.status == .restorationPrepared ? "Verifica e completa ripristino" : "Annulla questa modifica") {
                            target = entry.id; restoring = true; confirming = true
                        }.accessibilityIdentifier("calendar-history-restore-" + entry.id.uuidString)
                    } else if [.prepared, .uncertain].contains(entry.status) {
                        Button("Verifica esito nel Calendario") { target = entry.id; restoring = false; confirming = true }
                            .accessibilityIdentifier("calendar-history-reconcile-" + entry.id.uuidString)
                    }
                }
            }
            if entries.isEmpty { Text("Nessuna modifica al Calendario archiviata.") }
            if let message { Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("calendar-history-message") }
        }.disabled(busy || store.locked || calendar.mutationInProgress)
            .navigationTitle("Storico modifiche")
            .confirmationDialog(restoring ? "Ripristinare i dati originali di questo evento?" : "Verificare l’esito senza ripetere la modifica?", isPresented: $confirming, titleVisibility: .visible) {
                Button(restoring ? "Conferma ripristino" : "Verifica esito") { perform() }.accessibilityIdentifier("calendar-history-confirm")
                Button("Annulla", role: .cancel) { target = nil }
            } message: {
                Text(restoring ? "Un evento eliminato sarà ricreato come occorrenza singola nel calendario originale. Non vengono eliminati incassi o altri dati. Se l’evento è stato modificato altrove, Pivot non lo sovrascrive." : "Pivot rilegge l’evento. Se l’esito è ambiguo non applica altre operazioni.")
            }
            .onChange(of: scenePhase) { _, phase in if phase == .background { task?.cancel(); confirming = false } }
            .onDisappear { task?.cancel() }
    }
    private func status(_ entry: ArchivedCalendarMutation) -> String {
        switch entry.status {
        case .prepared, .uncertain: "Esito da verificare · non ripetere l’operazione"
        case .committed: "Modifica applicata"
        case .failed: "Originale presente · nessuna modifica da ripristinare"
        case .restorationPrepared: "Ripristino da completare · verifica prima di creare copie"
        case .restored: "Modifica annullata"
        }
    }
    private func perform() {
        guard !busy, let target else { return }; busy = true; message = nil
        task = Task {
            defer { busy = false }
            do {
                if restoring { message = try await calendar.restoreMutation(target, store: store) }
                else { message = try await calendar.reconcileMutation(target, store: store) }
            }
            catch { message = error.localizedDescription }
        }
    }
}
