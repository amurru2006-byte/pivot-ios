import SwiftUI

struct WorkoutChatCard: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @State private var applying = false
    @State private var message: String?
    private var draft: ActualWorkoutDraft? { store.data.actualWorkoutDraft }
    var body: some View {
        if let draft {
            PivotCard(tint: Color(calendarItem: draft.source)) {
                Label("Facciamo quadrare la giornata", systemImage: "bubble.left.and.bubble.right.fill").font(.headline)
                Text("Hai anticipato ‘\(draft.source.title)’. Conferma i dati reali: sveglia e pasti non si ricavano dall’allenamento.").font(.subheadline)
                ClockField(title: "Inizio allenamento", value: field(\.start), fallback: draft.start)
                ClockField(title: "Fine allenamento", value: optionalField(\.end), fallback: min(Date(), draft.start.addingTimeInterval(3600)))
                ClockField(title: "Sveglia reale", value: optionalField(\.wake), fallback: draft.start.addingTimeInterval(-3600))
                if (draft.contextEvents ?? calendar.events).contains(where: { EventCoalescer.normalized($0.title) == "sveglia" && PivotDate.calendar.isDate($0.start, inSameDayAs: draft.start) }) {
                    ClockField(title: "Fine preparazione mattina", value: optionalField(\.wakeEnd), fallback: draft.start)
                }
                ClockField(title: "A letto: data e ora", value: optionalField(\.bedtime), fallback: draft.start.addingTimeInterval(-8 * 3600))
                Text("Se non sai quando hai dormito, lascia il dato vuoto e verifica Salute. Il tempo a letto non viene dichiarato come tempo dormito.").font(.caption).foregroundStyle(PivotTheme.muted)
                Text("Hai fatto colazione?").font(.subheadline.weight(.semibold))
                HStack {
                    Button { update { $0.breakfastDone = true } } label: { Label("Sì", systemImage: draft.breakfastDone == true ? "checkmark.square.fill" : "square") }.buttonStyle(PivotSecondaryButton())
                    Button { update { $0.breakfastDone = false; $0.breakfastStart = nil; $0.breakfastEnd = nil } } label: { Label("Non ancora", systemImage: draft.breakfastDone == false ? "checkmark.square.fill" : "square") }.buttonStyle(PivotSecondaryButton())
                }
                if draft.breakfastDone == true {
                    ClockField(title: "Inizio colazione", value: optionalField(\.breakfastStart), fallback: draft.start.addingTimeInterval(-1800))
                    ClockField(title: "Fine colazione", value: optionalField(\.breakfastEnd), fallback: draft.start.addingTimeInterval(-900))
                } else if draft.breakfastDone == false {
                    Text("La colazione rimane da fare: non la cancello e non la segno come svolta.").font(.caption).foregroundStyle(PivotTheme.amber)
                }
                DisclosureGroup("Riepilogo delle modifiche") {
                    ForEach(WorkoutContext.moves(draft, events: calendar.events)) { move in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(move.source.title).font(.subheadline.weight(.semibold))
                            Text("Prima: \(move.source.timeSummary)").font(.caption).foregroundStyle(PivotTheme.muted)
                            Text("Dopo: \(PivotDate.shortDate(move.proposedStart)) \(PivotDate.time(move.proposedStart)) → \(PivotDate.shortDate(move.proposedEnd)) \(PivotDate.time(move.proposedEnd))").font(.caption)
                        }.padding(.vertical, 5)
                    }
                }
                Button { Task { await confirm(calendarWrite: true) } } label: { Label(applying ? "Aggiornamento…" : "Confermo: aggiorna anche il Calendario", systemImage: "calendar.badge.checkmark") }
                    .buttonStyle(PivotPrimaryButton()).disabled(applying || store.locked)
                Button("Confermo solo in Pivot") { Task { await confirm(calendarWrite: false) } }.buttonStyle(PivotSecondaryButton()).disabled(applying || store.locked)
                Button("Annulla la proposta") { update(nil); append("Proposta annullata. Nessun evento modificato.") }.font(.caption).disabled(applying)
                if let message { Text(message).font(.caption).foregroundStyle(PivotTheme.amber) }
            }
        }
    }
    private func field(_ path: WritableKeyPath<ActualWorkoutDraft, Date>) -> Binding<Date?> {
        Binding(get: { draft?[keyPath: path] }, set: { value in if let value { update { $0[keyPath: path] = value } } })
    }
    private func optionalField(_ path: WritableKeyPath<ActualWorkoutDraft, Date?>) -> Binding<Date?> {
        Binding(get: { draft?[keyPath: path] }, set: { value in update { $0[keyPath: path] = value } })
    }
    private func update(_ edit: (inout ActualWorkoutDraft) -> Void) {
        store.change { data in if var value = data.actualWorkoutDraft { edit(&value); data.actualWorkoutDraft = value } }
    }
    private func update(_ value: ActualWorkoutDraft?) { store.change { $0.actualWorkoutDraft = value } }
    private func append(_ text: String) { store.change { data in var coach = data.coachState; coach.messages.append(.init(dayKey: PivotDate.key(Date()), role: .system, text: text)); data.coachState = coach } }
    private func confirm(calendarWrite: Bool) async {
        guard !applying, !store.locked, !store.isRestoring, let draft else { return }
        applying = true; defer { applying = false }
        await calendar.refresh(settings: store.data.settings)
        let confirmedEvents = calendar.events
        if let error = WorkoutContext.validate(draft, events: confirmedEvents, now: Date()) { message = error; return }
        let moves = WorkoutContext.moves(draft, events: confirmedEvents)
        var simulated = store.data
        WorkoutContext.applyLocally(draft, events: confirmedEvents, data: &simulated, synced: false, now: Date())
        let overlaps = Planner.overlapsInPlannedEvents(on: draft.start, events: Planner.plannedEvents(confirmedEvents, data: simulated), data: simulated).filter { pair in moves.contains { $0.source.id == pair.0.id || $0.source.id == pair.1.id } }
        if calendarWrite && !overlaps.isEmpty {
            message = "Prima di aggiornare il Calendario chiarisci: " + overlaps.map { "\($0.0.title) / \($0.1.title)" }.joined(separator: ", ") + ". Puoi salvare i dati reali solo in Pivot e riorganizzare gli impegni con il Coach."; return
        }
        do {
            // This is the explicit chat approval; no language-model output can call the writer.
            if calendarWrite { try await calendar.applyActualWorkout(draft, data: store.data) }
            guard store.change({ data in
                WorkoutContext.applyLocally(draft, events: confirmedEvents, data: &data, synced: calendarWrite, now: Date())
                var coach = data.coachState
                coach.messages.append(.init(dayKey: PivotDate.key(Date()), role: .user, text: "Confermo \(draft.source.title) alle \(PivotDate.time(draft.start)), sveglia alle \(draft.wake.map(PivotDate.time) ?? "—"). \(calendarWrite ? "Aggiorna anche il Calendario." : "Salva solo in Pivot.")", healthDerived: draft.health == nil ? nil : true))
                coach.messages.append(.init(dayKey: PivotDate.key(Date()), role: .coach, text: "Allenamento registrato. \(calendarWrite ? "Calendario aggiornato per le sole occorrenze confermate." : "Calendario invariato.") \(draft.breakfastDone == false ? "La colazione resta da fare: controlla lo spazio disponibile." : "Colazione confermata.")"))
                data.coachState = coach
            }) else { message = "Salvataggio locale non riuscito. Aggiorna prima di riprovare."; return }
            await calendar.refresh(settings: store.data.settings)
        } catch { message = error.localizedDescription }
    }
}
