import SwiftUI

struct EventDetailView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    let event: CalendarItem
    @State private var record: EventRecord
    @State private var rule: EventRule
    @State private var message: String?
    @State private var suggestions: [RecoverySuggestion] = []
    @State private var pendingMove: PlanMove?
    @State private var calendarApproval = false
    @Environment(\.dismiss) private var dismiss

    init(event: CalendarItem, initial: EventRecord, rule: EventRule) {
        self.event = event
        _record = State(initialValue: initial)
        _rule = State(initialValue: rule)
    }
    var body: some View {
        PivotScreen {
            hero
            if !event.notes.isEmpty {
                PivotCard {
                    DisclosureGroup { Text(event.notes).font(.subheadline).foregroundStyle(PivotTheme.muted).textSelection(.enabled).padding(.top, 10) } label: { Label("Il programma di questa attività", systemImage: "list.bullet.clipboard").font(.subheadline.weight(.semibold)) }
                }
            }
            registration
            if event.kind == .meal { meal }
            PivotCard {
                DisclosureGroup { rules.padding(.top, 12) } label: { Label("Regole e tragitto", systemImage: "arrow.triangle.branch").font(.subheadline.weight(.semibold)) }
            }
            if let message { Label(message, systemImage: "info.circle").font(.subheadline).foregroundStyle(PivotTheme.amber) }
            Button { if save() { message = "Registrazione salvata." } } label: { Label("Salva registrazione", systemImage: "checkmark.circle.fill") }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
            if rule.flexibility != .fixed && !event.isAllDay {
                Button { findRecovery() } label: { Label("Trova uno spazio per recuperare", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
            }
            ForEach(suggestions) { suggestion in
                PivotCard(tint: PivotTheme.blue) {
                    Label("\(DisplayDate.label(suggestion.start, format: "EEE d MMM")) · \(PivotDate.time(suggestion.start))–\(PivotDate.time(suggestion.end))", systemImage: "calendar.badge.clock").font(.headline)
                    Text(suggestion.explanation).font(.subheadline).foregroundStyle(PivotTheme.muted)
                    Button("Usa questo spazio solo in Pivot") { choose(suggestion, sync: false) }.buttonStyle(PivotPrimaryButton())
                    Button("Modifica anche il Calendario…") { choose(suggestion, sync: true) }.buttonStyle(PivotSecondaryButton()).disabled(!event.writable)
                }
            }
        }
        .navigationTitle("Attività")
        .alert("Modificare il Calendario?", isPresented: $calendarApproval) {
            Button("Annulla", role: .cancel) { pendingMove = nil }
            Button("Confermo la modifica") { applyApprovedMove() }
        } message: {
            if let move = pendingMove {
                Text("\(event.title)\nDa: \(PivotDate.key(move.source.start)) \(PivotDate.time(move.source.start))–\(PivotDate.time(move.source.end))\nA: \(PivotDate.key(move.proposedStart)) \(PivotDate.time(move.proposedStart))–\(PivotDate.time(move.proposedEnd))\nSi modifica solo questa occorrenza. La modifica si sincronizza agli altri dispositivi.")
            }
        }
    }
    private var hero: some View {
        PivotCard(tint: Color(pivotHex: event.colorHex)) {
            HStack {
                Label(event.kind.label, systemImage: event.kind.icon).font(.subheadline.weight(.semibold)).foregroundStyle(Color(pivotHex: event.colorHex))
                Spacer(); StatusPill(status: record.status)
            }
            Text(event.title).font(.system(.title2, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Label(event.timeSummary, systemImage: "clock").font(.subheadline).foregroundStyle(PivotTheme.muted)
            Text(event.calendarTitle).font(.caption).foregroundStyle(PivotTheme.muted)
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(PivotTheme.muted) }
            if !event.isAllDay { Button {
                if record.status == .running { record.actualEnd = Date(); record.status = .completed; updateMinutes() }
                else { record.actualStart = Date(); record.actualEnd = nil; record.status = .running }
                save()
            } label: { Label(record.status == .running ? "Termina attività" : "Inizia attività", systemImage: record.status == .running ? "stop.fill" : "play.fill") }
                .buttonStyle(PivotPrimaryButton()).disabled(store.locked)
            }
            if let start = record.actualStart { Text("Inizio reale \(PivotDate.time(start))" + (record.actualEnd.map { " · fine \(PivotDate.time($0))" } ?? "")).font(.caption).foregroundStyle(PivotTheme.muted) }
        }
    }
    private var registration: some View {
        PivotCard {
            SectionHeading(title: "Come è andata?")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { outcomeButtons }
                VStack(spacing: 8) { outcomeButtons }
            }
            if record.status != .pending && record.status != .running {
                Button("Azzera l'esito") { record.status = .pending }.font(.caption).foregroundStyle(PivotTheme.muted)
            }
            Divider()
            Stepper("\(record.activeMinutes) minuti registrati", value: $record.activeMinutes, in: 0...1440, step: 5).font(.subheadline.weight(.semibold))
            Text("Il timer conta il tempo trascorso. Se hai fatto pause, correggi qui i minuti effettivi.").font(.caption).foregroundStyle(PivotTheme.muted)
            if record.status == .partial || record.status == .skipped {
                TextField("Cosa ti ha fermato?", text: $record.reason, axis: .vertical).lineLimit(2...5).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                Text("Racconta il motivo: ci aiuta ad adattare il programma.").font(.caption).foregroundStyle(PivotTheme.amber)
            }
            TextField("Note extra, difficoltà o progressi…", text: $record.notes, axis: .vertical).lineLimit(3...8).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            RatingField(title: "Energia", value: $record.energy)
        }
    }
    private var outcomeButtons: some View {
        ForEach([Completion.completed, .partial, .skipped], id: \.self) { status in
            Button { record.status = status } label: {
                Text(status.label).font(.subheadline.weight(.semibold)).padding(.vertical, 12).frame(maxWidth: .infinity)
                    .foregroundStyle(record.status == status ? PivotTheme.background : PivotTheme.muted)
                    .background(record.status == status ? PivotTheme.accent : PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityAddTraits(record.status == status ? .isSelected : [])
        }
    }
    private var meal: some View {
        PivotCard(tint: PivotTheme.amber) {
            Label("Il tuo pasto", systemImage: "fork.knife").font(.headline).foregroundStyle(PivotTheme.amber)
            RatingField(title: "Fame prima", value: $record.hungerBefore)
            RatingField(title: "Fame dopo", value: $record.hungerAfter)
            Picker("Piano rispettato", selection: Binding(get: { record.followedMeal.map { $0 ? 1 : 2 } ?? 0 }, set: { record.followedMeal = $0 == 0 ? nil : $0 == 1 })) {
                Text("Non indicato").tag(0); Text("Sì").tag(1); Text("No").tag(2)
            }
        }
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Gestione", selection: $rule.flexibility) { ForEach(EventFlexibility.allCases, id: \.self) { Text($0.label).tag($0) } }
            Stepper("Minimo: \(rule.minimumMinutes) min", value: $rule.minimumMinutes, in: 5...300, step: 5)
            Stepper("Tragitto prima: \(rule.travelBeforeMinutes) min", value: $rule.travelBeforeMinutes, in: 0...240, step: 5)
            Stepper("Tragitto dopo: \(rule.travelAfterMinutes) min", value: $rule.travelAfterMinutes, in: 0...240, step: 5)
            Toggle("Tempi di tragitto verificati", isOn: $rule.travelConfirmed)
            Text("Conferma anche quando il tragitto è zero. In palestra, cambio e doccia fanno parte dell'attività. Riduzioni e spostamenti richiedono la tua conferma.").font(.caption).foregroundStyle(PivotTheme.muted)
        }.font(.subheadline)
    }
    private func findRecovery() {
        guard rule.travelConfirmed else { message = "Prima conferma i tempi di tragitto. Non posso supporre che siano zero."; return }
        guard save() else { return }
        suggestions = Planner.recover(event, events: calendar.events, data: store.data, now: Date())
        if suggestions.isEmpty { message = "Non ho trovato uno spazio completo nei prossimi tre giorni. Verifica i tragitti e confrontiamoci su cosa puoi rimandare. Non ho tagliato altri eventi." }
    }
    private func updateMinutes() {
        if let start = record.actualStart, let end = record.actualEnd { record.activeMinutes = max(0, Int(end.timeIntervalSince(start) / 60)) }
    }
    @discardableResult private func save() -> Bool {
        if (record.status == .partial || record.status == .skipped) && record.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "Scrivi il motivo dell'attività parziale o saltata."; return false
        }
        record.updatedAt = Date()
        return store.change { data in data.records[event.id] = record; data.rules[event.id] = rule }
    }
    private func choose(_ suggestion: RecoverySuggestion, sync: Bool) {
        calendar.refresh(settings: store.data.settings)
        guard let source = calendar.events.first(where: { $0.id == event.id }) else {
            message = "L'evento è cambiato o non è più disponibile. Aggiorna la giornata."; return
        }
        let move = PlanMove(source: source, proposedStart: suggestion.start, proposedEnd: suggestion.end)
        guard slotIsAvailable(move) else { message = "Questo spazio non è più libero. Cerca una nuova proposta."; return }
        if sync { pendingMove = move; calendarApproval = true }
        else {
            if store.change({ $0.moves.append(move) }) { message = "Proposta approvata solo in Pivot. Il Calendario non è cambiato."; suggestions = [] }
        }
    }
    private func applyApprovedMove() {
        guard var move = pendingMove else { return }
        guard !store.locked else { message = "Lo storico è bloccato: ripristina il backup prima di modificare eventi."; return }
        do {
            // Validate the chosen slot against a fresh calendar view before writing.
            calendar.refresh(settings: store.data.settings)
            guard slotIsAvailable(move) else { message = "Questo spazio non è più libero. Cerca una nuova proposta."; return }
            try calendar.apply(move)
            move.syncedToCalendar = true
            if !store.change({ $0.moves.append(move) }) {
                message = "Il Calendario è stato modificato, ma lo storico locale non è stato salvato. Controlla la copia di backup."; return
            }
            calendar.refresh(settings: store.data.settings)
            message = "Evento aggiornato nel Calendario. Solo questa occorrenza."
            suggestions = []
        } catch { message = error.localizedDescription }
        pendingMove = nil
    }
    private func slotIsAvailable(_ move: PlanMove) -> Bool {
        guard rule.travelConfirmed, move.proposedStart > Date() else { return false }
        let occupiedStart = move.proposedStart.addingTimeInterval(-Double(rule.travelBeforeMinutes) * 60)
        let occupiedEnd = move.proposedEnd.addingTimeInterval(Double(rule.travelAfterMinutes) * 60)
        return !Planner.effectiveEvents(calendar.events, data: store.data).contains { item in
            guard item.id != event.id, !item.isAllDay else { return false }
            let other = store.rule(for: item)
            if !item.location.isEmpty && !other.travelConfirmed && PivotDate.key(item.start) == PivotDate.key(move.proposedStart) { return true }
            return item.start.addingTimeInterval(-Double(other.travelBeforeMinutes) * 60) < occupiedEnd
                && item.end.addingTimeInterval(Double(other.travelAfterMinutes) * 60) > occupiedStart
        }
    }
}
